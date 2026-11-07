# Configuración de Supabase (Etapa 2)

1. Crear un proyecto en https://supabase.com (plan gratuito alcanza).
2. **SQL Editor** → pegar y ejecutar `schema.sql`, y después `seed.sql` (datos de ejemplo).
3. **Authentication → Sign In / Providers → Email**: desactivar "Allow new users to sign up" (solo el personal entra, y lo crea el dueño).
4. **Authentication → Users → Add user**: crear un usuario por mozo/mostrador (email + contraseña, con "Auto Confirm User").
5. Autorizarlos como personal, en el SQL Editor:
   ```sql
   insert into public.staff (user_id)
   select id from auth.users where email in ('mozo1@ejemplo.com', 'mostrador@ejemplo.com');
   ```
6. **Project Settings → API**: copiar la URL y la clave `anon`/`publishable`. Copiar `.env.example` a `.env` y completarlo.
   - En Cloudflare Pages: Settings → Variables and Secrets → agregar `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY`, y volver a desplegar (se leen al compilar).
   - **Nunca** usar la clave `service_role` en el frontend.
7. Entrar a `/staff/login`, ajustar mesas y alias/CBU en **Ajustes**, e imprimir los QR desde **Códigos QR**.

Rutas: `/` carta (Etapa 1) · `/mesa/N` pedir · `/pedido/:id` seguimiento · `/staff` panel.
