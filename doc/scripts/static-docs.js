// Browser behavior for the static Mintlify export hosted on GitHub Pages.
(() => {
  'use strict';
  const script = document.querySelector('script[data-static-docs]');
  const base = script.dataset.basePath;
  const themeKey = `mintlify-docs-theme:${base}`;
  const themeButtons = [...document.querySelectorAll('button[aria-label*="theme" i]')];
  function applyTheme(theme) {
    document.documentElement.classList.toggle('dark', theme === 'dark');
    document.documentElement.classList.toggle('light', theme === 'light');
    document.documentElement.style.colorScheme = theme;
    themeButtons.forEach(button => {
      button.setAttribute('aria-label', `Switch to ${theme === 'dark' ? 'light' : 'dark'} theme`);
      button.removeAttribute('aria-haspopup');
      button.removeAttribute('aria-expanded');
    });
  }
  let savedTheme;
  try { savedTheme = localStorage.getItem(themeKey); } catch (_) { /* Storage can be disabled. */ }
  applyTheme(savedTheme === 'dark' || savedTheme === 'light' ? savedTheme
    : matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
  function toggleTheme() {
    const theme = document.documentElement.classList.contains('dark') ? 'light' : 'dark';
    applyTheme(theme);
    try { localStorage.setItem(themeKey, theme); } catch (_) { /* Still works for this page. */ }
  }
  themeButtons.forEach(button => button.addEventListener('click', toggleTheme));

  const style = document.createElement('style');
  style.textContent = `
    .static-docs-dialog { color: #111827; background: #fff; border: 1px solid #d1d5db;
      border-radius: 16px; padding: 24px; margin: 8vh auto; width: min(640px, calc(100vw - 32px));
      max-height: 84vh; overflow: auto; box-sizing: border-box; }
    .dark .static-docs-dialog { color: #f9fafb; background: #171717; border-color: #525252; }
    .static-docs-dialog::backdrop { background: #0009; }
    .static-docs-dialog h2 { font-size: 20px; font-weight: 600; margin: 0 0 20px; }
    .static-docs-dialog button { cursor: pointer; padding: 6px 10px; border: 1px solid #9ca3af;
      border-radius: 8px; background: transparent; color: inherit; }
    .static-docs-close { float: right; }
    .static-docs-dialog input { display: block; width: 100%; box-sizing: border-box; margin-top: 8px;
      padding: 12px; border: 1px solid #9ca3af; border-radius: 8px; background: transparent; color: inherit; }
    .static-docs-dialog a { display: block; padding: 12px 0; color: #2563eb; text-decoration: underline; }
    .dark .static-docs-dialog a { color: #93c5fd; }
    .static-docs-dialog small { display: block; color: #4b5563; margin-top: 6px; text-decoration: none; }
    .dark .static-docs-dialog small { color: #d1d5db; }
    .static-docs-dialog :focus-visible { outline: 2px solid #2563eb; outline-offset: 4px; }
    .static-docs-status { margin-top: 16px; }
  `;
  document.head.append(style);

  function makeDialog(title) {
    const dialog = document.createElement('dialog');
    dialog.className = 'static-docs-dialog';
    dialog.setAttribute('aria-label', title);
    const close = document.createElement('button');
    close.className = 'static-docs-close';
    close.type = 'button';
    close.textContent = 'Close';
    close.addEventListener('click', () => dialog.close());
    const heading = document.createElement('h2');
    heading.textContent = title;
    dialog.append(close, heading);
    dialog.addEventListener('click', event => {
      if (event.target !== dialog) return;
      const bounds = dialog.getBoundingClientRect();
      if (event.clientX < bounds.left || event.clientX > bounds.right ||
          event.clientY < bounds.top || event.clientY > bounds.bottom) dialog.close();
    });
    document.body.append(dialog);
    return dialog;
  }

  const search = makeDialog('Search documentation');
  const label = document.createElement('label');
  label.textContent = 'Search documentation';
  const input = document.createElement('input');
  input.type = 'search';
  input.autocomplete = 'off';
  label.append(input);
  const status = document.createElement('p');
  status.className = 'static-docs-status';
  status.setAttribute('role', 'status');
  const results = document.createElement('div');
  search.append(label, status, results);
  let pages;
  let pendingIndex;
  async function loadIndex() {
    if (!pendingIndex) {
      pendingIndex = fetch(`${base}/search-index.json`).then(response => {
        if (!response.ok) throw new Error('Search index unavailable');
        return response.json();
      }).then(value => { pages = value; }).catch(error => {
        pendingIndex = null;
        throw error;
      });
    }
    return pendingIndex;
  }
  function renderResults() {
    results.replaceChildren();
    if (!pages) return;
    const terms = input.value.trim().toLocaleLowerCase().split(/\s+/).filter(Boolean);
    if (!terms.length) { status.textContent = 'Enter words to search the documentation.'; return; }
    const matches = pages.filter(page => terms.every(term =>
      `${page.title} ${page.text}`.toLocaleLowerCase().includes(term)))
      .sort((a, b) => Number(terms.every(term => b.title.toLocaleLowerCase().includes(term)))
        - Number(terms.every(term => a.title.toLocaleLowerCase().includes(term))));
    status.textContent = matches.length ? `${matches.length} matching ${matches.length === 1 ? 'page' : 'pages'}` : 'No matching pages. Try fewer words.';
    for (const page of matches) {
      const link = document.createElement('a');
      link.href = page.url;
      link.textContent = page.title;
      const snippet = document.createElement('small');
      const offset = Math.max(0, page.text.toLocaleLowerCase().indexOf(terms[0]) - 50);
      snippet.textContent = `${offset ? '…' : ''}${page.text.slice(offset, offset + 180)}…`;
      link.append(snippet);
      results.append(link);
    }
  }
  input.addEventListener('input', renderResults);
  async function openSearch() {
    if (!search.open) search.showModal();
    input.focus();
    status.textContent = 'Loading search…';
    try { await loadIndex(); renderResults(); }
    catch (_) { status.textContent = 'Search could not load. Close and reopen search to retry, or use the page navigation.'; }
  }
  document.querySelectorAll('button[aria-label="Open search"]').forEach(button =>
    button.addEventListener('click', openSearch));
  document.addEventListener('keydown', event => {
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
      event.preventDefault();
      openSearch();
    }
  });

  document.querySelectorAll('[data-testid="copy-code-button"]').forEach(button => {
    const originalLabel = button.getAttribute('aria-label');
    button.addEventListener('click', async () => {
      const code = button.closest('.code-block')?.querySelector('pre code');
      if (!code) return;
      const announcement = button.parentElement.querySelector('[role="status"]');
      let message;
      try { await navigator.clipboard.writeText(code.textContent); message = 'Copied'; }
      catch (_) { message = 'Copy failed. Select the code and copy it manually.'; }
      button.setAttribute('aria-label', message);
      button.title = message;
      if (announcement) announcement.textContent = message;
      setTimeout(() => {
        button.setAttribute('aria-label', originalLabel);
        button.removeAttribute('title');
      }, 2000);
    });
  });

  const navigation = makeDialog('Pages');
  const nav = document.createElement('nav');
  nav.setAttribute('aria-label', 'Documentation pages');
  document.querySelectorAll('#sidebar a[href]').forEach(source => {
    const link = document.createElement('a');
    link.href = source.href;
    link.textContent = source.textContent;
    if (source.getAttribute('aria-current')) link.setAttribute('aria-current', 'page');
    nav.append(link);
  });
  navigation.append(nav);
  const mobileNavigation = [...document.querySelectorAll('#navbar button')]
    .find(button => button.textContent.startsWith('Navigation'));
  if (mobileNavigation) {
    mobileNavigation.setAttribute('aria-label', 'Open page navigation');
    mobileNavigation.setAttribute('aria-haspopup', 'dialog');
    mobileNavigation.addEventListener('click', () => navigation.showModal());
  }
  const actions = document.querySelector('button[aria-label="More actions"]');
  if (actions) {
    const menu = makeDialog('Links and appearance');
    document.querySelectorAll('nav[aria-label="Main"] a[href]').forEach(source => {
      const link = document.createElement('a');
      link.href = source.href;
      link.textContent = source.textContent;
      menu.append(link);
    });
    const theme = document.createElement('button');
    theme.type = 'button';
    theme.textContent = 'Switch light or dark theme';
    theme.addEventListener('click', toggleTheme);
    menu.append(theme);
    actions.addEventListener('click', () => menu.showModal());
  }
  const contents = document.querySelector('#table-of-contents-content');
  const contentsButton = document.querySelector('#table-of-contents button');
  if (contents && contentsButton) {
    contentsButton.setAttribute('aria-controls', contents.id);
    contentsButton.setAttribute('aria-expanded', 'true');
    contentsButton.addEventListener('click', () => {
      contents.hidden = !contents.hidden;
      contentsButton.setAttribute('aria-expanded', String(!contents.hidden));
    });
  }
  // Hosted assistant features are not part of a static export.
  document.querySelectorAll('[class*="chat-assistant"]').forEach(element => element.remove());
})();
