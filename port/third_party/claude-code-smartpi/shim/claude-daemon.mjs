#!/usr/bin/env node
// Claude Code job daemon for the Smart Pi One — bounded-concurrency supervisor for
// HEADLESS runs (`claude -p …` / piped stdin). It exists to let a small board accept
// many agent jobs without ever holding more than a few heavy runtimes resident:
//
//   * one warm coordinator process (this file), ~1 isolat, negligible RAM;
//   * a SEMAPHORE of CLAUDE_MAX_CONCURRENT live `node claude.mjs` children;
//   * a FIFO QUEUE for everything above the cap — a queued job costs ~0 until it runs.
//
// Because an agent spends its wall-clock waiting on the API (I/O-bound), the K live
// slots cycle quickly, so N≫K queued jobs still drain at a useful rate. RAM stays
// bounded to K × (per-process RSS), which is the only thing a 1 GB board cares about.
//
// Lifecycle: NO systemd, NO boot cost. The client lazy-spawns this on first headless
// job; when the queue is empty and no child runs for CLAUDE_IDLE_MS, it exits and
// removes its socket. A board that never runs a batch never pays for the daemon.
//
// Interactive `claude` (full TUI) never comes here — it stays a direct process (one
// TTY = one runtime), routed by the wrapper.
import net from 'node:net';
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { frame, frameJSON, createDecoder, T_JSON, T_OUT, T_ERR } from './wire.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const LAUNCHER  = path.join(__dirname, 'claude.mjs');          // the in-process launcher we supervise
// The child command for one job. Default: run our launcher under Node. Override with
// CLAUDE_CHILD (e.g. "claude" to supervise the installed wrapper, or a pinned version).
const CHILD     = (process.env.CLAUDE_CHILD || `${process.execPath} ${LAUNCHER}`).split(' ').filter(Boolean);
const SOCK      = process.env.CLAUDE_SOCK || defaultSock();
const MAX       = Math.max(1, Number(process.env.CLAUDE_MAX_CONCURRENT || 3));
const IDLE_MS   = Number(process.env.CLAUDE_IDLE_MS || 5 * 60_000);
const CPUS      = process.env.CLAUDE_CPUS || '0,1,2,3';
const log = (...a) => process.env.CLAUDE_DAEMON_DEBUG && console.error('[claude-daemon]', ...a);

function defaultSock() {
  const dir = process.env.XDG_RUNTIME_DIR || '/tmp';
  return path.join(dir, `claude-daemon-${process.getuid?.() ?? 'x'}.sock`);
}

let running = 0;              // live children
const queue = [];            // pending {req, sock, send}
let idleTimer = null;
let server;

function armIdle() { clearTimeout(idleTimer); idleTimer = setTimeout(shutdown, IDLE_MS); }
function shutdown() {
  if (running > 0 || queue.length > 0) { armIdle(); return; }   // race guard
  log('idle → exit');
  server.close(() => { try { fs.unlinkSync(SOCK); } catch {} process.exit(0); });
}

// Spawn one headless child, stream its output back over the socket, forward stdin & exit.
function startJob(job) {
  running++; clearTimeout(idleTimer);
  const { req, sock, send } = job;
  const base = [...CHILD, ...(req.args || [])];              // e.g. node claude.mjs -p "…"
  const hasTaskset = fs.existsSync('/usr/bin/taskset');
  const cmd  = hasTaskset ? 'taskset' : base[0];            // pin the board's cores when available
  const args = hasTaskset ? ['-c', CPUS, 'nice', '-n', '5', ...base] : base.slice(1);
  log('spawn', running + '/' + MAX, req.args);
  const child = spawn(cmd, args, {
    cwd: req.cwd || process.cwd(),
    env: { ...process.env, ...(req.env || {}) },
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  send({ type: 'started', running, max: MAX });
  if (req.stdin) { child.stdin.write(req.stdin); }
  child.stdin.end();
  child.stdout.on('data', (d) => { try { sock.write(frame(T_OUT, d)); } catch {} });   // raw, no base64
  child.stderr.on('data', (d) => { try { sock.write(frame(T_ERR, d)); } catch {} });
  child.on('close', (code) => {
    send({ type: 'exit', code: code ?? 0 });
    try { sock.end(); } catch {}
    running--;
    pump();                                    // a slot freed → pull the next queued job
    if (running === 0 && queue.length === 0) armIdle();
  });
  child.on('error', (e) => { send({ type: 'exit', code: 127, error: String(e) }); try { sock.end(); } catch {} running--; pump(); });
}

function pump() { while (running < MAX && queue.length) startJob(queue.shift()); }

function onConn(sock) {
  clearTimeout(idleTimer);
  const send = (msg) => { try { sock.write(frameJSON(msg)); } catch {} };
  const decode = createDecoder((type, payload) => {
    if (type !== T_JSON) return;                              // the client only sends control frames
    let req; try { req = JSON.parse(payload.toString('utf8')); } catch { return; }
    if (req.cmd === 'ping')   { send({ type: 'pong', running, max: MAX, queued: queue.length }); return; }
    if (req.cmd === 'status') { send({ type: 'status', running, max: MAX, queued: queue.length }); sock.end(); return; }
    if (req.cmd === 'run') {
      const job = { req, sock, send };
      if (running < MAX) startJob(job);
      else { queue.push(job); send({ type: 'queued', position: queue.length, running, max: MAX }); }
    }
  });
  sock.on('data', decode);
  sock.on('error', () => {});
}

function start() {
  server = net.createServer(onConn);
  server.on('error', (e) => {
    if (e.code !== 'EADDRINUSE') throw e;
    const probe = net.connect(SOCK);
    probe.on('connect', () => { probe.end(); log('daemon already live → exit'); process.exit(0); });
    probe.on('error', () => { try { fs.unlinkSync(SOCK); } catch {} server.listen(SOCK); });  // stale → reclaim
  });
  server.listen(SOCK, () => { log('listening', SOCK, 'MAX=' + MAX); armIdle(); });
}
for (const sig of ['SIGTERM', 'SIGINT']) process.on(sig, () => shutdown());
start();
