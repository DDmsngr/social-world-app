// Ветки комментариев и вложения поста в режиме заглушек.
// Проверяет то, чего не видят тесты: как дерево выглядит на экране, сворачивается
// ли ветка и встаёт ли ответ в нужное место.
const path = require('node:path');
const { chromium } = require('playwright');

const targetUrl = process.env.TARGET_URL || 'http://127.0.0.1:8765';
const artifactDir = process.env.PW_ARTIFACT_DIR || 'D:\\temp\\sw-shots';

(async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    const context = await browser.newContext({
      viewport: { width: 390, height: 844 },
      deviceScaleFactor: 2,
      locale: 'ru-RU',
      serviceWorkers: 'block',
    });
    const page = await context.newPage();
    page.on('pageerror', (e) => console.log('PAGE ERROR:', e.message));

    const shot = async (name) => {
      await page.screenshot({ path: path.join(artifactDir, `${name}.png`) });
      console.log('  shot:', name);
    };
    const tap = async (name, index = 0) => {
      const btn = page.getByRole('button', { name }).nth(index);
      await btn.waitFor({ state: 'visible', timeout: 8000 });
      await btn.click({ timeout: 4000 }).catch(() => btn.click({ force: true }));
      await page.waitForTimeout(1200);
      console.log('  tap:', name, index);
    };

    await page.goto(targetUrl, { waitUntil: 'load' });
    await page.waitForTimeout(9000);
    await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    await page.waitForTimeout(2000);

    await tap('Сразу в приложение');
    await page.waitForTimeout(1500);
    await shot('c1-01-feed');

    // Первый пост в ленте — сид с готовой веткой обсуждения.
    await tap('Обсуждение');
    await page.waitForTimeout(1800);
    await shot('c1-02-thread');

    const texts = await page.evaluate(() =>
      Array.from(document.querySelectorAll('flt-semantics'))
        .map((n) => n.getAttribute('aria-label'))
        .filter(Boolean),
    );
    console.log('  видно в ветке:', texts.filter((t) => t.length > 12).slice(0, 10));

    // Написать комментарий отсюда нельзя: в нижний композер Flutter не
    // прокидывает ввод из скрытого textarea (текст оказывается в DOM, но не в
    // контроллере поля), поэтому путь «написал → отправил» проверяется
    // виджет-тестом test/features/feed/post_detail_screen_test.dart.
    // Здесь остаётся то, чего тест не покажет: как ветки выглядят и
    // сворачиваются на живом экране.
    // Сворачивание висит на шапке комментария — тапаем по имени автора.
    await page.mouse.click(100, 561);
    await page.waitForTimeout(1200);
    await shot('c1-03-collapsed');

    const after = await page.evaluate(() =>
      Array.from(document.querySelectorAll('flt-semantics'))
        .map((n) => n.getAttribute('aria-label'))
        .filter((t) => t && t.length > 12),
    );
    console.log('  ветка после сворачивания:', after);

    console.log('url в конце:', page.url());
    console.log('flow complete');
  } catch (e) {
    console.log('FLOW FAILED:', e.message.split('\n')[0]);
    throw e;
  } finally {
    await browser.close();
  }
})();
