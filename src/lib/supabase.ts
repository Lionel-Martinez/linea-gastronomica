import { createClient, type SupabaseClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
const key = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined
// Un solo Supabase atiende a varios locales: cada sitio dice a cuál pertenece (se fija al compilar).
export const tenantSlug = ((import.meta.env.VITE_TENANT as string | undefined) ?? '').trim().toLowerCase()

// Si faltan las variables de entorno la app no se rompe: las pantallas de la
// Etapa 2 muestran un aviso y el menú de la Etapa 1 sigue funcionando.
/** Variables de compilación que faltan (para mostrarlas en el aviso). */
export const missingVars = [
  !url && 'VITE_SUPABASE_URL',
  !key && 'VITE_SUPABASE_ANON_KEY',
  !tenantSlug && 'VITE_TENANT'
].filter(Boolean) as string[]

export const isSupabaseConfigured = Boolean(url && key && tenantSlug)

export const supabase: SupabaseClient | null =
  url && key && tenantSlug
    ? createClient(url, key, {
        global: {
          // La cabecera del local se manda SOLO a la API de datos (/rest/v1). El login y las fotos
          // no la necesitan y un servidor puede rechazar cabeceras que no conoce (error de conexión).
          // Los datos cambian seguido (mesas, precios, pedidos): nunca se reutiliza una respuesta guardada.
          fetch: (input, init) => {
            const href = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url
            const headers = new Headers(init?.headers ?? (input instanceof Request ? input.headers : undefined))
            if (href.includes('/rest/v1/')) headers.set('x-tenant', tenantSlug)
            return fetch(input, { ...init, headers, cache: 'no-store' })
          }
        }
      })
    : null


export function db(): SupabaseClient {
  if (!supabase) throw new Error('not_configured')
  return supabase
}
