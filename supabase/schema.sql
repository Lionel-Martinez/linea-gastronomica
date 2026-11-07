-- =====================================================================
-- Línea Gastronómica · Etapa 2 · Esquema de base de datos (Supabase)
--
-- Cómo usarlo: Supabase → SQL Editor → pegar todo y ejecutar.
-- Se puede volver a ejecutar sin romper nada.
--
-- Reglas de acceso (lo más importante de este archivo):
--   · Público (cualquier visitante): lee el menú y los ajustes, y crea
--     pedidos SOLO a través de la función create_order().
--   · Personal (usuarios dados de alta en la tabla staff): lee todos los
--     pedidos, cambia su estado, y edita productos, categorías y ajustes.
--   · Nadie más puede leer pedidos ni modificar nada.
-- =====================================================================

-- ---------- Personal autorizado ----------
-- Tener una cuenta de Supabase Auth NO alcanza: hay que estar en esta tabla.
create table if not exists public.staff (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create or replace function public.is_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.staff where user_id = auth.uid());
$$;

-- ---------- Menú ----------
create table if not exists public.categories (
  id         text primary key,
  name       text not null check (char_length(name) between 1 and 60),
  sort_order int  not null default 0
);

create table if not exists public.products (
  id          uuid primary key default gen_random_uuid(),
  category_id text not null references public.categories (id) on update cascade,
  name        text not null check (char_length(name) between 1 and 80),
  description text not null default '' check (char_length(description) <= 300),
  price       numeric(10, 2) not null check (price >= 0),
  image       text not null default '',
  available   boolean not null default true,
  featured    boolean not null default false,
  sort_order  int not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- Una sola fila (id = 1) con los ajustes del local.
create table if not exists public.settings (
  id             int primary key default 1 check (id = 1),
  table_count    int  not null default 10 check (table_count between 1 and 200),
  payment_alias  text not null default '' check (char_length(payment_alias) <= 60),
  payment_cbu    text not null default '' check (char_length(payment_cbu) <= 40),
  payment_holder text not null default '' check (char_length(payment_holder) <= 80)
);

insert into public.settings (id) values (1) on conflict (id) do nothing;

-- ---------- Pedidos ----------
create table if not exists public.orders (
  id           uuid primary key default gen_random_uuid(),
  table_number int  not null check (table_number >= 1),
  status       text not null default 'pending'
               check (status in ('pending', 'preparing', 'ready', 'delivered', 'cancelled')),
  total        numeric(12, 2) not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists orders_status_created_idx on public.orders (status, created_at);
create index if not exists orders_table_pending_idx  on public.orders (table_number) where status = 'pending';

-- Cada línea guarda el nombre y el precio del momento: si después se edita
-- el producto, los pedidos ya hechos no cambian.
create table if not exists public.order_items (
  id         uuid primary key default gen_random_uuid(),
  order_id   uuid not null references public.orders (id) on delete cascade,
  product_id uuid references public.products (id) on delete set null,
  name       text not null,
  unit_price numeric(10, 2) not null,
  quantity   int  not null check (quantity between 1 and 50),
  note       text not null default '' check (char_length(note) <= 200)
);

create index if not exists order_items_order_idx on public.order_items (order_id);

-- ---------- updated_at automático ----------
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists products_touch on public.products;
create trigger products_touch before update on public.products
  for each row execute function public.touch_updated_at();

drop trigger if exists orders_touch on public.orders;
create trigger orders_touch before update on public.orders
  for each row execute function public.touch_updated_at();

-- ---------- Seguridad por filas (RLS) ----------
alter table public.staff       enable row level security;
alter table public.categories  enable row level security;
alter table public.products    enable row level security;
alter table public.settings    enable row level security;
alter table public.orders      enable row level security;
alter table public.order_items enable row level security;

-- staff: cada usuario puede ver solo su propia fila (sirve para saber si es personal)
drop policy if exists staff_select_own on public.staff;
create policy staff_select_own on public.staff
  for select to authenticated using (user_id = auth.uid());

-- categorías y productos: lectura pública, escritura solo del personal
drop policy if exists categories_read on public.categories;
create policy categories_read on public.categories
  for select to anon, authenticated using (true);

drop policy if exists categories_write on public.categories;
create policy categories_write on public.categories
  for all to authenticated using (public.is_staff()) with check (public.is_staff());

drop policy if exists products_read on public.products;
create policy products_read on public.products
  for select to anon, authenticated using (true);

drop policy if exists products_write on public.products;
create policy products_write on public.products
  for all to authenticated using (public.is_staff()) with check (public.is_staff());

-- ajustes: lectura pública (el alias/CBU se muestra a los clientes), edición del personal
drop policy if exists settings_read on public.settings;
create policy settings_read on public.settings
  for select to anon, authenticated using (true);

drop policy if exists settings_update on public.settings;
create policy settings_update on public.settings
  for update to authenticated using (public.is_staff()) with check (public.is_staff());

-- pedidos: solo el personal los lee y les cambia el estado.
-- No hay política de INSERT: los pedidos se crean únicamente con create_order().
drop policy if exists orders_staff_select on public.orders;
create policy orders_staff_select on public.orders
  for select to authenticated using (public.is_staff());

drop policy if exists orders_staff_update on public.orders;
create policy orders_staff_update on public.orders
  for update to authenticated using (public.is_staff()) with check (public.is_staff());

drop policy if exists order_items_staff_select on public.order_items;
create policy order_items_staff_select on public.order_items
  for select to authenticated using (public.is_staff());

-- ---------- Permisos de tabla (se suman a las políticas de arriba) ----------
grant usage on schema public to anon, authenticated;

grant select on public.categories, public.products, public.settings to anon, authenticated;
grant insert, update, delete on public.categories, public.products to authenticated;
grant update on public.settings to authenticated;
grant select on public.staff to authenticated;
grant select on public.orders, public.order_items to authenticated;
-- El personal solo puede cambiar el estado de un pedido, nunca el total ni la mesa.
grant update (status) on public.orders to authenticated;

-- ---------- Nombre del cliente y protección contra duplicados ----------
alter table public.orders add column if not exists customer_name text not null default '';
alter table public.orders add column if not exists client_token  uuid;

do $$
begin
  alter table public.orders
    add constraint orders_customer_name_len check (char_length(customer_name) <= 60);
exception when duplicate_object then null;
end $$;

-- Un mismo token no puede crear dos pedidos (reintentos por mala conexión).
create unique index if not exists orders_client_token_key
  on public.orders (client_token) where client_token is not null;

-- ---------- Crear un pedido ----------
-- El cliente envía nombre, producto, cantidad y nota. Los precios se leen acá,
-- de la base, así que no se pueden manipular desde el navegador.
-- p_token identifica el intento: si el cliente reintenta con el mismo token
-- (porque se cortó la respuesta), se devuelve el pedido ya creado.
drop function if exists public.create_order(int, jsonb);

create or replace function public.create_order(
  p_table int,
  p_items jsonb,
  p_name  text,
  p_token uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tables int;
  v_order  uuid;
  v_name   text;
  v_total  numeric(12, 2) := 0;
  v_row    jsonb;
  v_qty    int;
  v_note   text;
  v_prod   public.products%rowtype;
begin
  -- Reintento: si ya existe un pedido con este token, es el mismo.
  if p_token is not null then
    select id into v_order from public.orders where client_token = p_token;
    if found then
      return v_order;
    end if;
  end if;

  select table_count into v_tables from public.settings where id = 1;

  if p_table is null or p_table < 1 or p_table > v_tables then
    raise exception 'invalid_table';
  end if;

  v_name := left(btrim(coalesce(p_name, '')), 60);
  if char_length(v_name) < 2 then
    raise exception 'invalid_name';
  end if;

  if p_items is null
     or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0
     or jsonb_array_length(p_items) > 40 then
    raise exception 'invalid_items';
  end if;

  -- Freno básico contra pedidos falsos: máximo 5 sin confirmar por mesa.
  if (select count(*) from public.orders
       where table_number = p_table and status = 'pending') >= 5 then
    raise exception 'too_many_pending';
  end if;

  begin
    insert into public.orders (table_number, customer_name, client_token)
    values (p_table, v_name, p_token)
    returning id into v_order;
  exception when unique_violation then
    -- Dos envíos simultáneos con el mismo token: gana el primero.
    select id into v_order from public.orders where client_token = p_token;
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

    select * into v_prod from public.products where id = (v_row ->> 'product_id')::uuid;

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
$$;

-- ---------- Consultar un pedido propio ----------
-- Se accede con el id del pedido (un UUID imposible de adivinar).
-- Devuelve también cuántos pedidos activos hay por delante.
create or replace function public.get_order(p_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id',           o.id,
    'table_number', o.table_number,
    'status',       o.status,
    'total',        o.total,
    'created_at',   o.created_at,
    'ahead', case
      when o.status in ('pending', 'preparing') then
        (select count(*) from public.orders x
          where x.status in ('pending', 'preparing') and x.created_at < o.created_at)
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
  where o.id = p_id;
$$;

revoke all on function public.create_order(int, jsonb, text, uuid) from public;
revoke all on function public.get_order(uuid) from public;
grant execute on function public.create_order(int, jsonb, text, uuid) to anon, authenticated;
grant execute on function public.get_order(uuid) to anon, authenticated;

-- ---------- Tiempo real para el panel del personal ----------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      alter publication supabase_realtime add table public.orders;
    exception when duplicate_object then null;
    end;
    begin
      alter publication supabase_realtime add table public.order_items;
    exception when duplicate_object then null;
    end;
  end if;
end;
$$;
