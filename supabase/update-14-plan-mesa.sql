-- =====================================================================
-- update-14 · Plan «table» (Carta + Panel + Mesa)
-- Ejecutar DESPUÉS de update-13. Se puede correr más de una vez.
--
--   update public.settings set plan = 'table';   -- Carta + Panel + Mesa
--
-- Incluye: carta, edición completa de productos, pedidos desde el QR de cada mesa
-- y panel de pedidos. No incluye retiro ni delivery.
-- =====================================================================

alter table public.settings drop constraint if exists settings_plan_valid;
alter table public.settings add constraint settings_plan_valid
  check (plan in ('menu', 'menu_panel', 'table', 'orders', 'full'));

-- Pedidos por mesa: 'table' y 'full'. Retiro y delivery: 'orders' y 'full'.
create or replace function public.settings_plan_guard()
returns trigger
language plpgsql
as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.plan := old.plan;
  end if;

  if new.plan not in ('table', 'full') then
    new.ordering_enabled := false;
  end if;

  if new.plan not in ('orders', 'full') then
    new.pickup_enabled := false;
    new.delivery_enabled := false;
  end if;

  return new;
end;
$$;

-- Categorías: se editan con 'table', 'orders' y 'full'.
create or replace function public.categories_plan_guard()
returns trigger
language plpgsql
as $$
begin
  if current_user = 'authenticated' and public.current_plan() not in ('table', 'orders', 'full') then
    raise exception 'plan_not_allowed';
  end if;

  return coalesce(new, old);
end;
$$;

-- Fotos de productos: 'table', 'orders' y 'full'.
drop policy if exists product_images_insert on storage.objects;
drop policy if exists product_images_update on storage.objects;
drop policy if exists product_images_delete on storage.objects;

create policy product_images_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'product-images' and public.is_manager() and public.current_plan() in ('table', 'orders', 'full'));

create policy product_images_update on storage.objects
  for update to authenticated
  using (bucket_id = 'product-images' and public.is_manager() and public.current_plan() in ('table', 'orders', 'full'))
  with check (bucket_id = 'product-images' and public.is_manager() and public.current_plan() in ('table', 'orders', 'full'));

create policy product_images_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'product-images' and public.is_manager() and public.current_plan() in ('table', 'orders', 'full'));

update public.settings set plan = plan where id = 1;
