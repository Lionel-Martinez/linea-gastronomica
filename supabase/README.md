# Configuración de Supabase (Etapa 2)

1. Crear un proyecto en https://supabase.com (plan gratuito alcanza).
2. **SQL Editor** → pegar y ejecutar `schema.sql`, y después `seed.sql` (datos de ejemplo).
3. **Authentication → Sign In / Providers → Email**: desactivar "Allow new users to sign up" (solo el personal entra, y lo crea el dueño).
4. **Authentication → Users → Add user**: crear un usuario por mozo/mostrador (email + contraseña, con "Auto Confirm User").
5. Autorizarlos como personal, en el SQL Editor, con su **rol** (`manager` = encargado, `counter` = mostrador, `waiter` = mozo, `kitchen` = cocina, `courier` = repartidor). Solo el encargado ve y cambia los Ajustes:
   ```sql
   insert into public.staff (user_id, role)
   select id, 'manager' from auth.users where email in ('encargado@ejemplo.com');

   insert into public.staff (user_id, role)
   select id, 'waiter'  from auth.users where email in ('mozo1@ejemplo.com');
   ```
   Para cambiar el rol después: `update public.staff set role = 'manager' where user_id = (select id from auth.users where email = 'x@ejemplo.com');`
6. **Project Settings → API**: copiar la URL y la clave `anon`/`publishable`. Copiar `.env.example` a `.env` y completarlo.
   - En Cloudflare Pages: Settings → Variables and Secrets → agregar `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY`, y volver a desplegar (se leen al compilar).
   - **Nunca** usar la clave `service_role` en el frontend.
7. Entrar a `/staff/login`, ajustar mesas y alias/CBU en **Ajustes**, e imprimir los QR desde **Códigos QR**.

Rutas: `/` carta (Etapa 1) · `/mesa/N` pedir · `/pedido/:id` seguimiento · `/staff` panel.

## Si ya tenías el proyecto creado (actualizaciones)

Ejecutar en el SQL Editor, **en orden y solo las que falten** (se pueden repetir sin riesgo):

1. `update-02-nombre-y-duplicados.sql`: nombre del cliente obligatorio y protección contra pedidos duplicados.
2. `update-03-pagos-whatsapp-interruptor.sql`: formas de pago, WhatsApp, interruptor de pedidos, rol de encargado y pedidos por mesa. Quienes ya estén en `staff` pasan a ser encargados.
3. `update-04-pedidos-a-distancia.sql` (Etapa 3A): retiro y delivery, zonas de envío, código de seguimiento, repartos con orden de paradas, límite y bloqueo por teléfono y borrado de datos personales. No cambia los pedidos por mesa. Retiro y delivery quedan apagados hasta que el encargado los encienda.

4. `update-05-gps-repartidor.sql` (Etapa 3B, después de la 04): ubicación en vivo del repartidor (mapa con un punto que se mueve, solo cuando el pedido es la próxima parada), ubicación opcional del cliente y aviso automático de «Estoy cerca» a menos de 300 m. La posición del repartidor se borra al terminar el reparto.

5. `update-06-codigo-de-entrega.sql` (después de la 05): código de entrega de 4 dígitos para delivery, opcional por local (se enciende en **Ajustes**). El cliente lo ve en su seguimiento y el repartidor lo escribe para marcar «Entregado»; si el cliente no lo tiene, se entrega confirmando su nombre y queda registrado. Solo afecta a los pedidos nuevos.

6. `update-07-borrado-de-respaldo.sql` (después de la 06): el borrado de datos personales también corre cuando el personal abre el panel (como máximo cada 6 horas), por si la extensión `pg_cron` no está habilitada. Igual conviene habilitar `pg_cron` en Supabase (Database → Extensions).

7. `update-08-roles-y-contactos.sql` (después de la 07): **roles con permisos reales**. El teléfono y la dirección de los clientes pasan a una tabla aparte que solo ven quienes corresponde. Las cuentas existentes quedan como *manager* (las que eran encargadas) o *counter* (el resto). Roles: `manager` (encargado, puede todo), `counter` (mostrador), `waiter` (mozo), `kitchen` (cocina), `courier` (repartidor). Para dar un rol, primero crear el usuario en Authentication → Users (con signups apagados) y después en el SQL Editor:

   ```sql
   insert into public.staff (user_id, role) values ('<id del usuario>', 'kitchen');
   update public.staff set role = 'courier' where user_id = '<id del usuario>';
   ```

   Después de correr esta actualización hay que publicar el front-end nuevo (hace `git pull` y deploy), porque el viejo no entiende las tablas nuevas.

8. `update-09-limites-de-pedidos.sql` (después de la 08): límites contra pedidos falsos que el encargado ajusta en **Ajustes**: pedidos en curso por mesa (3), sin confirmar por teléfono (5), pedidos por teléfono por hora (3) y retiro/delivery por hora en todo el local (20).

9. `update-10-compuerta-turnstile.sql` (después de la 09): prepara la **compuerta opcional** para Turnstile (anti-bots). No cambia nada hasta que se enciende. La guía completa está en `Guia-Turnstile.md` (carpeta Seguridad del vault); resumen: crear el widget en Cloudflare, cargar las variables `TURNSTILE_SECRET`, `ORDER_GATE`, `SUPABASE_URL`, `SUPABASE_ANON_KEY` y `VITE_TURNSTILE_SITEKEY` en Pages, redeployar y recién ahí guardar `order_gate` en la tabla `app_secrets`.

11. `update-11-radio-de-aviso.sql` (después de la 10): el encargado elige en **Ajustes** a qué distancia se avisa solo «el delivery está cerca» (150, 300 o 500 m; 300 por defecto).

12. `update-12-fotos-de-productos.sql` (después de la 11): crea el depósito público `product-images` en Supabase Storage para que el encargado suba fotos de productos desde la galería (se achican solas; máximo 1 MB). Solo el encargado puede subir o borrar; todos pueden ver las fotos de la carta.

13. `update-13-planes-y-combos.sql` (después de la 12): **planes (combos) por local**. Cada local tiene un plan que cambia solo LM Studio desde el SQL Editor (el encargado no puede):

    ```sql
    update public.settings set plan = 'menu';        -- Carta
    update public.settings set plan = 'menu_panel';  -- Carta + Panel (el local solo cambia precios y «disponible»)
    update public.settings set plan = 'table';       -- Carta + Panel + Mesa (pedir desde el QR de cada mesa)
    update public.settings set plan = 'orders';      -- Pedidos y delivery
    update public.settings set plan = 'full';        -- Completo
    ```

    Los locales que ya existen quedan en `full`. La base apaga las formas de pedido que el plan no incluye y limita lo que el local puede editar; el panel muestra solo las pantallas del plan.

14. `update-14-plan-mesa.sql` (después de la 13): agrega el plan `table` (Carta + Panel + Mesa).

**Ediciones (versión 2):** cada local usa una edición del sistema (Carta, Carta + Panel, Carta + Panel + Mesa, Pedidos y delivery, Completo). Después de `schema.sql` y `seed.sql`, ejecutar `supabase/editions/<edicion>.sql`, que fija el plan. La edición Carta no usa Supabase. Ver `supabase/editions/README.md` y `docs/ediciones/`.

Mapa: sin configurar usa el mapa estándar de OpenStreetMap, que solo sirve para pruebas (su política lo desaconseja para apps comerciales). En producción usar Geoapify: variables de compilación `VITE_MAP_TILES_URL` y `VITE_MAP_ATTRIBUTION`. Ver `docs/Mapas-Geoapify.md`.

La ubicación depende del celular: funciona con la pantalla encendida y la página abierta (en iPhone sobre todo). Si el celular del repartidor se bloquea, el mapa del cliente deja de actualizarse.

Privacidad: teléfono, dirección y referencia se borran solos pasado el plazo que elige el encargado (7, 15 o 30 días, 15 por defecto). Si el proyecto tiene la extensión `pg_cron` activada, se ejecuta una vez por día; si no, se ejecuta cada vez que entra un pedido a distancia.

Un proyecto nuevo solo necesita `schema.sql` y `seed.sql`.
