#!/usr/bin/env node

import { mkdir, readdir, readFile, rm, writeFile } from 'node:fs/promises';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const [siteDir, rawBasePath, sourceDir = fileURLToPath(new URL('../', import.meta.url))] = process.argv.slice(2);

if (!siteDir || !rawBasePath) {
  console.error('Usage: prepare-github-pages.mjs <site-dir> <base-path> [docs-source-dir]');
  process.exit(2);
}

const trimmedBasePath = rawBasePath.replace(/^\/+|\/+$/g, '');
const basePath = trimmedBasePath ? `/${trimmedBasePath}` : '';
const config = JSON.parse(await readFile(join(sourceDir, 'docs.json'), 'utf8'));
const repository = new URL(config.footer.socials.github);
const owner = repository.pathname.split('/')[1];
if (repository.hostname !== 'github.com' || !/^[a-z\d-]+$/i.test(owner)) {
  throw new Error('docs.json must identify the GitHub repository hosting these Pages docs');
}
const publicOrigin = `https://${owner.toLowerCase()}.github.io`;

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
    .replace(/(\s(?:href|src|content|action)\s*=\s*)(["'])(\/(?!\/)[^"']*)\2/gi,
      (match, prefix, quote, path) => path === basePath || path.startsWith(`${basePath}/`)
        ? match : `${prefix}${quote}${basePath}${path}${quote}`)
    .replace(/url\(\s*(?:"(\/(?!\/)[^"]*)"|'(\/(?!\/)[^']*)'|(\/(?!\/)[^)\s]*))\s*\)/gi,
      (match, doubleQuoted, singleQuoted, unquoted) => {
        const path = doubleQuoted ?? singleQuoted ?? unquoted;
        return path === basePath || path.startsWith(`${basePath}/`)
          ? match : match.replace(path, () => `${basePath}${path}`);
      });
}

function plainText(html) {
  const entities = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ' };
  return html.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, '')
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, '')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&(#x[0-9a-f]+|#\d+|amp|lt|gt|quot|apos|nbsp);/gi, (_, value) => {
      if (value.startsWith('#')) {
        const hexadecimal = value.slice(0, 2).toLowerCase() === '#x';
        const point = parseInt(value.slice(hexadecimal ? 2 : 1), hexadecimal ? 16 : 10);
        return point > 0 && point <= 0x10ffff && !(point >= 0xd800 && point <= 0xdfff)
          ? String.fromCodePoint(point) : '\uFFFD';
      }
      return entities[value.toLowerCase()];
    }).replace(/\s+/g, ' ').trim();
}

function attributes(tag) {
  return Object.fromEntries([...tag.matchAll(/\b([\w-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/g)]
    .map(([, name, doubleQuoted, singleQuoted, unquoted]) =>
      [name.toLowerCase(), plainText(doubleQuoted ?? singleQuoted ?? unquoted)]));
}

function description(html) {
  for (const match of html.matchAll(/<meta\b[^>]*>/gi)) {
    const values = attributes(match[0]);
    if (values.name?.toLowerCase() === 'description') return values.content || '';
  }
  return '';
}

function escapeXml(value) {
  return value.replace(/[&<>"']/g, character =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' })[character]);
}

function escapeLabel(value) {
  return value.replace(/[\\[\]]/g, '\\$&');
}

function publicUrl(path) {
  const prefixed = path === basePath || path.startsWith(`${basePath}/`)
    ? path : `${basePath}${path}`;
  return `${publicOrigin}${prefixed}`;
}

function markdownLinks(text) {
  // The source pages use ordinary Markdown. Leave code examples untouched while
  // making documentation links work when the Markdown is fetched on its own.
  let fence;
  return text.split(/(?<=\n)/).map(line => {
    const marker = line.match(/^ {0,3}(`{3,}|~{3,})/);
    if (fence) {
      if (marker && marker[1][0] === fence[0] && marker[1].length >= fence.length
          && line.slice(marker[0].length).trim() === '') fence = undefined;
      return line;
    }
    if (marker) {
      fence = marker[1];
      return line;
    }
    return line.replace(/(`+)([\s\S]*?)\1(?!`)|\]\((<?)(\/(?!\/)[^\s)>]+)(>?)/g,
      (match, codeDelimiter, code, opening, path, closing) => codeDelimiter
        ? match : `](${opening}${publicUrl(path)}${closing}`)
      .replace(/^( {0,3}\[[^\]]+\]:\s*<?)(\/(?!\/)[^\s>]+)(>?)/,
        (_, prefix, path, suffix) => `${prefix}${publicUrl(path)}${suffix}`);
  }).join('');
}

function pageMarkdown(source, title, summary) {
  const body = source.replace(/^\uFEFF?---\r?\n[\s\S]*?\r?\n---(?:\r?\n|$)/, '').trim();
  return `# ${title}\n\n${summary ? `> ${summary}\n\n` : ''}${markdownLinks(body)}\n`;
}

function alternateLinks(html, markdownPath) {
  return html.replace(/<link\b[^>]*>/gi, tag => {
    const values = attributes(tag);
    if (!values.rel?.toLowerCase().split(/\s+/).includes('alternate')) return tag;
    if (values.type?.toLowerCase() === 'text/markdown') {
      return markdownPath
        ? `<link rel="alternate" type="text/markdown" href="${escapeXml(`${basePath}/${markdownPath}`)}">`
        : '';
    }
    if (values.type?.toLowerCase() === 'application/xml') {
      return `<link rel="alternate" type="application/xml" href="${escapeXml(`${basePath}/sitemap.xml`)}">`;
    }
    return tag;
  });
}

const searchPages = [];
const discoveryPages = [];
const markdownPages = new Map();
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
    const summary = description(updated);
    let markdownPath;
    if (title && body) {
      const sourceRoute = route.replace(/\/$/, '') || 'index';
      try {
        const source = await readFile(join(sourceDir, `${sourceRoute}.mdx`), 'utf8');
        markdownPath = `${sourceRoute}.md`;
        markdownPages.set(markdownPath, pageMarkdown(source, title, summary));
      } catch (error) {
        if (error.code !== 'ENOENT') throw error;
      }
    }
    updated = alternateLinks(updated, markdownPath);
    if (title && body && route !== 'index/') {
      searchPages.push({ title, text: plainText(body), url: `${basePath}/${route}` });
      discoveryPages.push({ title, summary, url: `${basePath}/${route}`, markdownPath });
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
for (const [path, markdown] of markdownPages) {
  await mkdir(dirname(join(siteDir, path)), { recursive: true });
  await writeFile(join(siteDir, path), markdown);
}
discoveryPages.sort((a, b) => a.url.localeCompare(b.url));
const sitemap = discoveryPages.map(page => `  <url><loc>${escapeXml(publicUrl(page.url))}</loc></url>`);
await writeFile(join(siteDir, 'sitemap.xml'),
  `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${sitemap.join('\n')}\n</urlset>\n`);
const indexLinks = discoveryPages.map(page => {
  const url = publicUrl(page.markdownPath ? `/${page.markdownPath}` : page.url);
  return `- [${escapeLabel(page.title)}](${url})${page.summary ? `: ${page.summary}` : ''}`;
});
await writeFile(join(siteDir, 'llms.txt'),
  `# ${plainText(config.name)}\n\n${config.description ? `> ${plainText(config.description)}\n\n` : ''}## Documentation\n\n${indexLinks.join('\n')}\n`);
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
