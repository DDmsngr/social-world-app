// Наполнитель системных каналов ChaWo из публичных Telegram-каналов.
//
// Как в meme-farm: читаем веб-превью t.me/s/<канал> (без бота и API-ключей),
// выбрасываем рекламу, берём свежее и публикуем в канал ChaWo от имени его
// владельца через RPC channel_feed_post (миграция 0039). Повторов не бывает:
// у каждого поста ключ source_ref = tg:<канал>/<номер>, и база не примет его
// дважды. Состояния между запусками не храним — всё нужное лежит в базе.
//
// Запуск: SUPABASE_URL=… SUPABASE_SERVICE_ROLE_KEY=… node feed.mjs [--dry]

const SUPABASE_URL = process.env.SUPABASE_URL?.replace(/\/$/, '');
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const DRY = process.argv.includes('--dry');

// everyMin — не чаще одного захода в столько минут; perRun — сколько постов за
// заход; maxAgeH — насколько старый пост ещё годится (у редких каналов — дольше).
// credit — подписывать ли источник (у мемов из своего @memepul не нужно).
//
// Источники проверены 02.10.2026 по дате последнего поста; мёртвые (naukapro,
// sochi_news, vcemem и т. п.) не берём. Чем больше источников у канала, тем
// разнообразнее лента: посты разных источников чередуются.
const CHANNELS = [
  { handle: 'chawo_memes', sources: ['memepul', 'prikol'], everyMin: 20, perRun: 2, maxAgeH: 24, credit: false },
  { handle: 'chawo_news', sources: ['tass_agency', 'rbc_news', 'interfaxonline', 'kommersant', 'vedomosti', 'izvestia_ru', 'lentadnya', 'bbbreaking'], everyMin: 10, perRun: 2 },
  { handle: 'chawo_science', sources: ['nplusone', 'habr_com', 'rozetked', 'postnauka', 'ixbt_official', 'tproger_official'], everyMin: 30, perRun: 2, maxAgeH: 24 },
  { handle: 'chawo_fashion', sources: ['LIVfashionmag', 'trendsetter', 'looktrend', 'goldchihuahua', 'beautyinsider'], everyMin: 45, perRun: 2, maxAgeH: 72 },
  { handle: 'chawo_food', sources: ['thesaltmagazine', 'topretsept', 'kulinarka', 'foodblogger'], everyMin: 45, perRun: 2, maxAgeH: 36 },
  { handle: 'chawo_sochi', sources: ['sochi24tv', 'sochi_online', 'sochi_today', 'sochigid', 'kuban24'], everyMin: 15, perRun: 2, maxAgeH: 24 },
  { handle: 'chawo_travel', sources: ['tutu_travel', 'aviasales'], everyMin: 60, perRun: 1, maxAgeH: 48 },
  { handle: 'chawo_kino', sources: ['kinopoisk', 'kineman'], everyMin: 60, perRun: 1, maxAgeH: 96 },
  { handle: 'chawo_sport', sources: ['sportsru', 'championat', 'sovsport'], everyMin: 20, perRun: 2 },
];

const MAX_AGE_HOURS = 12;
// Бесплатный Supabase Cloud не принимает файлы больше 50 МБ.
const MAX_MEDIA_BYTES = 45 * 1024 * 1024;
const BROWSER_UA =
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';

// ── реклама ───────────────────────────────────────────────────────────────
// Из meme-farm, без политических стоп-слов: здесь есть канал новостей.
// \b с кириллицей не работает, поэтому границы через \p{L}.
const AD_SOFT = [
  /промокод/i,
  /скидк[аиоуеы]/i,
  /купон/i,
  /(?<!\p{L})бонус\p{L}*(?!\p{L})/iu,
  /подпи[шс](ись|итесь|аться|ывай)|подписка на канал/i,
  /переход(и|ите)\s+по\s+ссылке|по\s+ссылке\s+ниже/i,
  /наш(и)?\s+канал|мой\s+канал|канал\s+друг/i,
];
const AD_HARD = [
  /#реклама|#ad\b|#промо|#partner/i,
  /(?<!\p{L})реклам[аеуы](?!\p{L})/iu,
  /(?<!\p{L})erid(?!\p{L})/iu, // маркировка рекламы по закону
  /без\s+вложени[йя]/iu,
  /перейти\s+в\s+бота|начать\s+зарабатывать|вывод\s+баланса/iu,
  /(?:блог|канал)\s*["«][^"»]{1,40}["»]/iu,
];

function isAd(text) {
  if (!text) return false;
  if (AD_HARD.some((re) => re.test(text))) return true;
  return AD_SOFT.filter((re) => re.test(text)).length >= 2;
}

// ── разбор t.me/s ─────────────────────────────────────────────────────────

const ENTITIES = {
  amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', hellip: '…',
  mdash: '—', ndash: '–', laquo: '«', raquo: '»', ldquo: '"', rdquo: '"',
  lsquo: "'", rsquo: "'", middot: '·', bull: '•',
};

function decodeEntities(s) {
  return s
    .replace(/&#(\d+);?/g, (_, d) => String.fromCodePoint(parseInt(d, 10)))
    .replace(/&#x([0-9a-f]+);?/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&([a-z]+);?/gi, (m, name) => ENTITIES[name.toLowerCase()] ?? m);
}

// Markdown-символы в обычном тексте экранируем, чтобы «*» из новости не
// превратился в курсив.
const escapeMd = (s) => s.replace(/([\\*_`\[\]])/g, '\\$1');

/** HTML текста поста → Markdown: ссылки, жирный, курсив, переносы. */
export function htmlToMarkdown(html) {
  // Эмодзи Telegram рисует картинкой внутри <i class="emoji"><b>🚗</b></i> —
  // оставляем сам символ, иначе получится «_**🚗**_».
  html = html.replace(/<i class="emoji"[^>]*>([\s\S]*?)<\/i>/gi, (_, inner) => inner.replace(/<[^>]+>/g, ''));
  let out = '';
  // Открывающий маркер ставим только перед первым видимым символом, а
  // закрывающий — до хвостовых пробелов и переносов: «**Заголовок\n\n**»
  // Markdown жирным не считает.
  let pending = '';
  const write = (text) => {
    if (pending) {
      const lead = /^\s*/.exec(text)[0];
      if (lead.length === text.length) {
        out += text;
        return;
      }
      out += lead + pending + text.slice(lead.length);
      pending = '';
    } else {
      out += text;
    }
  };
  const close = (marker) => {
    if (pending) {
      pending = ''; // пустой жирный — не ставим ничего
      return;
    }
    const tail = /\s*$/.exec(out)[0];
    out = out.slice(0, out.length - tail.length) + marker + tail;
  };

  const re = /<a\s+[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>|<br\s*\/?>|<(\/?)(b|strong|i|em)\b[^>]*>|<[^>]+>|([^<]+)/gi;
  let m;
  while ((m = re.exec(html))) {
    if (m[1] !== undefined) {
      const label = escapeMd(decodeEntities(m[2].replace(/<[^>]+>/g, '')).trim());
      const href = decodeEntities(m[1]);
      if (!/^https?:\/\//i.test(href)) {
        write(label); // хэштеги и упоминания — просто текстом
      } else if (label) {
        write(`[${label}](${href.replace(/\)/g, '%29')})`);
      }
    } else if (/^<br/i.test(m[0])) {
      out += '\n';
    } else if (m[4]) {
      const tag = m[4].toLowerCase();
      const marker = tag === 'b' || tag === 'strong' ? '**' : '_';
      if (m[3]) close(marker);
      else pending = marker;
    } else if (m[5] !== undefined) {
      write(escapeMd(decodeEntities(m[5])));
    }
  }
  return out
    .replace(/[ \t]+\n/g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

// Подвал источника: «✔ Подписывайтесь на ТАСС», «Наш канал | Прислать
// новость», ссылка на сам канал. Срезаем короткие последние абзацы с такими
// словами, сколько бы их ни было.
const FOOTER_RE = /подпи[сш]|прислать\s+новост|предложить\s+новост|наш\s+канал|все\s+(?:наши\s+)?каналы|каналы\s+дня|наши\s+соц\.?\s*сети|t\.me\//iu;

export function stripSignature(text) {
  const lines = text.split('\n');
  while (lines.length > 1) {
    const last = lines[lines.length - 1].trim();
    if (last === '' || (last.length <= 160 && FOOTER_RE.test(last))) lines.pop();
    else break;
  }
  return lines.join('\n').trim();
}

/** Посты одного Telegram-канала: новые в конце. */
export function parseChannelPage(html, channel) {
  const posts = [];
  for (const block of html.split('tgme_widget_message_wrap').slice(1)) {
    const id = /data-post="([^"]+)"/.exec(block)?.[1];
    if (!id) continue;
    // Кружки, опросы и пересланное из других каналов не берём.
    if (/roundvideo|tgme_widget_message_poll|tgme_widget_message_forwarded_from/i.test(block)) continue;

    const date = /<time[^>]*datetime="([^"]+)"/.exec(block)?.[1];
    const textHtml = /<div class="tgme_widget_message_text[^"]*"[^>]*>([\s\S]*?)<\/div>/.exec(block)?.[1] ?? '';
    const video = /<video[^>]*\ssrc=["']([^"']+)["']/.exec(block)?.[1];
    const photo = /tgme_widget_message_photo_wrap[\s\S]*?background-image:url\('([^']+)'/.exec(block)?.[1];
    const tooBig = /message_media_not_supported/i.test(block);
    if (tooBig && !textHtml) continue;

    posts.push({
      ref: `tg:${id}`,
      channel,
      url: `https://t.me/${id}`,
      date: date ? new Date(date) : null,
      text: stripSignature(htmlToMarkdown(textHtml)),
      plain: decodeEntities(textHtml.replace(/<br\s*\/?>/gi, '\n').replace(/<[^>]+>/g, '')),
      media: video ? { kind: 'video', url: video, mime: 'video/mp4' }
        : photo ? { kind: 'image', url: photo, mime: 'image/jpeg' }
        : null,
    });
  }
  return posts;
}

async function fetchChannel(channel) {
  const r = await fetch(`https://t.me/s/${channel}`, { headers: { 'User-Agent': BROWSER_UA } });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return parseChannelPage(await r.text(), channel);
}

// ── Supabase ──────────────────────────────────────────────────────────────

const headers = () => ({
  apikey: SERVICE_KEY,
  Authorization: `Bearer ${SERVICE_KEY}`,
});

async function rest(path, init = {}) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: { ...headers(), 'Content-Type': 'application/json', ...(init.headers ?? {}) },
  });
  const body = await r.text();
  if (!r.ok) throw new Error(`${path}: ${r.status} ${body}`);
  return body ? JSON.parse(body) : null;
}

async function channelState(handle) {
  const [conv] = await rest(`chat_conversations?select=id&handle=eq.${handle}&is_channel=is.true`);
  if (!conv) return null;
  const [last] = await rest(
    `chat_messages?select=sent_at&conversation_id=eq.${conv.id}&deleted_at=is.null&order=sent_at.desc&limit=1`,
  );
  return { id: conv.id, lastAt: last ? new Date(last.sent_at) : null };
}

async function knownRefs(conversationId, refs) {
  if (refs.length === 0) return new Set();
  const list = refs.map((r) => `"${r.replace(/"/g, '')}"`).join(',');
  const rows = await rest(
    `chat_messages?select=source_ref&conversation_id=eq.${conversationId}&source_ref=in.(${encodeURIComponent(list)})`,
  );
  return new Set(rows.map((r) => r.source_ref));
}

async function uploadMedia(conversationId, media) {
  const r = await fetch(media.url, { headers: { 'User-Agent': BROWSER_UA } });
  if (!r.ok) throw new Error(`media HTTP ${r.status}`);
  const bytes = Buffer.from(await r.arrayBuffer());
  if (bytes.length === 0 || bytes.length > MAX_MEDIA_BYTES) return null;
  const path = `${conversationId}/${crypto.randomUUID()}`;
  const up = await fetch(`${SUPABASE_URL}/storage/v1/object/chat-media/${path}`, {
    method: 'POST',
    headers: { ...headers(), 'Content-Type': media.mime, 'x-upsert': 'false' },
    body: bytes,
  });
  if (!up.ok) throw new Error(`upload ${up.status} ${await up.text()}`);
  return {
    kind: media.kind,
    json: { path, size: bytes.length, mime: media.mime, name: media.kind === 'video' ? 'video.mp4' : 'photo.jpg' },
  };
}

async function publish(handle, post, credit) {
  const state = await channelState(handle);
  let body = post.text;
  if (credit) body = `${body}${body ? '\n\n' : ''}[Источник: @${post.channel}](${post.url})`;
  let kind = 'text';
  let media = null;
  if (post.media) {
    try {
      const uploaded = await uploadMedia(state.id, post.media);
      if (uploaded) {
        kind = uploaded.kind;
        media = uploaded.json;
      }
    } catch (e) {
      console.warn(`  медиа не загрузилось (${post.ref}): ${e.message}`);
    }
  }
  if (!media && !post.text) return false; // без картинки и текста постить нечего
  const id = await rest('rpc/channel_feed_post', {
    method: 'POST',
    body: JSON.stringify({
      in_handle: handle,
      in_source_ref: post.ref,
      in_kind: kind,
      in_body: body.slice(0, 4000),
      in_media: media,
    }),
  });
  return id !== null;
}

// ── главный проход ────────────────────────────────────────────────────────

async function feedChannel(cfg) {
  const state = await channelState(cfg.handle);
  if (!state) {
    console.warn(`[${cfg.handle}] канала нет в базе — пропуск`);
    return;
  }
  const sinceLast = state.lastAt ? (Date.now() - state.lastAt.getTime()) / 60000 : Infinity;
  if (sinceLast < cfg.everyMin) {
    console.log(`[${cfg.handle}] рано: последний пост ${Math.round(sinceLast)} мин назад`);
    return;
  }

  const results = await Promise.allSettled(cfg.sources.map(fetchChannel));
  const fresh = Date.now() - (cfg.maxAgeH ?? MAX_AGE_HOURS) * 3600_000;
  let candidates = results
    .flatMap((r, i) => {
      if (r.status === 'rejected') console.warn(`[${cfg.handle}] @${cfg.sources[i]}: ${r.reason.message}`);
      return r.status === 'fulfilled' ? r.value : [];
    })
    .filter((p) => p.date && p.date.getTime() > fresh)
    .filter((p) => !isAd(p.plain));

  const known = await knownRefs(state.id, candidates.map((p) => p.ref));
  candidates = candidates
    .filter((p) => !known.has(p.ref))
    // Старые из свежих — первыми: лента канала идёт по порядку.
    .sort((a, b) => a.date - b.date);

  // Чередуем источники, чтобы канал не стал зеркалом одного.
  const bySource = new Map();
  for (const p of candidates) bySource.set(p.channel, [...(bySource.get(p.channel) ?? []), p]);
  const queue = [];
  while (queue.length < candidates.length) {
    for (const list of bySource.values()) if (list.length) queue.push(list.shift());
  }

  let posted = 0;
  for (const post of queue) {
    if (posted >= cfg.perRun) break;
    if (DRY) {
      console.log(`[${cfg.handle}] (dry) ${post.ref} ${post.media?.kind ?? 'text'} ${post.text.slice(0, 80)}`);
      posted++;
      continue;
    }
    try {
      if (await publish(cfg.handle, post, cfg.credit !== false)) {
        console.log(`[${cfg.handle}] + ${post.ref}`);
        posted++;
      }
    } catch (e) {
      console.warn(`[${cfg.handle}] ${post.ref}: ${e.message}`);
    }
  }
  if (posted === 0) console.log(`[${cfg.handle}] нового нет`);
}

async function main() {
  if (!SUPABASE_URL || !SERVICE_KEY) {
    console.error('Нужны SUPABASE_URL и SUPABASE_SERVICE_ROLE_KEY');
    process.exit(1);
  }
  for (const cfg of CHANNELS) {
    try {
      await feedChannel(cfg);
    } catch (e) {
      console.error(`[${cfg.handle}] ${e.message}`);
    }
  }
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith('feed.mjs')) {
  await main();
}
