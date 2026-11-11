import { db, supabase } from './supabase'
import type { Role } from './types'

// Cache del resultado "¿es personal?" para no consultar en cada cambio de ruta.
let cache: { uid: string; ok: boolean; role: Role | null } | null = null

/**
 * true si hay una sesión iniciada Y esa cuenta está en la tabla staff.
 * (La seguridad real la imponen las reglas de la base; esto solo decide qué pantalla mostrar.)
 */
export async function currentStaff(): Promise<boolean> {
  if (!supabase) return false

  const { data } = await supabase.auth.getSession()
  const uid = data.session?.user.id

  if (!uid) {
    cache = null
    return false
  }

  if (cache?.uid === uid) return cache.ok

  const { data: row, error } = await supabase
    .from('staff')
    .select('user_id, role')
    .eq('user_id', uid)
    .maybeSingle()

  const ok = !error && Boolean(row)
  cache = { uid, ok, role: ok ? ((row?.role as Role) ?? 'waiter') : null }
  return ok
}

/** true si además de ser personal es encargado (puede cambiar los ajustes). */
export async function isManager(): Promise<boolean> {
  return (await currentRole()) === 'manager'
}

/** Rol de la persona con sesión (null si no es personal). */
export async function currentRole(): Promise<Role | null> {
  if (!(await currentStaff())) return null
  return cache?.role ?? null
}

export async function signIn(email: string, password: string) {
  const { error } = await db().auth.signInWithPassword({ email, password })
  if (error) throw error

  cache = null

  if (!(await currentStaff())) {
    await signOut()
    throw new Error('not_staff')
  }
}

export async function signOut() {
  cache = null
  await supabase?.auth.signOut()
}

export async function sessionEmail(): Promise<string> {
  const { data } = (await supabase?.auth.getSession()) ?? { data: null }
  return data?.session?.user.email ?? ''
}

/** Avisa cuando se cierra la sesión (por ejemplo, si venció). */
export function onSignedOut(callback: () => void): () => void {
  if (!supabase) return () => {}

  const { data } = supabase.auth.onAuthStateChange((event) => {
    if (event === 'SIGNED_OUT') {
      cache = null
      callback()
    }
  })

  return () => data.subscription.unsubscribe()
}
