import { test } from 'node:test';
import assert from 'node:assert/strict';
import { htmlToMarkdown, stripSignature, parseChannelPage } from './feed.mjs';

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
});
