import { reactive } from 'vue'
import { loadSettings } from './api'
import { currentRole } from './auth'
import type { Role } from './types'

// Estado del panel que comparten el menú de navegación y las pantallas:
// qué formas de pedido tiene el local y si la persona es encargada.
export const panel = reactive({
  ready: false,
  ordering: true, // pedidos por mesa
  pickup: false,
  delivery: false,
  remote: false, // retiro o delivery
  manager: false,
  role: null as Role | null
})

export async function refreshPanel() {
  panel.role = await currentRole()
  panel.manager = panel.role === 'manager'

  try {
    const settings = await loadSettings()
    panel.ordering = settings.ordering_enabled
    panel.pickup = settings.pickup_enabled
    panel.delivery = settings.delivery_enabled
    panel.remote = settings.pickup_enabled || settings.delivery_enabled
  } catch {
    // Sin conexión: se conserva el último valor conocido.
  }

  panel.ready = true
}
