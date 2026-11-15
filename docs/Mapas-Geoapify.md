---
proyecto: linea-gastronomica
tipo: decisión técnica
estado: aprobado — pendiente de configurar en producción
fecha: 2026-11-15
---

# Proveedor de mapas para producción: Geoapify

Carpeta recomendada: `linea-gastronomica/Tecnico/` · Archivo: `Mapas-Geoapify.md`

## 1. Decisión
Usar **Geoapify (plan gratis)** como proveedor de mapas en producción. Aplica a las ediciones **Pedidos y delivery** y **Completo** (son las que muestran el mapa del repartidor). Las demás no cargan mapas.

## 2. Por qué
- OpenStreetMap estándar (`tile.openstreetmap.org`) **no se debe usar en producción comercial**: su política dice que no hay garantía de servicio, que pueden bloquear el acceso sin aviso y que las apps comerciales deben esperar que se les retire el acceso.
- Los planes gratis de Stadia Maps y MapTiler **no permiten uso comercial**.
- Geoapify gratis **sí permite uso comercial en producción**: 3.000 créditos por día; cada solicitud de mosaico cuesta 0,25 créditos, o sea **12.000 mosaicos por día**.

Fuentes: [Política de OSM](https://operations.osmfoundation.org/policies/tiles/) · [Geoapify precios](https://geoapify.com/pricing) · [Geoapify detalle de créditos](https://www.geoapify.com/pricing-details) · [Stadia](https://stadiamaps.com/pricing/) · [MapTiler](https://www.maptiler.com/cloud/pricing/). Consultadas el 2026-11-15.

## 3. Cuánto alcanza (estimación)
El mapa solo se muestra al cliente cuando su pedido es la próxima parada. Una consulta de seguimiento carga del orden de 30 a 60 mosaicos (estimación, no medida). Con 12.000 mosaicos por día alcanzan unas **200 a 400 consultas de seguimiento por día entre todos los locales**.

Si se supera, planes de pago:
| Proveedor | Precio | Cupo |
|---|---|---|
| Geoapify API 10 | USD 59/mes | 10.000 créditos/día (≈ 40.000 mosaicos/día) |
| Stadia Maps Starter | USD 20/mes | 1.000.000 créditos/mes (1 por mosaico), uso comercial |
| MapTiler Flex | USD 30/mes | 500.000 solicitudes/mes |

Stadia sale más barato si el volumen crece. Cambiar de proveedor es solo cambiar dos variables, sin tocar el código.

## 4. Configuración
1. Crear cuenta en geoapify.com y un **proyecto** (una clave). Se puede usar una clave por local o una compartida.
2. En el panel de Geoapify, restringir la clave a los dominios donde se usa (`*.lm-studio.com.ar`), si la opción está disponible en el plan. La clave queda visible en el navegador (es normal en mapas); la restricción evita que otros la usen.
3. En Cloudflare, en cada proyecto con delivery, agregar estas **variables de compilación**:
   - `VITE_MAP_TILES_URL` = `https://maps.geoapify.com/v1/tile/osm-bright/{z}/{x}/{y}.png?apiKey=TU_CLAVE`
   - `VITE_MAP_ATTRIBUTION` = `Powered by <a href="https://www.geoapify.com/">Geoapify</a> | &copy; <a href="https://openmaptiles.org/">OpenMapTiles</a> &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors`
4. Volver a publicar (se leen al compilar).
5. Probar: abrir un seguimiento con mapa en el celular, verificar que se vea el mapa y la atribución abajo a la derecha.

## 5. Riesgos y pendientes
- Los límites y precios de Geoapify pueden cambiar: revisar antes de sumar muchos locales.
- Si se agota el cupo diario, el mapa no carga (el resto del seguimiento sigue funcionando; la pantalla ya maneja el fallo del mapa).
- Verificar en el panel de Geoapify si el plan gratis permite restringir la clave por dominio y la política de atribución vigente.

## 6. Decisiones registradas
| Fecha | Decisión | Estado |
|---|---|---|
| 2026-11-15 | Geoapify (plan gratis) como proveedor de mapas en producción | Aprobado |
| 2026-11-15 | Sin ajuste periódico de la cuota por ahora | Aprobado |
