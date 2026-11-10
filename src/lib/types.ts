export type OrderStatus =
  | 'pending'
  | 'preparing'
  | 'ready'
  | 'on_the_way'
  | 'delivered'
  | 'cancelled'

/** Cómo recibe el pedido el cliente: en la mesa, retirando o delivery. */
export type Modality = 'dine_in' | 'pickup' | 'delivery'

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

/** Pistas de pago para pedidos a distancia (en delivery se paga al recibir). */
export const PAYMENT_HINT_REMOTE: Record<Modality, Partial<Record<PaymentMethod, string>>> = {
  dine_in: {},
  pickup: {
    transfer: 'Transferí y mandanos el comprobante por WhatsApp.',
    card: 'Pagás con tarjeta cuando retirás.',
    qr: 'Pagás con QR cuando retirás.',
    cash: 'Pagás en efectivo cuando retirás.'
  },
  delivery: {
    transfer: 'Transferí y mandanos el comprobante por WhatsApp.',
    cash: 'Pagás en efectivo cuando te llega el pedido.'
  }
}

export const MODALITY_LABEL: Record<Modality, string> = {
  dine_in: 'En el local',
  pickup: 'Retirar',
  delivery: 'Delivery'
}

export interface Settings {
  table_count: number
  payment_alias: string
  payment_cbu: string
  payment_holder: string
  ordering_enabled: boolean
  payment_methods: PaymentMethod[]
  whatsapp_number: string
  pickup_enabled: boolean
  delivery_enabled: boolean
  retention_days: 7 | 15 | 30
  stops_visibility: 'street' | 'zone'
  delivery_code_enabled: boolean
}

export interface DeliveryZone {
  id: string
  name: string
  fee: number
  active: boolean
  sort_order: number
}

export interface BlockedPhone {
  phone: string
  note: string
  created_at: string
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
  table_number: number | null
  modality: Modality
  customer_name: string
  customer_phone: string
  delivery_street: string
  delivery_number: string
  delivery_reference: string
  zone_name: string
  delivery_fee: number
  cash_change_from: number | null
  eta_at: string | null
  run_id: string | null
  stop_position: number | null
  near_at: string | null
  tracking_code: string | null
  dest_lat: number | null
  dest_lng: number | null
  /** El delivery se entrega solo con el código de 4 dígitos del cliente. */
  code_required: boolean
  /** Cómo se comprobó la entrega: con el código, confirmando el nombre, o sin exigencia ('' ). */
  delivered_check: '' | 'code' | 'name'
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

export interface RunStop {
  mine: boolean
  done: boolean
  place: string
}

/** Pedido a distancia visto con su código (respuesta de get_order_by_code). */
export interface TrackedOrder {
  id: string
  tracking_code: string
  modality: Modality
  status: OrderStatus
  payment_method: PaymentMethod | ''
  total: number
  delivery_fee: number
  zone_name: string
  created_at: string
  eta_at: string | null
  near: boolean
  ahead: number
  run: { position: number; total: number; before: number; stops: RunStop[] } | null
  /** Posición del repartidor: solo cuando este pedido es la próxima parada. */
  driver: DriverPosition | null
  items: OrderItem[]
}

export interface DriverPosition {
  lat: number
  lng: number
  /** Segundos desde que el celular del repartidor mandó este punto. */
  age_seconds: number
  /** Distancia aproximada a la entrega (redondeada a 50 m); null si el cliente no guardó su ubicación. */
  distance_m: number | null
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
  on_the_way: 'En camino',
  delivered: 'Entregado',
  cancelled: 'Cancelado'
}

export const ACTIVE_STATUSES: OrderStatus[] = ['pending', 'preparing', 'ready', 'on_the_way']

/** El código se muestra con un guion en el medio: K7M2-9QXA. */
export const formatCode = (code: string) => `${code.slice(0, 4)}-${code.slice(4)}`
