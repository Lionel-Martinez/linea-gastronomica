-- =====================================================================
-- Edición «panel» · alta del local (o cambio de edición) en el Supabase compartido
-- Ejecutar DESPUÉS de schema.sql. Se puede repetir sin riesgo.
-- Carta + Panel: el local cambia precios y «disponible».
--
-- 1) Cambiar las dos líneas marcadas con «EDITAR».
-- 2) El nombre corto (slug) es el mismo que se pone en VITE_TENANT al compilar el sitio del local.
-- El encargado no puede cambiar el plan ni suspender: solo se hace desde acá.
-- =====================================================================

do $$
declare
  v_slug text := 'mi-local';      -- EDITAR: nombre corto, minúsculas, números y guiones (ej. 'cafe-del-centro')
  v_name text := 'Mi local';      -- EDITAR: nombre para mostrar (solo orden interno)
begin
  if exists (select 1 from public.tenants where slug = v_slug) then
    perform public.set_tenant_plan(v_slug, 'menu_panel');
  else
    perform public.create_tenant(v_slug, v_name, 'menu_panel');
  end if;
end $$;

select t.slug, s.plan, s.ordering_enabled, s.pickup_enabled, s.delivery_enabled, s.suspended
  from public.settings s join public.tenants t on t.id = s.tenant_id
 order by t.slug;
