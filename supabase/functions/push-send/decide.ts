// Решение «как беспокоить» для одного получателя сообщения. Чистая функция:
// без обращений к базе, чтобы её можно было проверить тестами.

export type Mode = "sound" | "vibrate" | "silent" | "off";
export type MessageChannel = "messages" | "messages_vibrate" | "messages_silent";

export type Prefs = { mode: Mode; muted_until: string | null } | undefined;

/** `null` — пуш не отправлять. */
export function decide(prefs: Prefs, silentMessage: boolean, now: Date): MessageChannel | null {
  const mode = prefs?.mode ?? "sound";
  if (mode === "off") return null;
  if (prefs?.muted_until && new Date(prefs.muted_until).getTime() > now.getTime()) return null;

  // Отправитель выбрал «без звука» — это сильнее любого режима получателя
  // кроме «выключено».
  if (silentMessage) return "messages_silent";
  if (mode === "vibrate") return "messages_vibrate";
  if (mode === "silent") return "messages_silent";
  return "messages";
}
