---
proyecto: linea-gastronomica
tipo: guía de edición
edicion: delivery
fecha: 2026-11-15
---

# Edición «Pedidos y delivery»

Carpeta recomendada: `linea-gastronomica/Ediciones/` · Archivo: `delivery.md`

**Para quién es:** Locales que hoy mandan la carta por WhatsApp o en foto y quieren ordenar retiro y delivery. No hay carta pública ni mesas.

## 1. Qué incluye
- Pedido a distancia en `/pedir` (la raíz del sitio lleva ahí): retiro o delivery, zonas de envío con costo, formas de pago.
- Seguimiento con código (`/seguimiento`), con mapa en vivo del repartidor y aviso «estoy cerca» (150/300/500 m).
- Código de entrega de 4 dígitos (opcional por local).
- Panel: **Pedidos**, **Reparto** (armar salidas, GPS, código), **Productos** (edición completa, fotos) y **Ajustes**.
- Roles: encargado, mostrador, cocina y repartidor.
- Privacidad: aviso, plazo de borrado de datos configurable y «olvidar mis datos».

## 2. Qué no incluye
- Carta pública con QR ni página de QR.
- Pedidos por mesa.

## 3. Qué necesita
- Un proyecto de Supabase, Cloudflare Pages y WhatsApp del local.
- Los productos igual hay que cargarlos (en el panel).
- Opcional: Cloudflare Turnstile (update-10) y habilitar `pg_cron` en Supabase.

- Pestañas del panel: Pedidos · Reparto · Productos · Ajustes
- Roles que se usan: Encargado, mostrador, cocina, repartidor

## 4. Instalación paso a paso

1. **Supabase.** Crear el proyecto del local en https://supabase.com. En **Authentication → Sign In / Providers → Email**, desactivar «Allow new users to sign up».
2. **Base de datos.** En el SQL Editor, ejecutar `supabase/schema.sql` completo (ya trae todas las actualizaciones) y después `supabase/editions/delivery.sql` (fija el plan del local).
3. **Usuarios del personal.** Crearlos en Authentication → Users (con «Auto Confirm User») y darles su rol con SQL (ejemplos en `supabase/README.md`, paso 7): `insert into public.staff (user_id, role) values ('<id>', 'manager');`. El primero siempre es `manager` (encargado).
4. **Datos del local.** Editar `src/data/menu.json`: nombre, descripción, dirección, horarios, WiFi, WhatsApp y los productos de ejemplo (se reemplazan por los que cargue el local en el panel).
5. **Publicar en Cloudflare.** Conectar el repositorio. Comando de compilación: `npm run build:delivery` · Comando de implementación: `npx wrangler deploy` (usa `wrangler.jsonc`, que publica `dist`; el nombre del proyecto en Cloudflare debe coincidir con el `name` del archivo, o usar `npx wrangler deploy --name <proyecto>`). Variables de entorno (Settings → Variables and Secrets): `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY` (la clave `anon`/`publishable`; **nunca** la `service_role`). Se leen al compilar: si las cambiás, hay que volver a publicar.
6. **Opcional, anti-bots (Turnstile).** Seguir `supabase/README.md` (update-10) y cargar las variables de la Function de Pedidos en Cloudflare.
7. **Borrado de datos.** Habilitar la extensión `pg_cron` en Supabase (Database → Extensions); igual funciona sin ella cuando el personal abre el panel.
8. **Dominio.** Conectar el dominio del local (o un subdominio de `lm-studio.com.ar`) en Cloudflare.
9. **Ajustes y QR.** Entrar al panel → **Ajustes** (formas de pago, alias/CBU, WhatsApp, límites) y después **Códigos QR** para imprimir los QR.

## 5. Pruebas de aceptación (antes de entregar)

- [ ] Abrir la raíz del sitio: lleva a `/pedir`.
- [ ] Hacer un pedido de retiro y otro de delivery (con zona); llega el código de seguimiento.
- [ ] El personal confirma y arma el reparto; el repartidor sale (la ubicación arranca sola) y el cliente ve el mapa.
- [ ] A menos del radio configurado, el cliente recibe el aviso «cerca» (vibra y suena).
- [ ] Código de entrega: el repartidor lo escribe y marca entregado; sin código, se confirma por nombre.
- [ ] Repartidor: solo ve Reparto, y solo sus paradas.
- [ ] Probar con teléfono real el GPS y que retome al desbloquear la pantalla.
- [ ] `/mesa/1` y `/staff/qr` no existen.
- [ ] Probado en un celular real (no solo en la compu).

## 6. Pasar a otra edición

Cambiar de edición son dos pasos: (1) en Cloudflare Pages, cambiar el *Build command* y el *Build output directory* por los de la edición nueva y volver a publicar; (2) en el SQL Editor, `update public.settings set plan = '<plan nuevo>';` (los planes están en `supabase/editions/`). Los datos no se pierden.

Ir a una edición **menor** apaga funciones: la base ya no deja usarlas aunque el plan se cambie solo en el front.
