-- =====================================================================
-- update-16 · Un solo Supabase para varios locales (multi-local)
-- Ejecutar DESPUÉS de update-15. Se puede correr más de una vez.
--
-- Qué hace:
--  * Crea la tabla `tenants` (los locales) y le agrega `tenant_id` a las tablas del sistema.
--  * Los datos que ya existían pasan a ser el local «demo».
--  * Cada usuario del personal pertenece a UN solo local; las políticas de seguridad y las
--    funciones filtran siempre por local. Un local nunca ve ni toca los datos de otro.
--  * El local de cada consulta se resuelve en la base:
--      - personal con login  -> el local de su fila en `staff` (no se puede falsear);
--      - clientes (sin login) -> el encabezado `x-tenant` que manda cada sitio publicado.
--
-- Administración (solo desde el SQL Editor, nunca desde la app):
--   select public.create_tenant('mi-local', 'Mi Local', 'table');   -- crear un local
--   select public.add_staff('encargado@mi-local.com', 'mi-local', 'manager');
--   select public.set_tenant_plan('mi-local', 'full');
--   select public.suspend_tenant('mi-local', true);                  -- falta de pago
--   select public.use_tenant('mi-local');                            -- para scripts de carga
-- =====================================================================

-- 1) Locales ------------------------------------------------------------
create table if not exists public.tenants (
  id         uuid primary key default gen_random_uuid(),
  slug       text not null unique check (slug ~ '^[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])?$'),
  name       text not null check (char_length(name) between 1 and 80),
  created_at timestamptz not null default now()
);

alter table public.tenants enable row level security;  -- sin políticas: nadie la lee desde la app
revoke all on public.tenants from anon, authenticated;

-- 2) Columna tenant_id en cada tabla -----------------------------------------
alter table public.staff          add column if not exists tenant_id uuid;
alter table public.settings       add column if not exists tenant_id uuid;
alter table public.categories     add column if not exists tenant_id uuid;
alter table public.products       add column if not exists tenant_id uuid;
alter table public.orders         add column if not exists tenant_id uuid;
alter table public.blocked_phones add column if not exists tenant_id uuid;
alter table public.delivery_zones add column if not exists tenant_id uuid;

-- 3) Lo que ya existía pasa a ser el local «demo» -------------------------------
insert into public.tenants (slug, name)
select 'demo', 'Demo'
where not exists (select 1 from public.tenants);

alter table public.orders disable trigger user;
alter table public.products disable trigger user;

do $$
declare
  v_demo uuid := (select id from public.tenants where slug = 'demo');
begin
  if v_demo is not null then
    update public.staff          set tenant_id = v_demo where tenant_id is null;
    update public.settings       set tenant_id = v_demo where tenant_id is null;
    update public.categories     set tenant_id = v_demo where tenant_id is null;
    update public.products       set tenant_id = v_demo where tenant_id is null;
    update public.orders         set tenant_id = v_demo where tenant_id is null;
    update public.blocked_phones set tenant_id = v_demo where tenant_id is null;
    update public.delivery_zones set tenant_id = v_demo where tenant_id is null;
  end if;
end $$;

alter table public.orders enable trigger user;
alter table public.products enable trigger user;

alter table public.staff          alter column tenant_id set not null;
alter table public.settings       alter column tenant_id set not null;
alter table public.categories     alter column tenant_id set not null;
alter table public.products       alter column tenant_id set not null;
alter table public.orders         alter column tenant_id set not null;
alter table public.blocked_phones alter column tenant_id set not null;
alter table public.delivery_zones alter column tenant_id set not null;

-- 4) Claves, únicos y relaciones por local -------------------------------------
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'staff_tenant_fkey') then
    alter table public.staff add constraint staff_tenant_fkey
      foreign key (tenant_id) references public.tenants (id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'settings_tenant_fkey') then
    alter table public.settings add constraint settings_tenant_fkey
      foreign key (tenant_id) references public.tenants (id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'categories_tenant_fkey') then
    alter table public.categories add constraint categories_tenant_fkey
      foreign key (tenant_id) references public.tenants (id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'products_tenant_fkey') then
    alter table public.products add constraint products_tenant_fkey
      foreign key (tenant_id) references public.tenants (id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'orders_tenant_fkey') then
    alter table public.orders add constraint orders_tenant_fkey
      foreign key (tenant_id) references public.tenants (id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'blocked_phones_tenant_fkey') then
    alter table public.blocked_phones add constraint blocked_phones_tenant_fkey
      foreign key (tenant_id) references public.tenants (id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'delivery_zones_tenant_fkey') then
    alter table public.delivery_zones add constraint delivery_zones_tenant_fkey
      foreign key (tenant_id) references public.tenants (id) on delete cascade;
  end if;
end $$;

-- settings: una fila por local
alter table public.settings drop constraint if exists settings_id_check;
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.settings'::regclass and contype = 'p'
       and pg_get_constraintdef(oid) like '%tenant_id%'
  ) then
    alter table public.settings drop constraint if exists settings_pkey;
    alter table public.settings add primary key (tenant_id);
  end if;
end $$;

-- categorías: el identificador (texto) se repite entre locales, por eso la clave es (local, id)
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.categories'::regclass and contype = 'p'
       and pg_get_constraintdef(oid) like '%tenant_id%'
  ) then
    alter table public.products drop constraint if exists products_category_id_fkey;
    alter table public.categories drop constraint if exists categories_pkey;
    alter table public.categories add primary key (tenant_id, id);
  end if;

  if not exists (select 1 from pg_constraint where conname = 'products_category_fkey') then
    alter table public.products add constraint products_category_fkey
      foreign key (tenant_id, category_id) references public.categories (tenant_id, id) on update cascade;
  end if;
end $$;

-- teléfonos bloqueados: por local
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.blocked_phones'::regclass and contype = 'p'
       and pg_get_constraintdef(oid) like '%tenant_id%'
  ) then
    alter table public.blocked_phones drop constraint if exists blocked_phones_pkey;
    alter table public.blocked_phones add primary key (tenant_id, phone);
  end if;
end $$;

-- zonas de delivery: el nombre es único dentro de cada local
drop index if exists public.delivery_zones_name_key;
create unique index if not exists delivery_zones_tenant_name_key
  on public.delivery_zones (tenant_id, lower(name));

create index if not exists staff_tenant_idx          on public.staff (tenant_id);
create index if not exists orders_tenant_status_idx  on public.orders (tenant_id, status, created_at);
create index if not exists products_tenant_idx       on public.products (tenant_id, category_id);

-- 5) ¿De qué local es esta consulta? ---------------------------------------------
-- Personal con login: su local (de la tabla staff). Clientes: el encabezado x-tenant.
create or replace function public.tid()
returns uuid
language sql
stable
security definer
set search_path to 'public'
as $$
  select coalesce(
    (select s.tenant_id from public.staff s where s.user_id = auth.uid()),
    (select t.id from public.tenants t
      where t.slug = (nullif(current_setting('request.headers', true), '')::json ->> 'x-tenant'))
  );
$$;

grant execute on function public.tid() to anon, authenticated;

-- A partir de ahora todo lo que se inserta lleva el local de quien lo inserta.
-- (staff: sirve para cargarlo desde el SQL Editor después de select public.use_tenant('x'); la app no puede escribir en staff)
alter table public.staff          alter column tenant_id set default public.tid();
alter table public.categories     alter column tenant_id set default public.tid();
alter table public.products       alter column tenant_id set default public.tid();
alter table public.orders         alter column tenant_id set default public.tid();
alter table public.blocked_phones alter column tenant_id set default public.tid();
alter table public.delivery_zones alter column tenant_id set default public.tid();

-- Diagnóstico: devuelve el identificador del local que ve esta conexión (o null).
create or replace function public.whoami_tenant()
returns text
language sql
stable
security definer
set search_path to 'public'
as $$
  select slug from public.tenants where id = public.tid();
$$;

grant execute on function public.whoami_tenant() to anon, authenticated;

-- 6) Políticas de seguridad: todas filtran por local ------------------------------
drop policy if exists categories_read   on public.categories;
drop policy if exists categories_write  on public.categories;
drop policy if exists products_read     on public.products;
drop policy if exists products_write    on public.products;
drop policy if exists zones_read        on public.delivery_zones;
drop policy if exists zones_write       on public.delivery_zones;
drop policy if exists settings_read     on public.settings;
drop policy if exists settings_update   on public.settings;
drop policy if exists blocked_staff     on public.blocked_phones;
drop policy if exists orders_select     on public.orders;
drop policy if exists orders_update     on public.orders;
drop policy if exists order_items_select    on public.order_items;
drop policy if exists contacts_select       on public.order_contacts;

create policy categories_read on public.categories for select to anon, authenticated
  using (tenant_id = (select public.tid()));
create policy categories_write on public.categories for all to authenticated
  using (public.is_manager() and tenant_id = (select public.tid()))
  with check (public.is_manager() and tenant_id = (select public.tid()));

create policy products_read on public.products for select to anon, authenticated
  using (tenant_id = (select public.tid()));
create policy products_write on public.products for all to authenticated
  using (public.is_manager() and tenant_id = (select public.tid()))
  with check (public.is_manager() and tenant_id = (select public.tid()));

create policy zones_read on public.delivery_zones for select to anon, authenticated
  using (tenant_id = (select public.tid()));
create policy zones_write on public.delivery_zones for all to authenticated
  using (public.is_manager() and tenant_id = (select public.tid()))
  with check (public.is_manager() and tenant_id = (select public.tid()));

create policy settings_read on public.settings for select to anon, authenticated
  using (tenant_id = (select public.tid()));
create policy settings_update on public.settings for update to authenticated
  using (public.is_manager() and tenant_id = (select public.tid()))
  with check (public.is_manager() and tenant_id = (select public.tid()));

create policy blocked_staff on public.blocked_phones for all to authenticated
  using (public.has_role('manager', 'counter') and tenant_id = (select public.tid()))
  with check (public.has_role('manager', 'counter') and tenant_id = (select public.tid()));

create policy orders_select on public.orders for select to authenticated
  using (
    tenant_id = (select public.tid())
    and (
      public.has_role('manager', 'counter', 'kitchen')
      or (public.staff_role() = 'waiter' and modality = 'dine_in')
      or (
        public.staff_role() = 'courier' and modality = 'delivery'
        and (
          status = 'ready'
          or (status = 'on_the_way' and run_by = auth.uid())
          or (status = 'delivered' and run_by = auth.uid() and finished_at > now() - interval '12 hours')
        )
      )
    )
  );

create policy orders_update on public.orders for update to authenticated
  using (
    tenant_id = (select public.tid())
    and (
      public.has_role('manager', 'counter', 'kitchen')
      or (public.staff_role() = 'waiter' and modality = 'dine_in')
      or (
        public.staff_role() = 'courier' and modality = 'delivery'
        and status = 'on_the_way' and run_by = auth.uid()
      )
    )
  )
  with check (public.is_staff() and tenant_id = (select public.tid()));

create policy order_items_select on public.order_items for select to authenticated
  using (
    public.is_staff()
    and exists (
      select 1 from public.orders o
       where o.id = order_items.order_id and o.tenant_id = (select public.tid())
    )
  );

create policy contacts_select on public.order_contacts for select to authenticated
  using (
    exists (
      select 1 from public.orders o
       where o.id = order_contacts.order_id
         and o.tenant_id = (select public.tid())
         and (
           public.has_role('manager', 'counter')
           or (
             public.staff_role() = 'courier' and o.modality = 'delivery'
             and (o.status = 'ready' or (o.status = 'on_the_way' and o.run_by = auth.uid()))
           )
         )
    )
  );

-- Fotos de productos: cada local solo toca su carpeta (<local>/archivo).
drop policy if exists product_images_insert on storage.objects;
drop policy if exists product_images_update on storage.objects;
drop policy if exists product_images_delete on storage.objects;
drop policy if exists product_images_select on storage.objects;

create policy product_images_select on storage.objects for select to authenticated
  using (
    bucket_id = 'product-images' and public.is_manager()
    and split_part(name, '/', 1) = (select public.tid())::text
  );
create policy product_images_insert on storage.objects for insert to authenticated
  with check (
    bucket_id = 'product-images' and public.is_manager()
    and public.current_plan() in ('table', 'orders', 'full')
    and split_part(name, '/', 1) = (select public.tid())::text
  );
create policy product_images_update on storage.objects for update to authenticated
  using (
    bucket_id = 'product-images' and public.is_manager()
    and public.current_plan() in ('table', 'orders', 'full')
    and split_part(name, '/', 1) = (select public.tid())::text
  )
  with check (
    bucket_id = 'product-images' and public.is_manager()
    and public.current_plan() in ('table', 'orders', 'full')
    and split_part(name, '/', 1) = (select public.tid())::text
  );
create policy product_images_delete on storage.objects for delete to authenticated
  using (
    bucket_id = 'product-images' and public.is_manager()
    and public.current_plan() in ('table', 'orders', 'full')
    and split_part(name, '/', 1) = (select public.tid())::text
  );

-- 7) Funciones: ahora todas trabajan dentro del local de la consulta ----------------
CREATE OR REPLACE FUNCTION public._add_order_items(p_order uuid, p_items jsonb)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_total numeric := 0;
  v_row   jsonb;
  v_qty   int;
  v_note  text;
  v_prod  public.products%rowtype;
begin
  if p_items is null
     or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0
     or jsonb_array_length(p_items) > 40 then
    raise exception 'invalid_items';
  end if;

  for v_row in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(v_row) is distinct from 'object'
       or jsonb_typeof(v_row -> 'quantity') is distinct from 'number'
       or jsonb_typeof(v_row -> 'product_id') is distinct from 'string'
       or (v_row ->> 'product_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'invalid_items';
    end if;

    if (v_row ->> 'quantity')::numeric <> trunc((v_row ->> 'quantity')::numeric)
       or (v_row ->> 'quantity')::numeric < 1
       or (v_row ->> 'quantity')::numeric > 50 then
      raise exception 'invalid_items';
    end if;

    v_qty  := (v_row ->> 'quantity')::int;
    v_note := left(btrim(coalesce(v_row ->> 'note', '')), 200);

    select * into v_prod from public.products
     where id = (v_row ->> 'product_id')::uuid and tenant_id = public.tid();

    if not found or not v_prod.available then
      raise exception 'product_unavailable' using detail = coalesce(v_prod.name, '');
    end if;

    insert into public.order_items (order_id, product_id, name, unit_price, quantity, note)
    values (p_order, v_prod.id, v_prod.name, v_prod.price, v_qty, v_note);

    v_total := v_total + v_prod.price * v_qty;
  end loop;

  return v_total;
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_order(p_table integer, p_items jsonb, p_name text, p_token uuid DEFAULT NULL::uuid, p_method text DEFAULT NULL::text, p_gate text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tables  int;
  v_max_table int;
  v_enabled boolean;
  v_methods text[];
  v_order   uuid;
  v_name    text;
  v_total   numeric(12, 2) := 0;
  v_row     jsonb;
  v_qty     int;
  v_note    text;
  v_prod    public.products%rowtype;
begin
  if not public._gate_ok(p_gate) then
    raise exception 'gate_denied';
  end if;

  -- Reintento: si ya existe un pedido con este token, es el mismo.
  if p_token is not null then
    select id into v_order from public.orders where client_token = p_token and tenant_id = public.tid();
    if found then
      return v_order;
    end if;
  end if;

  select table_count, ordering_enabled, payment_methods, max_active_per_table
    into v_tables, v_enabled, v_methods, v_max_table
    from public.settings where tenant_id = public.tid();

  if not found then
    raise exception 'unknown_tenant';
  end if;

  if not v_enabled then
    raise exception 'ordering_disabled';
  end if;

  if p_table is null or p_table < 1 or p_table > v_tables then
    raise exception 'invalid_table';
  end if;

  v_name := left(btrim(coalesce(p_name, '')), 60);
  if char_length(v_name) < 2 then
    raise exception 'invalid_name';
  end if;

  if p_method is null or not (p_method = any (v_methods)) then
    raise exception 'invalid_payment';
  end if;

  if p_items is null
     or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0
     or jsonb_array_length(p_items) > 40 then
    raise exception 'invalid_items';
  end if;

  -- Freno contra pedidos falsos: tope de pedidos activos por mesa (lo define el encargado).
  if (select count(*) from public.orders
       where tenant_id = public.tid() and table_number = p_table
         and status in ('pending', 'preparing', 'ready')) >= v_max_table then
    raise exception 'table_limit';
  end if;

  begin
    insert into public.orders (table_number, customer_name, client_token, payment_method)
    values (p_table, v_name, p_token, p_method)
    returning id into v_order;
  exception when unique_violation then
    -- Dos envíos simultáneos con el mismo token: gana el primero.
    select id into v_order from public.orders where client_token = p_token and tenant_id = public.tid();
    return v_order;
  end;

  for v_row in select value from jsonb_array_elements(p_items) loop
    -- "is distinct from" (y no "<>") para que un campo ausente cuente como inválido
    if jsonb_typeof(v_row) is distinct from 'object'
       or jsonb_typeof(v_row -> 'quantity') is distinct from 'number'
       or jsonb_typeof(v_row -> 'product_id') is distinct from 'string'
       or (v_row ->> 'product_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'invalid_items';
    end if;

    if (v_row ->> 'quantity')::numeric <> trunc((v_row ->> 'quantity')::numeric)
       or (v_row ->> 'quantity')::numeric < 1
       or (v_row ->> 'quantity')::numeric > 50 then
      raise exception 'invalid_items';
    end if;

    v_qty  := (v_row ->> 'quantity')::int;
    v_note := left(btrim(coalesce(v_row ->> 'note', '')), 200);

    select * into v_prod from public.products
     where id = (v_row ->> 'product_id')::uuid and tenant_id = public.tid();

    if not found or not v_prod.available then
      raise exception 'product_unavailable' using detail = coalesce(v_prod.name, '');
    end if;

    insert into public.order_items (order_id, product_id, name, unit_price, quantity, note)
    values (v_order, v_prod.id, v_prod.name, v_prod.price, v_qty, v_note);

    v_total := v_total + v_prod.price * v_qty;
  end loop;

  update public.orders set total = v_total where id = v_order;

  return v_order;
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_remote_order(p_modality text, p_items jsonb, p_name text, p_phone text, p_method text, p_token uuid DEFAULT NULL::uuid, p_zone uuid DEFAULT NULL::uuid, p_street text DEFAULT NULL::text, p_number text DEFAULT NULL::text, p_reference text DEFAULT NULL::text, p_cash_from numeric DEFAULT NULL::numeric, p_dest_lat double precision DEFAULT NULL::double precision, p_dest_lng double precision DEFAULT NULL::double precision, p_gate text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_pickup   boolean;
  v_delivery boolean;
  v_methods  text[];
  v_name     text;
  v_phone    text;
  v_zone     public.delivery_zones%rowtype;
  v_street   text := '';
  v_number   text := '';
  v_ref      text := '';
  v_fee      numeric := 0;
  v_order    uuid;
  v_code     text;
  v_total    numeric;
  v_tries    int := 0;
  v_lat      double precision;
  v_lng      double precision;
  v_max_phone_pending int;
  v_max_phone_hour    int;
  v_max_local_hour    int;
begin
  if not public._gate_ok(p_gate) then
    raise exception 'gate_denied';
  end if;

  -- Reintento: si ya existe un pedido con este token, es el mismo.
  if p_token is not null then
    select id, tracking_code into v_order, v_code from public.orders
     where client_token = p_token and tenant_id = public.tid();
    if found then
      return jsonb_build_object('id', v_order, 'tracking_code', v_code);
    end if;
  end if;

  perform public.purge_personal_data();

  select pickup_enabled, delivery_enabled, payment_methods
    into v_pickup, v_delivery, v_methods
    from public.settings where tenant_id = public.tid();

  if not found then
    raise exception 'unknown_tenant';
  end if;

  if p_modality is null or p_modality not in ('pickup', 'delivery') then
    raise exception 'invalid_modality';
  end if;

  if (p_modality = 'pickup' and not v_pickup) or (p_modality = 'delivery' and not v_delivery) then
    raise exception 'modality_disabled';
  end if;

  v_name := left(btrim(coalesce(p_name, '')), 60);
  if char_length(v_name) < 2 then
    raise exception 'invalid_name';
  end if;

  v_phone := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  if char_length(v_phone) < 8 or char_length(v_phone) > 15 then
    raise exception 'invalid_phone';
  end if;

  -- Se compara por los últimos 10 dígitos: con o sin +54, 9 o 0 es el mismo teléfono.
  if exists (select 1 from public.blocked_phones where tenant_id = public.tid() and right(phone, 10) = right(v_phone, 10)) then
    raise exception 'phone_blocked';
  end if;

  if p_method is null or not (p_method = any (v_methods)) then
    raise exception 'invalid_payment';
  end if;

  if p_modality = 'delivery' then
    -- En delivery solo transferencia o efectivo (tarjeta y QR necesitarían posnet portátil).
    if p_method not in ('transfer', 'cash') then
      raise exception 'invalid_payment';
    end if;

    select * into v_zone from public.delivery_zones
     where id = p_zone and active and tenant_id = public.tid();
    if not found then
      raise exception 'invalid_zone';
    end if;

    v_street := left(btrim(coalesce(p_street, '')), 80);
    v_number := left(btrim(coalesce(p_number, '')), 10);
    v_ref    := left(btrim(coalesce(p_reference, '')), 120);

    if char_length(v_street) < 2 or char_length(v_number) < 1 then
      raise exception 'invalid_address';
    end if;

    v_fee := v_zone.fee;

    -- Ubicación opcional del cliente (botón "Usar mi ubicación"): si no es válida, se ignora.
    if p_dest_lat between -90 and 90 and p_dest_lng between -180 and 180 then
      v_lat := p_dest_lat;
      v_lng := p_dest_lng;
    end if;
  end if;

  if p_cash_from is not null and (p_modality <> 'delivery' or p_method <> 'cash') then
    p_cash_from := null;
  end if;

  if p_cash_from is not null and (p_cash_from <= 0 or p_cash_from > 10000000) then
    raise exception 'invalid_cash';
  end if;

  -- Frenos contra pedidos falsos; los topes los define el encargado en Ajustes.
  select max_pending_per_phone, max_orders_per_phone_hour, max_remote_per_hour
    into v_max_phone_pending, v_max_phone_hour, v_max_local_hour
    from public.settings where tenant_id = public.tid();

  if (select count(*) from public.orders o
        join public.order_contacts k on k.order_id = o.id
       where o.tenant_id = public.tid() and o.status = 'pending' and k.phone <> ''
         and right(k.phone, 10) = right(v_phone, 10)) >= v_max_phone_pending then
    raise exception 'too_many_pending';
  end if;

  if (select count(*) from public.orders o
        join public.order_contacts k on k.order_id = o.id
       where o.tenant_id = public.tid() and o.created_at > now() - interval '1 hour' and k.phone <> ''
         and right(k.phone, 10) = right(v_phone, 10)) >= v_max_phone_hour then
    raise exception 'phone_hour_limit';
  end if;

  if (select count(*) from public.orders
       where tenant_id = public.tid() and modality <> 'dine_in'
         and created_at > now() - interval '1 hour') >= v_max_local_hour then
    raise exception 'local_hour_limit';
  end if;

  loop
    v_code := public._new_tracking_code();

    begin
      insert into public.orders (
        modality, customer_name, payment_method, client_token, tracking_code,
        zone_id, zone_name, delivery_fee
      )
      values (
        p_modality, v_name, p_method, p_token, v_code,
        case when p_modality = 'delivery' then v_zone.id end,
        case when p_modality = 'delivery' then v_zone.name else '' end,
        v_fee
      )
      returning id into v_order;

      exit;
    exception when unique_violation then
      -- Puede ser el mismo token enviado dos veces a la vez, o un código repetido.
      if p_token is not null then
        select id, tracking_code into v_order, v_code from public.orders
     where client_token = p_token and tenant_id = public.tid();
        if found then
          return jsonb_build_object('id', v_order, 'tracking_code', v_code);
        end if;
      end if;

      v_tries := v_tries + 1;
      if v_tries >= 5 then
        raise;
      end if;
    end;
  end loop;

  v_total := public._add_order_items(v_order, p_items) + v_fee;

  if p_cash_from is not null and p_cash_from < v_total then
    raise exception 'invalid_cash';
  end if;

  update public.orders set total = v_total where id = v_order;

  -- Teléfono, dirección y ubicación viven aparte: solo los lee quien los necesita.
  insert into public.order_contacts (order_id, phone, street, number, reference, cash_change_from, dest_lat, dest_lng)
  values (v_order, v_phone, v_street, v_number, v_ref, p_cash_from, v_lat, v_lng);

  return jsonb_build_object('id', v_order, 'tracking_code', v_code);
end;
$function$;

CREATE OR REPLACE FUNCTION public.current_plan()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select plan from public.settings where tenant_id = public.tid()
$function$;

CREATE OR REPLACE FUNCTION public.get_delivery_code(p_code text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_out  text;
begin
  if char_length(v_code) <> 8 then
    return null;
  end if;

  select d.code into v_out
    from public.orders o
    join public.delivery_codes d on d.order_id = o.id
   where o.tracking_code = v_code and o.tenant_id = public.tid()
     and o.status in ('pending', 'preparing', 'ready', 'on_the_way');

  return v_out;
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_order(p_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'id',           o.id,
    'table_number', o.table_number,
    'status',       o.status,
    'payment_method', o.payment_method,
    'total',        o.total,
    'created_at',   o.created_at,
    'ahead', case
      when o.status in ('pending', 'preparing') then
        (select count(*) from public.orders x
          where x.tenant_id = o.tenant_id and x.status in ('pending', 'preparing')
             and x.created_at < o.created_at)
      else 0
    end,
    'items', coalesce(
      (select jsonb_agg(
                jsonb_build_object(
                  'name', i.name,
                  'quantity', i.quantity,
                  'unit_price', i.unit_price,
                  'note', i.note)
                order by i.name)
         from public.order_items i
        where i.order_id = o.id),
      '[]'::jsonb)
  )
  from public.orders o
  where o.id = p_id and o.tenant_id = public.tid();
$function$;

CREATE OR REPLACE FUNCTION public.get_order_by_code(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  o      public.orders%rowtype;
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_vis  text;
  v_run  jsonb := null;
  v_ahead int := 0;
  v_before int := 0;
  v_pos  public.driver_positions%rowtype;
  v_driver jsonb := null;
  v_ct   public.order_contacts%rowtype;
begin
  if char_length(v_code) <> 8 then
    return null;
  end if;

  select * into o from public.orders where tracking_code = v_code and tenant_id = public.tid();
  if not found then
    return null;
  end if;

  select stops_visibility into v_vis from public.settings where tenant_id = o.tenant_id;

  if o.status in ('pending', 'preparing') then
    select count(*) into v_ahead from public.orders x
     where x.tenant_id = o.tenant_id and x.status in ('pending', 'preparing')
       and x.created_at < o.created_at;
  end if;

  if o.status = 'on_the_way' and o.run_id is not null then
    select count(*) into v_before from public.orders x
     where x.run_id = o.run_id and x.status = 'on_the_way'
       and x.stop_position < o.stop_position;

    -- La posición del repartidor solo se ve cuando este pedido es la próxima parada.
    if v_before = 0 then
      select * into v_pos from public.driver_positions where run_id = o.run_id;
      if found then
        select * into v_ct from public.order_contacts where order_id = o.id;
        v_driver := jsonb_build_object(
          'lat',         round(v_pos.lat::numeric, 5),
          'lng',         round(v_pos.lng::numeric, 5),
          'age_seconds', extract(epoch from (now() - v_pos.updated_at))::int,
          'distance_m',  case when v_ct.dest_lat is not null then
                           (round(public._distance_m(v_pos.lat, v_pos.lng, v_ct.dest_lat, v_ct.dest_lng) / 50.0) * 50)::int
                         end
        );
      end if;
    end if;

    v_run := jsonb_build_object(
      'position', (select count(*) from public.orders x
                    where x.run_id = o.run_id and x.status <> 'cancelled'
                      and x.stop_position <= o.stop_position),
      'total',    (select count(*) from public.orders x
                    where x.run_id = o.run_id and x.status <> 'cancelled'),
      'before',   v_before,
      'stops',    (select coalesce(jsonb_agg(
                            jsonb_build_object(
                              'mine',  x.id = o.id,
                              'done',  x.status = 'delivered',
                              'place', case when v_vis = 'zone' then x.zone_name else coalesce(k.street, '') end)
                            order by x.stop_position), '[]'::jsonb)
                     from public.orders x
                     left join public.order_contacts k on k.order_id = x.id
                    where x.run_id = o.run_id and x.status <> 'cancelled')
    );
  end if;

  return jsonb_build_object(
    'id',             o.id,
    'tracking_code',  o.tracking_code,
    'modality',       o.modality,
    'status',         o.status,
    'payment_method', o.payment_method,
    'total',          o.total,
    'delivery_fee',   o.delivery_fee,
    'zone_name',      o.zone_name,
    'created_at',     o.created_at,
    'eta_at',         o.eta_at,
    'near',           (o.status = 'on_the_way' and o.near_at is not null),
    'ahead',          v_ahead,
    'run',            v_run,
    'driver',         v_driver,
    'items', coalesce(
      (select jsonb_agg(
                jsonb_build_object(
                  'name', i.name,
                  'quantity', i.quantity,
                  'unit_price', i.unit_price,
                  'note', i.note)
                order by i.name)
         from public.order_items i
        where i.order_id = o.id),
      '[]'::jsonb)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.complete_delivery(p_id uuid, p_code text DEFAULT NULL::text, p_by_name boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  o       public.orders%rowtype;
  v_real  text;
  v_check text := '';
begin
  if not public.has_role('manager', 'counter', 'courier') then
    raise exception 'not_allowed';
  end if;

  select * into o from public.orders where id = p_id and tenant_id = public.tid() for update;
  if not found then
    raise exception 'order_not_found';
  end if;

  -- El repartidor solo entrega los pedidos de su propio reparto.
  if not public.has_role('manager', 'counter') and o.run_by is distinct from auth.uid() then
    raise exception 'not_allowed';
  end if;

  if o.modality <> 'delivery' or o.status <> 'on_the_way' then
    raise exception 'invalid_status';
  end if;

  if o.code_required then
    if coalesce(p_by_name, false) then
      v_check := 'name';
    else
      select code into v_real from public.delivery_codes where order_id = o.id;
      if v_real is null or v_real <> regexp_replace(coalesce(p_code, ''), '[^0-9]', '', 'g') then
        raise exception 'invalid_code';
      end if;
      v_check := 'code';
    end if;
  end if;

  perform set_config('app.delivering', '1', true);
  update public.orders set status = 'delivered', delivered_check = v_check where id = o.id;
  perform set_config('app.delivering', '', true);
end;
$function$;

CREATE OR REPLACE FUNCTION public.mark_near(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.has_role('manager', 'counter', 'courier') then
    raise exception 'not_allowed';
  end if;

  update public.orders set near_at = now()
   where id = p_id and tenant_id = public.tid() and status = 'on_the_way'
     and (public.has_role('manager', 'counter') or run_by = auth.uid());

  if not found then
    raise exception 'invalid_status';
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_order_eta(p_id uuid, p_eta timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.has_role('manager', 'counter') then
    raise exception 'not_allowed';
  end if;

  if p_eta is not null and (p_eta < now() - interval '1 hour' or p_eta > now() + interval '1 day') then
    raise exception 'invalid_eta';
  end if;

  update public.orders set eta_at = p_eta
   where id = p_id and tenant_id = public.tid() and modality <> 'dine_in'
     and status in ('pending', 'preparing', 'ready', 'on_the_way');

  if not found then
    raise exception 'invalid_status';
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.start_run(p_order_ids uuid[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_run uuid := gen_random_uuid();
  v_n   int;
begin
  if not public.has_role('manager', 'counter', 'courier') then
    raise exception 'not_allowed';
  end if;

  v_n := coalesce(array_length(p_order_ids, 1), 0);

  if v_n = 0 or v_n > 20
     or (select count(distinct x) from unnest(p_order_ids) x) <> v_n
     or (select count(*) from public.orders
          where id = any (p_order_ids) and tenant_id = public.tid()
            and modality = 'delivery' and status = 'ready') <> v_n then
    raise exception 'invalid_run';
  end if;

  update public.orders o
     set run_id = v_run, stop_position = t.pos, status = 'on_the_way', near_at = null, run_by = auth.uid()
    from unnest(p_order_ids) with ordinality as t (id, pos)
   where o.id = t.id and o.tenant_id = public.tid();

  return v_run;
end;
$function$;

CREATE OR REPLACE FUNCTION public.table_orders(p_table integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',         o.id,
        'status',     o.status,
        'total',      o.total,
        'created_at', o.created_at,
        'items', coalesce(
          (select jsonb_agg(jsonb_build_object('name', i.name, 'quantity', i.quantity) order by i.name)
             from public.order_items i where i.order_id = o.id),
          '[]'::jsonb)
      )
      order by o.created_at
    ),
    '[]'::jsonb)
  from public.orders o
  where o.tenant_id = public.tid() and o.table_number = p_table
    and o.status in ('pending', 'preparing', 'ready')
    and o.created_at > now() - interval '12 hours';
$function$;

CREATE OR REPLACE FUNCTION public.update_run_position(p_run uuid, p_lat double precision, p_lng double precision, p_accuracy real DEFAULT NULL::real)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_next public.orders%rowtype;
  v_ct   public.order_contacts%rowtype;
  v_radius int;
begin
  select near_radius_m into v_radius from public.settings where tenant_id = public.tid();

  if not (
    public.has_role('manager', 'counter')
    or (public.staff_role() = 'courier'
        and exists (select 1 from public.orders
                     where run_id = p_run and run_by = auth.uid() and tenant_id = public.tid()))
  ) then
    raise exception 'not_allowed';
  end if;

  if p_lat is null or p_lng is null
     or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'invalid_position';
  end if;

  select * into v_next from public.orders
   where run_id = p_run and tenant_id = public.tid() and status = 'on_the_way'
   order by stop_position
   limit 1;

  if not found then
    raise exception 'invalid_run';
  end if;

  insert into public.driver_positions (run_id, lat, lng, accuracy, updated_at)
  values (p_run, p_lat, p_lng, p_accuracy, now())
  on conflict (run_id) do update
    set lat = excluded.lat, lng = excluded.lng, accuracy = excluded.accuracy, updated_at = now();

  select * into v_ct from public.order_contacts where order_id = v_next.id;

  if v_next.near_at is null and v_ct.dest_lat is not null
     and public._distance_m(p_lat, p_lng, v_ct.dest_lat, v_ct.dest_lng) <= v_radius then
    update public.orders set near_at = now() where id = v_next.id;
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.orders_code_before_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_on boolean;
begin
  if new.modality = 'delivery' then
    select delivery_code_enabled into v_on from public.settings where tenant_id = new.tenant_id;
    new.code_required := coalesce(v_on, false);
  else
    new.code_required := false;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.orders_suspended_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if exists (select 1 from public.settings where tenant_id = new.tenant_id and suspended) then
    raise exception 'service_suspended';
  end if;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.purge_if_due()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_last timestamptz;
begin
  if not public.is_staff() then
    raise exception 'not_allowed';
  end if;

  select last_purge_at into v_last from public.settings where tenant_id = public.tid() for update;

  if v_last is null or v_last < now() - interval '6 hours' then
    update public.settings set last_purge_at = now() where tenant_id = public.tid();
    perform public.purge_personal_data();
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.purge_personal_data()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_days int;
  v_n    int;
begin
  select retention_days into v_days from public.settings where tenant_id = public.tid();

  -- Se borran los datos de contacto (teléfono, dirección, ubicación, vuelto) de pedidos viejos.
  delete from public.order_contacts c
   using public.orders o
   where o.id = c.order_id and o.tenant_id = public.tid()
     and coalesce(o.finished_at, o.created_at) < now() - make_interval(days => coalesce(v_days, 15));

  get diagnostics v_n = row_count;

  -- Una posición que nadie actualiza en un día es de un reparto que quedó abierto.
  delete from public.driver_positions where updated_at < now() - interval '1 day';

  return v_n;
end;
$function$;

-- Una conexión sin un local válido no puede crear ni leer nada de ningún local:
-- tid() devuelve null y ninguna política ni función encuentra filas.

-- 8) Red de seguridad: un UPDATE sobre todos los locales a la vez se rechaza -----------
create or replace function public.settings_bulk_guard()
returns trigger
language plpgsql
as $$
begin
  if (select count(*) from new_rows) > 1 then
    raise exception 'bulk_settings_update'
      using hint = 'Usá select public.set_tenant_plan(...) o suspend_tenant(...), o agregá where tenant_id = ...';
  end if;
  return null;
end;
$$;

drop trigger if exists settings_bulk_guard on public.settings;
create trigger settings_bulk_guard after update on public.settings
  referencing new table as new_rows for each statement execute function public.settings_bulk_guard();

-- 9) Administración de locales (solo desde el SQL Editor) ------------------------------
create or replace function public.create_tenant(p_slug text, p_name text, p_plan text default 'full')
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_id uuid;
begin
  if p_plan not in ('menu', 'menu_panel', 'table', 'orders', 'full') then
    raise exception 'invalid_plan';
  end if;

  insert into public.tenants (slug, name) values (p_slug, p_name) returning id into v_id;

  insert into public.settings (tenant_id, plan, ordering_enabled, pickup_enabled, delivery_enabled)
  values (v_id, p_plan, p_plan in ('table', 'full'), p_plan in ('orders', 'full'), p_plan in ('orders', 'full'));

  return v_id;
end;
$$;

create or replace function public.set_tenant_plan(p_slug text, p_plan text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_id uuid := (select id from public.tenants where slug = p_slug);
begin
  if v_id is null then raise exception 'unknown_tenant'; end if;
  if p_plan not in ('menu', 'menu_panel', 'table', 'orders', 'full') then raise exception 'invalid_plan'; end if;

  update public.settings
     set plan = p_plan,
         ordering_enabled = p_plan in ('table', 'full'),
         pickup_enabled   = p_plan in ('orders', 'full'),
         delivery_enabled = p_plan in ('orders', 'full')
   where tenant_id = v_id;
end;
$$;

create or replace function public.suspend_tenant(p_slug text, p_suspended boolean default true)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_id uuid := (select id from public.tenants where slug = p_slug);
begin
  if v_id is null then raise exception 'unknown_tenant'; end if;
  update public.settings set suspended = p_suspended where tenant_id = v_id;
end;
$$;

create or replace function public.add_staff(p_email text, p_slug text, p_role text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_tenant uuid := (select id from public.tenants where slug = p_slug);
  v_user   uuid := (select id from auth.users where lower(email) = lower(p_email));
begin
  if v_tenant is null then raise exception 'unknown_tenant'; end if;
  if v_user is null then raise exception 'unknown_user' using hint = 'Crear primero el usuario en Authentication → Users.'; end if;

  insert into public.staff (user_id, tenant_id, role) values (v_user, v_tenant, p_role)
  on conflict (user_id) do update set tenant_id = excluded.tenant_id, role = excluded.role;
end;
$$;

-- Para scripts de carga (productos, datos iniciales): lo que se inserte en esta sesión es de este local.
create or replace function public.use_tenant(p_slug text)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not exists (select 1 from public.tenants where slug = p_slug) then
    raise exception 'unknown_tenant';
  end if;
  perform set_config('request.headers', json_build_object('x-tenant', p_slug)::text, false);
  return p_slug;
end;
$$;

revoke all on function public.create_tenant(text, text, text)  from public, anon, authenticated;
revoke all on function public.set_tenant_plan(text, text)      from public, anon, authenticated;
revoke all on function public.suspend_tenant(text, boolean)    from public, anon, authenticated;
revoke all on function public.add_staff(text, text, text)      from public, anon, authenticated;
revoke all on function public.use_tenant(text)                 from public, anon, authenticated;

select slug, name from public.tenants order by created_at;
