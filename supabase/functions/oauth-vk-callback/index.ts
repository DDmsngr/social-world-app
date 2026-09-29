// Redirect_uri, прописанный в приложении VK ID. Принимает code+state(+device_id),
// меняет на токен, забирает профиль через /oauth2/user_info (не users.get —
// это POST с client_id+access_token в теле, а не GET с заголовком, отсюда и
// весь этот мост вместо штатного custom-провайдера GoTrue) и выдаёт сессию.
import {
  PUBLIC_BASE_URL,
  mintSession,
  pkceConsume,
  redirectError,
  redirectToApp,
  resolveProfile,
} from "../_shared/oauth.ts";

const CLIENT_ID = Deno.env.get("VK_CLIENT_ID")!;
const CLIENT_SECRET = Deno.env.get("VK_CLIENT_SECRET")!;
const REDIRECT_URI = `${PUBLIC_BASE_URL}/functions/v1/oauth-vk-callback`;

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);
  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");
  const deviceId = url.searchParams.get("device_id");
  const vkError = url.searchParams.get("error");

  if (vkError) return redirectError(`vk:${vkError}`);
  if (!code || !state) return redirectError("vk:missing_code_or_state");

  try {
    const pkce = await pkceConsume(state);
    if (!pkce || !pkce.code_verifier) {
      return redirectError("vk:expired_or_unknown_state");
    }

    const tokenBody = new URLSearchParams({
      grant_type: "authorization_code",
      client_id: CLIENT_ID,
      client_secret: CLIENT_SECRET,
      redirect_uri: REDIRECT_URI,
      code,
      code_verifier: pkce.code_verifier,
    });
    if (deviceId) tokenBody.set("device_id", deviceId);

    const tokenRes = await fetch("https://id.vk.ru/oauth2/auth", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: tokenBody,
    });
    if (!tokenRes.ok) {
      console.error("vk token exchange failed", await tokenRes.text());
      return redirectError("vk:token_exchange_failed");
    }
    const token = await tokenRes.json();
    const accessToken = token.access_token as string | undefined;
    const userId = token.user_id as string | number | undefined;
    if (!accessToken || userId === undefined) {
      return redirectError("vk:no_access_token");
    }

    const emailFromIdToken = token.id_token
      ? emailFromJwt(token.id_token as string)
      : null;

    const userInfoRes = await fetch("https://id.vk.ru/oauth2/user_info", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ client_id: CLIENT_ID, access_token: accessToken }),
    });
    let vkUser: Record<string, unknown> = {};
    if (userInfoRes.ok) {
      const parsed = await userInfoRes.json();
      vkUser = parsed.user ?? {};
    } else {
      console.error("vk user_info failed", await userInfoRes.text());
    }

    const displayName = [vkUser.first_name, vkUser.last_name]
      .filter(Boolean)
      .join(" ")
      .trim() || null;

    const externalId = String(userId);
    await resolveProfile("vk", {
      externalId,
      email: emailFromIdToken,
      displayName,
      avatarUrl: (vkUser.avatar as string | undefined) ?? null,
    });

    const session = await mintSession("vk", externalId);
    return redirectToApp({
      access_token: session.access_token,
      refresh_token: session.refresh_token,
    });
  } catch (e) {
    console.error("vk callback error", e);
    return redirectError("vk:internal_error");
  }
});

function emailFromJwt(jwt: string): string | null {
  try {
    const payloadPart = jwt.split(".")[1];
    const json = atob(payloadPart.replace(/-/g, "+").replace(/_/g, "/"));
    const payload = JSON.parse(json);
    return payload.email ?? null;
  } catch {
    return null;
  }
}
