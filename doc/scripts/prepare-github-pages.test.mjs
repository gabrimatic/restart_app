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
