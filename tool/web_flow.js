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
      // Тема по умолчанию — «как в системе»: стартуем в тёмной, потом
      // в настройках явно выбираем светлую.
      colorScheme: 'dark',
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

    // Вкладки: Моменты / Карта / Создать / Чаты / Профиль. В дереве это
    // `tab` без названия — жмём мышью по центрам колонок.
    const tabCount = 5;
    const tabX = (i) => (390 / tabCount) * i + 390 / (tabCount * 2);
    const tabs = async (prefix) => {
      for (const [index, name] of [
        [0, 'moments'],
        [1, 'map'],
        [2, 'create'],
        [3, 'chats'],
        [4, 'profile'],
      ]) {
        await page.mouse.click(tabX(index), 844 - 30);
        await page.waitForTimeout(1500);
        await shot(`${prefix}-${name}`);
        console.log('    url:', new URL(page.url()).hash);
      }
    };

    await page.goto(targetUrl, { waitUntil: 'load' });
    await page.waitForTimeout(9000);
    await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    await page.waitForTimeout(2000);

    await shot('01-signin');
    // С настоящим бэкендом по умолчанию вход через VK/Яндекс, почта — за
    // отдельной кнопкой. На заглушках (пустой .env) форма почты открыта сразу.
    if (await page.getByRole('button', { name: 'Войти по почте' }).count()) {
      await tap('Войти по почте');
    }
    await typeInto('почта', 'lev@socialworld.ru');
    await tap('Получить код');

    // Код подставляется сам, пока почта не подключена — печатать нечего.
    await tap('Войти');
    await typeInto('имя', 'Алексей');
    await tap('Продолжить');
    // После входа главный экран — карта.
    await shot('02-home-map');

    await tap('Пульс города');
    await shot('03-events');
    await page.goBack();
    await page.waitForTimeout(1500);

    await tabs('dark');

    await tap('Настройки');
    await shot('10-settings-dark');
    await tap('Светлая');
    await page.waitForTimeout(800);
    await shot('11-settings-light');
    await page.goBack();
    await page.waitForTimeout(1500);

    await tabs('light');

    console.log('url в конце:', page.url());
    console.log('flow complete');
  } catch (e) {
    console.log('FLOW FAILED:', e.message.split('\n')[0]);
    throw e;
  } finally {
    await browser.close();
  }
})();
