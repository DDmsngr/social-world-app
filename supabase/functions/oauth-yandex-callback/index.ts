// Redirect URI, прописанный в OAuth-приложении Яндекса. Меняет code на
// токен, читает профиль с login.yandex.ru/info — этот эндпоинт требует
// заголовок "Authorization: OAuth <token>", а не "Bearer", поэтому через
// штатный custom-провайдер GoTrue (жёстко шлёт Bearer) не пройти.
import {
  PUBLIC_BASE_URL,
  mintSession,
  pkceConsume,
  redirectError,
  redirectToApp,
  resolveProfile,
} from "../_shared/oauth.ts";

const CLIENT_ID = Deno.env.get("YANDEX_CLIENT_ID")!;
const CLIENT_SECRET = Deno.env.get("YANDEX_CLIENT_SECRET")!;
const REDIRECT_URI = `${PUBLIC_BASE_URL}/functions/v1/oauth-yandex-callback`;

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);
  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");
  const yandexError = url.searchParams.get("error");

  if (yandexError) return redirectError(`yandex:${yandexError}`);
  if (!code || !state) return redirectError("yandex:missing_code_or_state");

  try {
    // Значение code_verifier тут пустое и не нужно — важен сам факт, что
    // state существовал (см. oauth-yandex-start).
    const pkce = await pkceConsume(state);
    if (!pkce) return redirectError("yandex:expired_or_unknown_state");

    const tokenRes = await fetch("https://oauth.yandex.ru/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "authorization_code",
        code,
        client_id: CLIENT_ID,
        client_secret: CLIENT_SECRET,
        redirect_uri: REDIRECT_URI,
      }),
    });
    if (!tokenRes.ok) {
      console.error("yandex token exchange failed", await tokenRes.text());
      return redirectError("yandex:token_exchange_failed");
    }
    const token = await tokenRes.json();
    const accessToken = token.access_token as string | undefined;
    if (!accessToken) return redirectError("yandex:no_access_token");

    const infoRes = await fetch("https://login.yandex.ru/info?format=json", {
      headers: { Authorization: `OAuth ${accessToken}` },
    });
    if (!infoRes.ok) {
      console.error("yandex login.info failed", await infoRes.text());
      return redirectError("yandex:userinfo_failed");
    }
    const info = await infoRes.json();

    const avatarUrl = info.is_avatar_empty
      ? null
      : `https://avatars.yandex.net/get-yapic/${info.default_avatar_id}/islands-200`;

    const externalId = String(info.id);
    await resolveProfile("yandex", {
      externalId,
      email: info.default_email ?? null,
      displayName: info.display_name ?? info.real_name ?? null,
      avatarUrl,
    });

    const session = await mintSession("yandex", externalId);
    return redirectToApp({
      access_token: session.access_token,
      refresh_token: session.refresh_token,
    });
  } catch (e) {
    console.error("yandex callback error", e);
    return redirectError("yandex:internal_error");
  }
});
