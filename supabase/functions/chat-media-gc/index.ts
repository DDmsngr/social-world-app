// Удаление осиротевших файлов chat-media (очередь chat_media_trash, 0035).
// Зовёт только база по pg_cron, с тем же общим секретом, что push-send,
// поэтому деплоится с --no-verify-jwt.
import { createClient } from "npm:@supabase/supabase-js@2";

const SECRET = Deno.env.get("PUSH_WEBHOOK_SECRET") ?? "";
const BATCH = 500;

const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

Deno.serve(async (req) => {
  if (!SECRET || req.headers.get("x-push-secret") !== SECRET) {
    return new Response("forbidden", { status: 403 });
  }

  const { data: rows, error } = await db
    .from("chat_media_trash")
    .select("path")
    .order("queued_at")
    .limit(BATCH);
  if (error) return new Response(error.message, { status: 500 });
  const paths = (rows ?? []).map((r) => r.path as string);
  if (paths.length === 0) return Response.json({ removed: 0 });

  // Уже удалённый файл Storage просто не вернёт в ответе — это не ошибка,
  // строку очереди всё равно убираем.
  const { error: removeError } = await db.storage.from("chat-media").remove(paths);
  if (removeError) return new Response(removeError.message, { status: 500 });

  await db.from("chat_media_trash").delete().in("path", paths);
  return Response.json({ removed: paths.length });
});
