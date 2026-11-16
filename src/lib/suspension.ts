import { reactive } from 'vue'
import { HAS_BACKEND } from '../edition'

// Servicio suspendido por falta de pago: lo marca solo LM Studio en la base de datos.
// Si no se puede consultar (sin conexión, sin base), el servicio se muestra normal.
export const suspension = reactive({ checked: !HAS_BACKEND, suspended: false })

let lastCheck = 0

export async function checkSuspension() {
  if (!HAS_BACKEND) return

  try {
    const [{ isSupabaseConfigured }, { loadSettings }] = await Promise.all([
      import('./supabase'),
      import('./api')
    ])

    if (isSupabaseConfigured) {
      // Si la base tarda demasiado, no se deja la pantalla en blanco: se muestra el sitio.
      const settings = await Promise.race([
        loadSettings(),
        new Promise<never>((_, reject) => setTimeout(() => reject(new Error('timeout')), 4000))
      ])
      suspension.suspended = settings.suspended === true
    }
  } catch {
    // Sin conexión: se conserva el último estado conocido.
  }

  lastCheck = Date.now()
  suspension.checked = true
}

/** Vuelve a consultar si la pestaña estuvo un rato sin mirarse (por ejemplo, el panel abierto todo el día). */
export function recheckSuspensionIfStale(maxAgeMs = 5 * 60 * 1000) {
  if (HAS_BACKEND && Date.now() - lastCheck > maxAgeMs) void checkSuspension()
}
