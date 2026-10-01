import { assertEquals } from "jsr:@std/assert@1";
import { decide } from "./decide.ts";

const now = new Date("2026-10-01T12:00:00Z");

Deno.test("без настроек — со звуком", () => {
  assertEquals(decide(undefined, false, now), "messages");
});

Deno.test("выключен — не отправлять", () => {
  assertEquals(decide({ mode: "off", muted_until: null }, false, now), null);
});

Deno.test("таймер в будущем — не отправлять, в прошлом — отправлять", () => {
  assertEquals(decide({ mode: "sound", muted_until: "2026-10-01T13:00:00Z" }, false, now), null);
  assertEquals(decide({ mode: "sound", muted_until: "2026-10-01T11:00:00Z" }, false, now), "messages");
});

Deno.test("режимы выбирают канал", () => {
  assertEquals(decide({ mode: "vibrate", muted_until: null }, false, now), "messages_vibrate");
  assertEquals(decide({ mode: "silent", muted_until: null }, false, now), "messages_silent");
});

Deno.test("«без звука» от отправителя — тихий канал, но не пробивает «выключено»", () => {
  assertEquals(decide(undefined, true, now), "messages_silent");
  assertEquals(decide({ mode: "vibrate", muted_until: null }, true, now), "messages_silent");
  assertEquals(decide({ mode: "off", muted_until: null }, true, now), null);
});

Deno.test("таймер при режиме «вибрация» тоже глушит", () => {
  assertEquals(decide({ mode: "vibrate", muted_until: "2026-10-01T12:30:00Z" }, false, now), null);
});
