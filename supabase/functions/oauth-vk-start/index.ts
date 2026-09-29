// Открывает эту страницу системный браузер из Flutter. VK ID (id.vk.ru) —
// OAuth 2.1 с обязательным PKCE, поэтому verifier генерируем и прячем здесь,
// а не в приложении: обмен кода на токен идёт с client_secret, ему не место
// в мобильной сборке.
import { PUBLIC_BASE_URL, pkceStore, randomUrlSafe, sha256Base64Url } from "../_shared/oauth.ts";

const CLIENT_ID = Deno.env.get("VK_CLIENT_ID")!;
const REDIRECT_URI = `${PUBLIC_BASE_URL}/functions/v1/oauth-vk-callback`;

Deno.serve(async () => {
  const state = randomUrlSafe(24);
  const verifier = randomUrlSafe(48);
  const challenge = await sha256Base64Url(verifier);

  await pkceStore(state, "vk", verifier);

  const params = new URLSearchParams({
    response_type: "code",
    client_id: CLIENT_ID,
    redirect_uri: REDIRECT_URI,
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
