#!/usr/bin/env node
// Launcher: runs the extracted Claude Code bundle (Bun standalone JS) under Node.js with a
// Bun API shim AND a persisted V8 bytecode cache.
//
// The 26 MB bundle's parse+compile is the bulk of cold start (~6.8 s on the H3, ~80% of the
// launch). We load it through vm.Script with a saved bytecode cache (produceCachedData /
// cachedData): the first launch compiles once and writes the cache; every launch after skips
// compilation entirely (~0 ms). Measured on the Smart Pi One: --version 8.4 s → 2.9 s.
//
// The bundle is CJS (esbuild --format=cjs, which also lowers the `import.meta` the app uses —
// the reason the old ESM wrapper existed). Two shapes, both produced by shim/bundle-bunfs.mjs:
//   * <= 2.1.241 (monolith): module.exports.default is the Claude CJS factory → we call it.
//   * >= 2.1.242 (ESM chunks bundled by esbuild): the app runs when the bundle is evaluated;
//     nothing is exported, so there is nothing more to call.
//
// Cache validity is automatic: the whole $LIB is replaced on update (VERSION changes → cache
// gone → rebuilt), and V8 rejects a cache built by a different engine (Node upgrade →
// cachedDataRejected → rebuilt). No stale-cache risk. The cache is written next to the bundle
// when writable (shared, primed at install time), else under ~/.cache/claude-code (per-user).
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { Script } from 'node:vm';
import os from 'node:os';
import path from 'node:path';
import { installBunShim, BUNFS_ROOT, requireBunfs } from './bun-shim.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

process.env.DISABLE_AUTOUPDATER ??= '1';

installBunShim();

// cli.js is the require base + the __filename the app sees (unchanged); bundle.cjs is the
// executable source we compile/cache.
const appPath = path.join(__dirname, 'cli.js');
const bundlePath = path.join(__dirname, 'bundle.cjs');
const src = readFileSync(bundlePath, 'utf8');
// Wrap so vm can inject (module, exports, require, __filename, __dirname). This string MUST be
// byte-identical on every launch or the bytecode cache is rejected.
const wrapped = '(function(module,exports,require,__filename,__dirname){' + src + '\n})';

let version = 'x';
try { version = (readFileSync(path.join(__dirname, 'VERSION'), 'utf8').trim() || 'x'); } catch { /* dev */ }
const sharedCache = path.join(__dirname, 'bundle.v8cache');
const userCache = path.join(os.homedir?.() || '/tmp', '.cache', 'claude-code', `bundle-${version}.v8cache`);

function loadCached(file) {
  let data;
  try { data = readFileSync(file); } catch { return null; }
  const s = new Script(wrapped, { filename: appPath, cachedData: data });
  return s.cachedDataRejected ? null : s;   // stale engine/version → force a rebuild
}
function persist(file, data) {
  try { mkdirSync(path.dirname(file), { recursive: true }); writeFileSync(file, data); return true; }
  catch { return false; }
}

let script = loadCached(sharedCache) || loadCached(userCache);
if (!script) {
  const produced = new Script(wrapped, { filename: appPath, produceCachedData: true }).cachedData;
  if (produced && !persist(sharedCache, produced)) persist(userCache, produced);
  script = new Script(wrapped, { filename: appPath, cachedData: produced });
}

// require patching: Bun-only modules throw MODULE_NOT_FOUND, embedded /$bunfs/root files map
// to the local assets/ dir (same mapping as the shim's fs remap — one source: bun-shim.mjs).
const baseRequire = createRequire(appPath);
function patchedRequire(id) {
  if (typeof id === 'string') {
    if (id.startsWith('bun:')) {
      const e = new Error(`Cannot find module '${id}' (Bun-only, Node shim)`);
      e.code = 'MODULE_NOT_FOUND';
      throw e;
    }
    if (id.startsWith(BUNFS_ROOT)) {
      try {
        return requireBunfs(id, baseRequire);
      } catch (cause) {
        const e = new Error(`Cannot find embedded module '${id}' (asset not extracted)`, { cause });
        e.code = 'MODULE_NOT_FOUND';
        throw e;
      }
    }
  }
  return baseRequire(id);
}
patchedRequire.resolve = baseRequire.resolve.bind(baseRequire);
patchedRequire.cache = baseRequire.cache;
patchedRequire.main = undefined;

// Run the outer CJS wrapper. Monolith bundles export the Claude factory as
// module.exports.default: invoke it exactly as the old launcher did (same this, same require,
// same argv/filename). Chunked bundles (>= 2.1.242) already ran the app at this point.
const outerFn = script.runInThisContext();
const outerModule = { exports: {} };
outerFn(outerModule, outerModule.exports, patchedRequire, appPath, __dirname);
const factory = (outerModule.exports && outerModule.exports.default) || outerModule.exports;

if (typeof factory === 'function') {
  const mod = { exports: {}, filename: appPath, id: '.', loaded: false };
  factory.call(mod.exports, mod.exports, patchedRequire, mod, appPath, path.dirname(appPath));
}
