#!/usr/bin/env node
// Thin client for the Claude Code job daemon. The wrapper routes HEADLESS runs here
// (`claude -p …` / piped stdin) only when CLAUDE_DAEMON=1; interactive stays direct.
//
// It connects to the daemon's Unix socket; if none is listening it lazy-spawns the
// daemon (detached) and waits for it. Then it streams one job and mirrors the child's
// stdout/stderr to this terminal, exiting with the child's code. No boot service.
import net from 'node:net';
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { frameJSON, createDecoder, T_JSON, T_OUT, T_ERR } from './wire.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DAEMON = path.join(__dirname, 'claude-daemon.mjs');
const SOCK   = process.env.CLAUDE_SOCK ||
  path.join(process.env.XDG_RUNTIME_DIR || '/tmp', `claude-daemon-${process.getuid?.() ?? 'x'}.sock`);

const connect = () => new Promise((res, rej) => {
  const s = net.connect(SOCK);
  s.once('connect', () => res(s));
  s.once('error', rej);
});
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function spawnDaemon() {
  spawn(process.execPath, [DAEMON], { detached: true, stdio: 'ignore', env: process.env }).unref();
}

async function getConn() {
  try { return await connect(); } catch {}
  spawnDaemon();
  for (let i = 0; i < 50; i++) { try { return await connect(); } catch { await sleep(100); } }
  throw new Error('claude daemon unreachable');
}

// Read all of stdin when piped (the headless prompt), else nothing.
async function readStdin() {
  if (process.stdin.isTTY) return '';
  const chunks = [];
  for await (const c of process.stdin) chunks.push(c);
  return Buffer.concat(chunks).toString('utf8');
}

const stdinData = await readStdin();
const sock = await getConn();
sock.write(frameJSON({ cmd: 'run', args: process.argv.slice(2), cwd: process.cwd(), stdin: stdinData || undefined }));

const decode = createDecoder((type, payload) => {
  if (type === T_OUT) { process.stdout.write(payload); return; }        // raw bytes straight through
  if (type === T_ERR) { process.stderr.write(payload); return; }
  if (type !== T_JSON) return;
  let m; try { m = JSON.parse(payload.toString('utf8')); } catch { return; }
  if (m.type === 'exit') process.exitCode = m.code || 0;
  else if (m.type === 'queued' && process.env.CLAUDE_DAEMON_DEBUG)
    process.stderr.write(`[queued #${m.position}, ${m.running}/${m.max} running]\n`);
});
sock.on('data', decode);
sock.on('close', () => process.exit(process.exitCode || 0));
sock.on('error', (e) => { process.stderr.write(`claude daemon error: ${e.message}\n`); process.exit(1); });
