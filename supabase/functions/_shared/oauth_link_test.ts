import { assertEquals } from "jsr:@std/assert@1";

// Модуль читает окружение при загрузке — задаём его до импорта.
Deno.env.set("SUPABASE_URL", "http://db.test");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service");
Deno.env.set("SUPABASE_ANON_KEY", "anon");
const { resolveProfile, authEmailFor } = await import("./oauth.ts");

type Call = { url: string; method: string; body: unknown };

/** Подмена fetch: роутер по подстроке адреса, журнал вызовов. */
function stub(routes: Record<string, (call: Call) => unknown>) {
  const calls: Call[] = [];
  const original = globalThis.fetch;
  globalThis.fetch = (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    const body = init?.body ? JSON.parse(String(init.body)) : null;
    const call = { url, method: init?.method ?? "GET", body };
    calls.push(call);
    const key = Object.keys(routes).find((k) => url.includes(k));
    const out = key ? routes[key](call) : null;
    const status = out instanceof Error ? 500 : 200;
    return Promise.resolve(
      new Response(JSON.stringify(out instanceof Error ? { error: out.message } : out), { status }),
    );
  };
  return { calls, restore: () => (globalThis.fetch = original) };
}

const person = { externalId: "42", email: null, displayName: "Алексей", avatarUrl: null };

Deno.test("известный вход возвращает свой профиль и номер не спрашивает", async () => {
  const s = stub({ "oauth_identities?provider": () => [{ profile_id: "p-own" }] });
  try {
    assertEquals(await resolveProfile("vk", { ...person, phone: "+7 900 123-45-67" }), "p-own");
    assertEquals(s.calls.some((c) => c.url.includes("profile_by_verified_phone")), false);
  } finally {
    s.restore();
  }
});

Deno.test("новый вход с номером, который уже у аккаунта, привязывается к нему", async () => {
  const s = stub({
    "oauth_identities?provider": () => [],
    "profile_by_verified_phone": () => "p-yandex",
    "rest/v1/oauth_identities": () => null,
  });
  try {
    const id = await resolveProfile("vk", { ...person, phone: "+7 900 123-45-67" });
    assertEquals(id, "p-yandex");
    const link = s.calls.find((c) => c.method === "POST" && c.url.endsWith("/rest/v1/oauth_identities"));
    assertEquals(link?.body, { provider: "vk", external_id: "42", profile_id: "p-yandex", email: null });
    assertEquals(s.calls.some((c) => c.url.includes("/auth/v1/admin/users")), false, "второй профиль не заводится");
  } finally {
    s.restore();
  }
});

Deno.test("номера нет или он ничей — заводится новый профиль, как раньше", async () => {
  for (const phone of [undefined, "+7 900 123-45-67"]) {
    const s = stub({
      "oauth_identities?provider": () => [],
      "profile_by_verified_phone": () => null,
      "/auth/v1/admin/users": () => ({ id: "p-new" }),
      "rest/v1/oauth_identities": () => null,
      "rest/v1/profiles": () => null,
    });
    try {
      assertEquals(await resolveProfile("vk", { ...person, phone }), "p-new");
      assertEquals(s.calls.some((c) => c.url.includes("/auth/v1/admin/users")), true);
    } finally {
      s.restore();
    }
  }
});

Deno.test("база без функции (миграция не накатана) не ломает вход: профиль заводится", async () => {
  const s = stub({
    "oauth_identities?provider": () => [],
    "profile_by_verified_phone": () => new Error("function not found"),
    "/auth/v1/admin/users": () => ({ id: "p-new" }),
    "rest/v1/oauth_identities": () => null,
    "rest/v1/profiles": () => null,
  });
  try {
    assertEquals(await resolveProfile("yandex", { ...person, phone: "+7 900 123-45-67" }), "p-new");
  } finally {
    s.restore();
  }
});

Deno.test("сессия привязанного входа выпускается на email настоящего аккаунта", async () => {
  const s = stub({
    "oauth_identities?provider": () => [{ profile_id: "p-yandex" }],
    "/auth/v1/admin/users/p-yandex": () => ({ id: "p-yandex", email: "yandex.7@id.socialworld.internal" }),
  });
  try {
    assertEquals(await authEmailFor("vk", "42"), "yandex.7@id.socialworld.internal");
  } finally {
    s.restore();
  }
});

Deno.test("обычный вход: email тот же синтетический; при сбое поиска — запасной", async () => {
  const ok = stub({
    "oauth_identities?provider": () => [{ profile_id: "p1" }],
    "/auth/v1/admin/users/p1": () => ({ email: "vk.42@id.socialworld.internal" }),
  });
  try {
    assertEquals(await authEmailFor("vk", "42"), "vk.42@id.socialworld.internal");
  } finally {
    ok.restore();
  }
  const broken = stub({ "oauth_identities?provider": () => new Error("db down") });
  try {
    assertEquals(await authEmailFor("vk", "42"), "vk.42@id.socialworld.internal");
  } finally {
    broken.restore();
  }
});
