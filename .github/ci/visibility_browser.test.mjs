import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { access, mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { createOwnedBrowserCleanup } from './visibility_browser.mjs';

const delay = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));

async function within(promise, milliseconds = 5000) {
  let timer;
  try {
    return await Promise.race([promise, new Promise((resolve, reject) => {
      timer = setTimeout(() => reject(new Error('Cleanup exceeded the fixture deadline')), milliseconds);
    })]);
  } finally {
    clearTimeout(timer);
  }
}

async function fixture() {
  const root = await mkdtemp(path.join(tmpdir(), 'restart_app_visibility_cleanup_'));
  const profile = path.join(root, 'profile');
  await mkdir(path.join(profile, 'Default'), { recursive: true });
  return { root, profile };
}

function child(source, arguments_ = []) {
  return spawn(process.execPath, ['--input-type=module', '-e', source, ...arguments_],
    { stdio: ['ignore', 'ignore', 'pipe'] });
}

function inheritedStderrWriter({ root, profile }) {
  const gate = path.join(root, 'release-writer');
  const written = path.join(root, 'late-write-finished');
  const descendant = `
    import { access, writeFile } from 'node:fs/promises';
    const [gate, file, written] = process.argv.slice(1);
    const deadline = Date.now() + 10000;
    while (Date.now() < deadline) {
      try { await access(gate); break; } catch {}
      await new Promise(resolve => setTimeout(resolve, 10));
    }
    await writeFile(file, 'written after the parent exited');
    await writeFile(written, 'done');
  `;
  const process_ = child(`
    import { spawn } from 'node:child_process';
    const writer = spawn(process.execPath,
      ['--input-type=module', '-e', ${JSON.stringify(descendant)}, ...process.argv.slice(1)],
      { stdio: ['ignore', 'ignore', 'inherit'] });
    writer.unref();
  `, [gate, path.join(profile, 'Default', 'late-write'), written]);
  const closed = once(process_, 'close');
  return { process: process_, closed, written, release: () => writeFile(gate, '') };
}

test('cleanup waits for inherited stdio to close after parent exit and a late profile write', async () => {
  const files = await fixture();
  const writer = inheritedStderrWriter(files);
  let observedClose = false;
  writer.process.once('close', () => { observedClose = true; });
  const dispose = createOwnedBrowserCleanup(writer.process, files.profile, {
    gracefulTimeoutMs: 5000,
    removeProfile: async (profile, options) => {
      assert.equal(observedClose, true, 'Profile removal must follow the close event');
      assert.equal(await readFile(path.join(profile, 'Default', 'late-write'), 'utf8'),
        'written after the parent exited');
      assert.deepEqual(options, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
      await rm(profile, options);
    },
  });
  try {
    await once(writer.process, 'exit');
    assert.equal(writer.process.exitCode, 0);
    assert.equal(observedClose, false, 'The descendant still owns the stderr pipe');
    const cleanup = dispose();
    await access(files.profile);
    await writer.release();
    await within(cleanup);
    assert.equal(await readFile(writer.written, 'utf8'), 'done');
    await assert.rejects(access(files.profile), { code: 'ENOENT' });
    await within(dispose());
  } finally {
    await writer.release();
    await writer.closed;
    await rm(files.root, { recursive: true, force: true });
  }
});

test('cleanup remembers an early close event', async () => {
  const files = await fixture();
  const process_ = child('process.exit(0)');
  const dispose = createOwnedBrowserCleanup(process_, files.profile, { gracefulTimeoutMs: 100 });
  try {
    await once(process_, 'close');
    await within(dispose());
    await assert.rejects(access(files.profile), { code: 'ENOENT' });
  } finally {
    await rm(files.root, { recursive: true, force: true });
  }
});

test('cleanup escalates a resistant owned child to SIGKILL and awaits close', {
  skip: process.platform === 'win32',
}, async () => {
  const files = await fixture();
  const term = path.join(files.root, 'received-term');
  const process_ = child(`
    import { writeFileSync } from 'node:fs';
    process.on('SIGTERM', () => writeFileSync(process.argv[1], 'received'));
    process.stderr.write('ready');
    setInterval(() => {}, 1000);
  `, [term]);
  const closed = once(process_, 'close');
  const dispose = createOwnedBrowserCleanup(process_, files.profile, {
    gracefulTimeoutMs: 100, forcedTimeoutMs: 2000,
  });
  try {
    await once(process_.stderr, 'data');
    await within(dispose());
    assert.equal(await readFile(term, 'utf8'), 'received');
    assert.deepEqual(await closed, [null, 'SIGKILL']);
    await assert.rejects(access(files.profile), { code: 'ENOENT' });
  } finally {
    if (process_.exitCode === null && process_.signalCode === null) process_.kill('SIGKILL');
    await closed;
    await rm(files.root, { recursive: true, force: true });
  }
});

test('an unclosed inherited stream fails within the shutdown bounds and preserves the profile', async () => {
  const files = await fixture();
  const writer = inheritedStderrWriter(files);
  const dispose = createOwnedBrowserCleanup(writer.process, files.profile, {
    gracefulTimeoutMs: 20, forcedTimeoutMs: 20,
    removeProfile: () => { assert.fail('An unclosed child must retain its profile'); },
  });
  try {
    await once(writer.process, 'exit');
    await within(assert.rejects(dispose(), /did not close process and stdio/), 2000);
    await access(files.profile);
  } finally {
    await writer.release();
    await writer.closed;
    await rm(files.root, { recursive: true, force: true });
  }
});

test('a rejected profile removal fails cleanup after bounded retry options', async () => {
  const files = await fixture();
  const process_ = child('process.exit(0)');
  const exhausted = Object.assign(new Error('profile is still busy after retries'), { code: 'EBUSY' });
  const dispose = createOwnedBrowserCleanup(process_, files.profile, {
    removeProfile: async (profile, options) => {
      assert.equal(profile, files.profile);
      assert.equal(options.maxRetries, 5);
      assert.equal(options.retryDelay, 100);
      throw exhausted;
    },
  });
  try {
    await once(process_, 'close');
    await within(assert.rejects(dispose(), error => error === exhausted));
    await access(files.profile);
  } finally {
    await rm(files.root, { recursive: true, force: true });
  }
});

test('a stalled browser close is bounded and a late rejection is handled', async () => {
  const files = await fixture();
  const process_ = child('setInterval(() => {}, 1000)');
  const closed = once(process_, 'close');
  const dispose = createOwnedBrowserCleanup(process_, files.profile, {
    browserCloseTimeoutMs: 20, gracefulTimeoutMs: 2000,
  });
  try {
    const browser = { close: () => new Promise((resolve, reject) => {
      setTimeout(() => reject(new Error('late transport rejection')), 100);
    }) };
    await within(assert.rejects(dispose(browser), /Timed out closing the browser connection/));
    await closed;
    await access(files.profile);
    await delay(150);
  } finally {
    if (process_.exitCode === null && process_.signalCode === null) process_.kill('SIGKILL');
    await closed;
    await rm(files.root, { recursive: true, force: true });
  }
});
