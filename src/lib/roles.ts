import type { OrderStatus, Role } from './types'

// Qué puede hacer cada rol en el panel. La seguridad real la imponen las reglas de la base;
// esto solo evita mostrar botones que la base va a rechazar.

export const ROLE_LABEL: Record<Role, string> = {
  manager: 'Encargado',
  counter: 'Mostrador',
  waiter: 'Mozo',
  kitchen: 'Cocina',
  courier: 'Repartidor'
}

/** Pantallas del panel a las que entra cada rol (la primera es la de inicio). */
export const ROLE_ROUTES: Record<Role, string[]> = {
  manager: ['staff-orders', 'staff-run', 'staff-products', 'staff-settings', 'staff-qr'],
  counter: ['staff-orders', 'staff-run'],
  waiter: ['staff-orders'],
  kitchen: ['staff-orders'],
  courier: ['staff-run']
}

export const canOpenRoute = (role: Role | null, name: string) =>
  Boolean(role && ROLE_ROUTES[role].includes(name))

/** Teléfono, dirección y ubicación del cliente en la pantalla de pedidos. */
export const canSeeContact = (role: Role | null) => role === 'manager' || role === 'counter'

/** Bloquear teléfonos. */
export const canBlockPhones = canSeeContact

/** Cambios de estado permitidos por rol (espejo de las reglas de la base). */
export function canMove(
  role: Role | null,
  modality: 'dine_in' | 'pickup' | 'delivery',
  from: OrderStatus,
  to: OrderStatus
): boolean {
  switch (role) {
    case 'manager':
    case 'counter':
      return (
        (from === 'pending' && (to === 'preparing' || to === 'cancelled')) ||
        (from === 'preparing' && (to === 'ready' || to === 'cancelled')) ||
        (from === 'ready' && (to === 'delivered' || to === 'cancelled')) ||
        (from === 'on_the_way' && (to === 'delivered' || to === 'cancelled'))
      )
    case 'waiter':
      return modality === 'dine_in' && ((from === 'pending' && to === 'preparing') || (from === 'ready' && to === 'delivered'))
    case 'kitchen':
      return from === 'preparing' && to === 'ready'
    default:
      return false
  }
}
