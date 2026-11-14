-- =====================================================================
-- update-11 · Radio del aviso «estoy cerca» configurable
-- Ejecutar DESPUÉS de update-10. Se puede correr más de una vez.
--
-- El encargado elige en Ajustes a cuántos metros de la próxima parada se
-- avisa solo al cliente: 150, 300 (por defecto) o 500 m.
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
