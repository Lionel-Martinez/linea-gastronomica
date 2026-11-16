---
proyecto: linea-gastronomica
tipo: guía de edición
edicion: mesa
fecha: 2026-11-15
---

# Edición «Carta + Panel + Mesa»

Carpeta recomendada: `linea-gastronomica/Ediciones/` · Archivo: `mesa.md`

**Para quién es:** Locales con salón que quieren que el cliente pida desde el QR de su mesa y que el personal vea los pedidos.

## 1. Qué incluye
- Todo lo de Carta + Panel, con **edición completa de productos** (crear, borrar, fotos desde la galería, categorías).
- Pedidos desde el QR de cada mesa (`/mesa/N`), con nombre del cliente, forma de pago y nota por producto.
- Pantalla de **Pedidos** para el personal (confirmar, preparar, listo, entregar) con aviso de pedidos nuevos.
- **Ajustes**: interruptor de pedidos, cantidad de mesas, formas de pago, alias/CBU, WhatsApp, límites contra pedidos falsos.
- QR de la carta y de **cada mesa**.
- Roles: encargado, mostrador, mozo y cocina.

## 2. Qué no incluye
- Retiro ni delivery, seguimiento con código, reparto ni mapa.
- Rol de repartidor.

## 3. Qué necesita
- Alta en el Supabase compartido de LM Studio y Cloudflare.
- Opcional: Cloudflare Turnstile (anti-bots) — ver `supabase/README.md`, update-10.

- Pestañas del panel: Pedidos · Productos · Ajustes · Códigos QR
- Roles que se usan: Encargado, mostrador, mozo, cocina

## 4. Instalación paso a paso

1. **Supabase (compartido).** No se crea un proyecto por local: se usa el proyecto único de LM Studio (ya configurado según `supabase/README.md`, «Proyecto nuevo»).
2. **Alta del local.** En el SQL Editor, ejecutar `supabase/editions/mesa.sql` cambiando el nombre corto (`v_slug`, ej. `cafe-del-centro`) y el nombre. Crea el local con el plan de la edición.
3. **Usuarios del personal.** Crearlos en Authentication → Users (con «Auto Confirm User») y asignarlos al local con su rol: `select public.add_staff('encargado@correo.com', 'cafe-del-centro', 'manager');` (roles: `manager`, `counter`, `waiter`, `kitchen`, `courier`; cada persona pertenece a un solo local). El primero siempre es `manager`.
4. **Datos del local.** Editar `src/data/menu.json`: nombre, descripción, dirección, horarios, WiFi, WhatsApp y los productos de ejemplo (se reemplazan por los que cargue el local en el panel).
5. **Publicar en Cloudflare.** Conectar el repositorio. Comando de compilación: `npm run build:mesa` · Comando de implementación: `npx wrangler deploy` (usa `wrangler.jsonc`, que publica `dist`; el nombre del proyecto en Cloudflare debe coincidir con el `name` del archivo, o usar `npx wrangler deploy --name <proyecto>`). Variables de entorno (Settings → Variables and Secrets): `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` y `VITE_TENANT` (el nombre corto del local, igual al del alta) (la clave `anon`/`publishable`; **nunca** la `service_role`). Se leen al compilar: si las cambiás, hay que volver a publicar.
6. **Opcional, anti-bots (Turnstile).** Seguir `supabase/README.md` (update-10) y cargar las variables de la Function de Pedidos en Cloudflare.
7. **Dominio.** Conectar el dominio del local (o un subdominio de `lm-studio.com.ar`) en Cloudflare.
8. **Ajustes y QR.** Entrar al panel → **Ajustes** (formas de pago, alias/CBU, WhatsApp, límites) y después **Códigos QR** para imprimir los QR de la carta y de cada mesa.

## 5. Pruebas de aceptación (antes de entregar)

- [ ] Pedir desde `/mesa/3` en un celular: el pedido aparece en **Pedidos** del personal.
- [ ] Pasar el pedido por confirmar → en preparación → listo → entregado.
- [ ] Mozo: ve solo pedidos de mesa y solo confirma y entrega; cocina: solo «Marcar listo».
- [ ] Mostrador y mozo no entran a Ajustes, Productos ni Códigos QR.
- [ ] El cliente ve el estado de su pedido en `/pedido/:id`.
- [ ] Superar el límite de pedidos activos por mesa muestra un aviso claro.
- [ ] Imprimir los QR de las mesas y escanear uno con un celular.
- [ ] `/pedir`, `/seguimiento` y `/staff/reparto` no existen.
- [ ] Probado en un celular real (no solo en la compu).

## 6. Pasar a otra edición

Cambiar de edición son dos pasos: (1) en Cloudflare Pages, cambiar el *Build command* y el *Build output directory* por los de la edición nueva y volver a publicar; (2) en el SQL Editor, `select public.set_tenant_plan('<local>', '<plan nuevo>');` (planes: `menu_panel`, `table`, `orders`, `full`). Los datos no se pierden.

Ir a una edición **menor** apaga funciones: la base ya no deja usarlas aunque el plan se cambie solo en el front.
