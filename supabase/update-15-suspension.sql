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
