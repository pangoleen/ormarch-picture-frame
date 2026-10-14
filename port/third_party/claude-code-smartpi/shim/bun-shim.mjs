// Bun API shim for running the extracted Claude Code bundle under Node.js.
// Implements only the surface actually referenced by the bundle; everything
// Bun-native-only (Terminal, SQL, serve) is left absent or throwing so the
// app's own feature detection degrades gracefully ("running under Node?").
import { spawn as nodeSpawn, spawnSync } from 'node:child_process';
import { Readable } from 'node:stream';
import { isDeepStrictEqual } from 'node:util';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);

// ---------------------------------------------------------------- stripANSI
const ANSI_PATTERN = '[\\u001b\\u009b][[\\]()#;?]*(?:(?:(?:(?:;[-\\w/#&.:=?%@~]+)*|[a-zA-Z\\d]+(?:;[-\\w/#&.:=?%@~]*)*)?(?:\\u0007|\\u001b\\\\))|(?:(?:\\d{1,4}(?:;\\d{0,4})*)?[\\dA-PR-TZcf-nq-uy=><~]))';
const ANSI_RE_G = new RegExp(ANSI_PATTERN, 'g');
function stripANSI(s) {
  return String(s).replace(ANSI_RE_G, '');
}

// ------------------------------------------------------------- stringWidth
// East Asian Wide/Fullwidth + emoji-presentation ranges (codepoints).
const WIDE = [
  [0x1100, 0x115f], [0x231a, 0x231b], [0x2329, 0x232a], [0x23e9, 0x23ec],
  [0x23f0, 0x23f0], [0x23f3, 0x23f3], [0x25fd, 0x25fe], [0x2614, 0x2615],
  [0x2648, 0x2653], [0x267f, 0x267f], [0x2693, 0x2693], [0x26a1, 0x26a1],
  [0x26aa, 0x26ab], [0x26bd, 0x26be], [0x26c4, 0x26c5], [0x26ce, 0x26ce],
  [0x26d4, 0x26d4], [0x26ea, 0x26ea], [0x26f2, 0x26f3], [0x26f5, 0x26f5],
  [0x26fa, 0x26fa], [0x26fd, 0x26fd], [0x2705, 0x2705], [0x270a, 0x270b],
  [0x2728, 0x2728], [0x274c, 0x274c], [0x274e, 0x274e], [0x2753, 0x2755],
  [0x2757, 0x2757], [0x2795, 0x2797], [0x27b0, 0x27b0], [0x27bf, 0x27bf],
  [0x2b1b, 0x2b1c], [0x2b50, 0x2b50], [0x2b55, 0x2b55], [0x2e80, 0x303e],
  [0x3041, 0x33ff], [0x3400, 0x4dbf], [0x4e00, 0x9fff], [0xa000, 0xa4cf],
  [0xa960, 0xa97f], [0xac00, 0xd7a3], [0xf900, 0xfaff], [0xfe10, 0xfe19],
  [0xfe30, 0xfe6f], [0xff00, 0xff60], [0xffe0, 0xffe6],
  [0x16fe0, 0x16fe4], [0x17000, 0x187f7], [0x18800, 0x18cd5],
  [0x1b000, 0x1b2fb], [0x1f004, 0x1f004], [0x1f0cf, 0x1f0cf],
  [0x1f18e, 0x1f18e], [0x1f191, 0x1f19a], [0x1f200, 0x1f320],
  [0x1f32d, 0x1f335], [0x1f337, 0x1f37c], [0x1f37e, 0x1f393],
  [0x1f3a0, 0x1f3ca], [0x1f3cf, 0x1f3d3], [0x1f3e0, 0x1f3f0],
  [0x1f3f4, 0x1f3f4], [0x1f3f8, 0x1f43e], [0x1f440, 0x1f440],
  [0x1f442, 0x1f4fc], [0x1f4ff, 0x1f53d], [0x1f54b, 0x1f54e],
  [0x1f550, 0x1f567], [0x1f57a, 0x1f57a], [0x1f595, 0x1f596],
  [0x1f5a4, 0x1f5a4], [0x1f5fb, 0x1f64f], [0x1f680, 0x1f6c5],
  [0x1f6cc, 0x1f6cc], [0x1f6d0, 0x1f6d2], [0x1f6d5, 0x1f6d7],
  [0x1f6dc, 0x1f6df], [0x1f6eb, 0x1f6ec], [0x1f6f4, 0x1f6fc],
  [0x1f7e0, 0x1f7eb], [0x1f7f0, 0x1f7f0], [0x1f90c, 0x1f93a],
  [0x1f93c, 0x1f945], [0x1f947, 0x1f9ff], [0x1fa70, 0x1faff],
  [0x20000, 0x2fffd], [0x30000, 0x3fffd],
];
function isWideCp(cp) {
  if (cp < 0x1100) return false;
  let lo = 0, hi = WIDE.length - 1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (cp < WIDE[mid][0]) hi = mid - 1;
    else if (cp > WIDE[mid][1]) lo = mid + 1;
    else return true;
  }
  return false;
}
const ZERO_RE = /^[\p{M}\u200b-\u200f\u2060-\u2064\ufeff\u1160-\u11ff]+$/u;
const ASCII_RE = /^[\x20-\x7e]*$/;
const HAS_ESC_RE = /[\u001b\u009b]/;
let segmenter;
const widthCache = new Map();
function graphemeWidth(g) {
  const cps = Array.from(g);
  const cp = g.codePointAt(0);
  if (cps.length === 1) {
    if (cp < 0x20 || (cp >= 0x7f && cp < 0xa0)) return 0;
    if (ZERO_RE.test(g)) return 0;
    return isWideCp(cp) ? 2 : 1;
  }
  if (g.includes('\u200d') || g.includes('\ufe0f')) return 2; // ZWJ / VS16 emoji
  if (/\p{RI}\p{RI}/u.test(g)) return 2; // flag
  if (ZERO_RE.test(g)) return 0;
  return isWideCp(cp) ? 2 : 1;
}
function stringWidth(input) {
  if (typeof input !== 'string' || input.length === 0) return 0;
  if (ASCII_RE.test(input)) return input.length;
  const cacheable = input.length <= 256;
  if (cacheable) {
    const hit = widthCache.get(input);
    if (hit !== undefined) return hit;
  }
  const s = HAS_ESC_RE.test(input) ? stripANSI(input) : input;
  let w = 0;
  if (ASCII_RE.test(s)) {
    w = s.length;
  } else {
    segmenter ??= new Intl.Segmenter();
    for (const { segment } of segmenter.segment(s)) w += graphemeWidth(segment);
  }
  if (cacheable) {
    if (widthCache.size > 20000) widthCache.clear();
    widthCache.set(input, w);
  }
  return w;
}

// ---------------------------------------------------------------- wrapAnsi
// ANSI-aware greedy word wrap (compact port of wrap-ansi semantics).
const ANSI_RE_Y = new RegExp(ANSI_PATTERN, 'y');
const SGR_RE = /^\u001b\[([\d;]*)m$/;
const LINK_OPEN_RE = /^\u001b\]8;;(.+)(?:\u0007|\u001b\\)$/;
const LINK_CLOSE = '\u001b]8;;\u0007';
function tokenize(line) {
  const out = [];
  let i = 0;
  while (i < line.length) {
    const code = line.charCodeAt(i);
    if (code === 0x1b || code === 0x9b) {
      ANSI_RE_Y.lastIndex = i;
      const m = ANSI_RE_Y.exec(line);
      if (m) { out.push({ esc: m[0] }); i += m[0].length; continue; }
    }
    const cp = line.codePointAt(i);
    const ch = String.fromCodePoint(cp);
    out.push({ ch, w: stringWidth(ch) });
    i += ch.length;
  }
  return out;
}
function sgrState(active, esc) {
  const m = SGR_RE.exec(esc);
  if (!m) return active;
  const body = m[1];
  if (body === '' || body === '0') return [];
  return [...active, esc];
}
function wrapAnsi(input, columns, options = {}) {
  const { hard = false, wordWrap = true, trim = true } = options;
  if (!(columns > 0)) return String(input);
  const out = [];
  for (const line of String(input).split('\n')) {
    if (trim && line.trim() === '') { out.push(''); continue; }
    const tokens = tokenize(line);
    let active = [];
    let openLink = null;
    let cur = '';
    let curW = 0;
    const pushed = [];
    const breakLine = () => {
      let l = cur;
      if (trim) l = l.replace(/ +$/, '');
      if (openLink) l += LINK_CLOSE;
      pushed.push(l);
      cur = active.join('') + (openLink ?? '');
      curW = 0;
    };
    let word = [];
    let wordW = 0;
    const emit = (t) => {
      if (t.esc !== undefined) {
        cur += t.esc;
        active = sgrState(active, t.esc);
        if (LINK_OPEN_RE.test(t.esc)) openLink = t.esc;
        else if (/^\u001b\]8;;(?:\u0007|\u001b\\)$/.test(t.esc)) openLink = null;
        return;
      }
      if (curW + t.w > columns && curW > 0) breakLine();
      cur += t.ch;
      curW += t.w;
    };
    const flushWord = () => {
      if (word.length === 0) return;
      if (wordWrap && curW > 0 && curW + 1 + wordW > columns && wordW <= columns) {
        breakLine();
      } else if (curW > 0) {
        cur += ' ';
        curW += 1;
      }
      for (const t of word) emit(t);
      word = [];
      wordW = 0;
    };
    for (const t of tokens) {
      if (t.esc !== undefined) { word.push(t); continue; }
      if (t.ch === ' ') { flushWord(); continue; }
      word.push(t);
      wordW += t.w;
    }
    flushWord();
    if (trim) cur = cur.replace(/ +$/, '');
    pushed.push(cur);
    out.push(pushed.join('\n'));
  }
  return out.join('\n');
}

// -------------------------------------------------------------------- hash
function bunHash(input, seed) {
  const h = createHash('sha1');
  if (seed !== undefined && seed !== null) h.update(String(seed));
  h.update(typeof input === 'string' ? input : Buffer.from(input));
  return h.digest().readBigUInt64LE(0);
}

// ------------------------------------------------------------------ semver
function parseVer(v) {
  const m = /^v?(\d+)\.(\d+)\.(\d+)(?:-([\w.-]+))?(?:\+[\w.-]+)?$/.exec(String(v).trim());
  if (!m) return null;
  return { maj: +m[1], min: +m[2], pat: +m[3], pre: m[4] ? m[4].split('.') : null };
}
function cmpVer(a, b) {
  const pa = parseVer(a), pb = parseVer(b);
  if (!pa || !pb) throw new Error(`Invalid SemVer: ${!pa ? a : b}`);
  for (const k of ['maj', 'min', 'pat']) {
    if (pa[k] !== pb[k]) return pa[k] < pb[k] ? -1 : 1;
  }
  if (!pa.pre && !pb.pre) return 0;
  if (!pa.pre) return 1;
  if (!pb.pre) return -1;
  for (let i = 0; i < Math.max(pa.pre.length, pb.pre.length); i++) {
    const x = pa.pre[i], y = pb.pre[i];
    if (x === undefined) return -1;
    if (y === undefined) return 1;
    const nx = /^\d+$/.test(x), ny = /^\d+$/.test(y);
    if (nx && ny) { if (+x !== +y) return +x < +y ? -1 : 1; }
    else if (nx) return -1;
    else if (ny) return 1;
    else if (x !== y) return x < y ? -1 : 1;
  }
  return 0;
}
function satisfiesComparator(v, comp) {
  comp = comp.trim();
  if (comp === '' || comp === '*' || comp === 'x') return true;
  const m = /^(\^|~|>=|<=|>|<|=)?\s*v?([\dx*]+)(?:\.([\dx*]+))?(?:\.([\dx*]+))?(?:-([\w.-]+))?(?:\+[\w.-]+)?$/.exec(comp);
  if (!m) return false;
  const [, op, maj, min, pat, pre] = m;
  const wild = (s) => s === undefined || s === 'x' || s === '*';
  const base = `${wild(maj) ? 0 : maj}.${wild(min) ? 0 : min}.${wild(pat) ? 0 : pat}${pre ? '-' + pre : ''}`;
  if (!op || op === '=') {
    if (wild(min)) return cmpVer(v, base) >= 0 && cmpVer(v, `${+maj + 1}.0.0-0`) < 0;
    if (wild(pat)) return cmpVer(v, base) >= 0 && cmpVer(v, `${maj}.${+min + 1}.0-0`) < 0;
    return cmpVer(v, base) === 0;
  }
  if (op === '>=') return cmpVer(v, base) >= 0;
  if (op === '<=') return cmpVer(v, base) <= 0;
  if (op === '>') return cmpVer(v, base) > 0;
  if (op === '<') return cmpVer(v, base) < 0;
  if (op === '^') {
    const M = wild(maj) ? 0 : +maj, mi = wild(min) ? 0 : +min;
    let upper;
    if (M > 0) upper = `${M + 1}.0.0-0`;
    else if (mi > 0) upper = `0.${mi + 1}.0-0`;
    else upper = `0.0.${(wild(pat) ? 0 : +pat) + 1}-0`;
    return cmpVer(v, base) >= 0 && cmpVer(v, upper) < 0;
  }
  if (op === '~') {
    const M = wild(maj) ? 0 : +maj, mi = wild(min) ? 0 : +min;
    return cmpVer(v, base) >= 0 && cmpVer(v, `${M}.${mi + 1}.0-0`) < 0;
  }
  return false;
}
function semverSatisfies(v, range) {
  if (!parseVer(v)) return false;
  return String(range).split('||').some((clause) => {
    clause = clause.trim();
    const hyphen = /^(\S+)\s+-\s+(\S+)$/.exec(clause);
    if (hyphen) return cmpVer(v, hyphen[1]) >= 0 && cmpVer(v, hyphen[2]) <= 0;
    return clause.split(/\s+/).every((c) => satisfiesComparator(v, c));
  });
}

// ------------------------------------------------------------------- which
function which(cmd) {
  if (!cmd) return null;
  if (cmd.includes(path.sep) || (process.platform === 'win32' && cmd.includes('/'))) {
    try { fs.accessSync(cmd, fs.constants.X_OK); return path.resolve(cmd); } catch { return null; }
  }
  const dirs = (process.env.PATH || '').split(path.delimiter);
  const exts = process.platform === 'win32'
    ? (process.env.PATHEXT || '.EXE;.CMD;.BAT;.COM').split(';')
    : [''];
  for (const d of dirs) {
    if (!d) continue;
    for (const ext of exts) {
      const p = path.join(d, cmd + ext.toLowerCase());
      try {
        const st = fs.statSync(p);
        if (st.isFile()) { fs.accessSync(p, fs.constants.X_OK); return p; }
      } catch { /* keep scanning */ }
    }
  }
  return null;
}

// ---------------------------------------------------------------- Bun.file
const BUNFILE = Symbol('bunfile');
class BunFile {
  constructor(p) { this[BUNFILE] = true; this.path = p; this.name = p; }
  async exists() { try { fs.accessSync(this.path); return true; } catch { return false; } }
  async text() { return fs.promises.readFile(this.path, 'utf8'); }
  async json() { return JSON.parse(await this.text()); }
  async arrayBuffer() { const b = await fs.promises.readFile(this.path); return b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength); }
  stream() { return Readable.toWeb(fs.createReadStream(this.path)); }
}

// --------------------------------------------------------------- Bun.spawn
function mapStdio(v, forWrite) {
  if (v === undefined || v === null) return 'pipe';
  if (v === 'pipe' || v === 'ignore' || v === 'inherit') return v;
  if (typeof v === 'number') return v;
  if (v && v[BUNFILE]) return fs.openSync(v.path, forWrite ? 'a' : 'r');
  return 'ignore';
}
function bunSpawn(cmdOrOpts, maybeOpts) {
  let cmd, opts;
  if (Array.isArray(cmdOrOpts)) { cmd = cmdOrOpts; opts = maybeOpts || {}; }
  else { opts = cmdOrOpts || {}; cmd = opts.cmd; }
  if (opts.terminal !== undefined) {
    throw new Error('Bun.spawn({terminal}) is not supported under the Node shim');
  }
  const stdioOpt = opts.stdio;
  const stdinFd = mapStdio(stdioOpt ? stdioOpt[0] : opts.stdin ?? 'ignore', false);
  const stdoutFd = mapStdio(stdioOpt ? stdioOpt[1] : opts.stdout ?? 'pipe', true);
  const stderrFd = mapStdio(stdioOpt ? stdioOpt[2] : opts.stderr ?? 'inherit', true);
  const child = nodeSpawn(cmd[0], cmd.slice(1), {
    cwd: opts.cwd,
    env: opts.env,
    argv0: opts.argv0,
    detached: opts.detached ?? false,
    windowsHide: opts.windowsHide ?? true,
    stdio: [stdinFd, stdoutFd, stderrFd],
  });
  const sub = {
    pid: child.pid,
    exitCode: null,
    signalCode: null,
    killed: false,
    stdout: child.stdout ? Readable.toWeb(child.stdout) : undefined,
    stderr: child.stderr ? Readable.toWeb(child.stderr) : undefined,
    stdin: child.stdin ? {
      write(chunk) { return child.stdin.write(chunk); },
      end() { child.stdin.end(); },
      flush() {},
      close() { child.stdin.end(); },
    } : undefined,
    kill(sig) { sub.killed = true; try { child.kill(sig ?? 'SIGTERM'); } catch { /* already gone */ } },
    unref() { child.unref(); },
    ref() { child.ref(); },
  };
  sub.exited = new Promise((resolve) => {
    child.once('exit', (code, signal) => {
      sub.exitCode = code;
      sub.signalCode = signal;
      resolve(code ?? (signal ? 128 : 0));
    });
    child.once('error', () => resolve(-1));
  });
  return sub;
}

// -------------------------------------------------------------------- YAML
let jsyaml = null;
function yamlLib() {
  if (!jsyaml) jsyaml = require('js-yaml');
  return jsyaml;
}

// -------------------------------------------------------------- Transpiler
class TranspilerStub {
  transformSync(code) { return code; }
  scanImports() { return []; }
  scan() { return { imports: [], exports: [] }; }
}

// ------------------------------------------------------ embedded files ($bunfs)
// A Bun standalone binary serves its embedded files (bundled skills/README .md.zst, prompt
// templates, native addons) from a virtual filesystem rooted at /$bunfs/root/, and the app
// reads them with plain fs calls: fs.readFileSync("/$bunfs/root/SKILL-….md.zst") followed by
// Bun.zstdDecompressSync. Under Node those files live in assets/ next to this shim (put there
// by install.sh / vendor-release.sh from the extractor's bunfs/ mirror), so every fs entry
// point that takes a path is remapped. Native .node addons are not shipped (host-specific):
// requiring one fails with MODULE_NOT_FOUND exactly where the feature is used, not earlier.
export const BUNFS_ROOT = '/$bunfs/root/';
export const ASSETS_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), 'assets');
export function resolveBunfsPath(p) {
  return typeof p === 'string' && p.startsWith(BUNFS_ROOT)
    ? path.join(ASSETS_DIR, p.slice(BUNFS_ROOT.length))
    : p;
}
// require() of an embedded file, as Bun's loaders answer it: `text` (.md/.txt) → the file
// contents, `file` (.zst/.asset) → the virtual path (read later through the remapped fs),
// anything else (.node napi addons, plain JS) → a real require of the mapped file.
const TEXT_EXTS = new Set(['.md', '.txt']);
const PATH_EXTS = new Set(['.zst', '.asset']);
export function requireBunfs(id, baseRequire) {
  const ext = path.extname(id);
  if (TEXT_EXTS.has(ext)) return fs.readFileSync(resolveBunfsPath(id), 'utf8');
  if (PATH_EXTS.has(ext)) return id;
  return baseRequire(resolveBunfsPath(id));
}
const FS_PATH_FUNCS = ['readFileSync', 'readFile', 'existsSync', 'statSync', 'stat', 'lstatSync', 'lstat',
  'accessSync', 'access', 'realpathSync', 'realpath', 'openSync', 'open', 'createReadStream',
  'readdirSync', 'readdir'];
const FS_PROMISES_FUNCS = ['readFile', 'stat', 'lstat', 'access', 'realpath', 'open', 'readdir'];
function wrapPathFn(orig) {
  // keep sub-functions such as fs.realpathSync.native reachable on the wrapper
  return Object.assign(function (p, ...rest) { return orig.call(this, resolveBunfsPath(p), ...rest); }, orig);
}
function remapBunfs() {
  for (const name of FS_PATH_FUNCS) if (typeof fs[name] === 'function') fs[name] = wrapPathFn(fs[name]);
  for (const name of FS_PROMISES_FUNCS) if (typeof fs.promises[name] === 'function') fs.promises[name] = wrapPathFn(fs.promises[name]);
}

// -------------------------------------------------------------------- zstd
// Bun.zstd* → node:zlib (zstd landed in Node 22.15 / 23.8; older Node has no zstd at all).
function zstdApi(name) {
  if (typeof zlib[name] !== 'function') {
    throw new Error(`Bun.${name}: node:zlib has no zstd support on ${process.version} (Node >= 22.15 required)`);
  }
  return zlib[name];
}

// ----------------------------------------------------------------- install
export function installBunShim() {
  if (globalThis.Bun) return globalThis.Bun;
  remapBunfs();
  const Bun = {
    // deliberately no `version`: runtime-detection then treats us as Node
    isStandaloneExecutable: false,
    hash: bunHash,
    stringWidth,
    stripANSI,
    wrapAnsi,
    deepEquals: (a, b) => isDeepStrictEqual(a, b),
    gc(force) { if (typeof globalThis.gc === 'function') { try { globalThis.gc(force); } catch { /* noop */ } } },
    generateHeapSnapshot() {
      const v8 = require('node:v8');
      const stream = v8.getHeapSnapshot();
      const chunks = [];
      let chunk;
      while ((chunk = stream.read()) !== null) chunks.push(chunk);
      const buf = Buffer.concat(chunks.map((c) => Buffer.from(c)));
      return buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
    },
    semver: { order: cmpVer, satisfies: semverSatisfies },
    which,
    file: (p) => new BunFile(p),
    zstdDecompressSync: (buf, opts) => zstdApi('zstdDecompressSync')(buf, opts),
    zstdCompressSync: (buf, opts) => zstdApi('zstdCompressSync')(buf, opts),
    zstdDecompress: (buf, opts) => new Promise((res, rej) => zstdApi('zstdDecompress')(buf, opts ?? {}, (e, out) => (e ? rej(e) : res(out)))),
    zstdCompress: (buf, opts) => new Promise((res, rej) => zstdApi('zstdCompress')(buf, opts ?? {}, (e, out) => (e ? rej(e) : res(out)))),
    spawn: bunSpawn,
    spawnSync(cmd, opts = {}) {
      const r = spawnSync(cmd[0], cmd.slice(1), { cwd: opts.cwd, env: opts.env });
      return { success: r.status === 0, exitCode: r.status, stdout: r.stdout, stderr: r.stderr, pid: r.pid };
    },
    YAML: {
      parse: (s) => yamlLib().load(s),
      stringify: (o, _replacer, indent) => yamlLib().dump(o, { indent: typeof indent === 'number' ? indent : 2 }).replace(/\n$/, ''),
    },
    Transpiler: TranspilerStub,
    serve() { throw new Error('Bun.serve is unavailable under the Node shim (native binary required)'); },
    listen() { throw new Error('Bun.listen is unavailable under the Node shim (native binary required)'); },
    SQL: class { constructor() { throw new Error('Bun.SQL is unavailable under the Node shim (native binary required)'); } },
    stdin: new BunFile('/dev/stdin'),
    sleep: (ms) => new Promise((r) => setTimeout(r, ms)),
    sleepSync() {},
    // JSC tuning knobs: since 2.1.269 the app calls `Bun.unsafe.setJITPolicy?.(1)` behind a bare
    // `typeof Bun` check — the object must exist, its members are optional.
    unsafe: {},
    env: process.env,
    argv: process.argv,
  };
  globalThis.Bun = Bun;
  return Bun;
}
