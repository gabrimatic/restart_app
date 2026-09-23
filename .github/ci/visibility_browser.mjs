import { chromium } from '@playwright/test';
import { spawn } from 'node:child_process';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { platform, tmpdir } from 'node:os';
import path from 'node:path';

const delay = (milliseconds) => new Promise(resolve => setTimeout(resolve, milliseconds));
const running = process => process.pid !== undefined && process.exitCode === null && process.signalCode === null;

async function completesWithin(promise, milliseconds) {
  let timer;
  try {
    return await Promise.race([
      promise.then(() => true),
      new Promise(resolve => { timer = setTimeout(() => resolve(false), milliseconds); }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}

export function createOwnedBrowserCleanup(process, profile, {
  browserCloseTimeoutMs = 5000,
  gracefulTimeoutMs = 5000,
  forcedTimeoutMs = 5000,
  removeProfile = rm,
} = {}) {
  // Observe close immediately after spawn because exit can precede stdio
  // closure. Chromium descendants may still finish filesystem cleanup;
  // bounded removal retries below cover that transient activity.
  let closed = false;
  let processError;
  const close = new Promise(resolve => process.once('close', () => {
    closed = true;
    resolve();
  }));
  process.on('error', error => { processError = error; });
  let cleanup;
  return browser => cleanup ??= (async () => {
    let browserError;
    if (browser) {
      try {
        // Promise.race observes a late rejection even if the deadline wins.
        if (!await completesWithin(Promise.resolve().then(() => browser.close()), browserCloseTimeoutMs)) {
          browserError = new Error(`Timed out closing the browser connection; profile retained: ${profile}`);
        }
      } catch (error) {
        browserError = error;
      }
    }
    if (!closed && running(process)) process.kill('SIGTERM');
    if (!closed && !await completesWithin(close, gracefulTimeoutMs)) {
      if (running(process)) process.kill('SIGKILL');
      if (!await completesWithin(close, forcedTimeoutMs)) {
        throw new Error(`Owned test browser did not close process and stdio: ${process.pid}; profile retained: ${profile}`,
          { cause: processError ?? browserError });
      }
    }
    if (browserError) throw browserError;
    await removeProfile(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
  })();
}

export async function launchVisibilityBrowser() {
  const profile = await mkdtemp(path.join(tmpdir(), 'restart_app_visibility_'));
  const process = spawn(chromium.executablePath(), [
    `--user-data-dir=${profile}`, '--remote-debugging-port=0',
    '--no-first-run', '--no-default-browser-check', '--disable-component-update',
    // Xvfb has no GPU. Use Chromium's software GL driver so Flutter can
    // exercise Wasm instead of selecting its JavaScript/Canvas2D fallback.
    ...(platform() === 'linux' ? ['--use-gl=angle', '--use-angle=swiftshader'] : []),
    '--no-sandbox', 'about:blank',
  ], { stdio: ['ignore', 'ignore', 'pipe'] });
  const cleanup = createOwnedBrowserCleanup(process, profile);
  let stderr = '';
  let startupError;
  process.stderr.on('data', chunk => { stderr = (stderr + chunk).slice(-16_384); });
  process.on('error', error => { startupError = error; });
  let browser;

  async function dispose() {
    await cleanup(browser);
  }

  try {
    let port;
    for (let attempt = 0; attempt < 200; attempt++) {
      if (startupError) throw startupError;
      if (!running(process)) throw new Error(`Test browser exited before startup: ${stderr}`);
      try {
        port = (await readFile(path.join(profile, 'DevToolsActivePort'), 'utf8')).split('\n')[0];
        break;
      } catch (error) {
        if (error.code !== 'ENOENT') throw error;
      }
      await delay(100);
    }
    if (!port || !/^\d+$/.test(port)) throw new Error(`Test browser did not expose its local port: ${stderr}`);
    // Standard Playwright contexts force page focus, making hidden-tab proof
    // impossible. This default context retains the browser's real visibility.
    browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`, { noDefaults: true });
    return { browser, dispose };
  } catch (error) {
    try {
      await dispose();
    } catch (cleanupError) {
      throw new AggregateError([error, cleanupError], 'Test browser startup and cleanup both failed');
    }
    throw error;
  }
}
