-- =====================================================================
-- Actualización 05 · Etapa 3B: GPS del repartidor y mapa.
-- Para proyectos que ya ejecutaron schema.sql + update-02, 03 y 04.
-- Se puede correr más de una vez sin riesgo.
--
-- Qué agrega:
--   · Ubicación opcional del cliente al pedir delivery ("Usar mi ubicación").
--   · Última posición del repartidor durante un reparto (una sola fila por reparto).
--   · El cliente ve al repartidor SOLO cuando su pedido es la próxima parada,
--     y solo la distancia aproximada (no su propia ubicación guardada).
--   · "Estoy cerca" automático a menos de 300 m de la próxima parada.
--   · Al terminar el reparto la posición se borra; la ubicación del cliente
--     se borra con el resto de sus datos personales.
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
