// Отправка push-уведомлений через FCM HTTP v1. Вызывает только база (триггеры
// миграции 0031 через pg_net) с общим секретом в заголовке x-push-secret —
// поэтому функция деплоится с --no-verify-jwt.
//
// Тело: {type: 'message', message_id} или {type: 'notification', notification_id}.
// Текст личных сообщений в пуш не попадает никогда: сервер его и не знает
// (сквозное шифрование), в пуше только «Новое сообщение».
import { createClient } from "npm:@supabase/supabase-js@2";
import { decide, type Prefs } from "./decide.ts";

const WEBHOOK_SECRET = Deno.env.get("PUSH_WEBHOOK_SECRET") ?? "";
const SERVICE_ACCOUNT = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "{}");

const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

type Push = {
  title: string;
  body: string;
  channel: string;
  // Одинаковый tag заменяет прошлое уведомление, а не копит стопку.
  tag: string;
  data: Record<string, string>;
};

Deno.serve(async (req) => {
  if (!WEBHOOK_SECRET || !timingSafeEqual(req.headers.get("x-push-secret") ?? "", WEBHOOK_SECRET)) {
    return new Response("forbidden", { status: 403 });
  }
  if (!SERVICE_ACCOUNT.private_key) {
    return new Response("FCM_SERVICE_ACCOUNT not set", { status: 500 });
  }

  const payload = await req.json().catch(() => null);
  try {
    if (payload?.type === "call" || payload?.type === "call_update") {
      return json(await forCall(payload.call_id, payload.type));
    }
    const jobs = payload?.type === "message"
      ? await forMessage(payload.message_id)
      : payload?.type === "notification"
      ? await forNotification(payload.notification_id)
      : payload?.type === "reaction"
      ? await forReaction(payload.message_id, payload.profile_id)
      : [];

    let sent = 0;
    let total = 0;
    for (const job of jobs) {
      if (job.recipients.length === 0) continue;
      const tokens = await tokensFor(job.recipients);
      total += tokens.length;
      // Цифра на значке приложения у каждого своя — общее число непрочитанных.
      // Только для сообщений: реакции и уведомления число не меняют.
      const counts = new Map<string, number | undefined>();
      if (job.push.data.type === "message") {
        for (const [profile] of tokens) {
          if (counts.has(profile)) continue;
          counts.set(profile, await unreadTotal(profile));
        }
      }
      for (const [profile, token] of tokens) {
        if (await send(token, job.push, counts.get(profile))) sent++;
      }
    }
    return json({ sent, tokens: total });
  } catch (error) {
    console.error("push-send", error);
    return new Response(String(error), { status: 500 });
  }
});

type Job = { recipients: string[]; push: Push };

async function forMessage(messageId: string): Promise<Job[]> {
  let { data: message, error } = await db
    .from("chat_messages")
    .select("id, conversation_id, sender_id, body, kind, silent")
    .eq("id", messageId)
    .maybeSingle();
  if (error) {
    // Колонки silent ещё нет (миграция 0034 не накатана): пуши не должны
    // из-за этого пропасть, шлём обычные.
    ({ data: message } = await db
      .from("chat_messages")
      .select("id, conversation_id, sender_id, body, kind")
      .eq("id", messageId)
      .maybeSingle());
  }
  if (!message) return [];

  const [{ data: conversation }, { data: sender }, { data: members }] = await Promise.all([
    db.from("chat_conversations")
      .select("id, direct_key, title, quest_id, is_channel")
      .eq("id", message.conversation_id)
      .single(),
    db.from("profiles").select("display_name").eq("id", message.sender_id).maybeSingle(),
    db.from("chat_members")
      .select("profile_id")
      .eq("conversation_id", message.conversation_id)
      .neq("profile_id", message.sender_id),
  ]);
  if (!conversation) return [];

  // Кто заблокировал или скрыл автора, пуша от него не получает.
  const { data: blocks } = await db
    .from("user_blocks")
    .select("blocker_id")
    .eq("blocked_id", message.sender_id);
  const blockedBy = new Set((blocks ?? []).map((b) => b.blocker_id));
  const recipients = (members ?? [])
    .map((m) => m.profile_id as string)
    .filter((id) => !blockedBy.has(id));

  const senderName = sender?.display_name ?? "Кто-то";
  // «Отправить без звука» (0034): тот же пуш, но в тихом канале.
  const silent = message.silent === true;
  const channel = "messages";
  let push: Push;
  if (conversation.direct_key) {
    push = {
      title: senderName,
      body: "Новое сообщение",
      channel,
      tag: conversation.id,
      data: {
        type: "message",
        conversation_id: conversation.id,
        title: senderName,
      },
    };
  } else {
    let title = conversation.title as string | null;
    if (!title && conversation.quest_id) {
      const { data: quest } = await db
        .from("quests").select("title").eq("id", conversation.quest_id).maybeSingle();
      title = quest?.title ?? null;
    }
    const isChannel = conversation.is_channel === true;
    title ??= isChannel ? "Канал" : "Группа";
    // Пост канала — от имени канала, без имени админа.
    const preview = groupPreview(message.kind, message.body);
    push = {
      title,
      body: isChannel ? preview : `${senderName}: ${preview}`,
      channel,
      tag: conversation.id,
      data: {
        type: "message",
        conversation_id: conversation.id,
        title,
        ...(isChannel ? { channel: "1" } : {}),
      },
    };
  }

  // Режим чата у каждого получателя свой: разводим по каналам и шлём группами.
  // Таблицы настроек может ещё не быть (миграция 0038) — тогда у всех «со звуком».
  const { data: prefRows } = recipients.length === 0
    ? { data: [] }
    : await db
      .from("chat_notification_prefs")
      .select("profile_id, mode, muted_until")
      .eq("conversation_id", conversation.id)
      .in("profile_id", recipients);
  const prefs = new Map<string, Prefs>(
    (prefRows ?? []).map((p) => [p.profile_id as string, p as Prefs]),
  );

  // Свой звук чата у каждого получателя (0057). Таблицы может ещё не быть — тогда без него.
  const { data: soundRows } = recipients.length === 0
    ? { data: [] }
    : await db
      .from("chat_settings")
      .select("profile_id, sound")
      .eq("conversation_id", conversation.id)
      .in("profile_id", recipients);
  const sounds = new Map<string, string | null>(
    (soundRows ?? []).map((s) => [s.profile_id as string, s.sound as string | null]),
  );

  const now = new Date();
  const byChannel = new Map<string, string[]>();
  for (const id of recipients) {
    const picked = decide(prefs.get(id), silent, now, sounds.get(id));
    if (!picked) continue;
    byChannel.set(picked, [...(byChannel.get(picked) ?? []), id]);
  }
  return [...byChannel].map(([picked, ids]) => ({
    recipients: ids,
    push: { ...push, channel: picked, data: { ...push.data, channel: picked } },
  }));
}

// Реакция на сообщение: пуш получает только его автор. В каналах реакций
// без пуша — под постом их десятки, а автор там системный профиль.
async function forReaction(messageId: string, reactorId: string): Promise<Job[]> {
  const [{ data: message }, { data: reaction }] = await Promise.all([
    db.from("chat_messages").select("id, conversation_id, sender_id").eq("id", messageId).maybeSingle(),
    db.from("chat_message_reactions")
      .select("emoji")
      .eq("message_id", messageId)
      .eq("profile_id", reactorId)
      .maybeSingle(),
  ]);
  if (!message || !reaction || message.sender_id === reactorId) return [];

  const { data: conversation } = await db
    .from("chat_conversations")
    .select("id, direct_key, title, is_channel")
    .eq("id", message.conversation_id)
    .single();
  if (!conversation || conversation.is_channel === true) return [];

  const { data: block } = await db
    .from("user_blocks")
    .select("blocker_id")
    .eq("blocker_id", message.sender_id)
    .eq("blocked_id", reactorId)
    .maybeSingle();
  if (block) return [];

  const { data: reactor } = await db.from("profiles").select("display_name").eq("id", reactorId).maybeSingle();
  const who = reactor?.display_name ?? "Кто-то";

  const { data: pref } = await db
    .from("chat_notification_prefs")
    .select("profile_id, mode, muted_until")
    .eq("conversation_id", conversation.id)
    .eq("profile_id", message.sender_id)
    .maybeSingle();
  const { data: look } = await db
    .from("chat_settings")
    .select("sound")
    .eq("conversation_id", conversation.id)
    .eq("profile_id", message.sender_id)
    .maybeSingle();
  const picked = decide((pref ?? undefined) as Prefs, false, new Date(), look?.sound as string | undefined);
  if (!picked) return [];

  const direct = !!conversation.direct_key;
  const title = direct ? who : (conversation.title ?? "Группа");
  return [{
    recipients: [message.sender_id as string],
    push: {
      title,
      body: direct
        ? `Реакция ${reaction.emoji} на ваше сообщение`
        : `${who}: реакция ${reaction.emoji} на ваше сообщение`,
      channel: picked,
      tag: `${conversation.id}:reaction`,
      data: {
        type: "message",
        conversation_id: conversation.id,
        title,
        channel: picked,
      },
    },
  }];
}

async function forNotification(notificationId: string): Promise<Job[]> {
  const { data: n } = await db
    .from("notifications")
    .select("id, recipient_id, actor_id, kind, target_type, target_id, title")
    .eq("id", notificationId)
    .maybeSingle();
  if (!n) return [];

  let actor = "Кто-то";
  if (n.actor_id) {
    const { data } = await db.from("profiles").select("display_name").eq("id", n.actor_id).maybeSingle();
    actor = data?.display_name ?? actor;
  }

  return [{
    recipients: [n.recipient_id as string],
    push: {
      title: "ChaWo",
      body: notificationText(n.kind, actor, n.title),
      channel: "activity",
      tag: `${n.kind}:${n.target_id}`,
      data: {
        type: "notification",
        notification_id: n.id,
        target_type: n.target_type ?? "",
        target_id: n.target_id ?? "",
      },
    },
  }];
}

// Звонок (0058). Только data-пуш без notification: его ловит приложение даже
// закрытым и само показывает экран входящего (flutter_callkit_incoming).
// 'call' — начал звонить; 'call_update' — звонок принят, сброшен или не
// дождался: телефоны получателя гасят звонилку, непринятый становится
// «пропущенным».
async function forCall(callId: string, type: "call" | "call_update") {
  const { data: call } = await db
    .from("calls")
    .select("id, conversation_id, caller_id, callee_id, video, status, created_at")
    .eq("id", callId)
    .maybeSingle();
  if (!call) return { sent: 0, tokens: 0 };
  if (type === "call" && call.status !== "ringing") return { sent: 0, tokens: 0 };

  const { data: caller } = await db
    .from("profiles")
    .select("display_name, avatar_url")
    .eq("id", call.caller_id)
    .maybeSingle();

  const data: Record<string, string> = {
    type,
    call_id: call.id,
    conversation_id: call.conversation_id,
    caller_id: call.caller_id,
    caller_name: caller?.display_name ?? "ChaWo",
    caller_avatar: caller?.avatar_url ?? "",
    video: call.video ? "1" : "0",
    status: call.status,
    created_at: call.created_at,
  };

  const tokens = await tokensFor([call.callee_id as string]);
  let sent = 0;
  for (const [, token] of tokens) {
    // Звонок старше полуминуты будить уже не должен; итог звонка доставляем
    // и позже — он станет «пропущенным».
    if (await sendData(token, data, type === "call" ? "30s" : "86400s")) sent++;
  }
  return { sent, tokens: tokens.length };
}

async function sendData(token: string, data: Record<string, string>, ttl: string): Promise<boolean> {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${SERVICE_ACCOUNT.project_id}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${await accessToken()}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ message: { token, data, android: { priority: "high", ttl } } }),
    },
  );
  if (response.ok) return true;
  const error = await response.json().catch(() => ({}));
  const code = error?.error?.details?.find((d: { errorCode?: string }) => d.errorCode)?.errorCode;
  if (response.status === 404 || code === "UNREGISTERED" || code === "SENDER_ID_MISMATCH") {
    await db.from("push_tokens").delete().eq("token", token);
  } else {
    console.error("fcm call", response.status, JSON.stringify(error));
  }
  return false;
}

// Те же подписи, что в списке чатов (MessageKind.preview).
function groupPreview(kind: string, body: string | null): string {
  const label: Record<string, string> = {
    image: "📷 Фото",
    video: "🎬 Видео",
    video_note: "🎥 Видеосообщение",
    voice: "🎤 Голосовое",
    file: "📎 Файл",
  };
  const text = body ? truncate(body, 140) : "";
  if (kind === "text" || kind === "sticker") return text || "Сообщение";
  return text ? `${label[kind] ?? "Вложение"} · ${text}` : label[kind] ?? "Вложение";
}

// Те же формулировки, что в приложении (AppNotification.text).
function notificationText(kind: string, who: string, title: string | null): string {
  const about = title ? `: «${truncate(title, 80)}»` : "";
  switch (kind) {
    case "follow": return `${who} — новый подписчик`;
    case "comment": return `${who}: новый комментарий к вашей публикации${about}`;
    case "reply": return `${who}: ответ на ваш комментарий${about}`;
    case "reaction": return `${who}: реакция на вашу публикацию`;
    case "event_join": return `${who} участвует в вашем событии${about}`;
    case "event_changed": return `Событие изменилось${about}`;
    case "event_cancelled": return `Событие отменено${about}`;
    case "message": return `${who}: новое сообщение`;
    case "quest_request": return `${who} хочет в ваш квест${about}`;
    case "quest_join": return `${who} теперь в вашем квесте${about}`;
    case "quest_approved": return `Вас приняли в квест${about}`;
    case "quest_rejected": return `Заявку в квест не приняли${about}`;
    case "quest_removed": return `Вас исключили из квеста${about}`;
    case "quest_cancelled": return `Квест отменён${about}`;
    case "need_response": return `${who} готов помочь с вашей просьбой${about}`;
    default: return "Новое уведомление";
  }
}

/** Пары [профиль, токен]: по профилю считаем число на значке. */
async function tokensFor(profileIds: string[]): Promise<[string, string][]> {
  const { data } = await db.from("push_tokens").select("profile_id, token").in("profile_id", profileIds);
  return (data ?? []).map((t) => [t.profile_id as string, t.token as string]);
}

/** Сколько непрочитанного у человека. Сбой подсчёта не должен ронять пуш. */
async function unreadTotal(profile: string): Promise<number | undefined> {
  const { data, error } = await db.rpc("chat_unread_total", { in_profile: profile });
  if (error) {
    console.error("unread", error.message);
    return undefined;
  }
  return typeof data === "number" ? data : undefined;
}

async function send(token: string, push: Push, badge?: number): Promise<boolean> {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${SERVICE_ACCOUNT.project_id}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${await accessToken()}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: push.title, body: push.body },
          data: push.data,
          android: {
            priority: "high",
            notification: {
              channel_id: push.channel,
              tag: push.tag,
              icon: "ic_notification",
              color: "#E89BBA",
              // Цифра на значке приложения (лаунчеры Samsung, Xiaomi и др.).
              ...(badge && badge > 0 ? { notification_count: badge } : {}),
            },
          },
        },
      }),
    },
  );
  if (response.ok) return true;

  const error = await response.json().catch(() => ({}));
  const code = error?.error?.details?.find((d: { errorCode?: string }) => d.errorCode)?.errorCode;
  // Приложение удалено или токен сменился — больше на него не шлём.
  // INVALID_ARGUMENT сюда не входит: это может быть ошибка в самом пуше, и
  // тогда стёрлись бы рабочие токены.
  if (response.status === 404 || code === "UNREGISTERED" || code === "SENDER_ID_MISMATCH") {
    await db.from("push_tokens").delete().eq("token", token);
  } else {
    console.error("fcm", response.status, JSON.stringify(error));
  }
  return false;
}

// ── OAuth-токен Google из ключа сервисного аккаунта ───────────────────────

let cachedToken: { value: string; expiresAt: number } | null = null;

async function accessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt - 60 > now) return cachedToken.value;

  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: SERVICE_ACCOUNT.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(claims))}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(SERVICE_ACCOUNT.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned)),
  );
  const assertion = `${unsigned}.${b64url(signature)}`;

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const body = await response.json();
  if (!response.ok) throw new Error(`google oauth: ${JSON.stringify(body)}`);
  cachedToken = { value: body.access_token, expiresAt: now + (body.expires_in ?? 3600) };
  return cachedToken.value;
}

function pemToDer(pem: string): ArrayBuffer {
  const base64 = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(base64), (c) => c.charCodeAt(0)).buffer;
}

function b64url(input: string | Uint8Array): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function truncate(text: string, max: number): string {
  return text.length <= max ? text : `${text.slice(0, max - 1)}…`;
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function json(body: unknown): Response {
  return new Response(JSON.stringify(body), { headers: { "Content-Type": "application/json" } });
}
