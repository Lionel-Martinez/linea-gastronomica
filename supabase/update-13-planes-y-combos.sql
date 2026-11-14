-- =====================================================================
-- update-13 · Planes (combos) por local
-- Ejecutar DESPUÉS de update-12. Se puede correr más de una vez.
--
-- Cada local tiene UN plan, que cambia solo LM Studio desde el SQL Editor:
--
--   update public.settings set plan = 'menu';        -- Carta
--   update public.settings set plan = 'menu_panel';  -- Carta + Panel
--   update public.settings set plan = 'orders';      -- Pedidos y delivery
--   update public.settings set plan = 'full';        -- Completo
--
-- El encargado del local NO puede cambiarlo (la base lo ignora).
-- Los locales que ya existen quedan en 'full' (nada cambia para ellos).
--
-- Qué hace la base según el plan:
--   · Pedidos por mesa: solo en 'full'.
--   · Retiro y delivery: solo en 'orders' y 'full'.
--   · 'menu': el local no edita productos (los carga LM Studio).
--   · 'menu_panel': el local solo cambia precios y «disponible»
--     (no crea ni borra productos, no sube fotos).
--   · 'orders' y 'full': el local edita todo.
-- =====================================================================

alter table public.settings add column if not exists plan text not null default 'full';

do $$
begin
  alter table public.settings add constraint settings_plan_valid
    check (plan in ('menu', 'menu_panel', 'orders', 'full'));
exception when duplicate_object then null;
end $$;

-- Plan vigente (para usar en reglas de otras tablas).
create or replace function public.current_plan()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select plan from public.settings where id = 1
$$;

revoke all on function public.current_plan() from public;
grant execute on function public.current_plan() to anon, authenticated;

-- Ajustes: el plan no lo cambia el local, y las formas de pedido respetan el plan.
create or replace function public.settings_plan_guard()
returns trigger
language plpgsql
as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.plan := old.plan;
  end if;

  if new.plan <> 'full' then
    new.ordering_enabled := false;
  end if;

  if new.plan not in ('orders', 'full') then
    new.pickup_enabled := false;
    new.delivery_enabled := false;
  end if;

  return new;
end;
$$;

drop trigger if exists settings_plan_guard on public.settings;
create trigger settings_plan_guard
  before update on public.settings
  for each row execute function public.settings_plan_guard();

-- Productos: qué puede editar el local según el plan.
create or replace function public.products_plan_guard()
returns trigger
language plpgsql
as $$
declare
  v_plan text;
begin
  -- Solo limita al personal que edita desde el panel (no a las funciones internas ni al SQL Editor).
  if current_user <> 'authenticated' then
    return coalesce(new, old);
  end if;

  v_plan := public.current_plan();

  if v_plan = 'menu' then
    raise exception 'plan_not_allowed';
  end if;

  if v_plan = 'menu_panel' then
    if tg_op <> 'UPDATE' then
      raise exception 'plan_not_allowed';
    end if;

    if new.category_id is distinct from old.category_id
       or new.name is distinct from old.name
       or new.description is distinct from old.description
       or new.image is distinct from old.image
       or new.featured is distinct from old.featured
       or new.sort_order is distinct from old.sort_order then
      raise exception 'plan_not_allowed';
    end if;
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists products_plan_guard on public.products;
create trigger products_plan_guard
  before insert or update or delete on public.products
  for each row execute function public.products_plan_guard();

-- Categorías: solo se editan con 'orders' o 'full'.
create or replace function public.categories_plan_guard()
returns trigger
language plpgsql
as $$
begin
  if current_user = 'authenticated' and public.current_plan() not in ('orders', 'full') then
    raise exception 'plan_not_allowed';
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists categories_plan_guard on public.categories;
create trigger categories_plan_guard
  before insert or update or delete on public.categories
  for each row execute function public.categories_plan_guard();

-- Fotos de productos: solo con 'orders' o 'full'.
drop policy if exists product_images_insert on storage.objects;
drop policy if exists product_images_update on storage.objects;
drop policy if exists product_images_delete on storage.objects;

create policy product_images_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'product-images' and public.is_manager() and public.current_plan() in ('orders', 'full'));

create policy product_images_update on storage.objects
  for update to authenticated
  using (bucket_id = 'product-images' and public.is_manager() and public.current_plan() in ('orders', 'full'))
  with check (bucket_id = 'product-images' and public.is_manager() and public.current_plan() in ('orders', 'full'));

create policy product_images_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'product-images' and public.is_manager() and public.current_plan() in ('orders', 'full'));

-- Se aplica el plan a lo que ya está guardado.
update public.settings set plan = plan where id = 1;
