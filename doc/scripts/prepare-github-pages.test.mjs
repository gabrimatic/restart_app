import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
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
