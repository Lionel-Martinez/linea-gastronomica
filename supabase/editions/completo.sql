-- =====================================================================
-- Edición «completo» · fija el plan del local
-- Ejecutar DESPUÉS de schema.sql (o de update-14 si es un proyecto viejo).
-- El encargado del local no puede cambiar el plan: solo se cambia desde acá.
-- =====================================================================

-- Completo: mesa + retiro + delivery.
update public.settings set plan = 'full', ordering_enabled = true, pickup_enabled = true, delivery_enabled = true where id = 1;

select plan, ordering_enabled, pickup_enabled, delivery_enabled from public.settings;
