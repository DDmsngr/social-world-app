import { test } from 'node:test';
import assert from 'node:assert/strict';
import { htmlToMarkdown, stripSignature, parseChannelPage, planPosts } from './feed.mjs';

test('жирный: пробелы и переносы вне маркеров', () => {
  assert.equal(htmlToMarkdown('<b>Заголовок<br/><br/></b>Текст'), '**Заголовок**\n\nТекст');
  assert.equal(htmlToMarkdown('слово <b>жирное</b> дальше'), 'слово **жирное** дальше');
  assert.equal(htmlToMarkdown('<b> </b>пусто'), ' пусто'.trim());
});

test('эмодзи без обёрток, ссылки в Markdown, упоминания текстом', () => {
  const html = '<i class="emoji" style="x"><b>🚗</b></i> Пробка <a href="https://example.com/a)b">тут</a> <a href="?q=%23tag">#тег</a>';
  assert.equal(htmlToMarkdown(html), '🚗 Пробка [тут](https://example.com/a%29b) #тег');
});

test('спецсимволы Markdown экранируются', () => {
  assert.equal(htmlToMarkdown('2*2 = 4_x'), '2\\*2 = 4\\_x');
});

test('подвал источника срезается', () => {
  const text = 'Новость дня.\n\n✔ [Подписывайтесь на ТАСС](https://t.me/tass_agency)';
  assert.equal(stripSignature(text), 'Новость дня.');
  assert.equal(stripSignature('Только текст'), 'Только текст');
  // Подвал с призывом в соцсети («💙 Наши соц.сети:») тоже срезается.
  assert.equal(stripSignature('Поезд пойдёт в январе.\n\n💙 Наши соц.сети:'), 'Поезд пойдёт в январе.');
});

test('разбор страницы: фото, видео, кружки и опросы пропускаются', () => {
  const html = `
    <div class="tgme_widget_message_wrap"><div data-post="ch/1">
      <a class="tgme_widget_message_photo_wrap" style="background-image:url('https://cdn/p.jpg')"></a>
      <div class="tgme_widget_message_text js-message_text">Фото</div>
      <time datetime="2026-10-01T10:00:00+00:00"></time></div></div>
    <div class="tgme_widget_message_wrap"><div data-post="ch/2" class="roundvideo"></div></div>
    <div class="tgme_widget_message_wrap"><div data-post="ch/3">
      <video src="https://cdn/v.mp4"></video>
      <time datetime="2026-10-01T11:00:00+00:00"></time></div></div>
    <div class="tgme_widget_message_wrap"><div data-post="ch/4"><div class="tgme_widget_message_poll"></div></div></div>`;
  const posts = parseChannelPage(html, 'ch');
  assert.deepEqual(posts.map((p) => p.ref), ['tg:ch/1', 'tg:ch/3']);
  assert.equal(posts[0].media.kind, 'image');
  assert.equal(posts[1].media.kind, 'video');
  assert.deepEqual(posts[0].album, []);
});

test('альбом: все фото поста, по порядку', () => {
  const html = `
    <div class="tgme_widget_message_wrap"><div data-post="ch/7">
      <div class="tgme_widget_message_grouped_wrap js-message_grouped_wrap">
        <a class="tgme_widget_message_photo_wrap grouped_media_wrap" style="left:0px;background-image:url('https://cdn/1.jpg')"></a>
        <a class="tgme_widget_message_photo_wrap grouped_media_wrap" style="left:186px;background-image:url('https://cdn/2.jpg')"></a>
        <a class="tgme_widget_message_photo_wrap grouped_media_wrap" style="background-image:url('https://cdn/3.jpg')"></a>
      </div>
      <div class="tgme_widget_message_text js-message_text">Рецепт</div>
      <time datetime="2026-10-01T10:00:00+00:00"></time></div></div>`;
  const [post] = parseChannelPage(html, 'ch');
  assert.equal(post.media.url, 'https://cdn/1.jpg');
  assert.deepEqual(post.album.map((m) => m.url), ['https://cdn/2.jpg', 'https://cdn/3.jpg']);
});

test('видео в разметке дважды (плеер и автоповтор) — один ролик, не альбом из двух', () => {
  const html = `
    <div class="tgme_widget_message_wrap"><div data-post="ch/9">
      <video src="https://cdn/file/a1.mp4?token=AAA" class="tgme_widget_message_video js-message_video"></video>
      <video src="https://cdn/file/a1.mp4?token=BBB" class="tgme_widget_message_video js-message_video"></video>
      <div class="tgme_widget_message_text js-message_text">Кот</div>
      <time datetime="2026-10-01T10:00:00+00:00"></time></div></div>`;
  const [post] = parseChannelPage(html, 'ch');
  assert.equal(post.media.kind, 'video');
  assert.deepEqual(post.album, []);
});

test('два разных видео в одном посте остаются альбомом', () => {
  const html = `
    <div class="tgme_widget_message_wrap"><div data-post="ch/10">
      <video src="https://cdn/file/a1.mp4?token=AAA"></video>
      <video src="https://cdn/file/b2.mp4?token=BBB"></video>
      <time datetime="2026-10-01T10:00:00+00:00"></time></div></div>`;
  const [post] = parseChannelPage(html, 'ch');
  assert.equal(post.album.length, 1);
});

const at = (iso) => ({ ref: iso, date: new Date(iso) });

test('план постов: по порядку времени, с зазором, только новее последнего', () => {
  const posts = [
    at('2026-10-13T10:05:00Z'),
    at('2026-10-13T09:00:00Z'),
    at('2026-10-13T10:00:00Z'),
    at('2026-10-13T11:30:00Z'),
    at('2026-10-13T08:00:00Z'),
  ];
  const last = new Date('2026-10-13T08:30:00Z');
  const plan = planPosts(posts, last, 30, 10).map((p) => p.ref);
  // 08:00 старше последнего, 10:05 ближе 30 минут к 10:00.
  assert.deepEqual(plan, ['2026-10-13T09:00:00Z', '2026-10-13T10:00:00Z', '2026-10-13T11:30:00Z']);
});

test('план постов: потолок за заход и пустой канал', () => {
  const posts = [at('2026-10-13T09:00:00Z'), at('2026-10-13T10:00:00Z'), at('2026-10-13T11:00:00Z')];
  assert.equal(planPosts(posts, null, 30, 2).length, 2);
  assert.equal(planPosts([], null, 30, 2).length, 0);
});
