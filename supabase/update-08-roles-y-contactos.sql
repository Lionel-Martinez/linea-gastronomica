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
