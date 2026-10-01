import { build } from 'esbuild';
import { mkdir, copyFile, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
const out = path.resolve('../../Resources/NotesEditor');
await mkdir(out, { recursive: true });
const result = await build({ entryPoints: ['editor.js'], outfile: `${out}/editor.js`, bundle: true,
  format: 'iife', platform: 'browser', target: 'safari17', minify: true, metafile: true, legalComments: 'eof' });
for (const file of ['index.html', 'editor.css']) await copyFile(file, `${out}/${file}`);
// Include the licenses of every package that contributes code to the vendored bundle.
const packages = new Set(Object.keys(result.metafile.inputs).flatMap(file => {
  const match = file.match(/node_modules\/((?:@[^/]+\/)?[^/]+)\//); return match ? [match[1]] : [];
}));
let notices = 'MacToys Notes uses Milkdown and the following open-source packages.\n\n';
for (const name of [...packages].sort()) {
  const root = `node_modules/${name}`;
  const pkg = JSON.parse(await readFile(`${root}/package.json`, 'utf8'));
  let license;
  for (const file of ['LICENSE', 'LICENSE.md', 'LICENSE-MIT', 'license', 'license.md', 'LICENSE.txt']) {
    try { license = await readFile(`${root}/${file}`, 'utf8'); break; } catch {}
  }
  if (!license) throw new Error(`Missing license: ${name}`);
  notices += `--- ${name} ${pkg.version} (${pkg.license}) ---\n${license}\n\n`;
}
await writeFile(`${out}/THIRD-PARTY-NOTICES.txt`, notices.trimEnd() + "\n");
console.log(`Bundled offline Notes editor (${Math.round(Object.values(result.metafile.outputs)[0].bytes / 1024) || 'see output'} KiB).`);
