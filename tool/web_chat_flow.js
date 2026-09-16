const path = require('node:path');
const { chromium } = require('playwright');

const targetUrl = process.env.TARGET_URL || 'http://127.0.0.1:8767';
const artifactDir = process.env.PW_ARTIFACT_DIR || 'D:\\temp\\sw-shots';

(async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      deviceScaleFactor: 2,
      locale: 'ru-RU',
    });
    page.on('pageerror', (e) => console.log('PAGE ERROR:', e.message));

    const shot = async (name) => {
      await page.screenshot({ path: path.join(artifactDir, `${name}.png`) });
      console.log('  shot:', name);
    };

    await page.goto(targetUrl, { waitUntil: 'load' });
    await page.waitForTimeout(9000);
    await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    await page.waitForTimeout(2000);

    const enter = page.getByRole('button', { name: 'Сразу в приложение' }).first();
    await enter.click({ timeout: 5000 }).catch(() => enter.click({ force: true }));
    await page.waitForTimeout(2000);

    // Пять вкладок при включённом флаге.
    const tabCount = await page.locator('flt-semantics[role="tab"]').count();
    console.log('  вкладок в панели:', tabCount);

    const tabs = [...Array(tabCount).keys()].map(
      (i) => (390 / tabCount) * i + 390 / (tabCount * 2),
    );
    await page.mouse.click(tabs[3], 844 - 30);
    await page.waitForTimeout(1800);
    await shot('chat-01-list');

    // Открываем первый диалог.
    const firstChat = page.locator('flt-semantics[flt-tappable]').filter({ hasText: 'Алина' }).first();
    await firstChat.click({ timeout: 6000 }).catch(() => firstChat.click({ force: true }));
    await page.waitForTimeout(1800);
    await shot('chat-02-thread');

    // Пишем сообщение.
    await page.evaluate(() => {
      const el = document.querySelector('input[aria-label="Написать сообщение"], textarea');
      el?.focus();
    });
    await page.waitForTimeout(500);
    await page.keyboard.type('Буду в семь, договорились', { delay: 30 });
    await page.waitForTimeout(700);

    const send = page.getByRole('button', { name: 'Отправить' }).first();
    await send.click({ timeout: 5000 }).catch(() => send.click({ force: true }));
    await page.waitForTimeout(1500);
    await shot('chat-03-sent');

    console.log('url в конце:', page.url());
    console.log('flow complete');
  } catch (e) {
    console.log('FLOW FAILED:', e.message.split('\n')[0]);
    throw e;
  } finally {
    await browser.close();
  }
})();
