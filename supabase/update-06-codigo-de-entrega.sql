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
