-- =====================================================================
-- Actualización 02: nombre del cliente + protección contra pedidos duplicados
-- Para proyectos que ya ejecutaron el schema.sql anterior.
-- Se puede ejecutar más de una vez sin riesgo. Los pedidos que ya existían
-- quedan con el nombre vacío.
-- =====================================================================

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

revoke all on function public.create_order(int, jsonb, text, uuid) from public;
grant execute on function public.create_order(int, jsonb, text, uuid) to anon, authenticated;
