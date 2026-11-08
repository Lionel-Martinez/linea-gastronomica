-- =====================================================================
-- Actualización 03: métodos de pago, WhatsApp, interruptor de pedidos,
-- rol de encargado y pedidos activos por mesa.
-- Para proyectos que ya ejecutaron schema.sql + update-02. Se puede correr
-- más de una vez sin riesgo.
-- IMPORTANTE: quienes ya están en la tabla staff pasan a ser encargados
-- (la primera vez que se corre). Los mozos nuevos se cargan con is_manager = false.
-- =====================================================================

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

-- Cómo va a pagar el cliente (vacío en pedidos anteriores a esta versión).
alter table public.orders add column if not exists payment_method text not null default '';

do $$
begin
  alter table public.orders add constraint orders_payment_method_valid
    check (payment_method in ('', 'transfer', 'card', 'qr', 'cash'));
exception when duplicate_object then null;
end $$;

-- Solo encargados editan los ajustes
drop policy if exists settings_update on public.settings;
create policy settings_update on public.settings
  for update to authenticated using (public.is_manager()) with check (public.is_manager());

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
