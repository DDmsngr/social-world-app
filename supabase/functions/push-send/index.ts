// Отправка push-уведомлений через FCM HTTP v1. Вызывает только база (триггеры
// миграции 0031 через pg_net) с общим секретом в заголовке x-push-secret —
// поэтому функция деплоится с --no-verify-jwt.
//
// Тело: {type: 'message', message_id} или {type: 'notification', notification_id}.
// Текст личных сообщений в пуш не попадает никогда: сервер его и не знает
// (сквозное шифрование), в пуше только «Новое сообщение».
import { createClient } from "npm:@supabase/supabase-js@2";

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
  channel: "messages" | "activity";
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
    const job = payload?.type === "message"
      ? await forMessage(payload.message_id)
      : payload?.type === "notification"
      ? await forNotification(payload.notification_id)
      : null;
    if (!job || job.recipients.length === 0) return json({ sent: 0 });

    const tokens = await tokensFor(job.recipients);
    let sent = 0;
    for (const token of tokens) {
      if (await send(token, job.push)) sent++;
    }
    return json({ sent, tokens: tokens.length });
  } catch (error) {
    console.error("push-send", error);
    return new Response(String(error), { status: 500 });
  }
});

async function forMessage(messageId: string) {
  const { data: message } = await db
    .from("chat_messages")
    .select("id, conversation_id, sender_id, body")
    .eq("id", messageId)
    .maybeSingle();
  if (!message) return null;

  const [{ data: conversation }, { data: sender }, { data: members }] = await Promise.all([
    db.from("chat_conversations")
      .select("id, direct_key, title, quest_id")
      .eq("id", message.conversation_id)
      .single(),
    db.from("profiles").select("display_name").eq("id", message.sender_id).maybeSingle(),
    db.from("chat_members")
      .select("profile_id")
      .eq("conversation_id", message.conversation_id)
      .neq("profile_id", message.sender_id),
  ]);
  if (!conversation) return null;

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
  let push: Push;
  if (conversation.direct_key) {
    push = {
      title: senderName,
      body: "Новое сообщение",
      channel: "messages",
      tag: conversation.id,
      data: { type: "message", conversation_id: conversation.id, title: senderName },
    };
  } else {
    let title = conversation.title as string | null;
    if (!title && conversation.quest_id) {
      const { data: quest } = await db
        .from("quests").select("title").eq("id", conversation.quest_id).maybeSingle();
      title = quest?.title ?? null;
    }
    title ??= "Группа";
    push = {
      title,
      body: `${senderName}: ${truncate(message.body ?? "", 140)}`,
      channel: "messages",
      tag: conversation.id,
      data: { type: "message", conversation_id: conversation.id, title },
    };
  }
  return { recipients, push };
}

async function forNotification(notificationId: string) {
  const { data: n } = await db
    .from("notifications")
    .select("id, recipient_id, actor_id, kind, target_type, target_id, title")
    .eq("id", notificationId)
    .maybeSingle();
  if (!n) return null;

  let actor = "Кто-то";
  if (n.actor_id) {
    const { data } = await db.from("profiles").select("display_name").eq("id", n.actor_id).maybeSingle();
    actor = data?.display_name ?? actor;
  }

  return {
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
    } satisfies Push,
  };
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

async function tokensFor(profileIds: string[]): Promise<string[]> {
  const { data } = await db.from("push_tokens").select("token").in("profile_id", profileIds);
  return (data ?? []).map((t) => t.token as string);
}

async function send(token: string, push: Push): Promise<boolean> {
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
