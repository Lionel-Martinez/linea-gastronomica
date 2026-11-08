# Configuración de Supabase (Etapa 2)

1. Crear un proyecto en https://supabase.com (plan gratuito alcanza).
2. **SQL Editor** → pegar y ejecutar `schema.sql`, y después `seed.sql` (datos de ejemplo).
3. **Authentication → Sign In / Providers → Email**: desactivar "Allow new users to sign up" (solo el personal entra, y lo crea el dueño).
4. **Authentication → Users → Add user**: crear un usuario por mozo/mostrador (email + contraseña, con "Auto Confirm User").
5. Autorizarlos como personal, en el SQL Editor. `is_manager = true` es para las personas **encargadas** del local (solo ellas ven y cambian los Ajustes: interruptor de pedidos, formas de pago, mesas, WhatsApp); los mozos van con `false`:
   ```sql
   insert into public.staff (user_id, is_manager)
   select id, true  from auth.users where email in ('encargado@ejemplo.com');

   insert into public.staff (user_id, is_manager)
   select id, false from auth.users where email in ('mozo1@ejemplo.com', 'mostrador@ejemplo.com');
   ```
   Para convertir a alguien en encargado después: `update public.staff set is_manager = true where user_id = (select id from auth.users where email = 'x@ejemplo.com');`
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

Privacidad: teléfono, dirección y referencia se borran solos pasado el plazo que elige el encargado (7, 15 o 30 días, 15 por defecto). Si el proyecto tiene la extensión `pg_cron` activada, se ejecuta una vez por día; si no, se ejecuta cada vez que entra un pedido a distancia.

Un proyecto nuevo solo necesita `schema.sql` y `seed.sql`.
