import { test, expect } from '@playwright/test';

const pages = [
  ['', 'Flutter app restarts'], ['quickstart/', 'Quickstart'], ['agent-skills/', 'AI agent skills'],
  ['product/platform-behavior/', 'Platform behavior'], ['product/ios-engine-restart/', 'iOS engine restart'],
  ['product/background-isolates/', 'Background isolates'], ['reference/api/', 'API reference'],
  ['reference/configuration/', 'Configuration'], ['reference/linux/', 'Linux'],
];

test('advertised documentation indexes and Markdown pages are available', async ({ page, request }) => {
  for (const [route, heading] of pages) {
    await page.goto(route || './');
    const alternatives = await page.locator('link[rel="alternate"]').evaluateAll(links =>
      links.map(link => ({ type: link.type, href: link.href })));
    expect(alternatives.map(link => link.type).sort()).toEqual(['application/xml', 'text/markdown']);
    for (const alternative of alternatives) {
      const response = await request.get(alternative.href);
      expect(response.ok(), alternative.href).toBe(true);
      const body = await response.text();
      if (alternative.type === 'text/markdown') {
        expect(body).toContain(heading);
        expect(body).not.toContain('<!DOCTYPE html>');
      } else {
        expect(body).toContain('<urlset');
        expect(body.match(/<loc>/g)).toHaveLength(pages.length);
      }
    }
    const indexLink = await page.locator('[data-agent-docs-index] a').getAttribute('href');
    expect(indexLink).toBe('/restart_app/llms.txt');
    const index = await request.get(indexLink);
    expect(index.ok()).toBe(true);
    const indexText = await index.text();
    for (const [, title] of pages) expect(indexText).toContain(title);
  }
});

for (const theme of ['light', 'dark']) {
  test(`theme ${theme}: visible icon, toggle and saved preference`, async ({ page }, info) => {
    await page.emulateMedia({ colorScheme: theme });
    await page.goto('./');
    await expect(page.locator('html')).toHaveAttribute('data-theme-preference', theme);
    // A desktop-only control still needs a visible SVG whenever it is displayed.
    const icon = page.locator(`[data-theme-preference-icon="${theme}"] svg`);
    if (info.project.name === 'desktop') await expect(icon).toBeVisible();
    const other = theme === 'dark' ? 'light' : 'dark';
    if (info.project.name === 'mobile') {
      await page.getByRole('button', { name: 'More actions', exact: true }).click();
      await page.getByRole('button', { name: 'Switch light or dark theme', exact: true }).click();
      await page.getByRole('dialog', { name: 'Links and appearance' }).getByRole('button', { name: 'Close', exact: true }).click();
    } else {
      await page.getByRole('button', { name: `Switch to ${other} theme`, exact: true }).click();
      await expect(page.locator(`[data-theme-preference-icon="${other}"] svg`)).toBeVisible();
      await expect(icon).toBeHidden();
    }
    await expect(page.locator('html')).toHaveAttribute('data-theme-preference', other);
    await page.reload();
    await expect(page.locator('html')).toHaveAttribute('data-theme-preference', other);
    if (info.project.name === 'desktop') {
      await expect(page.locator('[data-theme-preference-icon] svg:visible')).toHaveCount(1);
    }
    await page.screenshot({ path: info.outputPath(`theme-${other}.png`), fullPage: true });
  });

  for (const [route, heading] of pages) {
    test(`${theme} ${heading}: renders and loads local resources`, async ({ page }, info) => {
      const errors = [];
      page.on('pageerror', error => errors.push(error.message));
      page.on('requestfailed', request => errors.push(`${request.failure()?.errorText} ${request.url()}`));
      page.on('response', response => {
        if (response.url().startsWith('http://127.0.0.1:') && response.status() >= 400) {
          errors.push(`${response.status()} ${response.url()}`);
        }
      });
      await page.emulateMedia({ colorScheme: theme });
      await page.goto(route || './', { waitUntil: 'networkidle' });
      await expect(page.getByRole('heading', { level: 1, name: heading, exact: true })).toBeVisible();
      await expect(page.locator('html')).toHaveAttribute('data-theme-preference', theme);
      expect(await page.locator('img').evaluateAll(images => images
        .filter(image => image.getClientRects().length && (!image.complete || image.naturalWidth === 0))
        .map(image => image.src))).toEqual([]);
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true);
      expect(errors).toEqual([]);
      await page.screenshot({ path: info.outputPath(`${theme}-${route.replaceAll('/', '-') || 'home'}.png`), fullPage: true });
    });
  }
}

test('search results, empty search and mobile page navigation', async ({ page }, info) => {
  await page.goto('./');
  await page.getByRole('button', { name: 'Open search', exact: true }).click();
  const search = page.getByRole('dialog', { name: 'Search documentation', exact: true });
  await search.getByRole('searchbox', { name: 'Search documentation' }).fill('windowProvider');
  await expect(search.getByRole('status')).toContainText('matching');
  await expect(search.getByRole('link').first()).toBeVisible();
  await search.getByRole('searchbox').fill('no-result-unique-73894');
  await expect(search.getByRole('status')).toHaveText('No matching pages. Try fewer words.');
  await search.getByRole('searchbox').fill('');
  await expect(search.getByRole('status')).toHaveText('Enter words to search the documentation.');
  await search.getByRole('button', { name: 'Close', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Open search', exact: true })).toBeFocused();
  await page.keyboard.press('ControlOrMeta+k');
  await expect(search).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(search).toBeHidden();
  await expect(page.getByRole('button', { name: 'Open search', exact: true })).toBeFocused();
  if (info.project.name === 'mobile') {
    await page.getByRole('button', { name: 'Open page navigation', exact: true }).click();
    const navigation = page.getByRole('dialog', { name: 'Pages', exact: true });
    await expect(navigation.getByRole('link')).toHaveCount(pages.length);
    await navigation.getByRole('link', { name: 'Quickstart', exact: true }).click();
    await expect(page.getByRole('heading', { level: 1, name: 'Quickstart', exact: true })).toBeVisible();
  }
});

test('failed search index can retry without reloading the page', async ({ page }) => {
  let attempts = 0;
  await page.route('**/search-index.json', async route => {
    attempts += 1;
    if (attempts === 1) await route.fulfill({ status: 503, body: 'Temporarily unavailable' });
    else await route.continue();
  });
  await page.goto('./');
  const search = page.getByRole('dialog', { name: 'Search documentation', exact: true });
  await page.getByRole('button', { name: 'Open search', exact: true }).click();
  await expect(search.getByRole('status')).toContainText('Search could not load.');
  await search.getByRole('button', { name: 'Close', exact: true }).click();
  await page.getByRole('button', { name: 'Open search', exact: true }).click();
  await search.getByRole('searchbox').fill('windowProvider');
  await expect(search.getByRole('status')).toContainText('matching');
  expect(attempts).toBe(2);
});

test('code copies the complete displayed snippet', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.goto('quickstart/');
  const button = page.getByTestId('copy-code-button').first();
  const expected = await button.locator('xpath=ancestor::*[contains(@class,"code-block")]').locator('pre code').textContent();
  await button.click();
  await expect(button).toHaveAttribute('aria-label', 'Copied');
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(expected);
});
