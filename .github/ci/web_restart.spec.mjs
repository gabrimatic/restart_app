import { expect, test as standardTest } from '@playwright/test';
import { randomUUID } from 'node:crypto';
import { launchVisibilityBrowser } from './visibility_browser.mjs';

const mode = process.env.RESTART_WEB_MODE ?? 'js';
const headed = process.env.RESTART_WEB_HEADED === '1';
const test = headed ? standardTest.extend({
  browser: [async ({}, use) => {
    const owned = await launchVisibilityBrowser();
    try { await use(owned.browser); } finally { await owned.dispose(); }
  }, { scope: 'worker' }],
  context: async ({ browser }, use) => { await use(browser.contexts()[0]); },
  page: async ({ context, viewport }, use) => {
    const page = await context.newPage();
    if (viewport) await page.setViewportSize(viewport);
    try { await use(page); } finally { await page.close(); }
  },
}) : standardTest;
const observations = new WeakMap();
const scenarios = [
  'default', 'empty', 'hash', 'full', 'full-query', 'full-hash',
  'full-identical', 'full-remove-hash', 'full-empty-hash', 'relative',
  'relative-hash', 'relative-identical', 'relative-remove-hash', 'relative-empty-hash',
  'invalid-url',
];

function startUrl(baseURL, scenario, extra = {}) {
  const url = new URL('/probe/deep/route', baseURL);
  url.searchParams.set('case', scenario);
  url.searchParams.set('run', randomUUID());
  url.searchParams.set('value', 'spaces + unicode ü');
  for (const [key, value] of Object.entries(extra)) url.searchParams.set(key, value);
  url.hash = '/source';
  return url;
}

function destinationFor(start, scenario) {
  const url = new URL(start);
  switch (scenario) {
    case 'hash': case 'full-hash': case 'relative-hash': case 'invalid-url':
      url.hash = '/destination';
      break;
    case 'full':
      url.pathname = '/full-destination';
      break;
    case 'full-query':
      url.searchParams.set('destination', 'true');
      break;
    case 'full-remove-hash': case 'relative-remove-hash':
      url.hash = '';
      break;
    case 'full-empty-hash': case 'relative-empty-hash':
      return `${url.href.split('#')[0]}#`;
    case 'relative':
      return new URL(`relative-destination${url.search}`,
        new URL(url.searchParams.get('base') ?? '/', url)).href;
  }
  return url.href;
}

function observe(page) {
  const evidence = { pageErrors: [], consoleErrors: [], applicationResponses: [], navigations: [] };
  observations.set(page, evidence);
  page.on('pageerror', (error) => evidence.pageErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') evidence.consoleErrors.push(message.text());
  });
  page.on('response', (response) => {
    if (/\/main\.dart\.(js|mjs|wasm)$/.test(new URL(response.url()).pathname)) {
      evidence.applicationResponses.push({ url: response.url(), status: response.status(),
        contentType: response.headers()['content-type'] });
    }
  });
  page.on('framenavigated', (frame) => {
    evidence.navigations.push({ url: frame.url(), mainFrame: frame === page.mainFrame() });
  });
  return evidence;
}

function assertApplicationLoaded(evidence) {
  const application = mode === 'wasm' ? '/main.dart.wasm' : '/main.dart.js';
  const loads = evidence.applicationResponses.filter((response) =>
    new URL(response.url).pathname.endsWith(application));
  expect(loads.length, `Actual ${mode} application response`).toBeGreaterThan(0);
  expect(loads.every((response) => response.status === 200)).toBe(true);
  if (mode === 'wasm') {
    expect(loads.every((response) => response.contentType.startsWith('application/wasm'))).toBe(true);
    expect(evidence.applicationResponses.some((response) =>
      new URL(response.url).pathname.endsWith('/main.dart.js')), 'No JavaScript fallback').toBe(false);
  }
  expect(evidence.pageErrors).toEqual([]);
  expect(evidence.consoleErrors).toEqual([]);
}

async function resultText(scope) {
  const result = scope.getByText(/^(PASS |FAIL:)/).last();
  await expect(result).toBeAttached();
  const text = await result.textContent();
  expect(text, 'Built application result').not.toMatch(/^FAIL:/);
  return text;
}

function assertFreshBoot(text, start, scenario) {
  expect(text, 'Built application result').not.toMatch(/^FAIL:/);
  expect(text.startsWith(`PASS ${scenario}\n`)).toBe(true);
  const fields = Object.fromEntries(text.split('\n').slice(1).map((line) => {
    const equals = line.indexOf('=');
    return [line.slice(0, equals), line.slice(equals + 1)];
  }));
  expect(fields.run).toBe(start.searchParams.get('run'));
  expect(fields.boot).toMatch(/^\d+$/);
  expect(fields.previousBoot).toMatch(/^\d+$/);
  expect(fields.boot).not.toBe(fields.previousBoot);
  expect(Number(fields.document)).toBeGreaterThan(Number(fields.previousDocument));
  expect(fields.dirty).toBe('0');
  expect(fields.persisted).toBe('true');
  expect(fields.url).toBe(destinationFor(start, scenario));
  if (scenario === 'invalid-url') expect(fields.invalidURLRejected).toBe('true');
  return fields;
}

async function attachEvidence(testInfo, browser, evidence) {
  await testInfo.attach('restart-proof', {
    body: Buffer.from(JSON.stringify({
      browserVersion: browser.version(), buildMode: mode, project: testInfo.project.name,
      repetition: testInfo.repeatEachIndex, viewport: testInfo.project.use.viewport,
      candidateArchiveSha256: process.env.RESTART_PACKAGE_SHA256 ?? null, ...evidence,
    }, null, 2)),
    contentType: 'application/json',
  });
}

test.afterEach(async ({ page, browser }, testInfo) => {
  if (testInfo.status !== testInfo.expectedStatus && observations.has(page)) {
    await attachEvidence(testInfo, browser, observations.get(page));
  }
});

async function checkRoute({ page, browser, baseURL }, testInfo, scenario, extra = {}) {
  const start = startUrl(baseURL, scenario, extra);
  const before = new URL('/__restart_probe__/before.html', baseURL);
  before.searchParams.set('target', start.href);
  const evidence = observe(page);
  await page.goto(before.href);
  const initialHistory = await page.evaluate(() => history.length);
  await page.getByRole('link', { name: 'Open restart probe' }).click();
  const text = await resultText(page);
  const fields = assertFreshBoot(text, start, scenario);
  await expect(page).toHaveURL(fields.url);
  const finalHistory = await page.evaluate(() => history.length);
  expect(finalHistory).toBe(initialHistory + (scenario === 'hash' ? 2 : 1));
  assertApplicationLoaded(evidence);
  if (scenario === 'full-hash') {
    // The unfixed app reports failure ten seconds after falsely accepting.
    await page.waitForTimeout(10_500);
    expect(await resultText(page)).toBe(text);
    await testInfo.attach('rendered-result', { body: await page.screenshot(), contentType: 'image/png' });
  }
  await attachEvidence(testInfo, browser, { ...evidence, fields,
    initialUrl: start.href, initialHistory, finalHistory });
  await page.goBack();
  if (scenario === 'hash') {
    // Hash shorthand has always added one history entry before reloading.
    await expect(page).toHaveURL(start.href);
    await page.goBack();
  }
  await expect(page).toHaveURL(before.href);
  await expect(page.getByRole('heading', { name: 'Before restart probe' })).toBeVisible();
}

for (const scenario of scenarios) {
  test(`${scenario} recreates Dart and document state with correct history`, async ({ page, browser, baseURL }, testInfo) => {
    await checkRoute({ page, browser, baseURL }, testInfo, scenario);
  });
}

for (const scenario of ['relative', 'relative-hash', 'hash']) {
  test(`${scenario} respects a non-root document base`, async ({ page, browser, baseURL }, testInfo) => {
    await checkRoute({ page, browser, baseURL }, testInfo, scenario, { base: '/nested/base/' });
  });
}

test('unsupported modes preserve the current document and route', async ({ page, browser, baseURL }, testInfo) => {
  const start = startUrl(baseURL, 'unsupported');
  const evidence = observe(page);
  await page.goto(start.href);
  const text = await resultText(page);
  expect(text).toContain('PASS unsupported modes');
  expect(text).toContain(`run=${start.searchParams.get('run')}`);
  const document = await page.evaluate(() => performance.timeOrigin);
  await page.waitForTimeout(1_500);
  expect(await page.evaluate(() => performance.timeOrigin)).toBe(document);
  expect(await resultText(page)).toBe(text);
  await expect(page).toHaveURL(start.href);
  expect(evidence.navigations.filter((entry) => entry.mainFrame)).toHaveLength(1);
  assertApplicationLoaded(evidence);
  await attachEvidence(testInfo, browser, { ...evidence, text, document });
});

for (const scenario of ['default', 'hash', 'full-hash', 'full-remove-hash']) {
  test(`opaque-origin iframe ${scenario} restarts with parent-held state`, async ({ page, browser, baseURL }, testInfo) => {
    const start = startUrl(baseURL, scenario, { storage: 'parent' });
    const parent = new URL('/__restart_probe__/parent.html', baseURL);
    parent.searchParams.set('target', start.href);
    const evidence = observe(page);
    await page.goto(parent.href);
    await expect(page.locator('#result')).toHaveText(/^(PASS |FAIL:)/);
    const text = await page.locator('#result').textContent();
    const fields = assertFreshBoot(text, start, scenario);
    expect(await resultText(page.frameLocator('#probe'))).toBe(text);
    const parentEvidence = await page.evaluate(() => window.probeEvidence);
    expect(parentEvidence.origins.length).toBeGreaterThan(0);
    expect(parentEvidence.origins.every((origin) => origin === 'null')).toBe(true);
    expect(parentEvidence.requests.filter((request) => request.operation === 'write')).toHaveLength(1);
    expect(parentEvidence.requests.filter((request) => request.operation === 'read').length).toBeGreaterThanOrEqual(2);
    expect(await page.evaluate(() => history.length)).toBe(
      parentEvidence.historyAtRequest + (scenario === 'hash' ? 1 : 0));
    assertApplicationLoaded(evidence);
    await attachEvidence(testInfo, browser, { ...evidence, fields, parentEvidence });
  });
}

for (const scenario of headed ? ['default', 'full-hash'] : ['full-hash']) {
  const name = `${scenario === 'default' ? 'default ' : ''}restart completes across a tab switch and return`;
  test(name, async ({ page, context, browser, baseURL }, testInfo) => {
    const start = startUrl(baseURL, scenario);
    const evidence = observe(page);
    await page.goto(start.href);
    await expect(page.getByText(new RegExp(`^Restarting ${scenario}`)).last()).toBeAttached();
    const originalDocument = await page.evaluate(() => performance.timeOrigin);
    const other = await context.newPage();
    await other.goto(new URL('/__restart_probe__/before.html', baseURL).href);
    await other.bringToFront();
    if (headed) {
      await expect.poll(() => page.evaluate(() => document.visibilityState)
        .catch(() => 'navigating'), { message: 'The app must become a hidden tab' }).toBe('hidden');
    }
    const visibilityWhileAway = await page.evaluate(() => document.visibilityState);
    const documentWhenHidden = await page.evaluate(() => performance.timeOrigin);
    if (headed) expect(documentWhenHidden, 'Tab hidden before restart').toBe(originalDocument);
    await other.waitForTimeout(1_500);
    let restartedWhileHidden = false;
    if (headed) {
      await expect.poll(() => page.evaluate(() => performance.timeOrigin)
        .catch(() => 0), { message: 'The document must restart while hidden' }).toBeGreaterThan(originalDocument);
      expect(await page.evaluate(() => document.visibilityState)).toBe('hidden');
      restartedWhileHidden = true;
    }
    await page.bringToFront();
    await expect.poll(() => page.evaluate(() => document.visibilityState)
      .catch(() => 'navigating')).toBe('visible');
    const fields = assertFreshBoot(await resultText(page), start, scenario);
    assertApplicationLoaded(evidence);
    await attachEvidence(testInfo, browser, { ...evidence, fields, headed,
      playwrightBrowserDefaultsSuppressed: headed, restartedWhileHidden,
      mobileViewportOnly: headed && testInfo.project.use.isMobile === true,
      originalDocument, documentWhenHidden, visibilityWhileAway,
      visibilityOnReturn: await page.evaluate(() => document.visibilityState) });
    await other.close();
  });
}
