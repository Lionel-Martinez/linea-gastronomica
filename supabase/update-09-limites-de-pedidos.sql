-- =====================================================================
-- update-09 · Límites de pedidos configurables
-- Ejecutar DESPUÉS de update-08. Se puede correr más de una vez.
--
-- El encargado define en Ajustes cuántos pedidos se aceptan:
--   · por mesa activos (pendientes + en preparación + listos)   → 3
--   · sin confirmar por teléfono (retiro/delivery)               → 5
--   · por teléfono en la última hora                             → 3
--   · de retiro/delivery en total por hora en el local           → 20
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
