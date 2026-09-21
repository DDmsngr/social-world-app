// Проверка ребрендинга и выбора города: вкладка Pulse, заголовок с городом,
// смена города и её сохранение. Карты в вебе нет — вместо неё список тех же
// объектов, но заголовок, выбор города и вкладки общие с телефоном.
const path = require('node:path');
const { chromium } = require('playwright');

const targetUrl = process.env.TARGET_URL || 'http://127.0.0.1:8765';
const artifactDir = process.env.PW_ARTIFACT_DIR || 'D:\\temp\\sw-city';

(async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 },
      deviceScaleFactor: 2,
      locale: 'ru-RU',
      colorScheme: 'dark',
    });
    page.on('pageerror', (e) => console.log('PAGE ERROR:', e.message));

    const shot = async (name) => {
      await page.screenshot({ path: path.join(artifactDir, `${name}.png`) });
      console.log('  shot:', name);
    };
    const tap = async (name) => {
      const btn = page.getByRole('button', { name }).first();
      await btn.waitFor({ state: 'visible', timeout: 8000 });
      await btn.click({ timeout: 4000 }).catch(() => btn.click({ force: true }));
      await page.waitForTimeout(1200);
      console.log('  tap:', name);
    };
    const typeInto = async (label, text) => {
      await page.evaluate(
        (l) => document.querySelector(`input[aria-label="${l}"]`)?.focus(),
        label,
      );
      await page.waitForTimeout(600);
      await page.keyboard.type(text, { delay: 50 });
      await page.waitForTimeout(700);
    };
    // Что видно в дереве доступности — по нему проверяем, а не по картинке.
    const labels = () =>
      page.evaluate(() =>
        [...document.querySelectorAll('flt-semantics[aria-label]')]
          .map((n) => n.getAttribute('aria-label'))
          .filter(Boolean),
      );
    const has = async (needle) =>
      (await labels()).some((l) => l.includes(needle));

    await page.goto(targetUrl, { waitUntil: 'load' });
    await page.waitForTimeout(9000);
    await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    await page.waitForTimeout(2000);

    await shot('01-signin');
    console.log('  имя на входе ChaWo:', await has('ChaWo'));

    if (await page.getByRole('button', { name: 'Войти по почте' }).count()) {
      await tap('Войти по почте');
    }
    await typeInto('почта', 'lev@socialworld.ru');
    await tap('Получить код');
    await tap('Войти');
    await typeInto('имя', 'Алексей');
    await tap('Продолжить');
    await page.waitForTimeout(1500);
    await shot('02-pulse');

    console.log('  заголовок «Сочи»:', await has('Сочи'));

    // Заголовок Pulse открывает выбор города.
    await tap('Сочи');
    await shot('03-city-picker');
    const cities = await labels();
    console.log('  в списке есть Москва:', cities.some((l) => l.includes('Москва')));

    await tap('Краснодар');
    await page.waitForTimeout(2000);
    await shot('04-krasnodar');
    console.log('  заголовок стал «Краснодар»:', await has('Краснодар'));

    // Перезагрузка страницы = перезапуск приложения: выбор должен пережить её.
    await page.reload({ waitUntil: 'load' });
    await page.waitForTimeout(9000);
    await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    await page.waitForTimeout(2500);
    await shot('05-after-reload');
    console.log('  город пережил перезапуск:', await has('Краснодар'));

    console.log('flow complete');
  } catch (e) {
    console.log('FLOW FAILED:', e.message.split('\n')[0]);
    throw e;
  } finally {
    await browser.close();
  }
})();
