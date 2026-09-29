// Открывает эту страницу системный браузер из Flutter. У Яндекса, в отличие
// от VK ID, PKCE не обязателен — это классический authorization code flow.
import { PUBLIC_BASE_URL, pkceStore, randomUrlSafe } from "../_shared/oauth.ts";

const CLIENT_ID = Deno.env.get("YANDEX_CLIENT_ID")!;
const REDIRECT_URI = `${PUBLIC_BASE_URL}/functions/v1/oauth-yandex-callback`;

Deno.serve(async () => {
  const state = randomUrlSafe(24);
  // code_verifier здесь не нужен — сохраняем пустую запись только чтобы
  // callback мог отличить "неизвестный state" от "ещё не пришёл".
  await pkceStore(state, "yandex", "");

  const params = new URLSearchParams({
    response_type: "code",
    client_id: CLIENT_ID,
    redirect_uri: REDIRECT_URI,
    scope: "login:email login:info login:avatar",
    state,
  });

  return new Response(null, {
    status: 302,
    headers: { Location: `https://oauth.yandex.ru/authorize?${params.toString()}` },
  });
});
