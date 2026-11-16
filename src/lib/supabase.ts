import { createClient, type SupabaseClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
const key = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined
// Un solo Supabase atiende a varios locales: cada sitio dice a cuál pertenece (se fija al compilar).
export const tenantSlug = ((import.meta.env.VITE_TENANT as string | undefined) ?? '').trim().toLowerCase()

// Si faltan las variables de entorno la app no se rompe: las pantallas de la
// Etapa 2 muestran un aviso y el menú de la Etapa 1 sigue funcionando.
export const isSupabaseConfigured = Boolean(url && key && tenantSlug)

export const supabase: SupabaseClient | null =
  url && key && tenantSlug
    ? createClient(url, key, {
        global: {
          headers: { 'x-tenant': tenantSlug },
          // Los datos cambian seguido (mesas, precios, pedidos): nunca se reutiliza una respuesta guardada.
          fetch: (input, init) => fetch(input, { ...init, cache: 'no-store' })
        }
      })
    : null


export function db(): SupabaseClient {
  if (!supabase) throw new Error('not_configured')
  return supabase
}
