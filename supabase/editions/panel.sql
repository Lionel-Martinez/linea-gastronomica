-- =====================================================================
-- Edición «panel» · fija el plan del local
-- Ejecutar DESPUÉS de schema.sql (o de update-14 si es un proyecto viejo).
-- El encargado del local no puede cambiar el plan: solo se cambia desde acá.
-- =====================================================================

-- Carta + Panel: el local cambia solo precios y «disponible».
update public.settings set plan = 'menu_panel' where id = 1;

select plan, ordering_enabled, pickup_enabled, delivery_enabled from public.settings;
