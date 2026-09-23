import { defineConfig } from '@playwright/test';
import { existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const directory = path.dirname(fileURLToPath(import.meta.url));
const site = path.resolve(process.env.RESTART_DOCS_SITE ?? path.join(directory, '../../_site'));
if (!existsSync(path.join(site, 'index.html'))) throw new Error(`Missing exported documentation: ${site}`);
const results = path.resolve(process.env.RESTART_DOCS_RESULTS ?? path.join(tmpdir(), 'restart_app_docs_results'));
const port = Number(process.env.RESTART_DOCS_PORT ?? 8768);
if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error('Invalid RESTART_DOCS_PORT');

export default defineConfig({
  testDir: directory,
  testMatch: 'docs_export.spec.mjs',
  fullyParallel: true,
  workers: 2,
  retries: 0,
  timeout: 30_000,
  outputDir: path.join(results, 'artifacts'),
  reporter: [['list'], ['json', { outputFile: path.join(results, 'results.json') }]],
  use: {
    browserName: 'chromium',
    baseURL: `http://127.0.0.1:${port}/restart_app/`,
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
  },
  projects: [
    { name: 'desktop', use: { viewport: { width: 1440, height: 1000 } } },
    { name: 'mobile', use: { viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true } },
  ],
  webServer: {
    command: 'python3 -B serve_docs_export.py',
    cwd: directory,
    env: { RESTART_DOCS_SITE: site, RESTART_DOCS_PORT: String(port) },
    url: `http://127.0.0.1:${port}/restart_app/`,
    reuseExistingServer: false,
    gracefulShutdown: { signal: 'SIGTERM', timeout: 5_000 },
  },
});
