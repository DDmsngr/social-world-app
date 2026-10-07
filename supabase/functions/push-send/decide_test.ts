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

Deno.test("свой звук чата — канал с этим звуком, но не пробивает вибрацию, тишину и «выключено»", () => {
  assertEquals(decide(undefined, false, now, "pop"), "messages_pop");
  assertEquals(decide({ mode: "vibrate", muted_until: null }, false, now, "pop"), "messages_vibrate");
  assertEquals(decide({ mode: "silent", muted_until: null }, false, now, "pop"), "messages_silent");
  assertEquals(decide(undefined, true, now, "pop"), "messages_silent");
  assertEquals(decide({ mode: "off", muted_until: null }, false, now, "pop"), null);
});

Deno.test("неизвестный звук игнорируется: канал обычный", () => {
  assertEquals(decide(undefined, false, now, "dubstep"), "messages");
  assertEquals(decide(undefined, false, now, null), "messages");
});