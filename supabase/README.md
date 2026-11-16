# Configuración de Supabase (Etapa 2)

**Un solo proyecto de Supabase para todos los locales.** Cada local es un «tenant» (nombre corto, ej. `cafe-del-centro`): sus datos
están separados y ninguno ve lo del otro. Un encargado pertenece a **un solo** local. Cada sitio publicado sabe a qué local
pertenece por la variable de compilación `VITE_TENANT`. Plan **Pro** recomendado (backups y sin pausa por inactividad).

## Proyecto nuevo (una sola vez)

1. Crear el proyecto en https://supabase.com.
2. **SQL Editor** → pegar y ejecutar `schema.sql`. (`seed.sql` es opcional: crea el local de pruebas `demo` con productos de ejemplo.)
3. **Authentication → Sign In / Providers → Email**: desactivar "Allow new users to sign up" (solo el personal entra, y lo crea LM Studio).
4. **Project Settings → API**: copiar la URL y la clave `anon`/`publishable`. **Nunca** usar la clave `service_role` en el frontend.

## Alta de cada local nuevo (no se crea otro proyecto)

1. **SQL Editor**: ejecutar `editions/<edicion>.sql` cambiando el nombre corto y el nombre (o, a mano:
   `select public.create_tenant('cafe-del-centro', 'Café del Centro', 'table');` con plan `menu_panel`, `table`, `orders` o `full`).
2. **Authentication → Users → Add user** (con "Auto Confirm User"): el encargado y, si el plan lo pide, mozo, cocina y repartidor.
3. Darles rol y local (`manager` = encargado, `counter` = mostrador, `waiter` = mozo, `kitchen` = cocina, `courier` = repartidor):
   ```sql
   select public.add_staff('encargado@correo.com', 'cafe-del-centro', 'manager');
   select public.add_staff('mozo1@correo.com',     'cafe-del-centro', 'waiter');
   ```
   Para cambiar el rol o el local de alguien se vuelve a llamar a `add_staff` con los nuevos datos.
4. Compilar y publicar el sitio del local con tres variables: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` y `VITE_TENANT=cafe-del-centro`
   (en Cloudflare: Settings → Variables and Secrets; se leen al compilar, hay que volver a desplegar).
   Si el local usa la compuerta Turnstile, la Function además necesita `TENANT` con el mismo nombre corto.
5. Entrar a `/staff/login`, ajustar mesas y alias/CBU en **Ajustes**, e imprimir los QR desde **Códigos QR**.

## Operación (solo LM Studio, desde el SQL Editor)

```sql
select public.set_tenant_plan('cafe-del-centro', 'full');   -- cambiar de plan
select public.suspend_tenant('cafe-del-centro', true);        -- suspender por falta de pago (datos intactos)
select public.suspend_tenant('cafe-del-centro', false);       -- reactivar
select slug, name from public.tenants order by slug;          -- lista de locales
```

Estas funciones (`create_tenant`, `set_tenant_plan`, `suspend_tenant`, `add_staff`, `use_tenant`) solo las puede ejecutar el SQL Editor:
el público y el personal de los locales no pueden. **Cuidado:** nunca hacer `update public.settings set ...` sin `where tenant_id = ...`;
la base rechaza actualizar varias filas de ajustes a la vez, justamente para evitar tocar todos los locales por error.

Para cargar datos de un local desde el SQL Editor (productos, por ejemplo) primero se indica el local en esa misma ejecución:
`select public.use_tenant('cafe-del-centro');`.

Si más adelante un local crece y conviene darle su propio proyecto, se copian sus datos (todas las tablas tienen `tenant_id`) a un
proyecto nuevo con el mismo `schema.sql`.

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

15. `update-15-suspension.sql` (después de la 14): **suspensión por falta de pago**. Solo LM Studio la cambia, desde el SQL Editor (el local no puede). Con varios locales se usa `select public.suspend_tenant('<local>', true);` (ver «Operación»).

    Suspendido: la carta, los pedidos y el panel muestran «Servicio suspendido» y no entran pedidos nuevos. En la edición Carta (sin base) se suspende quitando el dominio en Cloudflare.

16. `update-16-multilocal.sql` (después de la 15): **un solo Supabase para varios locales**. Todo lo que ya había queda como el local `demo`; a los usuarios existentes se les asigna ese local. Después hay que publicar el front-end nuevo con `VITE_TENANT=demo` (el viejo no manda el local y dejaría de ver datos). Las fotos que ya estaban subidas (sin carpeta del local) siguen mostrándose, pero para borrarlas o reemplazarlas hay que volver a subirlas. El encargado sube las nuevas fotos a la carpeta de su local.

**Ediciones (versión 2):** cada local usa una edición del sistema (Carta, Carta + Panel, Carta + Panel + Mesa, Pedidos y delivery, Completo). Ver `supabase/editions/<edicion>.sql` (alta del local con su plan). La edición Carta no usa Supabase. Ver `supabase/editions/README.md` y `docs/ediciones/`.

Mapa: sin configurar usa el mapa estándar de OpenStreetMap, que solo sirve para pruebas (su política lo desaconseja para apps comerciales). En producción usar Geoapify: variables de compilación `VITE_MAP_TILES_URL` y `VITE_MAP_ATTRIBUTION`. Ver `docs/Mapas-Geoapify.md`.

La ubicación depende del celular: funciona con la pantalla encendida y la página abierta (en iPhone sobre todo). Si el celular del repartidor se bloquea, el mapa del cliente deja de actualizarse.

Privacidad: teléfono, dirección y referencia se borran solos pasado el plazo que elige el encargado (7, 15 o 30 días, 15 por defecto). Si el proyecto tiene la extensión `pg_cron` activada, se ejecuta una vez por día; si no, se ejecuta cada vez que entra un pedido a distancia.

Un proyecto nuevo solo necesita `schema.sql` (y `seed.sql` si se quiere el local de pruebas).
