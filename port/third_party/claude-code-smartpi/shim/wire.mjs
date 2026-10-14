// Binary wire framing for the Claude Code job daemon socket.
//
//     [1 byte type][4 bytes big-endian length][payload]
//     type 1 = JSON control message, 2 = stdout bytes, 3 = stderr bytes
//
// Control messages (run request, started/queued/exit/pong/status) travel as JSON in
// a type-1 frame; agent stdout/stderr travel RAW in type-2/3 frames — no base64, so
// no +33% on the wire and no per-chunk transcode (the H3's CPU is the scarce resource).
// Daemon and client are deployed together, so there is a single protocol, no fallback.
// Bench + numbers: bench/wire-bench.mjs, bench/results/wire-framing.md.

export const T_JSON = 1, T_OUT = 2, T_ERR = 3;

export function frame(type, payload) {
  const buf = Buffer.isBuffer(payload) ? payload : Buffer.from(String(payload), 'utf8');
  const head = Buffer.allocUnsafe(5);
  head[0] = type;
  head.writeUInt32BE(buf.length, 1);
  return Buffer.concat([head, buf], 5 + buf.length);
}

export const frameJSON = (obj) => frame(T_JSON, JSON.stringify(obj));

// Streaming decoder: feed raw socket chunks, get whole frames (handles a frame split
// across reads and several frames in one read).
export function createDecoder(onFrame) {
  let buf = Buffer.alloc(0);
  return (chunk) => {
    buf = buf.length ? Buffer.concat([buf, chunk]) : chunk;
    while (buf.length >= 5) {
      const len = buf.readUInt32BE(1);
      if (buf.length < 5 + len) break;
      onFrame(buf[0], buf.subarray(5, 5 + len));
      buf = buf.subarray(5 + len);
    }
  };
}
