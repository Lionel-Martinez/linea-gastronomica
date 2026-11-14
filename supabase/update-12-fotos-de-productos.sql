-- =====================================================================
-- update-12 · Fotos de productos subidas desde el celular o la compu
-- Ejecutar DESPUÉS de update-11. Se puede correr más de una vez.
--
-- Crea el depósito público «product-images» (solo imágenes, hasta 1 MB cada una).
-- Cualquiera puede VER las fotos (son de la carta pública); solo el encargado
-- puede subirlas, reemplazarlas o borrarlas.
-- =====================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('product-images', 'product-images', true, 1048576, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = true,
      file_size_limit = 1048576,
      allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

drop policy if exists product_images_select on storage.objects;
drop policy if exists product_images_insert on storage.objects;
drop policy if exists product_images_update on storage.objects;
drop policy if exists product_images_delete on storage.objects;

create policy product_images_select on storage.objects
  for select to authenticated
  using (bucket_id = 'product-images' and public.is_manager());

create policy product_images_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'product-images' and public.is_manager());

create policy product_images_update on storage.objects
  for update to authenticated
  using (bucket_id = 'product-images' and public.is_manager())
  with check (bucket_id = 'product-images' and public.is_manager());

create policy product_images_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'product-images' and public.is_manager());
