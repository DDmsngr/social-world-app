-- spatial_ref_sys — справочник PostGIS. У него выключен RLS, а у anon и
-- authenticated были права на INSERT/UPDATE/DELETE: публичный ключ из APK
-- позволял стереть строки и сломать все гео-функции. Таблицей владеет
-- supabase_admin, поэтому файл накатывается от этой роли (psql -U supabase_admin).
--
-- Читать справочник должен authenticated: ST_Transform и другие функции
-- обращаются к нему от имени вызывающего.

revoke all on public.spatial_ref_sys from public, anon, authenticated;
grant select on public.spatial_ref_sys to authenticated;
