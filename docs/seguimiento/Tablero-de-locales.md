---
proyecto: linea-gastronomica
tipo: tablero
fecha: 2026-11-15
---

# Tablero de locales

Carpeta recomendada: `linea-gastronomica/Locales/` · Archivo: `Tablero-de-locales.md`
Cada local es una nota en `linea-gastronomica/Locales/` creada con la plantilla `Plantilla-local.md`. Este tablero las lee solo (requiere el plugin **Dataview**).

## Estados (en orden)
`contacto` → `propuesta` → `aceptado` → `datos-recibidos` → `armando` → `en-prueba` → `en-produccion` → (`suspendido` | `baja`)

## Embudo
```dataview
TABLE length(rows) AS Locales
FROM "linea-gastronomica/Locales"
WHERE estado
GROUP BY estado
```

## Todos los locales
```dataview
TABLE edicion AS Edición, estado AS Estado, alta AS Alta, fin_prueba AS "Fin de prueba", proximo_cobro AS "Próximo cobro", cuota AS Cuota
FROM "linea-gastronomica/Locales"
WHERE estado
SORT estado ASC, nombre ASC
```

## Para hacer esta semana — armar
```dataview
LIST
FROM "linea-gastronomica/Locales"
WHERE estado = "aceptado" OR estado = "datos-recibidos" OR estado = "armando"
```

## Cobros que vencen (próximos 7 días o vencidos)
```dataview
TABLE edicion AS Edición, proximo_cobro AS Vence, cuota AS Cuota, estado AS Estado
FROM "linea-gastronomica/Locales"
WHERE proximo_cobro AND proximo_cobro <= date(today) + dur(7 days) AND estado = "en-produccion"
SORT proximo_cobro ASC
```

## Pruebas que terminan pronto
```dataview
TABLE edicion AS Edición, fin_prueba AS "Fin de prueba"
FROM "linea-gastronomica/Locales"
WHERE estado = "en-prueba" AND fin_prueba <= date(today) + dur(3 days)
SORT fin_prueba ASC
```

## Suspendidos (falta de pago)
```dataview
TABLE edicion AS Edición, suspendido_desde AS "Suspendido desde"
FROM "linea-gastronomica/Locales"
WHERE estado = "suspendido"
```

## Costo de infraestructura estimado
Locales con Supabase en producción o prueba × USD 10 + USD 25 de base (Supabase Pro, valores del 2026-11-15).
```dataview
TABLE length(rows) AS "Locales con Supabase", 25 + 10 * (length(rows) - 1) AS "USD por mes"
FROM "linea-gastronomica/Locales"
WHERE (estado = "en-produccion" OR estado = "en-prueba" OR estado = "armando") AND edicion != "carta"
GROUP BY true
```
