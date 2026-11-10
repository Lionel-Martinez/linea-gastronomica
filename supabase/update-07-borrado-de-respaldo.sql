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
