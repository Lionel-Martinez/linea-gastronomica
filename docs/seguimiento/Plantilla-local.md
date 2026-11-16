---
nombre: 
edicion: carta        # carta | panel | mesa | delivery | completo
estado: contacto      # contacto | propuesta | aceptado | datos-recibidos | armando | en-prueba | en-produccion | suspendido | baja
contacto_nombre: 
contacto_whatsapp: 
alta: 
fin_prueba: 
cuota: 
proximo_cobro: 
suspendido_desde: 
dominio: 
supabase_proyecto: 
cloudflare_proyecto: 
---

# {{nombre}}

Carpeta recomendada: `linea-gastronomica/Locales/` · Archivo: `<nombre-del-local>.md`

## Resumen
- Edición contratada:
- Esquema de cobro (sencillo / intermedio / completo):
- Puesta en producción acordada: $
- Cuota mensual: $
- Qué se acordó aparte:

## Checklist de alta
- [ ] Propuesta enviada
- [ ] Aceptó (fecha:      )
- [ ] Cobro de la primera parte (50 % antes, si corresponde)
- [ ] Recibí: logo, colores, horarios, WiFi, dirección, redes
- [ ] Recibí la planilla de productos completa (`productos-modelo.csv`)
- [ ] Planilla importada (`importar_productos.py --local <nombre-corto>`)
- [ ] Local dado de alta en el Supabase compartido (`editions/<edicion>.sql` con su nombre corto; **no** se crea otro proyecto)  *(no aplica a Carta)*
- [ ] Usuarios del personal creados y asignados al local (`select public.add_staff('correo','<local>','manager');`)  *(no aplica a Carta)*
- [ ] Proyecto de Cloudflare publicado con las variables de compilación (`VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, `VITE_TENANT=<nombre-corto>`)
- [ ] Subdominio `<local>.lm-studio.com.ar` conectado
- [ ] Supabase: *Site URL* con la dirección definitiva  *(no aplica a Carta)*
- [ ] Mapas: variables de Geoapify cargadas  *(solo delivery y completo)*
- [ ] Probado desde un celular: carta, QR, pedidos, panel
- [ ] QR impresos / entregados
- [ ] Capacitación hecha (cómo cambiar precios, cómo ver pedidos)
- [ ] Prueba iniciada (fin: dd/mm)
- [ ] Cobro del segundo pago / primera cuota
- [ ] En producción

## Bitácora
| Fecha | Qué pasó |
|---|---|
|  |  |

## Cobros
| Mes | Monto | Pagó (fecha) | Nota |
|---|---|---|---|
|  |  |  |  |

## Suspensión por falta de pago (si pasa)
1. Pasaron ~5 días de atraso → avisar por WhatsApp.
2. Suspender (SQL Editor del Supabase compartido): `select public.suspend_tenant('<local>', true);`  (Carta: quitar el dominio en Cloudflare). **No** usar `update public.settings` suelto: afectaría a todos los locales.
3. Al pagar: `select public.suspend_tenant('<local>', false);`  y anotar la fecha acá.
