import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

const source = fs.readFileSync(new URL('../site/main.js', import.meta.url), 'utf8');

// Small DOM doubles exercise the shipped event handlers, without a browser
// dependency. Real rendering and native dialog behavior are checked in Browser.
function createPage(hash = '') {
  let document;
  function element(id = '', attributes = {}) {
    const listeners = new Map();
    const classes = new Set();
    return {
      id, hidden: false, open: false, scrolls: 0,
      setAttribute(name, value) { attributes[name] = value; },
      getAttribute(name) { return attributes[name]; },
      addEventListener(type, listener) {
        if (!listeners.has(type)) listeners.set(type, []);
        listeners.get(type).push(listener);
      },
      dispatch(type, values = {}) {
        const event = { button: 0, preventDefault() {}, ...values };
        for (const listener of listeners.get(type) ?? []) listener(event);
      },
      focus() { document.activeElement = this; },
      scrollIntoView() { this.scrolls++; },
      classList: { add(name) { classes.add(name); } },
    };
  }
  const body = element('body');
  const names = ['overview', 'profiles', 'maintenance'];
  const tabs = names.map(name => element(`tab-${name}`, { 'aria-controls': `preview-${name}` }));
  const panels = names.map(name => element(`preview-${name}`));
  const summary = element('verification-summary');
  const answer = element('verify-download');
  answer.querySelector = selector => selector === 'summary' ? summary : null;
  const link = element('verification-link', { href: '#verify-download' });
  const controls = element();
  controls.querySelectorAll = () => tabs;
  const selectors = {
    '.preview-controls': controls, '.preview-gallery': element(),
    '.image-viewer': element(), '.viewer-canvas': element(),
  };
  const byId = new Map([...tabs, ...panels, answer].map(node => [node.id, node]));
  const window = element();
  const location = { hash };
  document = {
    body, activeElement: body,
    querySelector: selector => selectors[selector],
    querySelectorAll: selector => selector === 'a[href="#verify-download"]' ? [link] : [],
    getElementById: id => byId.get(id) ?? element(id),
  };
  vm.runInNewContext(source, { document, window, location, matchMedia: () => ({ matches: true }) });
  return { document, window, location, answer, summary, link, tabs, panels };
}

test('repeating the verification link reopens a manually closed answer without a hashchange', () => {
  const page = createPage('#verify-download');
  assert.equal(page.answer.open, true);
  page.answer.open = false;
  page.link.dispatch('click');
  assert.equal(page.answer.open, true);
  assert.equal(page.document.activeElement, page.summary);
});

test('explicit verification navigation opens the answer and moves keyboard focus', () => {
  const page = createPage('#install');
  page.link.dispatch('click');
  assert.equal(page.answer.open, true);
  assert.equal(page.document.activeElement, page.summary);
});

test('modified clicks leave the current page alone', () => {
  for (const modifier of [{ ctrlKey: true }, { metaKey: true }, { shiftKey: true }, { altKey: true }, { button: 1 }]) {
    const page = createPage();
    page.link.dispatch('click', modifier);
    assert.equal(page.answer.open, false);
    assert.equal(page.document.activeElement, page.document.body);
  }
});

test('direct and history hash navigation reveal the answer without stealing focus', () => {
  const page = createPage('#verify-download');
  assert.equal(page.answer.open, true);
  assert.equal(page.document.activeElement, page.document.body);
  page.answer.open = false;
  page.window.dispatch('hashchange');
  assert.equal(page.answer.open, true);
  assert.equal(page.document.activeElement, page.document.body);
});

test('preview keyboard navigation wraps and retains exactly one selected panel', () => {
  const page = createPage();
  page.tabs[0].dispatch('keydown', { key: 'ArrowLeft' });
  assert.equal(page.document.activeElement, page.tabs[2]);
  assert.deepEqual(page.panels.map(panel => panel.hidden), [true, true, false]);
  page.tabs[2].dispatch('keydown', { key: 'Home' });
  assert.equal(page.document.activeElement, page.tabs[0]);
  page.tabs[0].dispatch('keydown', { key: 'End' });
  assert.equal(page.tabs.filter(tab => tab.getAttribute('aria-selected') === 'true').length, 1);
  assert.equal(page.document.activeElement, page.tabs[2]);
});
