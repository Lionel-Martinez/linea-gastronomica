import { createClient, type SupabaseClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
const key = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined

// Si faltan las variables de entorno la app no se rompe: las pantallas de la
// Etapa 2 muestran un aviso y el menú de la Etapa 1 sigue funcionando.
export const isSupabaseConfigured = Boolean(url && key)

export const supabase: SupabaseClient | null =
  url && key ? createClient(url, key) : null

export function db(): SupabaseClient {
  if (!supabase) throw new Error('not_configured')
  return supabase
}
