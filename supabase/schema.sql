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

insert into public.settings (id) select 1 where not exists (select 1 from public.settings);

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

-- =====================================================================
-- Actualización 06 · Código de entrega (contra entregas a la persona equivocada).
-- Para proyectos que ya ejecutaron schema.sql + update-02 a 05.
-- Se puede correr más de una vez sin riesgo.
--
-- Qué agrega:
--   · Opción por local (Ajustes): "Código de entrega" para pedidos de delivery.
--   · Cada delivery nuevo recibe un código de 4 dígitos, DISTINTO del de seguimiento.
--     Lo ve el cliente en su seguimiento y se lo dice al repartidor al recibir.
--   · El repartidor lo escribe para marcar "Entregado". El personal no puede leer el
--     código en la base: solo comprobarlo con complete_delivery.
--   · Si el cliente no lo tiene, el repartidor puede entregar confirmando el nombre;
--     queda registrado como "sin código" para que el encargado lo vea.
--   · El código se borra cuando el pedido se entrega o se cancela.
-- =====================================================================

alter table public.settings add column if not exists delivery_code_enabled boolean not null default false;

alter table public.orders add column if not exists code_required boolean not null default false;
alter table public.orders add column if not exists delivered_check text not null default '';

do $$
begin
  alter table public.orders add constraint orders_delivered_check_valid
    check (delivered_check in ('', 'code', 'name'));
exception when duplicate_object then null;
end $$;

-- Códigos: tabla sin acceso directo para nadie (solo las funciones de abajo la usan).
create table if not exists public.delivery_codes (
  order_id uuid primary key references public.orders (id) on delete cascade,
  code     text not null check (code ~ '^[0-9]{4}$')
);

alter table public.delivery_codes enable row level security;
revoke all on public.delivery_codes from public, anon, authenticated;

-- ---------- Generación al crear el pedido ----------
create or replace function public.orders_code_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_on boolean;
begin
  if new.modality = 'delivery' then
    select delivery_code_enabled into v_on from public.settings where id = 1;
    new.code_required := coalesce(v_on, false);
  else
    new.code_required := false;
  end if;
  return new;
end;
$$;

create or replace function public.orders_code_after_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bytes bytea := decode(replace(gen_random_uuid()::text, '-', ''), 'hex');
  v_n     int;
begin
  if new.code_required then
    v_n := ((get_byte(v_bytes, 0) * 65536 + get_byte(v_bytes, 1) * 256 + get_byte(v_bytes, 2)) % 10000);
    insert into public.delivery_codes (order_id, code)
    values (new.id, lpad(v_n::text, 4, '0'))
    on conflict (order_id) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists orders_code_before_insert on public.orders;
create trigger orders_code_before_insert before insert on public.orders
  for each row execute function public.orders_code_before_insert();

drop trigger if exists orders_code_after_insert on public.orders;
create trigger orders_code_after_insert after insert on public.orders
  for each row execute function public.orders_code_after_insert();

-- El código se borra cuando el pedido termina.
create or replace function public.orders_code_cleanup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status in ('delivered', 'cancelled') then
    delete from public.delivery_codes where order_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists orders_code_cleanup on public.orders;
create trigger orders_code_cleanup after update of status on public.orders
  for each row execute function public.orders_code_cleanup();

-- ---------- Guarda: un delivery con código solo se entrega con complete_delivery ----------
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

  if new.code_required is distinct from old.code_required
     or new.delivered_check is distinct from old.delivered_check then
    if coalesce(current_setting('app.delivering', true), '') <> '1' then
      raise exception 'not_allowed';
    end if;
  end if;

  if new.status = 'delivered' and old.status <> 'delivered'
     and new.code_required and new.modality = 'delivery'
     and coalesce(current_setting('app.delivering', true), '') <> '1' then
    raise exception 'code_required';
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

-- ---------- Cliente: ver su código (solo con el código de seguimiento) ----------
create or replace function public.get_delivery_code(p_code text)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
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
   where o.tracking_code = v_code
     and o.status in ('pending', 'preparing', 'ready', 'on_the_way');

  return v_out;
end;
$$;

-- ---------- Repartidor: entregar comprobando el código ----------
create or replace function public.complete_delivery(
  p_id      uuid,
  p_code    text default null,
  p_by_name boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  o       public.orders%rowtype;
  v_real  text;
  v_check text := '';
begin
  if not public.is_staff() then
    raise exception 'not_allowed';
  end if;

  select * into o from public.orders where id = p_id for update;
  if not found then
    raise exception 'order_not_found';
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
$$;

-- ---------- Permisos ----------
revoke all on function public.orders_code_before_insert() from public, anon, authenticated;
revoke all on function public.orders_code_after_insert() from public, anon, authenticated;
revoke all on function public.orders_code_cleanup() from public, anon, authenticated;
revoke all on function public.get_delivery_code(text) from public;
revoke all on function public.complete_delivery(uuid, text, boolean) from public, anon;

grant execute on function public.get_delivery_code(text) to anon, authenticated;
grant execute on function public.complete_delivery(uuid, text, boolean) to authenticated;

-- =====================================================================
-- Actualización 07 · Respaldo del borrado automático de datos personales.
-- Para proyectos que ya ejecutaron schema.sql + update-02 a 06.
-- Se puede correr más de una vez sin riesgo.
--
-- El borrado diario depende de la extensión pg_cron. Si no está habilitada,
-- el borrado corría solo cuando entraba un pedido a distancia nuevo. Ahora
-- también corre cuando el personal abre el panel (como máximo cada 6 horas).
-- =====================================================================

alter table public.settings add column if not exists last_purge_at timestamptz;

create or replace function public.purge_if_due()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_last timestamptz;
begin
  if not public.is_staff() then
    raise exception 'not_allowed';
  end if;

  select last_purge_at into v_last from public.settings where id = 1 for update;

  if v_last is null or v_last < now() - interval '6 hours' then
    update public.settings set last_purge_at = now() where id = 1;
    perform public.purge_personal_data();
  end if;
end;
$$;

revoke all on function public.purge_if_due() from public, anon;
grant execute on function public.purge_if_due() to authenticated;

-- =====================================================================
-- Actualización 08 · Roles del personal y datos de contacto separados.
-- Para proyectos que ya ejecutaron schema.sql + update-02 a 07.
-- Se puede correr más de una vez sin riesgo.
--
-- Roles (columna staff.role):
--   manager  (encargado)  todo.
--   counter  (mostrador)  todos los pedidos con teléfono y dirección; confirma, cancela,
--                         arma repartos y bloquea teléfonos. No edita precios ni ajustes.
--   waiter   (mozo)       solo pedidos de mesa; confirma y entrega. Sin teléfonos.
--   kitchen  (cocina)     ve los pedidos y marca «Listo». Sin teléfonos ni direcciones.
--   courier  (repartidor) ve los delivery listos y su propio reparto; entrega.
--
-- El teléfono, la dirección, la ubicación y el vuelto salen de la tabla orders y pasan a
-- order_contacts, que solo leen el encargado, el mostrador y el repartidor que corresponde.
-- Los pedidos existentes se migran. Quienes ya eran personal conservan su poder:
-- los encargados siguen siendo encargados y el resto pasa a «mostrador».
-- =====================================================================

-- ---------- Roles ----------
do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'staff' and column_name = 'role'
  ) then
    alter table public.staff add column role text not null default 'waiter';
    update public.staff set role = case when is_manager then 'manager' else 'counter' end;
  end if;
end $$;

do $$
begin
  alter table public.staff add constraint staff_role_valid
    check (role in ('manager', 'counter', 'waiter', 'kitchen', 'courier'));
exception when duplicate_object then null;
end $$;

-- El rol manda; is_manager se mantiene igual para no romper nada anterior.
create or replace function public.staff_sync_role()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' and new.is_manager and new.role = 'waiter' then
    new.role := 'manager';
  end if;
  new.is_manager := (new.role = 'manager');
  return new;
end;
$$;

drop trigger if exists staff_sync_role on public.staff;
create trigger staff_sync_role before insert or update on public.staff
  for each row execute function public.staff_sync_role();

create or replace function public.staff_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role from public.staff where user_id = auth.uid();
$$;

create or replace function public.has_role(variadic p_roles text[])
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.staff_role() = any (p_roles), false);
$$;

create or replace function public.is_manager()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.staff_role() = 'manager', false);
$$;

-- ---------- Quién hizo salir cada reparto ----------
alter table public.orders add column if not exists run_by uuid references auth.users (id) on delete set null;

-- ---------- Datos de contacto aparte ----------
create table if not exists public.order_contacts (
  order_id         uuid primary key references public.orders (id) on delete cascade,
  phone            text not null default '',
  street           text not null default '',
  number           text not null default '',
  reference        text not null default '',
  cash_change_from numeric(10, 2),
  dest_lat         double precision,
  dest_lng         double precision,
  constraint order_contacts_dest_valid check (
    (dest_lat is null) = (dest_lng is null)
    and (dest_lat is null or (dest_lat between -90 and 90 and dest_lng between -180 and 180))
  )
);

alter table public.order_contacts enable row level security;

do $$
begin
  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'orders' and column_name = 'customer_phone'
  ) then
    insert into public.order_contacts (order_id, phone, street, number, reference, cash_change_from, dest_lat, dest_lng)
    select id, customer_phone, delivery_street, delivery_number, delivery_reference,
           cash_change_from, dest_lat, dest_lng
      from public.orders
     where modality <> 'dine_in'
    on conflict (order_id) do nothing;
  end if;
end $$;

-- ---------- Funciones que usaban las columnas viejas ----------
CREATE OR REPLACE FUNCTION public.create_remote_order(p_modality text, p_items jsonb, p_name text, p_phone text, p_method text, p_token uuid DEFAULT NULL::uuid, p_zone uuid DEFAULT NULL::uuid, p_street text DEFAULT NULL::text, p_number text DEFAULT NULL::text, p_reference text DEFAULT NULL::text, p_cash_from numeric DEFAULT NULL::numeric, p_dest_lat double precision DEFAULT NULL::double precision, p_dest_lng double precision DEFAULT NULL::double precision)
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
  if (select count(*) from public.orders o
        join public.order_contacts k on k.order_id = o.id
       where o.status = 'pending' and k.phone <> ''
         and right(k.phone, 10) = right(v_phone, 10)) >= 5 then
    raise exception 'too_many_pending';
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

  update public.orders set total = v_total where id = v_order;

  -- Teléfono, dirección y ubicación viven aparte: solo los lee quien los necesita.
  insert into public.order_contacts (order_id, phone, street, number, reference, cash_change_from, dest_lat, dest_lng)
  values (v_order, v_phone, v_street, v_number, v_ref, p_cash_from, v_lat, v_lng);

  return jsonb_build_object('id', v_order, 'tracking_code', v_code);
end;
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
  select retention_days into v_days from public.settings where id = 1;

  -- Se borran los datos de contacto (teléfono, dirección, ubicación, vuelto) de pedidos viejos.
  delete from public.order_contacts c
   using public.orders o
   where o.id = c.order_id
     and coalesce(o.finished_at, o.created_at) < now() - make_interval(days => coalesce(v_days, 15));

  get diagnostics v_n = row_count;

  -- Una posición que nadie actualiza en un día es de un reparto que quedó abierto.
  delete from public.driver_positions where updated_at < now() - interval '1 day';

  return v_n;
end;
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
begin
  if not (
    public.has_role('manager', 'counter')
    or (public.staff_role() = 'courier'
        and exists (select 1 from public.orders where run_id = p_run and run_by = auth.uid()))
  ) then
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

  select * into v_ct from public.order_contacts where order_id = v_next.id;

  if v_next.near_at is null and v_ct.dest_lat is not null
     and public._distance_m(p_lat, p_lng, v_ct.dest_lat, v_ct.dest_lng) <= 300 then
    update public.orders set near_at = now() where id = v_next.id;
  end if;
end;
$function$;

-- ---------- Funciones del reparto, ahora por rol ----------
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
  if not public.has_role('manager', 'counter', 'courier') then
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
     set run_id = v_run, stop_position = t.pos, status = 'on_the_way', near_at = null, run_by = auth.uid()
    from unnest(p_order_ids) with ordinality as t (id, pos)
   where o.id = t.id;

  return v_run;
end;
$$;

create or replace function public.mark_near(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_role('manager', 'counter', 'courier') then
    raise exception 'not_allowed';
  end if;

  update public.orders set near_at = now()
   where id = p_id and status = 'on_the_way'
     and (public.has_role('manager', 'counter') or run_by = auth.uid());

  if not found then
    raise exception 'invalid_status';
  end if;
end;
$$;

create or replace function public.set_order_eta(p_id uuid, p_eta timestamptz)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_role('manager', 'counter') then
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

create or replace function public.complete_delivery(
  p_id      uuid,
  p_code    text default null,
  p_by_name boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  o       public.orders%rowtype;
  v_real  text;
  v_check text := '';
begin
  if not public.has_role('manager', 'counter', 'courier') then
    raise exception 'not_allowed';
  end if;

  select * into o from public.orders where id = p_id for update;
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
$$;

-- ---------- Qué cambios de estado puede hacer cada rol ----------
create or replace function public.orders_guard()
returns trigger
language plpgsql
as $$
declare
  v_role    text;
  v_allowed boolean;
begin
  if new.status = 'on_the_way' then
    if new.modality <> 'delivery' or new.run_id is null then
      raise exception 'invalid_status';
    end if;
  end if;

  if new.code_required is distinct from old.code_required
     or new.delivered_check is distinct from old.delivered_check then
    if coalesce(current_setting('app.delivering', true), '') <> '1' then
      raise exception 'not_allowed';
    end if;
  end if;

  if new.status = 'delivered' and old.status <> 'delivered'
     and new.code_required and new.modality = 'delivery'
     and coalesce(current_setting('app.delivering', true), '') <> '1' then
    raise exception 'code_required';
  end if;

  -- Cambios hechos directamente por una cuenta del personal: se validan por rol y por orden.
  -- (Las funciones del sistema, como start_run, hacen sus propias comprobaciones.)
  if current_user = 'authenticated' and new.status is distinct from old.status then
    v_role := public.staff_role();

    v_allowed := case
      when v_role in ('manager', 'counter') then
        (old.status = 'pending'    and new.status in ('preparing', 'cancelled'))
        or (old.status = 'preparing'  and new.status in ('ready', 'cancelled'))
        or (old.status = 'ready'      and new.status in ('delivered', 'cancelled'))
        or (old.status = 'on_the_way' and new.status in ('delivered', 'cancelled'))
      when v_role = 'waiter' then
        old.modality = 'dine_in'
        and ((old.status = 'pending' and new.status = 'preparing')
          or (old.status = 'ready' and new.status = 'delivered'))
      when v_role = 'kitchen' then
        old.status = 'preparing' and new.status = 'ready'
      when v_role = 'courier' then
        old.modality = 'delivery' and old.status = 'on_the_way' and new.status = 'delivered'
        and old.run_by is not distinct from auth.uid()
      else false
    end;

    if not coalesce(v_allowed, false) then
      raise exception 'not_allowed';
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

-- ---------- Políticas de acceso ----------
drop policy if exists orders_staff_select on public.orders;
drop policy if exists orders_select on public.orders;
create policy orders_select on public.orders
  for select to authenticated
  using (
    public.has_role('manager', 'counter', 'kitchen')
    or (public.staff_role() = 'waiter' and modality = 'dine_in')
    or (public.staff_role() = 'courier' and modality = 'delivery'
        and (status = 'ready'
             or (status = 'on_the_way' and run_by = auth.uid())
             -- Lo que entregó en las últimas horas (hace falta para poder marcarlo entregado).
             or (status = 'delivered' and run_by = auth.uid() and finished_at > now() - interval '12 hours')))
  );

drop policy if exists orders_staff_update on public.orders;
drop policy if exists orders_update on public.orders;
create policy orders_update on public.orders
  for update to authenticated
  using (
    public.has_role('manager', 'counter', 'kitchen')
    or (public.staff_role() = 'waiter' and modality = 'dine_in')
    or (public.staff_role() = 'courier' and modality = 'delivery'
        and status = 'on_the_way' and run_by = auth.uid())
  )
  with check (public.is_staff());

drop policy if exists order_items_staff_select on public.order_items;
drop policy if exists order_items_select on public.order_items;
create policy order_items_select on public.order_items
  for select to authenticated
  using (
    public.is_staff()
    and exists (select 1 from public.orders o where o.id = order_id)
  );

drop policy if exists contacts_select on public.order_contacts;
create policy contacts_select on public.order_contacts
  for select to authenticated
  using (
    public.has_role('manager', 'counter')
    or (public.staff_role() = 'courier'
        and exists (
          select 1 from public.orders o
           where o.id = order_id and o.modality = 'delivery'
             and (o.status = 'ready' or (o.status = 'on_the_way' and o.run_by = auth.uid()))
        ))
  );

-- Solo el encargado edita la carta; el mostrador gestiona los teléfonos bloqueados.
drop policy if exists products_write on public.products;
create policy products_write on public.products
  for all to authenticated
  using (public.is_manager()) with check (public.is_manager());

drop policy if exists categories_write on public.categories;
create policy categories_write on public.categories
  for all to authenticated
  using (public.is_manager()) with check (public.is_manager());

drop policy if exists blocked_staff on public.blocked_phones;
create policy blocked_staff on public.blocked_phones
  for all to authenticated
  using (public.has_role('manager', 'counter')) with check (public.has_role('manager', 'counter'));

-- ---------- Se quitan los datos de contacto de orders ----------
alter table public.orders drop column if exists customer_phone;
alter table public.orders drop column if exists delivery_street;
alter table public.orders drop column if exists delivery_number;
alter table public.orders drop column if exists delivery_reference;
alter table public.orders drop column if exists cash_change_from;
alter table public.orders drop column if exists dest_lat;
alter table public.orders drop column if exists dest_lng;

-- ---------- Permisos ----------
revoke all on public.order_contacts from public, anon, authenticated;
grant select on public.order_contacts to authenticated;

revoke all on function public.staff_sync_role() from public, anon, authenticated;
revoke all on function public.start_run(uuid[]) from public, anon;
revoke all on function public.mark_near(uuid) from public, anon;
revoke all on function public.set_order_eta(uuid, timestamptz) from public, anon;
revoke all on function public.complete_delivery(uuid, text, boolean) from public, anon;
revoke all on function public.update_run_position(uuid, double precision, double precision, real) from public, anon;
revoke all on function public.purge_personal_data() from public, anon, authenticated;
revoke all on function public.create_remote_order(text, jsonb, text, text, text, uuid, uuid, text, text, text, numeric, double precision, double precision) from public;
revoke all on function public.get_order_by_code(text) from public;

grant execute on function public.start_run(uuid[]) to authenticated;
grant execute on function public.mark_near(uuid) to authenticated;
grant execute on function public.set_order_eta(uuid, timestamptz) to authenticated;
grant execute on function public.complete_delivery(uuid, text, boolean) to authenticated;
grant execute on function public.update_run_position(uuid, double precision, double precision, real) to authenticated;
grant execute on function public.create_remote_order(text, jsonb, text, text, text, uuid, uuid, text, text, text, numeric, double precision, double precision) to anon, authenticated;
grant execute on function public.get_order_by_code(text) to anon, authenticated;

-- Para dar un rol a una cuenta (después de crear el usuario en Authentication → Users):
--   insert into public.staff (user_id, role) values ('<id del usuario>', 'kitchen');
-- Roles: manager, counter, waiter, kitchen, courier. Para cambiarlo:
--   update public.staff set role = 'courier' where user_id = '<id del usuario>';


-- =====================================================================
-- update-09 (ver supabase/update-09-limites-de-pedidos.sql)
-- =====================================================================

alter table public.settings add column if not exists max_active_per_table      int not null default 3;
alter table public.settings add column if not exists max_pending_per_phone     int not null default 5;
alter table public.settings add column if not exists max_orders_per_phone_hour int not null default 3;
alter table public.settings add column if not exists max_remote_per_hour       int not null default 20;

do $$
begin
  alter table public.settings add constraint settings_limits_valid check (
    max_active_per_table      between 1 and 20 and
    max_pending_per_phone     between 1 and 20 and
    max_orders_per_phone_hour between 1 and 20 and
    max_remote_per_hour       between 1 and 200
  );
exception when duplicate_object then null;
end $$;

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
  -- Reintento: si ya existe un pedido con este token, es el mismo.
  if p_token is not null then
    select id into v_order from public.orders where client_token = p_token;
    if found then
      return v_order;
    end if;
  end if;

  select table_count, ordering_enabled, payment_methods, max_active_per_table
    into v_tables, v_enabled, v_methods, v_max_table
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

  -- Freno contra pedidos falsos: tope de pedidos activos por mesa (lo define el encargado).
  if (select count(*) from public.orders
       where table_number = p_table and status in ('pending', 'preparing', 'ready')) >= v_max_table then
    raise exception 'table_limit';
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

CREATE OR REPLACE FUNCTION public.create_remote_order(p_modality text, p_items jsonb, p_name text, p_phone text, p_method text, p_token uuid DEFAULT NULL::uuid, p_zone uuid DEFAULT NULL::uuid, p_street text DEFAULT NULL::text, p_number text DEFAULT NULL::text, p_reference text DEFAULT NULL::text, p_cash_from numeric DEFAULT NULL::numeric, p_dest_lat double precision DEFAULT NULL::double precision, p_dest_lng double precision DEFAULT NULL::double precision)
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

  -- Frenos contra pedidos falsos; los topes los define el encargado en Ajustes.
  select max_pending_per_phone, max_orders_per_phone_hour, max_remote_per_hour
    into v_max_phone_pending, v_max_phone_hour, v_max_local_hour
    from public.settings where id = 1;

  if (select count(*) from public.orders o
        join public.order_contacts k on k.order_id = o.id
       where o.status = 'pending' and k.phone <> ''
         and right(k.phone, 10) = right(v_phone, 10)) >= v_max_phone_pending then
    raise exception 'too_many_pending';
  end if;

  if (select count(*) from public.orders o
        join public.order_contacts k on k.order_id = o.id
       where o.created_at > now() - interval '1 hour' and k.phone <> ''
         and right(k.phone, 10) = right(v_phone, 10)) >= v_max_phone_hour then
    raise exception 'phone_hour_limit';
  end if;

  if (select count(*) from public.orders
       where modality <> 'dine_in' and created_at > now() - interval '1 hour') >= v_max_local_hour then
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

  update public.orders set total = v_total where id = v_order;

  -- Teléfono, dirección y ubicación viven aparte: solo los lee quien los necesita.
  insert into public.order_contacts (order_id, phone, street, number, reference, cash_change_from, dest_lat, dest_lng)
  values (v_order, v_phone, v_street, v_number, v_ref, p_cash_from, v_lat, v_lng);

  return jsonb_build_object('id', v_order, 'tracking_code', v_code);
end;
$function$;

-- Las funciones internas no se llaman desde afuera sin pasar por sus reglas.
revoke all on function public.create_order(int, jsonb, text, uuid, text) from public;
grant execute on function public.create_order(int, jsonb, text, uuid, text) to anon, authenticated;
revoke all on function public.create_remote_order(text, jsonb, text, text, text, uuid, uuid, text, text, text, numeric, double precision, double precision) from public;
grant execute on function public.create_remote_order(text, jsonb, text, text, text, uuid, uuid, text, text, text, numeric, double precision, double precision) to anon, authenticated;


-- =====================================================================
-- update-10 (ver supabase/update-10-compuerta-turnstile.sql)
-- =====================================================================

create table if not exists public.app_secrets (
  name  text primary key,
  value text not null
);
alter table public.app_secrets enable row level security;  -- sin políticas: nadie la lee desde la web
revoke all on public.app_secrets from public, anon, authenticated;

create or replace function public._gate_ok(p_gate text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select p_gate is not null and p_gate = value from public.app_secrets where name = 'order_gate'),
    true  -- sin secreto configurado, la compuerta está apagada
  );
$$;
revoke all on function public._gate_ok(text) from public, anon, authenticated;

-- Se reemplazan las versiones anteriores (cambia la lista de parámetros).
drop function if exists public.create_order(int, jsonb, text, uuid, text);
drop function if exists public.create_remote_order(text, jsonb, text, text, text, uuid, uuid, text, text, text, numeric, double precision, double precision);

create or replace function public.create_order(
  p_table  int,
  p_items  jsonb,
  p_name   text,
  p_token  uuid default null,
  p_method text default null,
  p_gate   text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
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
    select id into v_order from public.orders where client_token = p_token;
    if found then
      return v_order;
    end if;
  end if;

  select table_count, ordering_enabled, payment_methods, max_active_per_table
    into v_tables, v_enabled, v_methods, v_max_table
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

  -- Freno contra pedidos falsos: tope de pedidos activos por mesa (lo define el encargado).
  if (select count(*) from public.orders
       where table_number = p_table and status in ('pending', 'preparing', 'ready')) >= v_max_table then
    raise exception 'table_limit';
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

  -- Frenos contra pedidos falsos; los topes los define el encargado en Ajustes.
  select max_pending_per_phone, max_orders_per_phone_hour, max_remote_per_hour
    into v_max_phone_pending, v_max_phone_hour, v_max_local_hour
    from public.settings where id = 1;

  if (select count(*) from public.orders o
        join public.order_contacts k on k.order_id = o.id
       where o.status = 'pending' and k.phone <> ''
         and right(k.phone, 10) = right(v_phone, 10)) >= v_max_phone_pending then
    raise exception 'too_many_pending';
  end if;

  if (select count(*) from public.orders o
        join public.order_contacts k on k.order_id = o.id
       where o.created_at > now() - interval '1 hour' and k.phone <> ''
         and right(k.phone, 10) = right(v_phone, 10)) >= v_max_phone_hour then
    raise exception 'phone_hour_limit';
  end if;

  if (select count(*) from public.orders
       where modality <> 'dine_in' and created_at > now() - interval '1 hour') >= v_max_local_hour then
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

  update public.orders set total = v_total where id = v_order;

  -- Teléfono, dirección y ubicación viven aparte: solo los lee quien los necesita.
  insert into public.order_contacts (order_id, phone, street, number, reference, cash_change_from, dest_lat, dest_lng)
  values (v_order, v_phone, v_street, v_number, v_ref, p_cash_from, v_lat, v_lng);

  return jsonb_build_object('id', v_order, 'tracking_code', v_code);
end;
$function$;

revoke all on function public.create_order(int, jsonb, text, uuid, text, text) from public;
grant execute on function public.create_order(int, jsonb, text, uuid, text, text) to anon, authenticated;
revoke all on function public.create_remote_order(text, jsonb, text, text, text, uuid, uuid, text, text, text, numeric, double precision, double precision, text) from public;
grant execute on function public.create_remote_order(text, jsonb, text, text, text, uuid, uuid, text, text, text, numeric, double precision, double precision, text) to anon, authenticated;


-- =====================================================================
-- update-11 (ver supabase/update-11-radio-de-aviso.sql)
-- =====================================================================

alter table public.settings add column if not exists near_radius_m int not null default 300;

do $$
begin
  alter table public.settings add constraint settings_near_radius_valid check (near_radius_m in (150, 300, 500));
exception when duplicate_object then null;
end $$;

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
  select near_radius_m into v_radius from public.settings where id = 1;

  if not (
    public.has_role('manager', 'counter')
    or (public.staff_role() = 'courier'
        and exists (select 1 from public.orders where run_id = p_run and run_by = auth.uid()))
  ) then
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

  select * into v_ct from public.order_contacts where order_id = v_next.id;

  if v_next.near_at is null and v_ct.dest_lat is not null
     and public._distance_m(p_lat, p_lng, v_ct.dest_lat, v_ct.dest_lng) <= v_radius then
    update public.orders set near_at = now() where id = v_next.id;
  end if;
end;
$function$;

revoke all on function public.update_run_position(uuid, double precision, double precision, real) from public, anon;
grant execute on function public.update_run_position(uuid, double precision, double precision, real) to authenticated;


-- =====================================================================
-- update-12 (ver supabase/update-12-fotos-de-productos.sql)
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


-- =====================================================================
-- update-13 (ver supabase/update-13-planes-y-combos.sql)
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


-- =====================================================================
-- update-14 (ver supabase/update-14-plan-mesa.sql)
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
-- =====================================================================
-- update-15 · Suspensión del servicio por falta de pago
-- Ejecutar DESPUÉS de update-14. Se puede correr más de una vez.
--
-- Solo LM Studio lo cambia, desde el SQL Editor (el local no puede):
--
--   update public.settings set suspended = true;    -- cierra la vista
--   update public.settings set suspended = false;   -- la devuelve
--
-- Suspendido: la carta, los pedidos y el panel muestran «Servicio suspendido» y
-- no se pueden crear pedidos nuevos. Los datos del local se conservan.
-- =====================================================================

alter table public.settings add column if not exists suspended boolean not null default false;

-- El local (encargado) no puede cambiar ni el plan ni la suspensión.
create or replace function public.settings_plan_guard()
returns trigger
language plpgsql
as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.plan := old.plan;
    new.suspended := old.suspended;
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

-- Con el servicio suspendido no entran pedidos nuevos (por mesa ni a distancia).
create or replace function public.orders_suspended_guard()
returns trigger
language plpgsql
as $$
begin
  if exists (select 1 from public.settings where id = 1 and suspended) then
    raise exception 'service_suspended';
  end if;

  return new;
end;
$$;

drop trigger if exists orders_suspended_guard on public.orders;
create trigger orders_suspended_guard before insert on public.orders
  for each row execute function public.orders_suspended_guard();

update public.settings set plan = plan where id = 1;
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
