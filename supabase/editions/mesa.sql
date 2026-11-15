-- =====================================================================
-- Edición «mesa» · fija el plan del local
-- Ejecutar DESPUÉS de schema.sql (o de update-14 si es un proyecto viejo).
-- El encargado del local no puede cambiar el plan: solo se cambia desde acá.
-- =====================================================================

-- Carta + Panel + Mesa: pedidos desde el QR de cada mesa.
update public.settings set plan = 'table', ordering_enabled = true where id = 1;

select plan, ordering_enabled, pickup_enabled, delivery_enabled from public.settings;
