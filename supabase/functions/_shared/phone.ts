// Номер телефона → хеш для сверки контактов. Правила те же, что у клиента
// (lib/features/invite/data/contacts_match.dart): только цифры, российский
// формат приводится к 7XXXXXXXXXX, слишком короткое и длинное — не номер.

export function normalizePhone(raw: string): string | null {
  let digits = raw.replace(/\D/g, "");
  if (digits.length === 11 && digits.startsWith("8")) {
    digits = `7${digits.slice(1)}`;
  } else if (digits.length === 10) {
    digits = `7${digits}`;
  }
  if (digits.length < 10 || digits.length > 15) return null;
  return digits;
}

export async function hashPhone(normalized: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(normalized));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Хеш номера из того, что вернул провайдер входа; null — номера нет или он битый. */
export async function phoneHashFrom(raw: unknown): Promise<string | null> {
  if (typeof raw !== "string") return null;
  const normalized = normalizePhone(raw);
  return normalized ? await hashPhone(normalized) : null;
}
