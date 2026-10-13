#!/usr/bin/env python3
"""Extract a Silead GSL touch firmware from the Allwinner vendor module gslX680new.ko.

The script reads the ELF file directly. It needs only the Python standard library.

It does these steps:
  1. It reads the symbol table and the `.rel.data` relocations.
  2. It decodes the table `gslx680_fw_grp[]` ({name, size, fw pointer}, 12 bytes per entry)
     and the parallel table `gslX680_config_data[]` (one pointer per entry).
  3. It finds the entry whose name is equal to `ctp_name` from sys_config.fex.
  4. It writes three files:
       <name>.vendor-fw_data.bin  the vendor array, byte for byte
       <name>.fw                  the same records in the mainline `silead` format
       <name>.config_data.bin     the 512-word table for the vendor point library
  5. It checks the output against the rules of mainline drivers/input/touchscreen/silead.c.

Usage:
  python3 -I extract_gsl_fw.py <gslX680new.ko> [--name gsl_m86_hd] [--out DIR] [--list]

Do not publish the output files. They are the vendor's firmware.
"""
import argparse
import hashlib
import os
import struct
import sys

R_ARM_ABS32 = 2
PAGE_REG = 0xF0          # register that selects the firmware page
RECORD = struct.Struct('<II')   # struct fw_data { u32 offset; u32 val; }, little-endian


class Elf32:
    """Minimal reader for a little-endian ELF32 relocatable file."""

    def __init__(self, path):
        self.d = d = open(path, 'rb').read()
        if d[:4] != b'\x7fELF' or d[4] != 1 or d[5] != 1:
            sys.exit('error: the file is not a little-endian ELF32 file')
        shoff, = struct.unpack_from('<I', d, 0x20)
        shentsize, shnum, shstrndx = struct.unpack_from('<HHH', d, 0x2E)
        self.secs = [struct.unpack_from('<10I', d, shoff + i * shentsize) for i in range(shnum)]
        self.names = [self._cstr(self.secs[shstrndx][4] + s[0]) for s in self.secs]
        sym = self.secs[self.names.index('.symtab')]
        strtab = self.secs[sym[6]][4]
        self.syms = []
        for i in range(sym[5] // 16):
            nm, val, size, info, _other, shndx = struct.unpack_from('<IIIBBH', d, sym[4] + i * 16)
            self.syms.append((self._cstr(strtab + nm) if nm else '', val, size, info, shndx))

    def _cstr(self, off):
        return self.d[off:self.d.index(b'\0', off)].decode('latin1')

    def sec_off(self, name):
        return self.secs[self.names.index(name)][4]

    def data(self, name, off, size):
        base = self.sec_off(name)
        return self.d[base + off:base + off + size]

    def cstr(self, name, off):
        return self._cstr(self.sec_off(name) + off)

    def symbol(self, name):
        hits = [s for s in self.syms if s[0] == name and (s[3] & 15) == 1]
        if len(hits) != 1:
            sys.exit(f'error: expected one object symbol {name!r}, found {len(hits)}')
        _n, val, size, _info, shndx = hits[0]
        return self.names[shndx], val, size

    def symbol_at(self, sec, addr):
        for n, val, size, info, shndx in self.syms:
            if (info & 15) == 1 and shndx < len(self.names) and self.names[shndx] == sec and val == addr:
                return n, size
        return None, 0

    def relocs(self, name):
        s = self.secs[self.names.index(name)]
        out = {}
        for i in range(s[5] // 8):
            off, info = struct.unpack_from('<II', self.d, s[4] + i * 8)
            out[off] = (info >> 8, info & 0xFF)
        return out

    def pointer(self, sec, off, rel):
        """Resolve a 32-bit pointer stored at sec+off. Return (target section, target offset)."""
        addend, = struct.unpack('<I', self.data(sec, off, 4))
        if off not in rel:
            sys.exit(f'error: no relocation at {sec}+{off:#x}')
        symidx, rtype = rel[off]
        if rtype != R_ARM_ABS32:
            sys.exit(f'error: relocation type {rtype} at {sec}+{off:#x} is not R_ARM_ABS32')
        _n, val, _size, _info, shndx = self.syms[symidx]
        return self.names[shndx], val + addend


def read_table(elf):
    """Decode gslx680_fw_grp[] and gslX680_config_data[]."""
    gsec, goff, gsize = elf.symbol('gslx680_fw_grp')
    csec, coff, csize = elf.symbol('gslX680_config_data')
    count = gsize // 12
    if gsize % 12 or csize != count * 4:
        sys.exit('error: the table sizes do not agree')
    rel = elf.relocs('.rel' + gsec)
    rows = []
    for i in range(count):
        o = goff + 12 * i
        nsec, noff = elf.pointer(gsec, o, rel)
        nrec, = struct.unpack('<I', elf.data(gsec, o + 4, 4))
        fsec, foff = elf.pointer(gsec, o + 8, rel)
        ksec, koff = elf.pointer(csec, coff + 4 * i, rel)
        rows.append(dict(index=i, entry_off=o, name=elf.cstr(nsec, noff), records=nrec,
                         fw_sec=fsec, fw_off=foff, fw_sym=elf.symbol_at(fsec, foff),
                         cfg_sec=ksec, cfg_off=koff, cfg_sym=elf.symbol_at(ksec, koff)))
    return (gsec, goff), (csec, coff), rows


def check_vendor_layout(raw):
    """Check the vendor layout. Return the list of (offset, val) records."""
    if len(raw) % 8:
        sys.exit('error: the array length is not a multiple of 8')
    recs = [RECORD.unpack_from(raw, i) for i in range(0, len(raw), 8)]
    if any(off > 0xFF for off, _ in recs):
        sys.exit('error: an offset is larger than one byte (padding bytes are not zero)')
    if recs[0][0] != PAGE_REG:
        sys.exit('error: the first record does not select a page')
    i = 0
    pages = []
    while i < len(recs):
        if recs[i][0] != PAGE_REG:
            sys.exit(f'error: record {i} should select a page')
        body = recs[i + 1:i + 33]
        if len(body) != 32 or any(off != 4 * k for k, (off, _v) in enumerate(body)):
            sys.exit(f'error: page {recs[i][1]:#x} does not hold registers 0x00..0x7c in sequence')
        pages.append(recs[i][1])
        i += 33
    if len(set(pages)) != len(pages):
        sys.exit('error: a page occurs two times')
    return recs, pages


def vendor_loader_writes(recs):
    """Model gsl_load_fw() from the vendor module (disassembly at .text 0xd8).

    A page record goes out immediately as a 4-byte write to register 0xf0.
    Other records collect in a buffer. The loader sends the buffer after 32 values,
    as one write to the register of the first value in the buffer.
    Return a memory image {(page, register): value}.
    """
    image, page, buf, start, send_flag = {}, None, [], None, 1
    for off, val in recs:
        if off == PAGE_REG:
            page, send_flag = val, 1
            continue
        if send_flag % 32 == 1:
            start = off
        buf.append(val)
        if send_flag % 32 == 0:
            for k, v in enumerate(buf):
                image[(page, start + 4 * k)] = v
            buf = []
        send_flag = (send_flag + 1) & 0xFF
    if buf:
        sys.exit('error: the vendor loader would not send the last partial block')
    return image


def mainline_loader_writes(blob):
    """Model silead_ts_load_fw() from mainline silead.c.

    The driver casts the file to struct silead_fw_data { u32 offset; u32 val; }.
    It writes each record alone: 4 bytes of `val` to the register `offset` (8 bits on the bus).
    Page records get no special handling.
    """
    image, page = {}, None
    for i in range(len(blob) // 8):
        off, val = RECORD.unpack_from(blob, i * 8)
        reg = off & 0xFF
        if reg == PAGE_REG:
            page = val
        else:
            image[(page, reg)] = val
    return image


def sha256(b):
    return hashlib.sha256(b).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('ko', help='path to gslX680new.ko')
    ap.add_argument('--name', default='gsl_m86_hd', help='ctp_name from sys_config.fex')
    ap.add_argument('--out', default=os.path.dirname(os.path.abspath(__file__)), help='output directory')
    ap.add_argument('--list', action='store_true', help='print the table and stop')
    args = ap.parse_args()

    elf = Elf32(args.ko)
    (gsec, goff), (csec, coff), rows = read_table(elf)
    print(f'module: {args.ko} ({len(elf.d)} bytes, sha256 {sha256(elf.d)})')
    print(f'gslx680_fw_grp at {gsec}+{goff:#x}, gslX680_config_data at {csec}+{coff:#x}, {len(rows)} entries')
    if args.list:
        for r in rows:
            print(f"  [{r['index']:2d}] {r['name']:20s} {r['records']:5d} records  "
                  f"{r['fw_sym'][0]:26s} {r['fw_sec']}+{r['fw_off']:#08x}  "
                  f"{r['cfg_sym'][0]} {r['cfg_sec']}+{r['cfg_off']:#07x}")
        return

    hits = [r for r in rows if r['name'] == args.name]
    if len(hits) != 1:
        sys.exit(f'error: {len(hits)} table entries have the name {args.name!r}')
    r = hits[0]
    fw_name, fw_size = r['fw_sym']
    cfg_name, cfg_size = r['cfg_sym']
    print(f"entry [{r['index']}] at {gsec}+{r['entry_off']:#x}: name={r['name']!r} size={r['records']} records")
    print(f"  fw     -> {fw_name} at {r['fw_sec']}+{r['fw_off']:#x} ({fw_size} bytes)")
    print(f"  config -> {cfg_name} at {r['cfg_sec']}+{r['cfg_off']:#x} ({cfg_size} bytes)")
    if fw_size != r['records'] * 8:
        sys.exit('error: the symbol size is not equal to 8 bytes x the record count')
    if cfg_size != 2048:
        sys.exit('error: the config table is not 512 words')

    raw = elf.data(r['fw_sec'], r['fw_off'], fw_size)
    cfg = elf.data(r['cfg_sec'], r['cfg_off'], cfg_size)
    recs, pages = check_vendor_layout(raw)

    # Mainline format: the same records, packed again as two little-endian u32 values.
    fw = b''.join(RECORD.pack(off & 0xFF, val) for off, val in recs)

    # Checks against the mainline loader.
    assert len(fw) % 8 == 0 and len(fw) // 8 == r['records']
    v_img, m_img = vendor_loader_writes(recs), mainline_loader_writes(fw)
    assert v_img == m_img, 'the two loaders do not write the same memory image'
    assert len(m_img) == 32 * len(pages)
    print(f'layout: {len(recs)} records = {len(pages)} pages x (1 page record + 32 registers)')
    print('pages : ' + ' '.join(f'{p:x}' for p in pages))
    print(f'check : vendor loader and mainline loader write the same {len(m_img)} registers: OK')
    print(f'check : .fw is byte-identical to the vendor array: {fw == raw}')

    # What the data says about the sensor.
    w = struct.unpack('<512I', cfg)
    page = {p: [v for _o, v in recs[i * 33 + 1:i * 33 + 33]] for i, p in enumerate(pages)}
    print('config_data (decoded as gsl_DataInit does for word[0] >= 0x1000):')
    print(f'  word[0]={w[0]:#x} word[1]={w[1]:#x} (length in words)')
    print(f'  global_flag   word[16]      = {w[16]:#010x}')
    print(f'  point_num_max word[17]      = {w[17]}')
    print(f'  drv_num / sen_num           = {w[18] & 0xFFFF} / {w[18] >> 16}   (word[18]={w[18]:#x})')
    print(f'  drv_num_nokey / sen_num_nokey = {w[19] & 0xFFFF} / {w[19] >> 16} (word[19]={w[19]:#x})')
    print(f'  screen_x_max / screen_y_max = {w[20] & 0xFFFF} / {w[20] >> 16} (word[20]={w[20]:#x})')
    p6 = page.get(6)
    if p6:
        print('firmware page 6: '
              f'reg 0x00={p6[0]} reg 0x08={p6[2]} reg 0x24={p6[9]} reg 0x28={p6[10]} reg 0x30={p6[12]:#010x}')
        print(f'  line count x 64 = {p6[0] * 64} x {p6[2] * 64} (expected raw coordinate range, not proved)')
    last = page[pages[-1]]
    stamp = b''.join(struct.pack('>I', v) for v in last[26:32]).replace(b'\0', b' ').decode('latin1')
    print(f'firmware build stamp in the last page: {" ".join(stamp.split())!r}')

    os.makedirs(args.out, exist_ok=True)
    for suffix, blob in (('.vendor-fw_data.bin', raw), ('.fw', fw), ('.config_data.bin', cfg)):
        path = os.path.join(args.out, args.name + suffix)
        with open(path, 'wb') as f:
            f.write(blob)
        print(f'wrote {path}  {len(blob)} bytes  sha256 {sha256(blob)}')


if __name__ == '__main__':
    main()
