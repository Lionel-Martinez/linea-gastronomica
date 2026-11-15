---
proyecto: linea-gastronomica
tipo: guía de edición
edicion: completo
fecha: 2026-11-15
---

# Edición «Completo»

Carpeta recomendada: `linea-gastronomica/Ediciones/` · Archivo: `completo.md`

**Para quién es:** Locales que quieren todo: carta, pedidos en mesa, retiro y delivery.

## 1. Qué incluye
- Todo lo de las otras ediciones: carta pública con QR, pedidos por mesa, retiro y delivery con seguimiento, reparto con mapa y código de entrega.
- Panel completo: **Pedidos**, **Reparto**, **Productos**, **Ajustes** y **Códigos QR**.
- Roles: encargado, mostrador, mozo, cocina y repartidor.

## 2. Qué no incluye
- Nada: incluye todo.

## 3. Qué necesita
- Un proyecto de Supabase, Cloudflare Pages y WhatsApp del local.
- Opcional: Cloudflare Turnstile (update-10) y `pg_cron` habilitado.

- Pestañas del panel: Pedidos · Reparto · Productos · Ajustes · Códigos QR
- Roles que se usan: Encargado, mostrador, mozo, cocina, repartidor

## 4. Instalación paso a paso

1. **Supabase.** Crear el proyecto del local en https://supabase.com. En **Authentication → Sign In / Providers → Email**, desactivar «Allow new users to sign up».
2. **Base de datos.** En el SQL Editor, ejecutar `supabase/schema.sql` completo (ya trae todas las actualizaciones) y después `supabase/editions/completo.sql` (fija el plan del local).
3. **Usuarios del personal.** Crearlos en Authentication → Users (con «Auto Confirm User») y darles su rol con SQL (ejemplos en `supabase/README.md`, paso 7): `insert into public.staff (user_id, role) values ('<id>', 'manager');`. El primero siempre es `manager` (encargado).
4. **Datos del local.** Editar `src/data/menu.json`: nombre, descripción, dirección, horarios, WiFi, WhatsApp y los productos de ejemplo (se reemplazan por los que cargue el local en el panel).
5. **Publicar en Cloudflare.** Conectar el repositorio. Comando de compilación: `npm run build:completo` · Comando de implementación: `npx wrangler deploy` (usa `wrangler.jsonc`, que publica `dist`; el nombre del proyecto en Cloudflare debe coincidir con el `name` del archivo, o usar `npx wrangler deploy --name <proyecto>`). Variables de entorno (Settings → Variables and Secrets): `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY` (la clave `anon`/`publishable`; **nunca** la `service_role`). Se leen al compilar: si las cambiás, hay que volver a publicar.
6. **Opcional, anti-bots (Turnstile).** Seguir `supabase/README.md` (update-10) y cargar las variables de la Function de Pedidos en Cloudflare.
7. **Borrado de datos.** Habilitar la extensión `pg_cron` en Supabase (Database → Extensions); igual funciona sin ella cuando el personal abre el panel.
8. **Dominio.** Conectar el dominio del local (o un subdominio de `lm-studio.com.ar`) en Cloudflare.
9. **Ajustes y QR.** Entrar al panel → **Ajustes** (formas de pago, alias/CBU, WhatsApp, límites) y después **Códigos QR** para imprimir los QR.

## 5. Pruebas de aceptación (antes de entregar)

- [ ] Carta pública con «Seguí tu pedido», chips de modalidades y QR.
- [ ] Pedido por mesa y pedido a distancia llegan a **Pedidos**.
- [ ] Retiro/delivery de punta a punta (ver edición Pedidos y delivery).
- [ ] Cada rol ve solo lo suyo (ver tabla de roles en `docs/ediciones/README.md`).
- [ ] Ajustes muestra «Pedidos desde la mesa» y «Pedidos desde casa».
- [ ] Probado en un celular real (no solo en la compu).

## 6. Pasar a otra edición

Cambiar de edición son dos pasos: (1) en Cloudflare Pages, cambiar el *Build command* y el *Build output directory* por los de la edición nueva y volver a publicar; (2) en el SQL Editor, `update public.settings set plan = '<plan nuevo>';` (los planes están en `supabase/editions/`). Los datos no se pierden.

Ir a una edición **menor** apaga funciones: la base ya no deja usarlas aunque el plan se cambie solo en el front.
