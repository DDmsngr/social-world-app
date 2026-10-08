// Общий помощник для мостов входа VK ID / Яндекс ID. GoTrue (self-hosted,
// v2.196.0) умеет "Custom OAuth2 providers", но только по стандартной форме
// (GET userinfo + заголовок Authorization: Bearer). Ни VK ID
// (POST /oauth2/user_info с client_id+access_token в теле, ответ {user:{}}),
// ни Яндекс (заголовок "Authorization: OAuth", не "Bearer") в неё не влезают —
// поэтому обмен кодами и профиль делаем сами, а сессию всё равно выпускает
// настоящий GoTrue через generate_link + verify.

import { phoneHashFrom } from "./phone.ts";

export const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
export const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
export const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

// Публичный адрес, который видит браузер/VK/Яндекс — внутри self-hosted
// контейнера SUPABASE_URL указывает на приватный http://api-gw:8000, поэтому
// там задан отдельный SUPABASE_PUBLIC_URL. На Supabase Cloud завести секрет
// с префиксом SUPABASE_ нельзя (зарезервировано платформой), но там
// автоматически подставляемый SUPABASE_URL уже и есть публичный адрес —
// используем его как запасной вариант.
export const PUBLIC_BASE_URL = Deno.env.get("SUPABASE_PUBLIC_URL") ?? SUPABASE_URL;

// Кастомная схема приложения — сюда редиректим браузер в конце обмена вместе
// с токенами сессии во фрагменте (#), чтобы они не осели в серверных логах.
export const APP_CALLBACK = "socialworld://auth-callback";

export function randomUrlSafe(bytes = 32): string {
  const arr = new Uint8Array(bytes);
  crypto.getRandomValues(arr);
  return base64UrlEncode(arr);
}

export async function sha256Base64Url(input: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(input),
  );
  return base64UrlEncode(new Uint8Array(digest));
}

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function restHeaders(extra?: Record<string, string>) {
  return {
    apikey: SERVICE_ROLE_KEY,
    Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    "Content-Type": "application/json",
    ...extra,
  };
}

/** Срок жизни записи входа: хватает на весь экран согласия у провайдера. */
const PKCE_TTL_MS = 10 * 60 * 1000;

/** Срок жизни одноразового кода, который приложение меняет на сессию. */
export const LOGIN_CODE_TTL_MS = 2 * 60 * 1000;

/**
 * Принимать ли вход старых версий приложения, которые не присылают
 * app_challenge и получают токены прямо в ссылке (небезопасно, см. 0065).
 * Выключается переменной окружения OAUTH_ALLOW_LEGACY=false, когда все
 * обновятся.
 */
export const ALLOW_LEGACY = Deno.env.get("OAUTH_ALLOW_LEGACY") !== "false";

/** Хеш секрета приложения: base64url от SHA-256, ровно 43 знака. */
export function validChallenge(value: string | null): value is string {
  return value !== null && /^[A-Za-z0-9_-]{43}$/.test(value);
}

/** Кладёт code_verifier и хеш секрета приложения на время входа. */
export async function pkceStore(
  state: string,
  provider: string,
  codeVerifier: string,
  appChallenge: string | null = null,
): Promise<void> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/oauth_pkce_state`, {
    method: "POST",
    headers: restHeaders({ Prefer: "return=minimal" }),
    body: JSON.stringify({
      state,
      provider,
      code_verifier: codeVerifier,
      app_challenge: appChallenge,
    }),
  });
  if (!res.ok) {
    throw new Error(`pkce store failed: ${res.status} ${await res.text()}`);
  }
}

/** Читает и сразу удаляет запись — код авторизации одноразовый. Запись
 * старше 10 минут считается несуществующей. */
export async function pkceConsume(
  state: string,
): Promise<
  { provider: string; code_verifier: string | null; app_challenge: string | null } | null
> {
  const url =
    `${SUPABASE_URL}/rest/v1/oauth_pkce_state?state=eq.${encodeURIComponent(state)}&select=provider,code_verifier,app_challenge,created_at`;
  const res = await fetch(url, { headers: restHeaders() });
  if (!res.ok) return null;
  const rows = await res.json();
  if (!Array.isArray(rows) || rows.length === 0) return null;

  await fetch(
    `${SUPABASE_URL}/rest/v1/oauth_pkce_state?state=eq.${encodeURIComponent(state)}`,
    { method: "DELETE", headers: restHeaders() },
  );

  const age = Date.now() - new Date(rows[0].created_at as string).getTime();
  if (!(age >= 0 && age <= PKCE_TTL_MS)) return null;
  return rows[0];
}

/** Кладёт одноразовый код входа. Возвращает сам код для ссылки в приложение. */
export async function loginCodeStore(
  provider: string,
  externalId: string,
  challenge: string,
): Promise<string> {
  const code = randomUrlSafe(32);
  const res = await fetch(`${SUPABASE_URL}/rest/v1/oauth_login_codes`, {
    method: "POST",
    headers: restHeaders({ Prefer: "return=minimal" }),
    body: JSON.stringify({ code, provider, external_id: externalId, challenge }),
  });
  if (!res.ok) {
    throw new Error(`login code store failed: ${res.status} ${await res.text()}`);
  }
  return code;
}

/** Забирает код: запись удаляется при любом исходе, второй попытки нет. Код
 * старше двух минут считается несуществующим. */
export async function loginCodeConsume(
  code: string,
): Promise<{ provider: string; external_id: string; challenge: string } | null> {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/oauth_login_codes?code=eq.${encodeURIComponent(code)}`,
    {
      method: "DELETE",
      headers: restHeaders({ Prefer: "return=representation" }),
    },
  );
  if (!res.ok) return null;
  const rows = await res.json();
  if (!Array.isArray(rows) || rows.length === 0) return null;
  const age = Date.now() - new Date(rows[0].created_at as string).getTime();
  if (!(age >= 0 && age <= LOGIN_CODE_TTL_MS)) return null;
  return rows[0];
}

/** Сравнение строк за постоянное время. */
export function safeEqual(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  const n = Math.max(x.length, y.length);
  for (let i = 0; i < n; i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

export interface ExternalProfile {
  externalId: string;
  email: string | null;
  displayName: string | null;
  avatarUrl: string | null;
}

/**
 * Находит существующую привязку provider+externalId или заводит нового
 * пользователя. Возвращает profile_id (== auth.users.id).
 */
export async function resolveProfile(
  provider: string,
  profile: ExternalProfile,
): Promise<string> {
  const lookupUrl =
    `${SUPABASE_URL}/rest/v1/oauth_identities?provider=eq.${provider}&external_id=eq.${encodeURIComponent(profile.externalId)}&select=profile_id`;
  const existing = await fetch(lookupUrl, { headers: restHeaders() });
  if (existing.ok) {
    const rows = await existing.json();
    if (Array.isArray(rows) && rows.length > 0) {
      return rows[0].profile_id as string;
    }
  }

  // Синтетический email — не почтовый ящик, а стабильный идентификатор
  // аккаунта в auth.users. Реальный email (если провайдер его дал) хранится
  // отдельно в oauth_identities.email только для справки.
  const syntheticEmail = `${provider}.${profile.externalId}@id.socialworld.internal`;

  const createRes = await fetch(`${SUPABASE_URL}/auth/v1/admin/users`, {
    method: "POST",
    headers: restHeaders(),
    body: JSON.stringify({
      email: syntheticEmail,
      email_confirm: true,
      user_metadata: {
        display_name: profile.displayName,
        avatar_url: profile.avatarUrl,
        oauth_provider: provider,
      },
    }),
  });
  if (!createRes.ok) {
    throw new Error(
      `admin.createUser failed: ${createRes.status} ${await createRes.text()}`,
    );
  }
  const created = await createRes.json();
  const profileId = created.id ?? created.user?.id;
  if (!profileId) throw new Error("admin.createUser: no id in response");

  const linkRes = await fetch(`${SUPABASE_URL}/rest/v1/oauth_identities`, {
    method: "POST",
    headers: restHeaders({ Prefer: "return=minimal" }),
    body: JSON.stringify({
      provider,
      external_id: profile.externalId,
      profile_id: profileId,
      email: profile.email,
    }),
  });
  if (!linkRes.ok) {
    throw new Error(
      `oauth_identities insert failed: ${linkRes.status} ${await linkRes.text()}`,
    );
  }

  if (profile.displayName || profile.avatarUrl) {
    await fetch(`${SUPABASE_URL}/rest/v1/profiles?id=eq.${profileId}`, {
      method: "PATCH",
      headers: restHeaders({ Prefer: "return=minimal" }),
      body: JSON.stringify({
        display_name: profile.displayName ?? undefined,
        avatar_url: profile.avatarUrl ?? undefined,
      }),
    });
  }

  return profileId as string;
}

/**
 * Подтверждённый номер от провайдера входа (Яндекс login:default_phone, VK
 * phone). Сбой не должен ломать вход: номер — приятное дополнение, а не
 * условие, поэтому ошибки только в лог.
 */
export async function saveVerifiedPhone(profileId: string, rawPhone: unknown): Promise<void> {
  try {
    const hash = await phoneHashFrom(rawPhone);
    if (!hash) return;
    const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/set_verified_phone`, {
      method: "POST",
      headers: restHeaders(),
      body: JSON.stringify({ p_profile: profileId, p_hash: hash }),
    });
    if (!res.ok) console.error("set_verified_phone failed", res.status, await res.text());
  } catch (e) {
    console.error("saveVerifiedPhone", e);
  }
}

/** Стандартный приём для входа через провайдера, которого GoTrue не знает:
 * generate_link выдаёт одноразовый токен на существующего пользователя,
 * verify его сразу гасит и возвращает настоящую сессию. */
export async function mintSession(
  provider: string,
  externalId: string,
): Promise<{ access_token: string; refresh_token: string }> {
  const email = `${provider}.${externalId}@id.socialworld.internal`;

  const linkRes = await fetch(`${SUPABASE_URL}/auth/v1/admin/generate_link`, {
    method: "POST",
    headers: restHeaders(),
    body: JSON.stringify({ type: "magiclink", email }),
  });
  if (!linkRes.ok) {
    throw new Error(
      `generate_link failed: ${linkRes.status} ${await linkRes.text()}`,
    );
  }
  const linkData = await linkRes.json();
  const hashedToken = linkData.hashed_token ?? linkData.properties?.hashed_token;
  if (!hashedToken) throw new Error("generate_link: no hashed_token in response");

  // token_hash идёт БЕЗ email — GoTrue иначе трактует это как сырой
  // token и пересчитывает хеш заново от чужого значения (см. verify.go):
  // тогда сравнение с сохранённым хешем не совпадает и приходит
  // "otp_expired", даже если токен свежий.
  const verifyRes = await fetch(`${SUPABASE_URL}/auth/v1/verify`, {
    method: "POST",
    headers: { apikey: ANON_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ type: "magiclink", token_hash: hashedToken }),
  });
  if (!verifyRes.ok) {
    throw new Error(`verify failed: ${verifyRes.status} ${await verifyRes.text()}`);
  }
  const session = await verifyRes.json();
  if (!session.access_token || !session.refresh_token) {
    throw new Error("verify: no session tokens in response");
  }
  return session;
}

export function redirectToApp(params: Record<string, string>): Response {
  const fragment = new URLSearchParams(params).toString();
  return new Response(null, {
    status: 302,
    headers: { Location: `${APP_CALLBACK}#${fragment}` },
  });
}

/** Редирект в приложение с одноразовым кодом. Токенов в ссылке нет: сессию
 * приложение получит в oauth-exchange, предъявив секрет, хеш которого мы
 * запомнили при старте входа. */
export function redirectWithCode(code: string): Response {
  return new Response(null, {
    status: 302,
    headers: { Location: `${APP_CALLBACK}?code=${encodeURIComponent(code)}` },
  });
}

/**
 * Конец входа: новое приложение (прислало app_challenge) получает код,
 * старое — токены в ссылке, пока это разрешено (ALLOW_LEGACY).
 */
export async function finishLogin(
  provider: string,
  externalId: string,
  appChallenge: string | null,
): Promise<Response> {
  if (appChallenge) {
    return redirectWithCode(await loginCodeStore(provider, externalId, appChallenge));
  }
  if (!ALLOW_LEGACY) return redirectError(`${provider}:update_app`);
  const session = await mintSession(provider, externalId);
  return redirectToApp({
    access_token: session.access_token,
    refresh_token: session.refresh_token,
  });
}

export function redirectError(message: string): Response {
  return redirectToApp({ error: message });
}
