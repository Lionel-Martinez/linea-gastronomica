# Línea Gastronómica

Carta digital, pedidos y delivery para locales gastronómicos (Vue 3 + Vite + Tailwind, Cloudflare Pages + Supabase). Un solo código, cinco ediciones.

| Edición | Compilar | Salida | Supabase |
|---|---|---|---|
| Carta | `npm run build:carta` | `dist-carta` | No |
| Carta + Panel | `npm run build:panel` | `dist-panel` | Sí (`editions/panel.sql`) |
| Carta + Panel + Mesa | `npm run build:mesa` | `dist-mesa` | Sí (`editions/mesa.sql`) |
| Pedidos y delivery | `npm run build:delivery` | `dist-delivery` | Sí (`editions/delivery.sql`) |
| Completo | `npm run build:completo` (o `npm run build`) | `dist-completo` (`dist`) | Sí (`editions/completo.sql`) |

- `npm run build:all` compila las cinco. `npm run dev:<edicion>` para desarrollar.
- Variables (`.env.example`): `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` (no para Carta).
- Carta: los productos están en `src/data/menu.json`; el QR del local se imprime desde `/qr`.
- Guías por edición: `docs/ediciones/`. Base de datos: `supabase/README.md`.
