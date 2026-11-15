import type { Plan } from './lib/types'

// Cada edición se compila aparte (npm run build:carta, build:panel, build:mesa, build:delivery,
// build:completo). Lo que una edición no incluye no está en su sitio: ni la ruta, ni los botones.
// Las constantes se resuelven al compilar, así el código que no se usa se descarta.

export type Edition = 'carta' | 'panel' | 'mesa' | 'delivery' | 'completo'

export const EDITION: Edition = __EDITION__

export const EDITION_LABEL: Record<Edition, string> = {
  carta: 'Carta',
  panel: 'Carta + Panel',
  mesa: 'Carta + Panel + Mesa',
  delivery: 'Pedidos y delivery',
  completo: 'Completo'
}

/** Plan que la base de datos debe tener en el local de cada edición. */
export const EDITION_PLAN: Record<Edition, Plan> = {
  carta: 'menu',
  panel: 'menu_panel',
  mesa: 'table',
  delivery: 'orders',
  completo: 'full'
}

/** Usa Supabase (la edición Carta es un sitio estático, sin servidor ni login). */
export const HAS_BACKEND: boolean = __HAS_BACKEND__
/** Carta pública con QR. */
export const HAS_PUBLIC_MENU: boolean = __HAS_PUBLIC_MENU__
/** Pedidos desde el QR de cada mesa. */
export const HAS_TABLE_ORDERING: boolean = __HAS_TABLE_ORDERING__
/** Pedidos desde casa: retiro y delivery, seguimiento y reparto. */
export const HAS_REMOTE_ORDERING: boolean = __HAS_REMOTE_ORDERING__
/** Pantalla de pedidos para el personal. */
export const HAS_ORDERS: boolean = __HAS_TABLE_ORDERING__ || __HAS_REMOTE_ORDERING__
/** Página de códigos QR. */
export const HAS_QR_PAGE: boolean = __HAS_QR_PAGE__

/** Pantallas del panel que existen en esta edición (el plan de la base y el rol las acotan más). */
export const EDITION_STAFF_ROUTES: string[] = [
  HAS_ORDERS ? 'staff-orders' : '',
  'staff-products',
  HAS_REMOTE_ORDERING ? 'staff-run' : '',
  HAS_ORDERS ? 'staff-settings' : '',
  HAS_QR_PAGE ? 'staff-qr' : ''
].filter(Boolean)
