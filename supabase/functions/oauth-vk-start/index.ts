// Открывает эту страницу системный браузер из Flutter. VK ID (id.vk.ru) —
// OAuth 2.1 с обязательным PKCE, поэтому verifier генерируем и прячем здесь,
// а не в приложении: обмен кода на токен идёт с client_secret, ему не место
// в мобильной сборке.
import {
  ALLOW_LEGACY,
  PUBLIC_BASE_URL,
  pkceStore,
  randomUrlSafe,
  sha256Base64Url,
  validChallenge,
} from "../_shared/oauth.ts";

const CLIENT_ID = Deno.env.get("VK_CLIENT_ID")!;
const REDIRECT_URI = `${PUBLIC_BASE_URL}/functions/v1/oauth-vk-callback`;

Deno.serve(async (req: Request) => {
  // Хеш секрета приложения (см. миграцию 0065): без него токены уйдут в
  // ссылку, как в старых версиях, — пока это разрешено.
  const appChallenge = new URL(req.url).searchParams.get("app_challenge");
  if (appChallenge !== null && !validChallenge(appChallenge)) {
    return new Response("bad app_challenge", { status: 400 });
  }
  if (appChallenge === null && !ALLOW_LEGACY) {
    return new Response("update the app", { status: 400 });
  }

  const state = randomUrlSafe(24);
  const verifier = randomUrlSafe(48);
  const challenge = await sha256Base64Url(verifier);

  await pkceStore(state, "vk", verifier, appChallenge);

  const params = new URLSearchParams({
    response_type: "code",
    client_id: CLIENT_ID,
    redirect_uri: REDIRECT_URI,
    // Право `phone` добавить сюда ("email phone"), когда VK одобрит его в
    // кабинете VK ID: до этого запрос с ним может отклониться.
    scope: "email",
    state,
    code_challenge: challenge,
    code_challenge_method: "S256",
  });

  return new Response(null, {
    status: 302,
    headers: { Location: `https://id.vk.ru/authorize?${params.toString()}` },
  });
});
