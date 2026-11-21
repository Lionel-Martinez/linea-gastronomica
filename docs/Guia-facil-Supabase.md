---
proyecto: linea-gastronomica
tipo: guía
fecha: 2026-11-21
---

# Guía fácil de Supabase (uso diario)

Carpeta recomendada: `linea-gastronomica/Tecnico/` · Archivo: `Guia-facil-Supabase.md`

## 1. Qué es, en 4 líneas
- Supabase es **la base de datos y el login** de todos los locales. Hay **un solo proyecto** y adentro cada local tiene sus datos separados.
- Cada local se identifica por un **nombre corto** (ej. `cafe-aurora`). Ese mismo nombre va en el sitio como `VITE_TENANT`.
- Vos trabajás en dos lugares: **SQL Editor** (pegás un comando y tocás «Run») y **Authentication → Users** (crear usuarios).
- No hace falta saber SQL: solo copiar, cambiar el nombre y ejecutar.

## 2. Una sola vez (proyecto nuevo)
1. Crear el proyecto en supabase.com. Guardar la contraseña de la base en un gestor de claves.
2. **SQL Editor** → pegar todo `supabase/schema.sql` → **Run**.
3. **Authentication → Sign In / Providers → Email**: apagar «Allow new users to sign up».
4. **Project Settings → API**: copiar la **URL** y la clave **anon / publishable**. Nunca usar ni compartir la `service_role`.
5. (Opcional) `supabase/seed.sql` crea el local de pruebas `demo`.

## 3. Cada local nuevo (5 pasos, ~5 minutos)
1. **SQL Editor**: abrir `supabase/editions/<edicion>.sql` (panel, mesa, delivery o completo), cambiar `v_slug` y `v_name`, **Run**.
2. **Authentication → Users → Add user → Create new user**: correo y contraseña del encargado, con **Auto Confirm User** marcado.
3. **SQL Editor** (cambiar los datos y **Run**):
   ```sql
   select public.add_staff('encargado@correo.com', 'cafe-aurora', 'manager');
   ```
   Roles: `manager` (encargado), `counter` (mostrador), `waiter` (mozo), `kitchen` (cocina), `courier` (repartidor). Cada persona pertenece a **un solo** local.
4. En Cloudflare, en el proyecto del local → **Settings → Build → Variables and secrets**: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, `VITE_TENANT=cafe-aurora`. Volver a desplegar.
5. Entrar a `https://<sitio>/staff/login` y probar.

Cargar productos desde planilla (opcional): `python3 scripts/importar_productos.py productos.csv --sql productos.sql --local cafe-aurora` y pegar `productos.sql` en el SQL Editor.

## 4. Operación (los 5 comandos)
```sql
select slug, name from public.tenants order by slug;          -- 1. lista de locales
select public.set_tenant_plan('cafe-aurora', 'table');         -- 2. cambiar de plan (menu_panel, table, orders, full)
select public.suspend_tenant('cafe-aurora', true);             -- 3. suspender por falta de pago (los datos quedan)
select public.suspend_tenant('cafe-aurora', false);            -- 4. reactivar al pagar
select public.add_staff('otro@correo.com', 'cafe-aurora', 'waiter');  -- 5. sumar o cambiar a una persona
```
Para sacar a una persona: Authentication → Users → ese usuario → Delete.

## 5. Qué NO hacer
- **Nunca** `update public.settings set ...` sin `where tenant_id = ...` (afectaría a todos; la base lo rechaza, pero no lo intentes).
- No borrar tablas ni ejecutar `schema.sql` de nuevo sobre un proyecto con locales sin avisar (se puede repetir sin romper, pero no hace falta).
- No usar la clave `service_role` en el sitio ni pegarla en chats.
- No crear otro proyecto de Supabase por local: es lo que se quiso evitar para no pagar de más.

## 6. Dónde mirar cuando algo falla
| Síntoma | Qué revisar |
|---|---|
| «Falta conectar Supabase» | El aviso dice qué variable falta. Cargarla en **Build → Variables and secrets** y volver a desplegar. |
| Entra al login pero dice credenciales inválidas | Authentication → Users: ¿existe el usuario? ¿Confirmado? Restablecer la contraseña. |
| Entra pero no ve nada / «sin acceso» | Falta `add_staff` o el nombre corto de `VITE_TENANT` no coincide con el del local. |
| «Servicio suspendido» | `suspend_tenant('<local>', false)` (¿pagó?). |
| Se ve el panel con funciones de más | Revisar el plan: `set_tenant_plan` y la edición publicada. |
| Los pedidos no entran | Ajustes del local: «Recibir pedidos» activado; revisar los topes y si el local está suspendido. |
| Supabase pausado (plan gratis) | Entrar al panel de Supabase y reactivar el proyecto (en Pro no pasa). |

## 7. Costos y respaldo
- Plan gratis: sirve para demos y pruebas; se pausa tras una semana sin uso y no tiene respaldos.
- Plan Pro (USD 25 fijos por mes, todos los locales juntos): pasar a Pro cuando cobres al primer local.
- Antes de cambios grandes: Database → Backups (en Pro) o exportar desde el SQL Editor.
