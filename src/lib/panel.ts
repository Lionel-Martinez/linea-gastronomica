import { reactive } from 'vue'
import { loadSettings } from './api'
import { isManager } from './auth'

// Estado del panel que comparten el menú de navegación y las pantallas:
// si el local recibe pedidos y si la persona es encargada.
export const panel = reactive({ ready: false, ordering: true, manager: false })

export async function refreshPanel() {
  panel.manager = await isManager()

  try {
    panel.ordering = (await loadSettings()).ordering_enabled
  } catch {
    // Sin conexión: se conserva el último valor conocido.
  }

  panel.ready = true
}
