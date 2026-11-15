import type { Plan, Role } from './types'
import { EDITION, EDITION_PLAN, EDITION_STAFF_ROUTES } from '../edition'
import { ROLE_ROUTES } from './roles'

// Combos que vende LM Studio. El plan lo cambia solo LM Studio (SQL Editor); el local no puede.
// La base de datos aplica estas mismas reglas: esto solo evita mostrar lo que no corresponde.

export const PLAN_LABEL: Record<Plan, string> = {
  menu: 'Carta',
  menu_panel: 'Carta + Panel',
  table: 'Carta + Panel + Mesa',
  orders: 'Pedidos y delivery',
  full: 'Completo'
}

export const PLAN_SUMMARY: Record<Plan, string> = {
  menu: 'Carta digital con QR. Los productos y precios los carga LM Studio.',
  menu_panel: 'Carta digital con QR. El local cambia los precios y marca «agotado».',
  table: 'Carta digital con QR, panel para editar productos y pedidos desde el QR de cada mesa.',
  orders: 'Pedidos de retiro y delivery con seguimiento y reparto. El local edita sus productos.',
  full: 'Carta, pedidos en mesa, retiro y delivery con reparto.'
}

/** Pantallas del panel que incluye cada plan. */
export const PLAN_ROUTES: Record<Plan, string[]> = {
  menu: ['staff-qr'],
  menu_panel: ['staff-products', 'staff-qr'],
  table: ['staff-orders', 'staff-products', 'staff-settings', 'staff-qr'],
  orders: ['staff-orders', 'staff-run', 'staff-products', 'staff-settings'],
  full: ['staff-orders', 'staff-run', 'staff-products', 'staff-settings', 'staff-qr']
}

/** Pantallas a las que entra esta persona: lo que permite su rol Y lo que incluye el plan. */
export const allowedRoutes = (role: Role | null, plan: Plan) =>
  role
    ? ROLE_ROUTES[role].filter((name) => PLAN_ROUTES[plan].includes(name) && EDITION_STAFF_ROUTES.includes(name))
    : []

export const canOpen = (role: Role | null, plan: Plan, name: string) => allowedRoutes(role, plan).includes(name)

export const hasTableOrdering = (plan: Plan) => plan === 'table' || plan === 'full'
export const hasRemoteOrdering = (plan: Plan) => plan === 'orders' || plan === 'full'
/** En «Carta + Panel» el local solo cambia precio y disponibilidad. */
export const priceOnly = (plan: Plan) => plan === 'menu_panel'

/**
 * Plan que se aplica en pantalla. Cada edición ya trae su plan: si la base tiene otro
 * (por ejemplo un Supabase de pruebas en «Completo»), manda la edición. Solo la edición
 * «Completo» sigue el plan de la base, porque puede estar limitada por LM Studio.
 */
export const effectivePlan = (dbPlan: Plan | null | undefined): Plan =>
  EDITION === 'completo' ? (dbPlan ?? EDITION_PLAN[EDITION]) : EDITION_PLAN[EDITION]

/** La base de datos tiene un plan distinto al de la edición publicada (hay que correr supabase/editions/<edicion>.sql). */
export const planMismatch = (dbPlan: Plan | null | undefined) =>
  EDITION !== 'completo' && !!dbPlan && dbPlan !== EDITION_PLAN[EDITION]
