-- =====================================================================
-- Línea Gastronómica · Etapas 2, 3A y 3B · Esquema de base de datos (Supabase)
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

-- Encargados: además de ser personal, pueden cambiar los ajustes del local
-- (interruptor de pedidos, métodos de pago, mesas, WhatsApp). Los mozos no.
do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'staff' and column_name = 'is_manager'
  ) then
    alter table public.staff add column is_manager boolean not null default false;
    -- Quienes ya estaban cargados pasan a ser encargados, para no perder acceso a Ajustes.
    update public.staff set is_manager = true;
  end if;
end $$;

create or replace function public.is_manager()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.staff where user_id = auth.uid() and is_manager
  );
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

-- Interruptor de pedidos (plan solo-carta), métodos de pago aceptados y WhatsApp del local.
alter table public.settings add column if not exists ordering_enabled boolean not null default true;
alter table public.settings add column if not exists payment_methods  text[]  not null default array['transfer', 'cash'];
alter table public.settings add column if not exists whatsapp_number  text    not null default '';

do $$
begin
  alter table public.settings add constraint settings_methods_valid
    check (payment_methods <@ array['transfer', 'card', 'qr', 'cash']::text[]);
exception when duplicate_object then null;
end $$;

do $$
begin
  alter table public.settings add constraint settings_whatsapp_valid
    check (whatsapp_number ~ '^[0-9]{0,15}$');
exception when duplicate_object then null;
end $$;

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

-- ajustes: lectura pública (el alias/CBU se muestra a los clientes), edición solo de encargados
drop policy if exists settings_read on public.settings;
create policy settings_read on public.settings
  for select to anon, authenticated using (true);

drop policy if exists settings_update on public.settings;
create policy settings_update on public.settings
  for update to authenticated using (public.is_manager()) with check (public.is_manager());

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
-- Cómo va a pagar el cliente (vacío en pedidos anteriores a esta versión).
alter table public.orders add column if not exists payment_method text not null default '';

do $$
begin
  alter table public.orders add constraint orders_payment_method_valid
    check (payment_method in ('', 'transfer', 'card', 'qr', 'cash'));
exception when duplicate_object then null;
end $$;

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
-- El cliente envía nombre, forma de pago, producto, cantidad y nota. Los precios se
-- leen acá, de la base, así que no se pueden manipular desde el navegador.
-- p_token identifica el intento: si el cliente reintenta con el mismo token
-- (porque se cortó la respuesta), se devuelve el pedido ya creado.
drop function if exists public.create_order(int, jsonb);
drop function if exists public.create_order(int, jsonb, text, uuid);

create or replace function public.create_order(
  p_table  int,
  p_items  jsonb,
  p_name   text,
  p_token  uuid default null,
  p_method text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tables  int;
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
  -- Reintento: si ya existe un pedido con este token, es el mismo.
  if p_token is not null then
    select id into v_order from public.orders where client_token = p_token;
    if found then
      return v_order;
    end if;
  end if;

  select table_count, ordering_enabled, payment_methods
    into v_tables, v_enabled, v_methods
    from public.settings where id = 1;

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

  -- Freno básico contra pedidos falsos: máximo 5 sin confirmar por mesa.
  if (select count(*) from public.orders
       where table_number = p_table and status = 'pending') >= 5 then
    raise exception 'too_many_pending';
  end if;

  begin
    insert into public.orders (table_number, customer_name, client_token, payment_method)
    values (p_table, v_name, p_token, p_method)
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
    'payment_method', o.payment_method,
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

-- ---------- Pedidos activos de una mesa ----------
-- Para que quien se sienta en una mesa (o vuelve con otro celular) vea en qué
-- está el pedido. NO incluye nombres ni notas; solo estado, productos y total.
-- Solo pedidos activos de las últimas 12 horas.
create or replace function public.table_orders(p_table int)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
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
  where o.table_number = p_table
    and o.status in ('pending', 'preparing', 'ready')
    and o.created_at > now() - interval '12 hours';
$$;

revoke all on function public.create_order(int, jsonb, text, uuid, text) from public;
revoke all on function public.table_orders(int) from public;
revoke all on function public.get_order(uuid) from public;
grant execute on function public.create_order(int, jsonb, text, uuid, text) to anon, authenticated;
grant execute on function public.table_orders(int) to anon, authenticated;
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

-- =====================================================================
-- Etapa 3A · Pedidos a distancia (retiro y delivery)
-- Es el contenido de update-04-pedidos-a-distancia.sql, para instalaciones nuevas.
-- =====================================================================

-- ---------- Ajustes del local ----------
alter table public.settings add column if not exists pickup_enabled   boolean not null default false;
alter table public.settings add column if not exists delivery_enabled boolean not null default false;
alter table public.settings add column if not exists retention_days   int     not null default 15;
alter table public.settings add column if not exists stops_visibility text    not null default 'street';

do $$
begin
  alter table public.settings add constraint settings_retention_valid
    check (retention_days in (7, 15, 30));
exception when duplicate_object then null;
end $$;

do $$
begin
  alter table public.settings add constraint settings_stops_valid
    check (stops_visibility in ('street', 'zone'));
exception when duplicate_object then null;
end $$;

-- ---------- Zonas de envío ----------
create table if not exists public.delivery_zones (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(name) between 1 and 60),
  fee        numeric(10, 2) not null check (fee >= 0),
  active     boolean not null default true,
  sort_order int not null default 0
);

create unique index if not exists delivery_zones_name_key on public.delivery_zones (lower(name));

-- ---------- Teléfonos bloqueados ----------
create table if not exists public.blocked_phones (
  phone      text primary key check (phone ~ '^[0-9]{8,15}$'),
  note       text not null default '' check (char_length(note) <= 80),
  created_at timestamptz not null default now()
);

-- ---------- Pedidos: campos para retiro y delivery ----------
-- Los pedidos a distancia no tienen mesa.
alter table public.orders alter column table_number drop not null;

alter table public.orders add column if not exists modality           text not null default 'dine_in';
alter table public.orders add column if not exists tracking_code      text;
alter table public.orders add column if not exists customer_phone     text not null default '';
alter table public.orders add column if not exists delivery_street    text not null default '';
alter table public.orders add column if not exists delivery_number    text not null default '';
alter table public.orders add column if not exists delivery_reference text not null default '';
alter table public.orders add column if not exists zone_id            uuid references public.delivery_zones (id) on delete set null;
alter table public.orders add column if not exists zone_name          text not null default '';
alter table public.orders add column if not exists delivery_fee       numeric(10, 2) not null default 0;
alter table public.orders add column if not exists cash_change_from   numeric(10, 2);
alter table public.orders add column if not exists eta_at             timestamptz;
alter table public.orders add column if not exists run_id             uuid;
alter table public.orders add column if not exists stop_position      int;
alter table public.orders add column if not exists near_at            timestamptz;
alter table public.orders add column if not exists finished_at        timestamptz;

do $$
begin
  alter table public.orders add constraint orders_modality_valid
    check (modality in ('dine_in', 'pickup', 'delivery'));
exception when duplicate_object then null;
end $$;

-- Mesa si y solo si es un pedido en el local.
do $$
begin
  alter table public.orders add constraint orders_table_by_modality
    check ((modality = 'dine_in') = (table_number is not null));
exception when duplicate_object then null;
end $$;

do $$
begin
  alter table public.orders add constraint orders_phone_valid
    check (customer_phone ~ '^[0-9]{0,15}$');
exception when duplicate_object then null;
end $$;

do $$
begin
  alter table public.orders add constraint orders_address_len
    check (char_length(delivery_street) <= 80
       and char_length(delivery_number) <= 10
       and char_length(delivery_reference) <= 120);
exception when duplicate_object then null;
end $$;

-- Alfabeto del código: sin I, L, O, 0 ni 1 para que no se confundan (31 símbolos).
do $$
begin
  alter table public.orders add constraint orders_tracking_code_valid
    check (tracking_code is null or tracking_code ~ '^[A-HJKMNP-Z2-9]{8}$');
exception when duplicate_object then null;
end $$;

create unique index if not exists orders_tracking_code_key
  on public.orders (tracking_code) where tracking_code is not null;

create index if not exists orders_phone_pending_idx
  on public.orders (right(customer_phone, 10)) where status = 'pending' and customer_phone <> '';

create index if not exists orders_run_idx on public.orders (run_id) where run_id is not null;

-- Estado nuevo: "En camino" (solo delivery). Se reemplaza la restricción de estados.
do $$
declare
  c record;
begin
  for c in
    select conname from pg_constraint
     where conrelid = 'public.orders'::regclass
       and contype = 'c'
       and pg_get_constraintdef(oid) like '%preparing%'
       and conname <> 'orders_status_valid'
  loop
    execute format('alter table public.orders drop constraint %I', c.conname);
  end loop;

  begin
    alter table public.orders add constraint orders_status_valid
      check (status in ('pending', 'preparing', 'ready', 'on_the_way', 'delivered', 'cancelled'));
  exception when duplicate_object then null;
  end;
end $$;

-- Los pedidos ya terminados antes de esta versión toman su última actualización como fin.
update public.orders
   set finished_at = updated_at
 where status in ('delivered', 'cancelled') and finished_at is null;

-- Reglas de estado: "En camino" solo en delivery y solo dentro de un reparto
-- (se llega con start_run); al terminar un pedido se guarda cuándo.
create or replace function public.orders_guard()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'on_the_way' then
    if new.modality <> 'delivery' or new.run_id is null then
      raise exception 'invalid_status';
    end if;
  end if;

  if new.status in ('delivered', 'cancelled') then
    if old.status not in ('delivered', 'cancelled') then
      new.finished_at := now();
    end if;
  else
    new.finished_at := null;
  end if;

  return new;
end;
$$;

drop trigger if exists orders_guard on public.orders;
create trigger orders_guard before update on public.orders
  for each row execute function public.orders_guard();

-- ---------- Seguridad de las tablas nuevas ----------
alter table public.delivery_zones enable row level security;
alter table public.blocked_phones enable row level security;

-- zonas: las ve cualquiera (el cliente elige una), las edita solo el encargado
drop policy if exists zones_read on public.delivery_zones;
create policy zones_read on public.delivery_zones
  for select to anon, authenticated using (true);

drop policy if exists zones_write on public.delivery_zones;
create policy zones_write on public.delivery_zones
  for all to authenticated using (public.is_manager()) with check (public.is_manager());

-- teléfonos bloqueados: solo el personal
drop policy if exists blocked_staff on public.blocked_phones;
create policy blocked_staff on public.blocked_phones
  for all to authenticated using (public.is_staff()) with check (public.is_staff());

grant select on public.delivery_zones to anon, authenticated;
grant insert, update, delete on public.delivery_zones to authenticated;
grant select, insert, delete on public.blocked_phones to authenticated;

-- ---------- Funciones internas ----------

-- Código de seguimiento: 8 caracteres al azar (con la fuente aleatoria segura de la base).
create or replace function public._new_tracking_code()
returns text
language plpgsql
volatile
as $$
declare
  v_alpha constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_bytes bytea := decode(replace(gen_random_uuid()::text, '-', ''), 'hex');
  v_pick  int[] := array[0, 1, 2, 3, 4, 5, 10, 11]; -- salteamos los bytes de versión del UUID
  v_code  text := '';
  i       int;
begin
  foreach i in array v_pick loop
    v_code := v_code || substr(v_alpha, (get_byte(v_bytes, i) % 31) + 1, 1);
  end loop;
  return v_code;
end;
$$;

-- Carga las líneas de un pedido leyendo los precios de la base. Devuelve el subtotal.
create or replace function public._add_order_items(p_order uuid, p_items jsonb)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
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

    select * into v_prod from public.products where id = (v_row ->> 'product_id')::uuid;

    if not found or not v_prod.available then
      raise exception 'product_unavailable' using detail = coalesce(v_prod.name, '');
    end if;

    insert into public.order_items (order_id, product_id, name, unit_price, quantity, note)
    values (p_order, v_prod.id, v_prod.name, v_prod.price, v_qty, v_note);

    v_total := v_total + v_prod.price * v_qty;
  end loop;

  return v_total;
end;
$$;

-- Borra teléfono, dirección y referencia de los pedidos que pasaron el plazo
-- (el pedido en sí, con sus productos y total, se conserva).
create or replace function public.purge_personal_data()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_days int;
  v_n    int;
begin
  select retention_days into v_days from public.settings where id = 1;

  update public.orders
     set customer_phone = '', delivery_street = '', delivery_number = '',
         delivery_reference = '', cash_change_from = null
   where (customer_phone <> '' or delivery_street <> '' or delivery_number <> ''
          or delivery_reference <> '' or cash_change_from is not null)
     and coalesce(finished_at, created_at) < now() - make_interval(days => coalesce(v_days, 15));

  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- ---------- Crear un pedido a distancia ----------
-- Igual que create_order, pero para retiro o delivery: pide teléfono y, en delivery,
-- zona y dirección. El costo de envío sale de la zona y se suma en la base.
create or replace function public.create_remote_order(
  p_modality  text,
  p_items     jsonb,
  p_name      text,
  p_phone     text,
  p_method    text,
  p_token     uuid default null,
  p_zone      uuid default null,
  p_street    text default null,
  p_number    text default null,
  p_reference text default null,
  p_cash_from numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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
begin
  -- Reintento: si ya existe un pedido con este token, es el mismo.
  if p_token is not null then
    select id, tracking_code into v_order, v_code from public.orders where client_token = p_token;
    if found then
      return jsonb_build_object('id', v_order, 'tracking_code', v_code);
    end if;
  end if;

  perform public.purge_personal_data();

  select pickup_enabled, delivery_enabled, payment_methods
    into v_pickup, v_delivery, v_methods
    from public.settings where id = 1;

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
  if exists (select 1 from public.blocked_phones where right(phone, 10) = right(v_phone, 10)) then
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

    select * into v_zone from public.delivery_zones where id = p_zone and active;
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
  end if;

  if p_cash_from is not null and (p_modality <> 'delivery' or p_method <> 'cash') then
    p_cash_from := null;
  end if;

  if p_cash_from is not null and (p_cash_from <= 0 or p_cash_from > 10000000) then
    raise exception 'invalid_cash';
  end if;

  -- Freno básico contra pedidos falsos: máximo 5 sin confirmar por teléfono.
  if (select count(*) from public.orders
       where status = 'pending' and customer_phone <> ''
         and right(customer_phone, 10) = right(v_phone, 10)) >= 5 then
    raise exception 'too_many_pending';
  end if;

  loop
    v_code := public._new_tracking_code();

    begin
      insert into public.orders (
        modality, customer_name, customer_phone, payment_method, client_token, tracking_code,
        zone_id, zone_name, delivery_street, delivery_number, delivery_reference, delivery_fee
      )
      values (
        p_modality, v_name, v_phone, p_method, p_token, v_code,
        case when p_modality = 'delivery' then v_zone.id end,
        case when p_modality = 'delivery' then v_zone.name else '' end,
        v_street, v_number, v_ref, v_fee
      )
      returning id into v_order;

      exit;
    exception when unique_violation then
      -- Puede ser el mismo token enviado dos veces a la vez, o un código repetido.
      if p_token is not null then
        select id, tracking_code into v_order, v_code from public.orders where client_token = p_token;
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

  update public.orders set total = v_total, cash_change_from = p_cash_from where id = v_order;

  return jsonb_build_object('id', v_order, 'tracking_code', v_code);
end;
$$;

-- ---------- Seguimiento por código ----------
-- Lo que ve quien tiene el código. NO incluye teléfono, nombre ni número de casa.
-- En un reparto muestra las paradas en orden con la calle (o la zona) de cada una.
create or replace function public.get_order_by_code(p_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  o      public.orders%rowtype;
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_vis  text;
  v_run  jsonb := null;
  v_ahead int := 0;
begin
  if char_length(v_code) <> 8 then
    return null;
  end if;

  select * into o from public.orders where tracking_code = v_code;
  if not found then
    return null;
  end if;

  select stops_visibility into v_vis from public.settings where id = 1;

  if o.status in ('pending', 'preparing') then
    select count(*) into v_ahead from public.orders x
     where x.status in ('pending', 'preparing') and x.created_at < o.created_at;
  end if;

  if o.status = 'on_the_way' and o.run_id is not null then
    v_run := jsonb_build_object(
      'position', (select count(*) from public.orders x
                    where x.run_id = o.run_id and x.status <> 'cancelled'
                      and x.stop_position <= o.stop_position),
      'total',    (select count(*) from public.orders x
                    where x.run_id = o.run_id and x.status <> 'cancelled'),
      'before',   (select count(*) from public.orders x
                    where x.run_id = o.run_id and x.status = 'on_the_way'
                      and x.stop_position < o.stop_position),
      'stops',    (select coalesce(jsonb_agg(
                            jsonb_build_object(
                              'mine',  x.id = o.id,
                              'done',  x.status = 'delivered',
                              'place', case when v_vis = 'zone' then x.zone_name else x.delivery_street end)
                            order by x.stop_position), '[]'::jsonb)
                     from public.orders x
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
$$;

-- ---------- Acciones del personal sobre los repartos ----------

-- Sale a repartir: los pedidos (todos "listos" y de delivery) pasan a "En camino",
-- con el orden de paradas dado por la lista.
create or replace function public.start_run(p_order_ids uuid[])
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run uuid := gen_random_uuid();
  v_n   int;
begin
  if not public.is_staff() then
    raise exception 'not_allowed';
  end if;

  v_n := coalesce(array_length(p_order_ids, 1), 0);

  if v_n = 0 or v_n > 20
     or (select count(distinct x) from unnest(p_order_ids) x) <> v_n
     or (select count(*) from public.orders
          where id = any (p_order_ids) and modality = 'delivery' and status = 'ready') <> v_n then
    raise exception 'invalid_run';
  end if;

  update public.orders o
     set run_id = v_run, stop_position = t.pos, status = 'on_the_way', near_at = null
    from unnest(p_order_ids) with ordinality as t (id, pos)
   where o.id = t.id;

  return v_run;
end;
$$;

-- "Estoy cerca": el cliente ve el aviso en su página.
create or replace function public.mark_near(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_staff() then
    raise exception 'not_allowed';
  end if;

  update public.orders set near_at = now() where id = p_id and status = 'on_the_way';

  if not found then
    raise exception 'invalid_status';
  end if;
end;
$$;

-- Hora estimada de entrega o retiro (null la borra).
create or replace function public.set_order_eta(p_id uuid, p_eta timestamptz)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_staff() then
    raise exception 'not_allowed';
  end if;

  if p_eta is not null and (p_eta < now() - interval '1 hour' or p_eta > now() + interval '1 day') then
    raise exception 'invalid_eta';
  end if;

  update public.orders set eta_at = p_eta
   where id = p_id and modality <> 'dine_in'
     and status in ('pending', 'preparing', 'ready', 'on_the_way');

  if not found then
    raise exception 'invalid_status';
  end if;
end;
$$;

-- ---------- Permisos de las funciones ----------
-- En Supabase, anon y authenticated reciben permiso de ejecución por defecto:
-- se les quita explícitamente a las funciones internas.
revoke all on function public._new_tracking_code() from public, anon, authenticated;
revoke all on function public._add_order_items(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.purge_personal_data() from public, anon, authenticated;

revoke all on function public.create_remote_order(text, jsonb, text, text, text, uuid, uuid, text, text, text, numeric) from public;
revoke all on function public.get_order_by_code(text) from public;
revoke all on function public.start_run(uuid[]) from public, anon;
revoke all on function public.mark_near(uuid) from public, anon;
revoke all on function public.set_order_eta(uuid, timestamptz) from public, anon;

grant execute on function public.create_remote_order(text, jsonb, text, text, text, uuid, uuid, text, text, text, numeric) to anon, authenticated;
grant execute on function public.get_order_by_code(text) to anon, authenticated;
grant execute on function public.start_run(uuid[]) to authenticated;
grant execute on function public.mark_near(uuid) to authenticated;
grant execute on function public.set_order_eta(uuid, timestamptz) to authenticated;

-- ---------- Borrado diario automático (si el proyecto tiene pg_cron) ----------
-- Si no, el borrado igual ocurre cada vez que entra un pedido a distancia.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('purge-personal-data', '17 6 * * *', 'select public.purge_personal_data()');
  end if;
exception when others then null;
end $$;

-- =====================================================================
-- Etapa 3B · GPS del repartidor y mapa
-- Es el contenido de update-05-gps-repartidor.sql, para instalaciones nuevas.
-- =====================================================================

-- ---------- Ubicación del cliente (opcional) ----------
alter table public.orders add column if not exists dest_lat double precision;
alter table public.orders add column if not exists dest_lng double precision;

do $$
begin
  alter table public.orders add constraint orders_dest_valid
    check ((dest_lat is null) = (dest_lng is null)
       and (dest_lat is null or (dest_lat between -90 and 90 and dest_lng between -180 and 180)));
exception when duplicate_object then null;
end $$;

-- ---------- Posición del repartidor ----------
-- Una fila por reparto con el último punto. Nadie accede a la tabla directamente:
-- el personal escribe con update_run_position() y el cliente lee con get_order_by_code().
create table if not exists public.driver_positions (
  run_id     uuid primary key,
  lat        double precision not null check (lat between -90 and 90),
  lng        double precision not null check (lng between -180 and 180),
  accuracy   real,
  updated_at timestamptz not null default now()
);

alter table public.driver_positions enable row level security;
revoke all on public.driver_positions from public, anon, authenticated;

-- Distancia en metros entre dos puntos (fórmula de haversine).
create or replace function public._distance_m(
  lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision
)
returns double precision
language sql
immutable
as $$
  select 2 * 6371000 * asin(least(1, sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)
  )));
$$;

-- Al terminar el último pedido "En camino" de un reparto, se borra su posición.
create or replace function public.orders_after_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status = 'on_the_way' and new.status <> 'on_the_way' and new.run_id is not null then
    if not exists (
      select 1 from public.orders where run_id = new.run_id and status = 'on_the_way'
    ) then
      delete from public.driver_positions where run_id = new.run_id;
    end if;
  end if;

  return null;
end;
$$;

drop trigger if exists orders_after_update on public.orders;
create trigger orders_after_update after update of status on public.orders
  for each row execute function public.orders_after_update();

-- El celular del repartidor manda su posición. Si queda a menos de 300 m de la
-- próxima parada (y el cliente guardó su ubicación), se avisa "Estoy cerca" solo.
create or replace function public.update_run_position(
  p_run      uuid,
  p_lat      double precision,
  p_lng      double precision,
  p_accuracy real default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_next public.orders%rowtype;
begin
  if not public.is_staff() then
    raise exception 'not_allowed';
  end if;

  if p_lat is null or p_lng is null
     or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'invalid_position';
  end if;

  select * into v_next from public.orders
   where run_id = p_run and status = 'on_the_way'
   order by stop_position
   limit 1;

  if not found then
    raise exception 'invalid_run';
  end if;

  insert into public.driver_positions (run_id, lat, lng, accuracy, updated_at)
  values (p_run, p_lat, p_lng, p_accuracy, now())
  on conflict (run_id) do update
    set lat = excluded.lat, lng = excluded.lng, accuracy = excluded.accuracy, updated_at = now();

  if v_next.near_at is null and v_next.dest_lat is not null
     and public._distance_m(p_lat, p_lng, v_next.dest_lat, v_next.dest_lng) <= 300 then
    update public.orders set near_at = now() where id = v_next.id;
  end if;
end;
$$;

-- ---------- Funciones que cambian ----------
-- Se reemplazan por versiones con ubicación (las anteriores se descartan).
drop function if exists public.create_remote_order(text, jsonb, text, text, text, uuid, uuid, text, text, text, numeric);

create or replace function public.purge_personal_data()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_days int;
  v_n    int;
begin
  select retention_days into v_days from public.settings where id = 1;

  update public.orders
     set customer_phone = '', delivery_street = '', delivery_number = '',
         delivery_reference = '', cash_change_from = null,
         dest_lat = null, dest_lng = null
   where (customer_phone <> '' or delivery_street <> '' or delivery_number <> ''
          or delivery_reference <> '' or cash_change_from is not null or dest_lat is not null)
     and coalesce(finished_at, created_at) < now() - make_interval(days => coalesce(v_days, 15));

  get diagnostics v_n = row_count;

  -- Una posición que nadie actualiza en un día es de un reparto que quedó abierto.
  delete from public.driver_positions where updated_at < now() - interval '1 day';

  return v_n;
end;
$$;

create or replace function public.create_remote_order(
  p_modality  text,
  p_items     jsonb,
  p_name      text,
  p_phone     text,
  p_method    text,
  p_token     uuid default null,
  p_zone      uuid default null,
  p_street    text default null,
  p_number    text default null,
  p_reference text default null,
  p_cash_from numeric default null,
  p_dest_lat  double precision default null,
  p_dest_lng  double precision default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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
begin
  -- Reintento: si ya existe un pedido con este token, es el mismo.
  if p_token is not null then
    select id, tracking_code into v_order, v_code from public.orders where client_token = p_token;
    if found then
      return jsonb_build_object('id', v_order, 'tracking_code', v_code);
    end if;
  end if;

  perform public.purge_personal_data();

  select pickup_enabled, delivery_enabled, payment_methods
    into v_pickup, v_delivery, v_methods
    from public.settings where id = 1;

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
  if exists (select 1 from public.blocked_phones where right(phone, 10) = right(v_phone, 10)) then
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

    select * into v_zone from public.delivery_zones where id = p_zone and active;
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

  -- Freno básico contra pedidos falsos: máximo 5 sin confirmar por teléfono.
  if (select count(*) from public.orders
       where status = 'pending' and customer_phone <> ''
         and right(customer_phone, 10) = right(v_phone, 10)) >= 5 then
    raise exception 'too_many_pending';
  end if;

  loop
    v_code := public._new_tracking_code();

    begin
      insert into public.orders (
        modality, customer_name, customer_phone, payment_method, client_token, tracking_code,
        zone_id, zone_name, delivery_street, delivery_number, delivery_reference, delivery_fee,
        dest_lat, dest_lng
      )
      values (
        p_modality, v_name, v_phone, p_method, p_token, v_code,
        case when p_modality = 'delivery' then v_zone.id end,
        case when p_modality = 'delivery' then v_zone.name else '' end,
        v_street, v_number, v_ref, v_fee,
        v_lat, v_lng
      )
      returning id into v_order;

      exit;
    exception when unique_violation then
      -- Puede ser el mismo token enviado dos veces a la vez, o un código repetido.
      if p_token is not null then
        select id, tracking_code into v_order, v_code from public.orders where client_token = p_token;
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

  update public.orders set total = v_total, cash_change_from = p_cash_from where id = v_order;

  return jsonb_build_object('id', v_order, 'tracking_code', v_code);
end;
$$;

create or replace function public.get_order_by_code(p_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  o      public.orders%rowtype;
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_vis  text;
  v_run  jsonb := null;
  v_ahead int := 0;
  v_before int := 0;
  v_pos  public.driver_positions%rowtype;
  v_driver jsonb := null;
begin
  if char_length(v_code) <> 8 then
    return null;
  end if;

  select * into o from public.orders where tracking_code = v_code;
  if not found then
    return null;
  end if;

  select stops_visibility into v_vis from public.settings where id = 1;

  if o.status in ('pending', 'preparing') then
    select count(*) into v_ahead from public.orders x
     where x.status in ('pending', 'preparing') and x.created_at < o.created_at;
  end if;

  if o.status = 'on_the_way' and o.run_id is not null then
    select count(*) into v_before from public.orders x
     where x.run_id = o.run_id and x.status = 'on_the_way'
       and x.stop_position < o.stop_position;

    -- La posición del repartidor solo se ve cuando este pedido es la próxima parada.
    if v_before = 0 then
      select * into v_pos from public.driver_positions where run_id = o.run_id;
      if found then
        v_driver := jsonb_build_object(
          'lat',         round(v_pos.lat::numeric, 5),
          'lng',         round(v_pos.lng::numeric, 5),
          'age_seconds', extract(epoch from (now() - v_pos.updated_at))::int,
          'distance_m',  case when o.dest_lat is not null then
                           (round(public._distance_m(v_pos.lat, v_pos.lng, o.dest_lat, o.dest_lng) / 50.0) * 50)::int
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
                              'place', case when v_vis = 'zone' then x.zone_name else x.delivery_street end)
                            order by x.stop_position), '[]'::jsonb)
                     from public.orders x
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
$$;


-- ---------- Permisos ----------
revoke all on function public._distance_m(double precision, double precision, double precision, double precision) from public, anon, authenticated;
revoke all on function public.orders_after_update() from public, anon, authenticated;
revoke all on function public.update_run_position(uuid, double precision, double precision, real) from public, anon;
revoke all on function public.create_remote_order(text, jsonb, text, text, text, uuid, uuid, text, text, text, numeric, double precision, double precision) from public;
revoke all on function public.get_order_by_code(text) from public;
revoke all on function public.purge_personal_data() from public, anon, authenticated;

grant execute on function public.update_run_position(uuid, double precision, double precision, real) to authenticated;
grant execute on function public.create_remote_order(text, jsonb, text, text, text, uuid, uuid, text, text, text, numeric, double precision, double precision) to anon, authenticated;
grant execute on function public.get_order_by_code(text) to anon, authenticated;
