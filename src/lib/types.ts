export type OrderStatus = 'pending' | 'preparing' | 'ready' | 'delivered' | 'cancelled'

export interface Category {
  id: string
  name: string
  sort_order: number
}

export interface Product {
  id: string
  category_id: string
  name: string
  description: string
  price: number
  image: string
  available: boolean
  featured: boolean
  sort_order: number
}

export type PaymentMethod = 'transfer' | 'card' | 'qr' | 'cash'

export const PAYMENT_METHODS: PaymentMethod[] = ['transfer', 'card', 'qr', 'cash']

export const PAYMENT_LABEL: Record<PaymentMethod, string> = {
  transfer: 'Transferencia',
  card: 'Tarjeta',
  qr: 'QR',
  cash: 'Efectivo'
}

export const PAYMENT_HINT: Record<PaymentMethod, string> = {
  transfer: 'Transferí y mandanos el comprobante por WhatsApp.',
  card: 'Pagás con tarjeta en el local.',
  qr: 'Pagás con QR en el local.',
  cash: 'Pagás en efectivo en el local.'
}

export interface Settings {
  table_count: number
  payment_alias: string
  payment_cbu: string
  payment_holder: string
  ordering_enabled: boolean
  payment_methods: PaymentMethod[]
  whatsapp_number: string
}

export interface OrderItem {
  id?: string
  name: string
  unit_price: number
  quantity: number
  note: string
}

/** Pedido tal como lo ve el personal (con sus líneas). */
export interface Order {
  id: string
  table_number: number
  customer_name: string
  payment_method: PaymentMethod | ''
  status: OrderStatus
  total: number
  created_at: string
  order_items: OrderItem[]
}

/** Pedido tal como lo ve el cliente (respuesta de get_order). */
export interface PublicOrder {
  id: string
  table_number: number
  status: OrderStatus
  total: number
  created_at: string
  ahead: number
  payment_method: PaymentMethod | ''
  items: OrderItem[]
}

/** Pedido activo de una mesa, visible para quien está sentado ahí (sin nombres ni notas). */
export interface TableOrder {
  id: string
  status: OrderStatus
  total: number
  created_at: string
  items: { name: string; quantity: number }[]
}

export const STATUS_LABEL: Record<OrderStatus, string> = {
  pending: 'Por confirmar',
  preparing: 'En preparación',
  ready: 'Listo',
  delivered: 'Entregado',
  cancelled: 'Cancelado'
}

export const ACTIVE_STATUSES: OrderStatus[] = ['pending', 'preparing', 'ready']
