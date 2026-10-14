#!/usr/bin/env node
// bundle-bunfs.mjs — rebuild ONE Node-loadable CommonJS file (bundle.cjs) from an
// extract-bun-js.py output directory.
//
//   node bundle-bunfs.mjs --extracted DIR --out bundle.cjs [--esbuild-dir DIR] [--target node20]
//
// Two layouts, detected from the manifest + entry header:
//   * monolith (Claude Code <= 2.1.241): the entry is ONE CJS factory expression
//     ("// @bun @bytecode @bun-cjs\n(function(exports, require, module, ...){...})").
//     We keep the historical transform: `export default <factory>` -> esbuild
//     --format=cjs (no bundling). The launcher then calls module.exports.default.
//   * chunks (>= 2.1.242): the entry (/$bunfs/root/cli) is an ESM module importing
//     ~1 640 sibling chunks by their VIRTUAL paths (/$bunfs/root/chunk-xxxxxxxx.js).
//     esbuild bundles the whole graph into one CJS file; a resolver plugin maps the
//     virtual paths onto the extracted bunfs/ mirror. Embedded non-JS files imported or
//     require()d by a chunk get a tiny virtual module shaped like Bun's loader would
//     export them: `text` (.md/.txt) → the file contents, `napi` (.node) → a runtime
//     require() of the virtual path (served by the launcher's patched require), anything
//     else (`file`: .zst, .asset) → the virtual path string, which the app then reads
//     through fs — remapped onto assets/ by the shim. Bare specifiers (node builtins,
//     bun:*, ws/undici/js-yaml) stay external.
//
// In both cases `using`/`await using` are lowered for the target and the output has no
// top-level ESM syntax. Bun-only `import.meta` members used by the chunks are mapped onto
// their CommonJS equivalents (2.1.258: 382 `import.meta.require("/$bunfs/root/chunk-…")`
// lazy chunk loads, 103 `import.meta.dirname`, 7 `import.meta.url`; 2.1.296 adds 7 Bun-only
// `import.meta.dir` as the built-in plugins' hooks folder) — left as `{}` by the cjs format
// they would make every lazy chunk load throw, and a missing `dir` makes the built-in plugin
// listing throw in path.join, which ends `claude -p` silently. The launcher runs the bundle
// inside a `(module, exports, require, __filename, __dirname)` wrapper, so those names exist.
//
// esbuild is resolved from --esbuild-dir (a directory holding node_modules/esbuild,
// e.g. the install work dir) or from this file's own node_modules.
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs';
import path from 'node:path';

const VFS_PREFIX = '/$bunfs/';
const MONOLITH_MARK = '@bun-cjs';
const ASSET_NS = 'bunfs-asset';
// bun.options.Loader as byte 1 of the manifest `flags` word (observed on Bun 1.3 binaries:
// 1 = js, 5 = file, 10 = napi, 13 = text).
const LOADER_NAPI = 10;
const LOADER_TEXT = 13;

const argv = process.argv.slice(2);
function opt(name, dflt) {
  const i = argv.indexOf(name);
  return i >= 0 && argv[i + 1] !== undefined ? argv[i + 1] : dflt;
}
const extracted = opt('--extracted');
const outfile = opt('--out');
const target = opt('--target', 'node20');
const esbuildDir = opt('--esbuild-dir', path.dirname(fileURLToPath(import.meta.url)));
if (!extracted || !outfile) {
  console.error('usage: bundle-bunfs.mjs --extracted DIR --out bundle.cjs [--esbuild-dir DIR] [--target node20]');
  process.exit(2);
}

const manifestFile = fs.readdirSync(extracted).find((f) => /^claude-.*\.manifest\.json$/.test(f));
if (!manifestFile) {
  console.error(`no claude-<ver>.manifest.json in ${extracted} (extract-bun-js.py output expected)`);
  process.exit(1);
}
const manifest = JSON.parse(fs.readFileSync(path.join(extracted, manifestFile), 'utf8'));
const vfsDir = path.join(extracted, 'bunfs');
const kindByName = new Map(manifest.modules.map((m) => [m.name, m.kind]));
const moduleByName = new Map(manifest.modules.map((m) => [m.name, m]));
const loaderOf = (m) => (m.flags == null ? null : (m.flags >> 8) & 0xff);
const toFs = (vpath) => path.join(vfsDir, vpath.slice(VFS_PREFIX.length));

const entryFile = toFs(manifest.entry);
if (!fs.existsSync(entryFile)) {
  console.error(`entry ${manifest.entry} missing at ${entryFile}`);
  process.exit(1);
}
const firstLine = fs.readFileSync(entryFile, { encoding: 'latin1', flag: 'r' }).split('\n', 1)[0];
const monolith = firstLine.includes(MONOLITH_MARK);

const require = createRequire(path.join(esbuildDir, 'package.json'));
const esbuild = require('esbuild');

const common = {
  outfile,
  format: 'cjs',
  platform: 'node',
  target: [target],
  logLevel: 'warning',
  legalComments: 'none',
};

let build;
if (monolith) {
  build = esbuild.build({
    ...common,
    stdin: {
      contents: 'export default ' + fs.readFileSync(entryFile, 'utf8'),
      resolveDir: path.dirname(entryFile),
      sourcefile: path.basename(entryFile) + '.mjs',
      loader: 'js',
    },
    bundle: false,
  });
} else {
  build = esbuild.build({
    ...common,
    stdin: {
      contents: `import ${JSON.stringify(manifest.entry)};\n`,
      resolveDir: vfsDir,
      sourcefile: 'entry.mjs',
      loader: 'js',
    },
    bundle: true,
    packages: 'external',
    define: {
      'import.meta.require': 'require',
      'import.meta.dirname': '__dirname',
      'import.meta.dir': '__dirname',
      'import.meta.filename': '__filename',
      'import.meta.path': '__filename',
      'import.meta.url': '__bunfs_import_meta_url',
      'import.meta.main': 'true',
    },
    banner: { js: 'var __bunfs_import_meta_url = require("node:url").pathToFileURL(__filename).href;' },
    plugins: [
      {
        name: 'bunfs',
        setup(b) {
          b.onResolve({ filter: /^\/\$bunfs\// }, (args) => {
            if (args.namespace === ASSET_NS) return { path: args.path, external: true }; // napi runtime require
            if (kindByName.get(args.path) === 'module') return { path: toFs(args.path) };
            if (moduleByName.has(args.path)) return { path: args.path, namespace: ASSET_NS };
            return { path: args.path, external: true }; // unknown virtual path: leave it to the launcher
          });
          b.onLoad({ filter: /.*/, namespace: ASSET_NS }, (args) => {
            const m = moduleByName.get(args.path);
            const loader = loaderOf(m);
            let contents;
            if (loader === LOADER_TEXT) contents = `module.exports = ${JSON.stringify(fs.readFileSync(toFs(args.path), 'utf8'))};`;
            else if (loader === LOADER_NAPI) contents = `module.exports = require(${JSON.stringify(args.path)});`;
            else contents = `module.exports = ${JSON.stringify(args.path)};`;
            return { contents, loader: 'js' };
          });
        },
      },
    ],
  });
}

build
  .then(() => {
    const size = fs.statSync(outfile).size;
    console.log(`${monolith ? 'monolith' : 'chunks'} layout -> ${outfile} (${(size / 1e6).toFixed(1)} MB, ${manifest.js_module_count} JS module(s), target ${target})`);
  })
  .catch((err) => {
    console.error(err.message || err);
    process.exit(1);
  });
