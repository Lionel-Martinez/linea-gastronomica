import { db } from './supabase'
import type {
  Category,
  Order,
  OrderStatus,
  Product,
  PaymentMethod,
  PublicOrder,
  Settings,
  TableOrder
} from './types'

/* ---------- Errores ---------- */

// Convierte cualquier error técnico en un mensaje entendible para la persona.
export function friendlyError(error: unknown): string {
  const message = (error as { message?: string } | null)?.message ?? ''

  if (message.includes('invalid_table'))
    return 'Esta mesa no existe. Avisale al personal para que revise el código QR.'
  if (message.includes('too_many_pending'))
    return 'Esta mesa ya tiene varios pedidos esperando confirmación. Avisale al personal.'
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
    .or(`status.in.(pending,preparing,ready),created_at.gte.${startOfDay.toISOString()}`)
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
      whatsapp_number: settings.whatsapp_number
    })
    .eq('id', 1)
    .select('id')

  if (error) throw error
  if (!data?.length) throw new Error('not_allowed')
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
