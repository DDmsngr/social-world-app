import { assertEquals } from "jsr:@std/assert@1";
import { hashPhone, normalizePhone, phoneHashFrom } from "./phone.ts";

Deno.test("разные записи одного номера дают один хеш", async () => {
  const variants = ["+7 (900) 123-45-67", "8 900 123 45 67", "89001234567", "9001234567", "7-900-123-45-67"];
  const hashes = new Set<string>();
  for (const v of variants) hashes.add((await phoneHashFrom(v))!);
  assertEquals(hashes.size, 1);
  assertEquals(normalizePhone("8 900 123 45 67"), "79001234567");
});

// Эталон посчитан отдельно (sha256 от «79001234567»): клиентский Dart-код
// даёт то же значение, иначе сверка контактов не найдёт никого.
Deno.test("хеш — SHA-256 в hex", async () => {
  assertEquals(
    await hashPhone("79001234567"),
    "da3cc66efc5e1894feb632d7dc0d2426e15465775b88be1635a0cad3b8884415",
  );
});

Deno.test("короткое, длинное и не строка — не номер", async () => {
  assertEquals(normalizePhone("112"), null);
  assertEquals(normalizePhone("1234567890123456"), null);
  assertEquals(await phoneHashFrom(undefined), null);
  assertEquals(await phoneHashFrom(79001234567), null);
});

Deno.test("иностранный номер сохраняется как есть", () => {
  assertEquals(normalizePhone("+44 20 7946 0958"), "442079460958");
});
