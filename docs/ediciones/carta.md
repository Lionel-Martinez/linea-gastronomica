---
proyecto: linea-gastronomica
tipo: guía de edición
edicion: carta
fecha: 2026-11-15
---

# Edición «Carta»

Carpeta recomendada: `linea-gastronomica/Ediciones/` · Archivo: `carta.md`

**Para quién es:** Locales que solo quieren su carta digital con QR, sin panel ni pedidos.

## 1. Qué incluye
- Carta digital pública con categorías, buscador, fotos, horarios, WiFi y formulario de opinión.
- QR de la carta con estilos y colores del local (página `/qr`, para vos; no tiene enlace desde la carta).
- Sitio estático: **sin Supabase, sin login, sin servidor**. Costo de infraestructura: solo el dominio.
- Los productos y precios los cargás vos en `src/data/menu.json` y volvés a publicar.

## 2. Qué no incluye
- Panel del local ni edición propia.
- Pedidos (mesa, retiro o delivery) y seguimiento.
- Roles ni usuarios.

## 3. Qué necesita
- Cuenta de Cloudflare Pages (o cualquier hosting estático) y un dominio.

- Pestañas del panel: —
- Roles que se usan: —

## 4. Instalación paso a paso

1. **Datos del local.** Editar `src/data/menu.json`: nombre, descripción, dirección, horarios, WiFi, WhatsApp y los productos de ejemplo (en esta edición **son** los productos que ve el cliente).
2. **Publicar en Cloudflare Pages.** Conectar el repositorio. Build command: `npm run build:carta` · Build output directory: `dist-carta`. Variables de entorno: **ninguna**.
3. **Dominio.** Conectar el dominio del local (o un subdominio de `lm-studio.com.ar`) en Cloudflare Pages.
4. **QR.** Abrir `https://<dominio>/qr`, elegir estilo y colores, descargar el SVG/PNG y entregárselo al local.

## 5. Pruebas de aceptación (antes de entregar)

- [ ] La carta abre en el celular y se ve bien (390 px) y en escritorio.
- [ ] Los precios y productos coinciden con lo que pidió el local.
- [ ] `/qr`: descargar el QR (SVG/PNG), escanearlo con un celular y comprobar que abre la carta.
- [ ] `/staff`, `/mesa/1`, `/pedir`, `/seguimiento` no existen: vuelven a la carta.
- [ ] En las herramientas del navegador (pestaña Red) no hay llamadas a ningún servidor externo.
- [ ] Probado en un celular real (no solo en la compu).

## 6. Pasar a otra edición

Para subir a **Carta + Panel** o más: crear el proyecto de Supabase (pasos 1 a 3 de la guía de esa edición), cargar los productos en el panel y publicar con el *Build command* de la edición nueva.

Ir a una edición **menor** apaga funciones: la base ya no deja usarlas aunque el plan se cambie solo en el front.
