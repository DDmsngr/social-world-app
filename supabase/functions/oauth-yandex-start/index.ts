// Открывает эту страницу системный браузер из Flutter. У Яндекса, в отличие
// от VK ID, PKCE не обязателен — это классический authorization code flow.
import {
  ALLOW_LEGACY,
  PUBLIC_BASE_URL,
  pkceStore,
  randomUrlSafe,
  validChallenge,
} from "../_shared/oauth.ts";

const CLIENT_ID = Deno.env.get("YANDEX_CLIENT_ID")!;
const REDIRECT_URI = `${PUBLIC_BASE_URL}/functions/v1/oauth-yandex-callback`;

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
  // code_verifier здесь не нужен — сохраняем пустую запись только чтобы
  // callback мог отличить "неизвестный state" от "ещё не пришёл".
  await pkceStore(state, "yandex", "", appChallenge);

  const params = new URLSearchParams({
    response_type: "code",
    client_id: CLIENT_ID,
    redirect_uri: REDIRECT_URI,
    scope: "login:email login:info login:avatar login:default_phone",
    state,
  });

  return new Response(null, {
    status: 302,
    headers: { Location: `https://oauth.yandex.ru/authorize?${params.toString()}` },
  });
});
