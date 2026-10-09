// Удаление осиротевших файлов из хранилища (очередь chat_media_trash, 0035,
// с бакетом с 0064): вложения удалённых сообщений и групп, а также файлы
// удалённых аккаунтов. Зовёт только база по pg_cron, с тем же общим секретом,
// что push-send, поэтому деплоится с --no-verify-jwt.
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
    .select("bucket, path")
    .order("queued_at")
    .limit(BATCH);
  if (error) return new Response(error.message, { status: 500 });
  if (!rows || rows.length === 0) return Response.json({ removed: 0 });

  const byBucket = new Map<string, string[]>();
  for (const row of rows) {
    const list = byBucket.get(row.bucket as string) ?? [];
    list.push(row.path as string);
    byBucket.set(row.bucket as string, list);
  }

  let removed = 0;
  const failures: string[] = [];
  for (const [bucket, paths] of byBucket) {
    // Уже удалённый файл Storage просто не вернёт в ответе — это не ошибка,
    // строку очереди всё равно убираем.
    const { error: removeError } = await db.storage.from(bucket).remove(paths);
    if (removeError) {
      failures.push(`${bucket}: ${removeError.message}`);
      continue;
    }
    await db.from("chat_media_trash").delete().eq("bucket", bucket).in("path", paths);
    removed += paths.length;
  }

  if (failures.length > 0) {
    return new Response(failures.join("; "), { status: 500 });
  }
  return Response.json({ removed });
});
