const path = require('node:path');
const { chromium } = require('playwright');

const targetUrl = process.env.TARGET_URL || 'http://127.0.0.1:8765';
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
    const tap = async (name) => {
      const btn = page.getByRole('button', { name }).first();
      await btn.waitFor({ state: 'visible' });
      await btn.click({ timeout: 4000 }).catch(() => btn.click({ force: true }));
      await page.waitForTimeout(1500);
      console.log('  tap:', name);
    };
    const typeInto = async (label, text) => {
      await page.evaluate(
        (l) => document.querySelector(`input[aria-label="${l}"], textarea[aria-label="${l}"]`)?.focus(),
        label,
      );
      await page.waitForTimeout(500);
      await page.keyboard.type(text, { delay: 35 });
      await page.waitForTimeout(600);
      console.log(`  ввод в «${label}»`);
    };

    await page.goto(targetUrl, { waitUntil: 'load' });
    await page.waitForTimeout(9000);
    await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    await page.waitForTimeout(2000);

    // Через dev-панель сразу внутрь, авторизацию уже проверяли отдельно.
    await tap('Сразу в приложение');
    await page.waitForTimeout(1500);
    await shot('p1-01-feed');

    const tabs = [0, 1, 2, 3].map((i) => (390 / 4) * i + 390 / 8);

    // Создание поста
    await page.mouse.click(tabs[2], 844 - 30);
    await page.waitForTimeout(1500);
    await shot('p1-02-create');

    const area = await page.evaluate(() => {
      const el = document.querySelector('textarea, input[aria-label*="Напишите"]');
      return el ? (el.getAttribute('aria-label') || el.tagName) : null;
    });
    console.log('  поле ввода поста:', area);
    await page.evaluate(() => {
      const el = document.querySelector('textarea') || document.querySelector('flt-semantics input');
      el?.focus();
    });
    await page.waitForTimeout(400);
    await page.keyboard.type('Пробую ленту: вечер на набережной, тепло.', { delay: 25 });
    await page.waitForTimeout(700);
    await shot('p1-03-create-filled');

    await tap('Опубликовать');
    await page.waitForTimeout(1800);
    await shot('p1-04-feed-after-publish');

    // Лайк на чужом посте
    const like = page.getByRole('button', { name: 'Нравится' }).nth(1);
    await like.click({ timeout: 5000 }).catch(() => like.click({ force: true }));
    await page.waitForTimeout(1200);
    await shot('p1-05-liked');

    // Жалоба на чужой пост
    const flag = page.getByRole('button', { name: 'Пожаловаться' }).nth(1);
    await flag.click({ timeout: 5000 }).catch(() => flag.click({ force: true }));
    await page.waitForTimeout(1500);
    await shot('p1-06-report-sheet');

    // Радиокнопки в дереве без подписей — текст лежит соседним узлом.
    // Первая по порядку это «Спам или реклама».
    const reason = page.locator('flt-semantics[role="radio"]').first();
    await reason.click({ timeout: 6000 }).catch(() => reason.click({ force: true }));
    await page.waitForTimeout(800);
    await tap('Отправить');
    await page.waitForTimeout(1500);
    await shot('p1-07-after-report');

    // Профиль с публикациями
    await page.mouse.click(tabs[3], 844 - 30);
    await page.waitForTimeout(1600);
    await shot('p1-08-profile');

    console.log('url в конце:', page.url());
    console.log('flow complete');
  } catch (e) {
    console.log('FLOW FAILED:', e.message.split('\n')[0]);
    throw e;
  } finally {
    await browser.close();
  }
})();
