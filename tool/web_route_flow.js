// Проверка записи маршрута без телефона.
//
// Playwright умеет подменять геопозицию и двигать её — этого хватает, чтобы
// пройти весь сценарий прогулки: старт, накопление точек, финиш, публикация,
// карточка в ленте. На вебе карта рисуется силуэтом (MapKit туда не собирается),
// но вся логика записи — та же самая, что на телефоне.
const path = require('node:path');
const { chromium } = require('playwright');

const targetUrl = process.env.TARGET_URL || 'http://127.0.0.1:8765';
const artifactDir = process.env.PW_ARTIFACT_DIR || 'D:\\temp\\sw-shots';

// Набережная Сочи, идём на северо-восток.
//
// Шаг ~20 метров раз в 1.2 секунды. Цифры подобраны не на глаз: меньше 12 м
// рекордер игнорирует как дрожание GPS, а быстрее 40 м/с считает выбросом и
// тоже отбрасывает. Слишком резвая «прогулка» в тесте проходит мимо обоих
// фильтров и записывает пустоту.
const start = { latitude: 43.5789, longitude: 39.7232 };
const steps = 12;
const stepDelayMs = 1200;
const stepLat = 0.00018;
const stepLng = 0.00025;

(async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    const context = await browser.newContext({
      viewport: { width: 390, height: 844 },
      deviceScaleFactor: 2,
      locale: 'ru-RU',
      permissions: ['geolocation'],
      geolocation: { ...start, accuracy: 5 },
      // Иначе Flutter-овский service worker отдаёт прошлую сборку, и правка
      // выглядит как «не помогла».
      serviceWorkers: 'block',
    });
    const page = await context.newPage();
    page.on('pageerror', (e) => console.log('PAGE ERROR:', e.message));

    const shot = async (name) => {
      await page.screenshot({ path: path.join(artifactDir, `${name}.png`) });
      console.log('  shot:', name);
    };
    const tap = async (name) => {
      const btn = page.getByRole('button', { name }).first();
      await btn.waitFor({ state: 'visible', timeout: 15000 });
      await btn.click({ timeout: 4000 }).catch(() => btn.click({ force: true }));
      await page.waitForTimeout(1200);
      console.log('  tap:', name);
    };

    await page.goto(targetUrl, { waitUntil: 'load' });
    await page.waitForTimeout(9000);
    await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    await page.waitForTimeout(2000);

    await tap('Сразу в приложение');
    await page.waitForTimeout(1500);

    // Шесть вкладок в дев-режиме: Лента, Карта, События, Создать, Чаты, Профиль.
    const tabs = [0, 1, 2, 3, 4, 5].map((i) => (390 / 6) * i + 390 / 12);

    await page.mouse.click(tabs[3], 844 - 30);
    await page.waitForTimeout(1500);
    await shot('r-01-create');

    await tap('Маршрут');
    await page.waitForTimeout(800);
    await shot('r-02-route-intro');

    await tap('Начать запись');
    await page.waitForTimeout(1500);
    await shot('r-03-recorder-idle');

    await tap('Начать маршрут');
    await page.waitForTimeout(2000);
    await shot('r-04-recording-started');

    // Прогулка: двигаем точку и даём приложению время принять обновление.
    for (let i = 1; i <= steps; i++) {
      await context.setGeolocation({
        latitude: start.latitude + stepLat * i,
        longitude: start.longitude + stepLng * i,
        accuracy: 5,
      });
      await page.waitForTimeout(stepDelayMs);
    }
    await page.waitForTimeout(1500);
    await shot('r-05-walking');

    const stats = await page.evaluate(() =>
      Array.from(document.querySelectorAll('flt-semantics'))
        .map((el) => el.getAttribute('aria-label'))
        .filter((l) => l && (l.includes('м') || l.includes(':')))
        .slice(0, 12),
    );
    console.log('  показания на экране:', JSON.stringify(stats));

    await tap('Финиш');
    await page.waitForTimeout(1800);
    await shot('r-06-publish-sheet');

    await page.evaluate(() => {
      const el = document.querySelector('input[aria-label*="Вечер"], input, textarea');
      el?.focus();
    });
    await page.waitForTimeout(500);
    await page.keyboard.type('Вечер у моря', { delay: 30 });
    await page.waitForTimeout(800);
    await shot('r-07-title-filled');

    await tap('Опубликовать');
    await page.waitForTimeout(3000);
    await shot('r-08-route-detail');
    console.log('  url после публикации:', page.url());

    // Возвращаемся в ленту: там должна появиться карточка маршрута.
    // Именно кнопкой на экране, а не goBack — путь пользователя проверяем,
    // а не историю браузера.
    const back = page.getByRole('button', { name: 'Назад' }).first();
    await back.click({ timeout: 6000 }).catch(() => back.click({ force: true }));
    await page.waitForTimeout(3000);
    await shot('r-09-feed-with-route');

    const routeCard = await page.evaluate(() =>
      Array.from(document.querySelectorAll('flt-semantics'))
        .map((el) => el.getAttribute('aria-label'))
        .filter((l) => l && (l.includes('Вечер у моря') || l.includes(' м · ')))
        .slice(0, 5),
    );
    console.log('  карточка в ленте:', JSON.stringify(routeCard));

    console.log('flow complete');
  } catch (e) {
    console.log('FLOW FAILED:', e.message.split('\n')[0]);
    throw e;
  } finally {
    await browser.close();
  }
})();
