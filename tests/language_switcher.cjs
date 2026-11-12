// Opens each language's first fixture page in Chrome, picks the other language in the switcher and expects its page.
const { chromium } = require('playwright-core');

const base = process.argv[2];
const titles = { nl: 'Aan de slag', en: 'Getting started' };
const labels = { nl: /^\s*(Nederlands|Dutch|nl)\s*$/i, en: /^\s*(English|Engels|en)\s*$/i };
const clickable = 'button, [role="button"], [role="combobox"], [role="option"], [role="menuitem"], [role="menuitemradio"], a, li, select';
// The menu's entries may be plain elements, so an option is any visible element whose own text is the language.
const anything = `${clickable}, div, span`;

async function visibleMatching(page, label, selector = clickable) {
  const found = [];
  for (const element of await page.locator(selector).all()) {
    if (!(await element.isVisible())) continue;
    const text = (await element.innerText().catch(() => '')).trim();
    if (label.test(text)) found.push(element);
  }
  return found;
}

async function describe(page) {
  const texts = await page.locator(anything).evaluateAll((elements) =>
    elements.filter((e) => e.offsetParent !== null && e.innerText.trim()).map((e) => `${e.tagName.toLowerCase()}: ${e.innerText.trim().replace(/\s+/g, ' ').slice(0, 60)}`));
  return `url ${page.url()}\n${[...new Set(texts)].join('\n')}`;
}

async function switchLanguage(page, from, to) {
  await page.goto(`${base}/${from}/getting-started`, { waitUntil: 'networkidle' });
  await page.locator('h1', { hasText: titles[from] }).first().waitFor({ timeout: 30000 });
  const select = page.locator('select').filter({ has: page.locator('option', { hasText: labels[to] }) });
  if (await select.count()) {
    const value = await select.first().locator('option', { hasText: labels[to] }).first().getAttribute('value');
    await select.first().selectOption(value);
  } else {
    const openers = await visibleMatching(page, labels[from]);
    if (!openers.length) throw new Error(`no switcher showing ${from} on /${from}/getting-started\n${await describe(page)}`);
    await openers[0].click();
    let options = [];
    for (let tries = 0; tries < 10 && !options.length; tries++) {
      if (tries) await page.waitForTimeout(500);
      options = await visibleMatching(page, labels[to], anything);
    }
    if (!options.length) throw new Error(`switcher opened but offers no ${to}\n${await describe(page)}`);
    await options[options.length - 1].click();
  }
  await page.waitForURL(new RegExp(`/${to}/getting-started`), { timeout: 30000 });
  await page.locator('h1', { hasText: titles[to] }).first().waitFor({ timeout: 30000 });
  console.log(`switcher: /${from}/getting-started -> ${new URL(page.url()).pathname}`);
}

(async () => {
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
    await switchLanguage(page, 'nl', 'en');
    await switchLanguage(page, 'en', 'nl');
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
