---
proyecto: linea-gastronomica
tipo: guía
fecha: 2026-11-15
---

# Guía: planilla de productos del local

Carpeta recomendada: `linea-gastronomica/Ediciones/` · Archivo: `Guia-planilla-de-productos.md`

Cargar productos a mano es lo más lento de cada alta. Con la planilla, el local completa sus productos y vos los importás de una vez.

## 1. Qué le mandás al local
El archivo `plantillas/productos-modelo.csv` (se abre con Google Sheets o Excel). Una fila por producto:

| Columna | Qué poner | Ejemplo |
|---|---|---|
| `categoria` | Sección de la carta | Pastelería |
| `producto` | Nombre | Medialunas |
| `descripcion` | Texto corto (puede ir vacío) | Dos medialunas de manteca |
| `precio` | Número, con o sin `$` y puntos | 2800 o $ 2.800 |
| `imagen` | Enlace `https://…` (vacío si no hay) | |
| `disponible` | `si` o `no` (vacío = si) | si |
| `destacado` | `si` o `no` (vacío = no) | no |

El local la devuelve como archivo (Google Sheets: *Archivo → Descargar → CSV*). Las fotos se pueden subir después desde el panel (ediciones con panel) o cargar como enlace.

## 2. Importar
Desde la carpeta del repo principal:

- **Ediciones con Supabase** (Panel, Mesa, Pedidos y delivery, Completo):
  `python3 scripts/importar_productos.py productos.csv --sql productos-local.sql`
  y pegar `productos-local.sql` en el **SQL Editor** del Supabase del local. Se puede ejecutar más de una vez: no duplica productos.
- **Edición Carta**:
  `python3 scripts/importar_productos.py productos.csv --menu src/data/menu.json`
  dentro del proyecto de la edición Carta de ese local, y volver a publicar. Reemplaza los productos y categorías; los datos del local (nombre, horarios, WiFi) no se tocan.

## 3. Errores
Si la planilla tiene errores (categoría o nombre vacío, precio inválido, producto repetido, imagen sin `https://`, valor distinto de si/no), el script **no genera nada** y lista cada fila a corregir.

## 4. Lo que no hace
- No borra productos existentes ni cambia los que ya cargó el local (solo agrega los que faltan).
- No sube fotos desde archivos: solo enlaces.
- Los datos del local para la edición Carta (nombre, horarios, WiFi) se editan a mano en `src/data/menu.json`.
