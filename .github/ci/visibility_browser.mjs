import { chromium } from '@playwright/test';
import { spawn } from 'node:child_process';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

const delay = (milliseconds) => new Promise(resolve => setTimeout(resolve, milliseconds));
const running = process => process.pid !== undefined && process.exitCode === null && process.signalCode === null;

export async function launchVisibilityBrowser() {
  const profile = await mkdtemp(path.join(tmpdir(), 'restart_app_visibility_'));
  const process = spawn(chromium.executablePath(), [
    `--user-data-dir=${profile}`, '--remote-debugging-port=0',
    '--no-first-run', '--no-default-browser-check', '--disable-component-update',
    '--no-sandbox', 'about:blank',
  ], { stdio: ['ignore', 'ignore', 'pipe'] });
  let stderr = '';
  let startupError;
  process.stderr.on('data', chunk => { stderr = (stderr + chunk).slice(-16_384); });
  process.on('error', error => { startupError = error; });
  let browser;

  async function dispose() {
    try {
      if (browser) await browser.close();
    } finally {
      if (running(process)) process.kill('SIGTERM');
      for (let attempt = 0; attempt < 100 && running(process); attempt++) await delay(50);
      if (running(process)) process.kill('SIGKILL');
      for (let attempt = 0; attempt < 100 && running(process); attempt++) await delay(50);
      if (running(process)) throw new Error(`Owned test browser did not stop: ${process.pid}`);
      await rm(profile, { recursive: true, force: true });
    }
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
    await dispose();
    throw error;
  }
}
