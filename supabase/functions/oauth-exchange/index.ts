// Обмен одноразового кода входа на сессию (см. миграцию 0065).
//
// Приложение присылает {code, secret}. Код мы выдали в конце входа через
// VK ID / Яндекс ID; секрет приложение придумало перед входом, а нам при
// старте отдало только его хеш. Совпало — выпускаем сессию. Код сгорает при
// любом исходе: подобрать секрет по одному коду нельзя, и украденный из ссылки
// код без секрета бесполезен. Функция публичная (запрос идёт до входа),
// поэтому деплоится с --no-verify-jwt.
import { loginCodeConsume, mintSession, safeEqual, sha256Base64Url } from "../_shared/oauth.ts";

const fail = (status: number, error: string) =>
  Response.json({ error }, { status, headers: { "Cache-Control": "no-store" } });

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return fail(405, "method_not_allowed");

  let body: { code?: unknown; secret?: unknown };
  try {
    body = await req.json();
  } catch {
    return fail(400, "bad_request");
  }
  const code = typeof body.code === "string" ? body.code : "";
  const secret = typeof body.secret === "string" ? body.secret : "";
  if (code.length < 20 || code.length > 128 || secret.length < 20 || secret.length > 128) {
    return fail(400, "bad_request");
  }

  try {
    const row = await loginCodeConsume(code);
    if (!row) return fail(400, "invalid_or_expired");

    const hash = await sha256Base64Url(secret);
    if (!safeEqual(hash, row.challenge)) return fail(400, "invalid_or_expired");

    const session = await mintSession(row.provider, row.external_id);
    return Response.json(
      { access_token: session.access_token, refresh_token: session.refresh_token },
      { headers: { "Cache-Control": "no-store" } },
    );
  } catch (e) {
    console.error("oauth-exchange error", e);
    return fail(500, "internal_error");
  }
});
