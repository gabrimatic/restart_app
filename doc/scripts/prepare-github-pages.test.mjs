import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { access, mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

const prepare = fileURLToPath(new URL('./prepare-github-pages.mjs', import.meta.url));

test('export preserves external URLs, installs controls and indexes actual page content', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'restart-docs-'));
  try {
    await mkdir(join(directory, 'reference'), { recursive: true });
    const page = `<html><head><script>throw new Error('hosted runtime');</script></head><body>
      <a href="/quickstart">Start</a><a href="//example.org/page">External</a>
      <img src="/_next/image.png"><link href="https://example.org/style.css">
      <main><h1>API &amp; usage</h1><p>windowProvider &lt;UIWindow&gt; &#39;selected&#39;</p></main>
      </body></html>`;
    await writeFile(join(directory, 'reference/index.html'), page);
    await writeFile(join(directory, 'style.css'), 'a{background:url(/image.png)} b{background:url(//example.org/x.png)}');
    execFileSync(process.execPath, [prepare, directory, '/restart_app']);
    const output = await readFile(join(directory, 'reference/index.html'), 'utf8');
    assert.ok(!output.includes('hosted runtime'));
    assert.ok(output.includes('href="/restart_app/quickstart"'));
    assert.ok(output.includes('href="//example.org/page"'));
    assert.ok(output.includes('href="https://example.org/style.css"'));
    assert.ok(output.includes('src="/restart_app/static-docs.js"'));
    assert.ok(output.includes('data-base-path="/restart_app"'));
    assert.equal(await readFile(join(directory, 'style.css'), 'utf8'),
      'a{background:url(/restart_app/image.png)} b{background:url(//example.org/x.png)}');
    assert.deepEqual(JSON.parse(await readFile(join(directory, 'search-index.json'), 'utf8')), [{
      title: 'API & usage', text: "API & usage windowProvider <UIWindow> 'selected'",
      url: '/restart_app/reference/',
    }]);
    execFileSync(process.execPath, [prepare, directory, '/restart_app']);
    assert.equal(await readFile(join(directory, 'reference/index.html'), 'utf8'), output,
      'Processing an export twice must not duplicate the base path or controls');
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('export rewrites quoted CSS resources and preserves URL syntax', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'restart-docs-css-'));
  const css = `a{mask:url("/icons/check.svg")}
b{background:url('/images/space (1).png')}
@font-face{src:URL( "/font.woff2" )}
c{background:url("//cdn.example/image.png")}
d{background:url('https://example.org/image.png')}
e{background:url('./relative.png')}
f{background:url('/restart_app')}`;
  try {
    await writeFile(join(directory, 'style.css'), css);
    execFileSync(process.execPath, [prepare, directory, '/restart_app']);
    const expected = css.replace('/icons/', '/restart_app/icons/')
      .replace('/images/', '/restart_app/images/')
      .replace('/font.woff2', '/restart_app/font.woff2');
    assert.equal(await readFile(join(directory, 'style.css'), 'utf8'), expected);
    execFileSync(process.execPath, [prepare, directory, '/restart_app']);
    assert.equal(await readFile(join(directory, 'style.css'), 'utf8'), expected);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('export rewrites quoted HTML attributes without changing external or prefixed URLs', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'restart-docs-html-'));
  const html = `<html><body><a HREF = "/quickstart">Start</a>
<img src='/icons/check.svg'><form action = '/submit'></form>
<meta CONTENT='/social.png'><a href='//example.org/path'>External</a>
<a href = "https://example.org/path">External</a>
<a href='/restart_app/reference'>Ready</a><span data-src='/unrelated'>Data</span>
</body></html>`;
  try {
    await writeFile(join(directory, 'index.html'), html);
    execFileSync(process.execPath, [prepare, directory, '/restart_app']);
    const output = await readFile(join(directory, 'index.html'), 'utf8');
    for (const value of ['HREF = "/restart_app/quickstart"', "src='/restart_app/icons/check.svg'",
      "action = '/restart_app/submit'", "CONTENT='/restart_app/social.png'",
      "href='//example.org/path'", 'href = "https://example.org/path"',
      "href='/restart_app/reference'", "data-src='/unrelated'"]) assert.ok(output.includes(value), value);
    execFileSync(process.execPath, [prepare, directory, '/restart_app']);
    assert.equal(await readFile(join(directory, 'index.html'), 'utf8'), output);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('search indexing decodes uppercase hex and replaces invalid Unicode entities', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'restart-docs-entities-'));
  try {
    await writeFile(join(directory, 'index.html'),
      '<html><body><main><h1>&#X1F600; &#x41; &#66; &AMP; &#0; &#x110000; &#xD800;</h1></main></body></html>');
    execFileSync(process.execPath, [prepare, directory, '/restart_app']);
    assert.deepEqual(JSON.parse(await readFile(join(directory, 'search-index.json'), 'utf8')), [{
      title: '😀 A B & � � �', text: '😀 A B & � � �', url: '/restart_app/',
    }]);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('discovery resources contain actual pages and preserve source examples', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'restart-docs-discovery-'));
  const site = join(directory, 'site');
  const source = join(directory, 'source');
  const base = '/nested/docs';
  const page = (title, description, markdown) => `<html><head>
    <meta content="${description}" name='description'>
    <link rel="alternate" type="application/xml" href="/sitemap.xml">
    <link rel="alternate" type="text/markdown" href="/${markdown}">
    </head><body><blockquote data-agent-docs-index="true"><a href="/llms.txt">Index</a></blockquote>
    <main><h1>${title}</h1><p>Rendered content.</p></main></body></html>`;
  const code = '```dart\nfinal sample = "[literal](/unchanged/)";\n```';
  const longerFence = '````markdown\n```\n[literal](/unchanged/)\n```\n````';
  const inlineCode = '`[literal](/unchanged/)`';
  try {
    await mkdir(join(site, 'reference/api&tips'), { recursive: true });
    await mkdir(join(site, 'index'), { recursive: true });
    await mkdir(join(site, 'unavailable'), { recursive: true });
    await mkdir(join(source, 'reference'), { recursive: true });
    await writeFile(join(source, 'docs.json'), JSON.stringify({
      name: 'Example docs', description: 'A small documentation site.',
      footer: { socials: { github: 'https://github.com/example/docs' } },
    }));
    await writeFile(join(source, 'index.mdx'), `---\ntitle: Source title\n---\n
[API](/reference/api&tips/#details), [ready](/nested/docs/reference/api&tips/),
[external](https://example.net/guide), [CDN](//cdn.example/guide).

${code}

${longerFence}

${inlineCode} and [API](/reference/api&tips/).

[reference]: /reference/api&tips/#details "API reference"
`);
    await writeFile(join(source, 'reference/api&tips.mdx'),
      '---\ntitle: API\n---\n\n## Details\n\nThe actual source body.\n');
    const home = page('Getting started', 'Install &amp; configure.', 'index.md');
    await writeFile(join(site, 'index.html'), home);
    await writeFile(join(site, 'index/index.html'), home);
    await writeFile(join(site, 'reference/api&tips/index.html'),
      page('API [A] &amp; tips', 'Inputs &quot;and&quot; results.', 'reference/api&tips.md'));
    await writeFile(join(site, 'unavailable/index.html'),
      page('No source', 'This page has only an HTML export.', 'unavailable.md'));

    execFileSync(process.execPath, [prepare, site, `${base}/`, source]);
    const index = await readFile(join(site, 'llms.txt'), 'utf8');
    assert.match(index, /^# Example docs\n\n> A small documentation site\./);
    assert.ok(index.includes('- [Getting started](https://example.github.io/nested/docs/index.md): Install & configure.'));
    assert.ok(index.includes('- [API \\[A\\] & tips](https://example.github.io/nested/docs/reference/api&tips.md): Inputs "and" results.'));
    assert.ok(index.includes('- [No source](https://example.github.io/nested/docs/unavailable/):'));
    assert.equal((index.match(/^- \[/gm) || []).length, 3, 'The duplicate index route is omitted');

    const markdown = await readFile(join(site, 'index.md'), 'utf8');
    assert.match(markdown, /^# Getting started\n\n> Install & configure\./);
    assert.ok(markdown.includes('[API](https://example.github.io/nested/docs/reference/api&tips/#details)'));
    assert.ok(markdown.includes('[ready](https://example.github.io/nested/docs/reference/api&tips/)'));
    assert.ok(markdown.includes('[external](https://example.net/guide)'));
    assert.ok(markdown.includes('[CDN](//cdn.example/guide)'));
    assert.ok(markdown.includes(code), 'Fenced code must stay byte-identical');
    assert.ok(markdown.includes(longerFence), 'A shorter fence inside an example cannot end the block');
    assert.ok(markdown.includes(`${inlineCode} and [API](https://example.github.io/nested/docs/reference/api&tips/).`),
      'Inline code stays unchanged beside a rewritten link');
    assert.ok(markdown.includes('[reference]: https://example.github.io/nested/docs/reference/api&tips/#details "API reference"'));
    assert.ok(!markdown.includes('Source title'), 'Frontmatter is replaced with the exported page metadata');
    assert.ok((await readFile(join(site, 'reference/api&tips.md'), 'utf8')).includes('The actual source body.'));

    const sitemap = await readFile(join(site, 'sitemap.xml'), 'utf8');
    assert.ok(sitemap.includes('xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"'));
    assert.deepEqual([...sitemap.matchAll(/<loc>(.*?)<\/loc>/g)].map(match => match[1]), [
      'https://example.github.io/nested/docs/',
      'https://example.github.io/nested/docs/reference/api&amp;tips/',
      'https://example.github.io/nested/docs/unavailable/',
    ]);
    const missing = await readFile(join(site, 'unavailable/index.html'), 'utf8');
    assert.ok(!missing.includes('type="text/markdown"'), 'Do not advertise unavailable Markdown');

    const generated = ['llms.txt', 'sitemap.xml', 'index.md', 'reference/api&tips.md'];
    const pages = ['index.html', 'index/index.html', 'reference/api&tips/index.html', 'unavailable/index.html'];
    for (const file of pages) {
      const html = await readFile(join(site, file), 'utf8');
      const resources = [...html.matchAll(/href="([^\"]+\.(?:xml|md|txt))"/g)]
        .map(match => match[1].replaceAll('&amp;', '&'));
      assert.ok(resources.includes(`${base}/llms.txt`));
      assert.ok(resources.includes(`${base}/sitemap.xml`));
      for (const resource of resources) {
        assert.ok(resource.startsWith(`${base}/`));
        await access(join(site, resource.slice(base.length + 1)));
      }
    }
    const before = await Promise.all([...generated, ...pages].map(file => readFile(join(site, file), 'utf8')));
    execFileSync(process.execPath, [prepare, site, base, source]);
    assert.deepEqual(await Promise.all([...generated, ...pages].map(file => readFile(join(site, file), 'utf8'))), before);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('discovery URLs also work at the site root', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'restart-docs-root-'));
  try {
    await writeFile(join(directory, 'index.html'), '<html><body><main><h1>Home</h1></main></body></html>');
    execFileSync(process.execPath, [prepare, directory, '/']);
    const pages = JSON.parse(await readFile(join(directory, 'search-index.json'), 'utf8'));
    assert.equal(pages[0].url, '/');
    const sitemap = await readFile(join(directory, 'sitemap.xml'), 'utf8');
    assert.ok(sitemap.includes('<loc>https://gabrimatic.github.io/</loc>'));
    const html = await readFile(join(directory, 'index.html'), 'utf8');
    assert.ok(html.includes('src="/static-docs.js"'));
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
