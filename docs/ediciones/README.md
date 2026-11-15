---
proyecto: linea-gastronomica
tipo: guía general de ediciones
fecha: 2026-11-15
---

# Ediciones de linea-gastronomica (versión 2)

Carpeta recomendada: `linea-gastronomica/Ediciones/` · Archivo: `README.md`

Un solo código, cinco ediciones. Cada edición se compila aparte y publica **solo** lo que incluye: lo que no está en el plan no existe en el sitio (la dirección vuelve a la carta) y la base de datos tampoco lo permite.

| | Carta | Carta + Panel | Carta + Panel + Mesa | Pedidos y delivery | Completo |
|---|:-:|:-:|:-:|:-:|:-:|
| Carta pública con QR | ✔ | ✔ | ✔ | — | ✔ |
| Servidor (Supabase) | — | ✔ | ✔ | ✔ | ✔ |
| Edición de productos | Vos | Solo precio y «disponible» | Completa | Completa | Completa |
| Fotos desde la galería | — | — | ✔ | ✔ | ✔ |
| Pedidos desde la mesa (QR por mesa) | — | — | ✔ | — | ✔ |
| Retiro y delivery con seguimiento | — | — | — | ✔ | ✔ |
| Reparto, mapa en vivo y código de entrega | — | — | — | ✔ | ✔ |
| Pantalla de pedidos | — | — | ✔ | ✔ | ✔ |
| Ajustes del local | — | — | ✔ | ✔ | ✔ |
| Página de QR | `/qr` | panel | panel | — | panel |
| Plan en la base | — | `menu_panel` | `table` | `orders` | `full` |
| Comando | `build:carta` | `build:panel` | `build:mesa` | `build:delivery` | `build:completo` |
| Carpeta de salida | `dist-carta` | `dist-panel` | `dist-mesa` | `dist-delivery` | `dist-completo` |

Guías: [[carta]] · [[panel]] · [[mesa]] · [[delivery]] · [[completo]]

## Roles por edición

| Rol | Panel | Mesa | Delivery | Completo |
|---|:-:|:-:|:-:|:-:|
| Encargado (`manager`) | ✔ | ✔ | ✔ | ✔ |
| Mostrador (`counter`) | — | ✔ | ✔ | ✔ |
| Mozo (`waiter`) | — | ✔ | — | ✔ |
| Cocina (`kitchen`) | — | ✔ | ✔ | ✔ |
| Repartidor (`courier`) | — | — | ✔ | ✔ |

## Cómo se arma cada edición

```bash
npm install
npm run build:carta      # → dist-carta
npm run build:panel      # → dist-panel
npm run build:mesa       # → dist-mesa
npm run build:delivery   # → dist-delivery
npm run build:completo   # → dist-completo
npm run build:all        # las cinco
npm run dev:panel        # desarrollo de una edición (dev:carta, dev:mesa, ...)
```

`npm run build` sigue generando la edición Completa en `dist` (lo que ya tenías publicado).

## Un sistema por local

Cada local tiene su propio proyecto de Supabase y su propio proyecto de Cloudflare Pages, con su comando de compilación (ver la guía de su edición). La edición **Carta** no usa Supabase.

## Decisiones tomadas (2026-11-15)
- Un solo repositorio con cinco ediciones (no cinco copias del proyecto).
- La edición Carta es un sitio estático sin Supabase; los productos viven en `src/data/menu.json`.
- Mismo `schema.sql` para todas las ediciones con Supabase; cada edición fija su plan con `supabase/editions/<edición>.sql`.
- «Completo» = mesa + retiro + delivery.
- El plan lo cambia solo LM Studio (SQL Editor); el local lo ve en Ajustes pero no lo cambia.

## Límite conocido
El sitio de cada edición no lleva las pantallas que no usa. Dentro de las pantallas compartidas (pedido, panel) queda algo de código que esa edición nunca ejecuta; no se ve ni se puede abrir.
