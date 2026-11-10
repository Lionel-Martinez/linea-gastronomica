import { db } from './supabase'
import type {
  BlockedPhone,
  Category,
  DeliveryZone,
  Modality,
  Order,
  OrderStatus,
  Product,
  PaymentMethod,
  PublicOrder,
  Settings,
  TableOrder,
  TrackedOrder
} from './types'

/* ---------- Errores ---------- */

// Convierte cualquier error técnico en un mensaje entendible para la persona.
export function friendlyError(error: unknown): string {
  const message = (error as { message?: string } | null)?.message ?? ''

  if (message.includes('invalid_table'))
    return 'Esta mesa no existe. Avisale al personal para que revise el código QR.'
  if (message.includes('too_many_pending'))
    return 'Ya hay varios pedidos esperando confirmación. Esperá a que el local los confirme o avisale al personal.'
  if (message.includes('modality_disabled') || message.includes('invalid_modality'))
    return 'Por ahora el local no recibe pedidos de esta forma. Elegí otra o consultá con el local.'
  if (message.includes('invalid_phone'))
    return 'Escribí un teléfono válido, con código de área (entre 8 y 15 números).'
  if (message.includes('phone_blocked'))
    return 'No pudimos recibir tu pedido. Comunicate con el local.'
  if (message.includes('invalid_code'))
    return 'El código no coincide. Pedíselo de nuevo al cliente, o confirmá su nombre si no lo tiene.'
  if (message.includes('code_required'))
    return 'Este pedido se entrega con el código del cliente.'
  if (message.includes('invalid_zone'))
    return 'Elegí una zona de entrega de la lista.'
  if (message.includes('invalid_address'))
    return 'Completá la calle y el número de la entrega.'
  if (message.includes('invalid_cash'))
    return 'El monto con el que pagás tiene que cubrir el total del pedido.'
  if (message.includes('invalid_run'))
    return 'Los pedidos elegidos ya no están listos para salir. Actualizá y probá de nuevo.'
  if (message.includes('invalid_status'))
    return 'Ese pedido ya cambió de estado. Actualizá la pantalla.'
  if (message.includes('invalid_position'))
    return 'No pudimos leer la ubicación del celular. Revisá el permiso de ubicación.'
  if (message.includes('zone_duplicate'))
    return 'Ya hay una zona con ese nombre.'
  if (message.includes('invalid_eta'))
    return 'La hora estimada tiene que ser de las próximas horas.'
  if (message.includes('product_unavailable'))
    return 'Algún producto ya no está disponible. Actualizamos la carta, revisá tu pedido.'
  if (message.includes('ordering_disabled'))
    return 'Por ahora este local no recibe pedidos desde la mesa. Pedile al personal.'
  if (message.includes('invalid_payment'))
    return 'Elegí una forma de pago de las disponibles.'
  if (message.includes('invalid_name'))
    return 'Escribí tu nombre (al menos 2 letras) para que el personal sepa de quién es el pedido.'
  if (message.includes('invalid_items'))
    return 'Hay un problema con el pedido. Revisalo e intentá de nuevo.'
  if (message.includes('Invalid login credentials'))
    return 'El email o la contraseña no son correctos.'
  if (message.includes('not_staff'))
    return 'Tu cuenta existe, pero no tiene permiso de personal.'
  if (message.includes('not_saved'))
    return 'Los cambios no quedaron guardados en la base. Probá de nuevo; si sigue igual, avisá a soporte.'
  if (message.includes('not_allowed'))
    return 'No se pudo guardar: no tenés permiso o el registro ya no existe.'
  if (message.includes('not_configured'))
    return 'Falta configurar la conexión con Supabase.'
  if (/fetch|network|load failed/i.test(message))
    return 'No hay conexión. Revisá tu internet e intentá de nuevo.'

  return 'Ocurrió un error inesperado. Intentá de nuevo.'
}

export function isProductUnavailable(error: unknown) {
  return ((error as { message?: string } | null)?.message ?? '').includes('product_unavailable')
}

/* ---------- Público ---------- */

export interface MenuData {
  categories: Category[]
  products: Product[]
  settings: Settings
}

export async function loadMenu(): Promise<MenuData> {
  const client = db()

  const [categories, products, settings] = await Promise.all([
    client.from('categories').select('*').order('sort_order'),
    client.from('products').select('*').order('sort_order').order('name'),
    client.from('settings').select('*').eq('id', 1).single()
  ])

  const failed = categories.error ?? products.error ?? settings.error
  if (failed) throw failed

  return {
    categories: categories.data as Category[],
    products: products.data as Product[],
    settings: settings.data as Settings
  }
}

export async function loadSettings(): Promise<Settings> {
  const { data, error } = await db().from('settings').select('*').eq('id', 1).single()

  if (error) throw error
  return data as Settings
}

/** Zonas de entrega con su precio de envío (las carga el encargado). */
export async function loadZones(): Promise<DeliveryZone[]> {
  const { data, error } = await db()
    .from('delivery_zones')
    .select('*')
    .order('sort_order')
    .order('name')

  if (error) throw error
  return data as DeliveryZone[]
}

export interface OrderLinePayload {
  product_id: string
  quantity: number
  note: string
}

/**
 * `token` identifica este intento de envío: si se corta la respuesta y se reintenta
 * con el mismo token, la base devuelve el pedido ya creado en lugar de duplicarlo.
 */
export async function createOrder(
  table: number,
  items: OrderLinePayload[],
  name: string,
  token: string,
  method: PaymentMethod
): Promise<string> {
  const { data, error } = await db().rpc('create_order', {
    p_table: table,
    p_items: items,
    p_name: name,
    p_token: token,
    p_method: method
  })

  if (error) throw error
  return data as string
}

export interface RemoteOrderInput {
  modality: Exclude<Modality, 'dine_in'>
  items: OrderLinePayload[]
  name: string
  phone: string
  method: PaymentMethod
  token: string
  zone?: string | null
  street?: string
  number?: string
  reference?: string
  cashFrom?: number | null
  /** Ubicación opcional del cliente (solo delivery). */
  destLat?: number | null
  destLng?: number | null
}

/** Pedido para retirar o delivery. Devuelve el id y el código de seguimiento. */
export async function createRemoteOrder(input: RemoteOrderInput) {
  const { data, error } = await db().rpc('create_remote_order', {
    p_modality: input.modality,
    p_items: input.items,
    p_name: input.name,
    p_phone: input.phone,
    p_method: input.method,
    p_token: input.token,
    p_zone: input.zone ?? null,
    p_street: input.street ?? null,
    p_number: input.number ?? null,
    p_reference: input.reference ?? null,
    p_cash_from: input.cashFrom ?? null,
    p_dest_lat: input.destLat ?? null,
    p_dest_lng: input.destLng ?? null
  })

  if (error) throw error
  return data as { id: string; tracking_code: string }
}

/** Seguimiento de un pedido a distancia con su código (null si no existe). */
export async function getOrderByCode(code: string): Promise<TrackedOrder | null> {
  const { data, error } = await db().rpc('get_order_by_code', { p_code: code })

  if (error) throw error
  return (data as TrackedOrder | null) ?? null
}

/** Pedidos activos de una mesa (sin nombres). Sirve para volver a ver el estado desde cualquier celular. */
export async function getTableOrders(table: number): Promise<TableOrder[]> {
  const { data, error } = await db().rpc('table_orders', { p_table: table })

  if (error) throw error
  return (data as TableOrder[] | null) ?? []
}

export async function getOrder(id: string): Promise<PublicOrder | null> {
  const { data, error } = await db().rpc('get_order', { p_id: id })

  if (error) throw error
  return (data as PublicOrder | null) ?? null
}

/* ---------- Personal ---------- */

export async function listOrders(): Promise<Order[]> {
  // Todos los pedidos activos, más lo entregado o cancelado desde las 00:00 de hoy.
  const startOfDay = new Date()
  startOfDay.setHours(0, 0, 0, 0)

  const { data, error } = await db()
    .from('orders')
    .select('*, order_items(*)')
    .or(`status.in.(pending,preparing,ready,on_the_way),created_at.gte.${startOfDay.toISOString()}`)
    .order('created_at', { ascending: true })
    .limit(300)

  if (error) throw error
  return data as Order[]
}

export async function setOrderStatus(id: string, status: OrderStatus) {
  const { data, error } = await db()
    .from('orders')
    .update({ status })
    .eq('id', id)
    .select('id')

  if (error) throw error
  if (!data?.length) throw new Error('not_allowed')
}

/** Entrega un delivery comprobando el código del cliente (o, sin código, confirmando su nombre). */
export async function completeDelivery(id: string, code: string | null, byName = false) {
  const { error } = await db().rpc('complete_delivery', { p_id: id, p_code: code, p_by_name: byName })
  if (error) throw error
}

/** Código de entrega de 4 dígitos, visible solo para quien tiene el código de seguimiento. */
export async function getDeliveryCode(trackingCode: string): Promise<string | null> {
  const { data, error } = await db().rpc('get_delivery_code', { p_code: trackingCode })
  if (error) throw error
  return (data as string | null) ?? null
}

export interface ProductInput {
  id: string | null
  category_id: string
  name: string
  description: string
  price: number
  image: string
  available: boolean
  featured: boolean
  sort_order?: number
}

export async function saveProduct(product: ProductInput) {
  const row = {
    category_id: product.category_id,
    name: product.name,
    description: product.description,
    price: product.price,
    image: product.image,
    available: product.available,
    featured: product.featured
  }

  const query = product.id
    ? db().from('products').update(row).eq('id', product.id).select('id')
    : db()
        .from('products')
        .insert({ ...row, sort_order: product.sort_order ?? 0 })
        .select('id')

  const { data, error } = await query

  if (error) throw error
  if (!data?.length) throw new Error('not_allowed')
}

export async function setProductAvailable(id: string, available: boolean) {
  const { data, error } = await db()
    .from('products')
    .update({ available })
    .eq('id', id)
    .select('id')

  if (error) throw error
  if (!data?.length) throw new Error('not_allowed')
}

export async function deleteProduct(id: string) {
  const { data, error } = await db().from('products').delete().eq('id', id).select('id')

  if (error) throw error
  if (!data?.length) throw new Error('not_allowed')
}

export async function saveSettings(settings: Settings) {
  const { data, error } = await db()
    .from('settings')
    .update({
      table_count: settings.table_count,
      payment_alias: settings.payment_alias,
      payment_cbu: settings.payment_cbu,
      payment_holder: settings.payment_holder,
      ordering_enabled: settings.ordering_enabled,
      payment_methods: settings.payment_methods,
      whatsapp_number: settings.whatsapp_number,
      pickup_enabled: settings.pickup_enabled,
      delivery_enabled: settings.delivery_enabled,
      retention_days: settings.retention_days,
      stops_visibility: settings.stops_visibility,
      delivery_code_enabled: settings.delivery_code_enabled
    })
    .eq('id', 1)
    .select('id')

  if (error) throw error
  if (!data?.length) throw new Error('not_allowed')
}

/* ---------- Zonas, bloqueos y repartos (personal) ---------- */

export interface ZoneInput {
  id: string | null
  name: string
  fee: number
  active: boolean
  sort_order?: number
}

export async function saveZone(zone: ZoneInput) {
  const row = { name: zone.name, fee: zone.fee, active: zone.active }

  const query = zone.id
    ? db().from('delivery_zones').update(row).eq('id', zone.id).select('id')
    : db()
        .from('delivery_zones')
        .insert({ ...row, sort_order: zone.sort_order ?? 0 })
        .select('id')

  const { data, error } = await query

  if (error) {
    if (error.code === '23505') throw new Error('zone_duplicate')
    throw error
  }
  if (!data?.length) throw new Error('not_allowed')
}

export async function deleteZone(id: string) {
  const { data, error } = await db().from('delivery_zones').delete().eq('id', id).select('id')

  if (error) throw error
  if (!data?.length) throw new Error('not_allowed')
}

export async function listBlockedPhones(): Promise<BlockedPhone[]> {
  const { data, error } = await db()
    .from('blocked_phones')
    .select('*')
    .order('created_at', { ascending: false })

  if (error) throw error
  return data as BlockedPhone[]
}

export async function blockPhone(phone: string, note: string) {
  const { error } = await db().from('blocked_phones').insert({ phone, note })

  // Ya estaba bloqueado: no es un error para quien lo hace.
  if (error && error.code !== '23505') throw error
}

export async function unblockPhone(phone: string) {
  const { error } = await db().from('blocked_phones').delete().eq('phone', phone)

  if (error) throw error
}

/** El pedido sale a repartir: la lista da el orden de las paradas. */
export async function startRun(orderIds: string[]) {
  const { error } = await db().rpc('start_run', { p_order_ids: orderIds })

  if (error) throw error
}

/** El celular del repartidor manda su posición (solo mientras comparte). */
export async function updateRunPosition(run: string, lat: number, lng: number, accuracy: number | null) {
  const { error } = await db().rpc('update_run_position', {
    p_run: run,
    p_lat: lat,
    p_lng: lng,
    p_accuracy: accuracy
  })

  if (error) throw error
}

export async function markNear(id: string) {
  const { error } = await db().rpc('mark_near', { p_id: id })

  if (error) throw error
}

export async function setOrderEta(id: string, eta: Date | null) {
  const { error } = await db().rpc('set_order_eta', { p_id: id, p_eta: eta ? eta.toISOString() : null })

  if (error) throw error
}

/**
 * Avisa cuando cambia algo en los pedidos (tiempo real).
 * Devuelve la función para dejar de escuchar.
 */
export function subscribeOrders(
  onChange: () => void,
  onStatus: (status: string) => void
): () => void {
  const client = db()

  const channel = client
    .channel(`orders-live-${Math.random().toString(36).slice(2)}`)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'orders' }, onChange)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'order_items' }, onChange)
    .subscribe((status) => onStatus(status))

  return () => {
    void client.removeChannel(channel)
  }
}
