#!/usr/bin/env node

import { readdir, readFile, rm, writeFile } from 'node:fs/promises';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const [siteDir, rawBasePath] = process.argv.slice(2);

if (!siteDir || !rawBasePath) {
  console.error('Usage: prepare-github-pages.mjs <site-dir> <base-path>');
  process.exit(2);
}

const basePath = `/${rawBasePath.replace(/^\/+|\/+$/g, '')}`;

const textExtensions = new Set([
  '.css',
  '.html',
  '.js',
  '.json',
  '.svg',
  '.txt',
  '.xml',
]);

function extname(path) {
  const index = path.lastIndexOf('.');
  return index === -1 ? '' : path.slice(index);
}

async function* walk(dir) {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) {
      yield* walk(path);
    } else {
      yield path;
    }
  }
}

function rewrite(text) {
  return text.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, '')
    .replace(/((?:href|src|content|action)=")\/(?!\/)([^"\s]*)/g,
      (match, prefix, path) => path === basePath.slice(1) || path.startsWith(`${basePath.slice(1)}/`)
        ? match : `${prefix}${basePath}/${path}`)
    .replace(/url\(\/(?!\/)([^)]*)\)/g, (match, path) =>
      path.startsWith(`${basePath.slice(1)}/`) ? match : `url(${basePath}/${path})`);
}

function plainText(html) {
  const entities = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ' };
  return html.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, '')
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, '')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&(#x[0-9a-f]+|#\d+|amp|lt|gt|quot|apos|nbsp);/gi, (_, value) => {
      if (value.startsWith('#x')) return String.fromCodePoint(parseInt(value.slice(2), 16));
      if (value.startsWith('#')) return String.fromCodePoint(parseInt(value.slice(1), 10));
      return entities[value.toLowerCase()];
    }).replace(/\s+/g, ' ').trim();
}

const searchPages = [];
let changed = 0;

for await (const path of walk(siteDir)) {
  if (!textExtensions.has(extname(path))) {
    continue;
  }

  const original = await readFile(path, 'utf8');
  let updated = rewrite(original);
  if (path.endsWith('.html') && updated.includes('</body>')) {
    const route = relative(siteDir, path).replace(/\\/g, '/').replace(/index\.html$/, '');
    const title = plainText(updated.match(/<h1\b[^>]*>([\s\S]*?)<\/h1>/i)?.[1] || '');
    const body = updated.match(/<main\b[^>]*>([\s\S]*?)<\/main>/i)?.[1];
    if (title && body && route !== 'index/') {
      searchPages.push({ title, text: plainText(body), url: `${basePath}/${route}` });
    }
    updated = updated.replace('</body>', `<script defer src="${basePath}/static-docs.js" data-static-docs data-base-path="${basePath}"></script></body>`);
  }

  if (updated !== original) {
    await writeFile(path, updated);
    changed += 1;
  }
}

searchPages.sort((a, b) => a.url.localeCompare(b.url));
await writeFile(join(siteDir, 'search-index.json'), JSON.stringify(searchPages));
await writeFile(join(siteDir, 'static-docs.js'), await readFile(
  fileURLToPath(new URL('./static-docs.js', import.meta.url)), 'utf8'));

await Promise.all([
  rm(join(siteDir, '.mintignore'), { force: true }),
  rm(join(siteDir, 'serve.js'), { force: true }),
  rm(join(siteDir, 'Start Docs.command'), { force: true }),
  rm(join(siteDir, 'Start Docs.bat'), { force: true }),
  rm(join(siteDir, 'scripts'), { recursive: true, force: true }),
]);

console.log(`Prepared ${changed} exported files for ${basePath}`);
