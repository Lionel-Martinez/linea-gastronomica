import type { Plan, Role } from './types'
import { ROLE_ROUTES } from './roles'

// Combos que vende LM Studio. El plan lo cambia solo LM Studio (SQL Editor); el local no puede.
// La base de datos aplica estas mismas reglas: esto solo evita mostrar lo que no corresponde.

export const PLAN_LABEL: Record<Plan, string> = {
  menu: 'Carta',
  menu_panel: 'Carta + Panel',
  orders: 'Pedidos y delivery',
  full: 'Completo'
}

export const PLAN_SUMMARY: Record<Plan, string> = {
  menu: 'Carta digital con QR. Los productos y precios los carga LM Studio.',
  menu_panel: 'Carta digital con QR. El local cambia los precios y marca «agotado».',
  orders: 'Pedidos de retiro y delivery con seguimiento y reparto. El local edita sus productos.',
  full: 'Carta, pedidos en mesa, retiro y delivery con reparto.'
}

/** Pantallas del panel que incluye cada plan. */
export const PLAN_ROUTES: Record<Plan, string[]> = {
  menu: ['staff-qr'],
  menu_panel: ['staff-products', 'staff-qr'],
  orders: ['staff-orders', 'staff-run', 'staff-products', 'staff-settings'],
  full: ['staff-orders', 'staff-run', 'staff-products', 'staff-settings', 'staff-qr']
}

/** Pantallas a las que entra esta persona: lo que permite su rol Y lo que incluye el plan. */
export const allowedRoutes = (role: Role | null, plan: Plan) =>
  role ? ROLE_ROUTES[role].filter((name) => PLAN_ROUTES[plan].includes(name)) : []

export const canOpen = (role: Role | null, plan: Plan, name: string) => allowedRoutes(role, plan).includes(name)

export const hasTableOrdering = (plan: Plan) => plan === 'full'
export const hasRemoteOrdering = (plan: Plan) => plan === 'orders' || plan === 'full'
/** En «Carta + Panel» el local solo cambia precio y disponibilidad. */
export const priceOnly = (plan: Plan) => plan === 'menu_panel'
