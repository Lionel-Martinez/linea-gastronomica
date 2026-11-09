import { computed, ref, watch, type Ref } from 'vue'
import type { Product } from '../lib/types'
import type { OrderLinePayload } from '../lib/api'

export interface CartLine {
  productId: string
  name: string
  price: number
  qty: number
  note: string
}

const MAX_QTY = 50

function isLine(value: unknown): value is CartLine {
  const line = value as CartLine
  return (
    typeof line?.productId === 'string' &&
    typeof line.name === 'string' &&
    typeof line.price === 'number' &&
    Number.isInteger(line.qty) &&
    line.qty >= 1 &&
    typeof line.note === 'string'
  )
}

function read(key: string): CartLine[] {
  try {
    const parsed = JSON.parse(localStorage.getItem(key) ?? '[]')
    return Array.isArray(parsed) ? parsed.filter(isLine) : []
  } catch {
    return []
  }
}

function write(key: string, lines: CartLine[]) {
  try {
    localStorage.setItem(key, JSON.stringify(lines))
  } catch {
    // Sin almacenamiento disponible: el carrito vive solo mientras la página esté abierta.
  }
}

/** Carrito de una mesa (o de pedidos a distancia). Se guarda en el navegador para no perderse si se recarga. */
export function useCart(table: Ref<number | string>) {
  const key = computed(() => `lg:cart:${table.value}`)
  const lines = ref<CartLine[]>(read(key.value))

  watch(key, () => {
    lines.value = read(key.value)
  })
  watch(lines, (value) => write(key.value, value), { deep: true })

  const count = computed(() => lines.value.reduce((sum, line) => sum + line.qty, 0))
  // Total solo para mostrar: el precio real lo calcula la base al crear el pedido.
  const total = computed(() => lines.value.reduce((sum, line) => sum + line.price * line.qty, 0))

  const find = (id: string) => lines.value.find((line) => line.productId === id)
  const qtyOf = (id: string) => find(id)?.qty ?? 0

  function add(product: Product) {
    const line = find(product.id)

    if (line) {
      line.qty = Math.min(MAX_QTY, line.qty + 1)
      return
    }

    lines.value.push({
      productId: product.id,
      name: product.name,
      price: product.price,
      qty: 1,
      note: ''
    })
  }

  function inc(id: string) {
    const line = find(id)
    if (line) line.qty = Math.min(MAX_QTY, line.qty + 1)
  }

  function dec(id: string) {
    const line = find(id)
    if (!line) return

    if (line.qty <= 1) {
      lines.value = lines.value.filter((item) => item.productId !== id)
      return
    }

    line.qty -= 1
  }

  function clear() {
    lines.value = []
  }

  /**
   * Alinea el carrito con la carta actual: quita lo que ya no existe o se agotó
   * y actualiza nombres y precios. Devuelve los nombres de lo que se quitó.
   */
  function reconcile(products: Product[]): string[] {
    const removed: string[] = []

    lines.value = lines.value.filter((line) => {
      const product = products.find((item) => item.id === line.productId)

      if (!product || !product.available) {
        removed.push(line.name)
        return false
      }

      line.name = product.name
      line.price = product.price
      return true
    })

    return removed
  }

  const payload = (): OrderLinePayload[] =>
    lines.value.map((line) => ({
      product_id: line.productId,
      quantity: line.qty,
      note: line.note.trim()
    }))

  return { lines, count, total, qtyOf, add, inc, dec, clear, reconcile, payload }
}
