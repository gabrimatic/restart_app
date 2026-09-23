import { defineConfig } from '@playwright/test';
import { existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const directory = path.dirname(fileURLToPath(import.meta.url));
const build = path.resolve(process.env.RESTART_WEB_BUILD ?? path.join(directory, '../../example/build/web'));
const mode = process.env.RESTART_WEB_MODE ?? 'js';
const headed = process.env.RESTART_WEB_HEADED === '1';
if (!['js', 'wasm'].includes(mode)) throw new Error('RESTART_WEB_MODE must be js or wasm');
if (!existsSync(path.join(build, 'index.html'))) throw new Error(`Missing web build: ${build}`);
const port = Number(process.env.RESTART_WEB_PORT ?? 8765);
if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error('Invalid RESTART_WEB_PORT');
const results = path.resolve(process.env.RESTART_WEB_RESULTS ?? path.join(tmpdir(), `restart_app_web_results_${mode}`));
const viewport = { width: 1366, height: 900 };
const mobile = { viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true };

export default defineConfig({
  testDir: directory,
  testMatch: 'web_restart.spec.mjs',
  fullyParallel: true,
  workers: 2,
  repeatEach: 3,
  retries: 0,
  timeout: 90_000,
  expect: { timeout: 45_000 },
  outputDir: path.join(results, 'artifacts'),
  reporter: [['list'], ['json', { outputFile: path.join(results, 'results.json') }]],
  metadata: { build, mode, headed, candidateArchiveSha256: process.env.RESTART_PACKAGE_SHA256 ?? null },
  use: {
    baseURL: `http://127.0.0.1:${port}`,
    headless: !headed,
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
  },
  projects: [
    { name: 'chromium-desktop', use: { browserName: 'chromium', viewport } },
    { name: 'chromium-mobile', use: { browserName: 'chromium', ...mobile } },
    ...(mode === 'js' && !headed ? [
      { name: 'webkit-desktop', use: { browserName: 'webkit', viewport } },
      { name: 'webkit-mobile', use: { browserName: 'webkit', ...mobile } },
    ] : []),
  ],
  webServer: {
    command: 'python3 -B serve_web_probe.py',
    cwd: directory,
    env: { RESTART_WEB_BUILD: build, RESTART_WEB_PORT: String(port) },
    url: `http://127.0.0.1:${port}/__restart_probe__/before.html`,
    reuseExistingServer: false,
    timeout: 30_000,
    gracefulShutdown: { signal: 'SIGTERM', timeout: 5_000 },
  },
});
