---
proyecto: linea-gastronomica
tipo: guía de edición
edicion: panel
fecha: 2026-11-15
---

# Edición «Carta + Panel»

Carpeta recomendada: `linea-gastronomica/Ediciones/` · Archivo: `panel.md`

**Para quién es:** Locales que quieren cambiar sus precios y marcar «agotado» sin depender de vos, sin pedidos.

## 1. Qué incluye
- Todo lo de la edición Carta (la carta ahora se lee de la base de datos).
- Login del local y panel con **Productos**: el local cambia **precio** y **disponible**.
- QR con estilos del local, dentro del panel (**Códigos QR**).

## 2. Qué no incluye
- Crear ni borrar productos, categorías, ni subir fotos (lo hacés vos; la base lo impide).
- Pedidos (mesa, retiro o delivery).
- Ajustes, reparto ni roles de cocina/mozo/repartidor.

## 3. Qué necesita
- Un proyecto de Supabase (plan gratuito alcanza para empezar) y Cloudflare Pages.

- Pestañas del panel: Productos · Códigos QR
- Roles que se usan: Encargado (`manager`)

## 4. Instalación paso a paso

1. **Supabase.** Crear el proyecto del local en https://supabase.com. En **Authentication → Sign In / Providers → Email**, desactivar «Allow new users to sign up».
2. **Base de datos.** En el SQL Editor, ejecutar `supabase/schema.sql` completo (ya trae todas las actualizaciones) y después `supabase/editions/panel.sql` (fija el plan del local).
3. **Usuarios del personal.** Crearlos en Authentication → Users (con «Auto Confirm User») y darles su rol con SQL (ejemplos en `supabase/README.md`, paso 7): `insert into public.staff (user_id, role) values ('<id>', 'manager');`. El primero siempre es `manager` (encargado).
4. **Datos del local.** Editar `src/data/menu.json`: nombre, descripción, dirección, horarios, WiFi, WhatsApp y los productos de ejemplo (se reemplazan por los que cargue el local en el panel).
5. **Publicar en Cloudflare Pages.** Conectar el repositorio. Build command: `npm run build:panel` · Build output directory: `dist-panel`. Variables de entorno (Settings → Variables and Secrets): `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY` (la clave `anon`/`publishable`; **nunca** la `service_role`). Se leen al compilar: si las cambiás, hay que volver a publicar.
6. **Dominio.** Conectar el dominio del local (o un subdominio de `lm-studio.com.ar`) en Cloudflare Pages.
7. **QR.** Entrar al panel → **Códigos QR**, elegir estilo y descargar.

## 5. Pruebas de aceptación (antes de entregar)

- [ ] El encargado entra en `/staff/login` y cae en **Productos**.
- [ ] Cambia un precio y «disponible»: se ve enseguida en la carta pública.
- [ ] No aparece «Nuevo», ni foto, ni nombre/descripción/categoría editables, ni «Eliminar».
- [ ] Las pestañas son solo Productos y Códigos QR; `/staff/ajustes` y `/staff/reparto` no existen.
- [ ] Un usuario sin fila en `staff` no puede entrar.
- [ ] `/mesa/1`, `/pedir`, `/seguimiento` no existen.
- [ ] Probado en un celular real (no solo en la compu).

## 6. Pasar a otra edición

Cambiar de edición son dos pasos: (1) en Cloudflare Pages, cambiar el *Build command* y el *Build output directory* por los de la edición nueva y volver a publicar; (2) en el SQL Editor, `update public.settings set plan = '<plan nuevo>';` (los planes están en `supabase/editions/`). Los datos no se pierden.

Ir a una edición **menor** apaga funciones: la base ya no deja usarlas aunque el plan se cambie solo en el front.
