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
      // Соседние semantics-ноды перекрывают кнопку — проверку перекрытия
      // отключаем, Flutter всё равно делает свой hit-test.
      await btn.click({ timeout: 4000 }).catch(() => btn.click({ force: true }));
      await page.waitForTimeout(1500);
      console.log('  tap:', name);
    };
    // Semantics-ноды перекрывают поля, поэтому фокус ставим из JS по aria-label,
    // а текст шлём клавиатурой — так его забирает сам Flutter, а не DOM-инпут.
    const typeInto = async (label, text) => {
      await page.evaluate(
        (l) => document.querySelector(`input[aria-label="${l}"]`)?.focus(),
        label,
      );
      await page.waitForTimeout(600);
      await page.keyboard.type(text, { delay: 50 });
      await page.waitForTimeout(700);
      console.log(`  ввод «${text}» в поле «${label}»`);
    };

    await page.goto(targetUrl, { waitUntil: 'load' });
    await page.waitForTimeout(9000);
    await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    await page.waitForTimeout(2000);

    await shot('01-signin');
    await typeInto('почта', 'lev@socialworld.ru');
    await tap('Получить код');
    await shot('02-code');

    await typeInto('______', '123456');
    await tap('Войти');
    await shot('03-onboarding');

    await typeInto('имя', 'Алексей');
    await shot('04-onboarding-filled');
    await tap('Продолжить');
    await shot('05-feed');

    const tree = await page.evaluate(() =>
      Array.from(document.querySelectorAll('flt-semantics')).map((el) => {
        const r = el.getBoundingClientRect();
        return `${el.getAttribute('role') || '-'} "${(el.textContent || '').trim().slice(0, 24)}" @${Math.round(r.x)},${Math.round(r.y)} ${Math.round(r.width)}x${Math.round(r.height)}`;
      }),
    );
    console.log('--- дерево на ленте ---\n' + tree.join('\n'));

    // Вкладки нижней панели: четыре равные колонки, бьём мышью по центрам.
    const tabCenters = [0, 1, 2, 3].map((i) => (390 / 4) * i + 390 / 8);
    for (const [index, name] of [
      [1, '06-discover'],
      [2, '07-create'],
      [3, '08-profile'],
    ]) {
      await page.mouse.click(tabCenters[index], 844 - 30);
      await page.waitForTimeout(1500);
      await shot(name);
    }

    console.log('url в конце:', page.url());
    console.log('flow complete');
  } catch (e) {
    console.log('FLOW FAILED:', e.message.split('\n')[0]);
    throw e;
  } finally {
    await browser.close();
  }
})();
