// Datos que se recuerdan en este navegador: el nombre del cliente y el token de envío
// (para que un reintento no duplique el pedido).

/* ---------- Nombre del cliente ---------- */

export function getName(): string {
  try {
    return localStorage.getItem('lg:name') ?? ''
  } catch {
    return ''
  }
}

export function setName(name: string) {
  try {
    localStorage.setItem('lg:name', name)
  } catch {
    // Sin almacenamiento: tendrá que escribirlo de nuevo la próxima vez.
  }
}

/* ---------- Token de envío (evita pedidos duplicados) ---------- */

function randomUuid(): string {
  if (typeof crypto.randomUUID === 'function') return crypto.randomUUID()

  const b = crypto.getRandomValues(new Uint8Array(16))
  b[6] = (b[6]! & 0x0f) | 0x40
  b[8] = (b[8]! & 0x3f) | 0x80
  const h = [...b].map((x) => x.toString(16).padStart(2, '0')).join('')
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`
}

/**
 * Devuelve el token del envío en curso de esta mesa (lo crea si no hay).
 * Se conserva hasta que el pedido se crea bien, así un reintento no duplica.
 */
export function submitToken(table: number): string {
  const key = `lg:token:${table}`

  try {
    const saved = localStorage.getItem(key)
    if (saved) return saved

    const fresh = randomUuid()
    localStorage.setItem(key, fresh)
    return fresh
  } catch {
    return randomUuid()
  }
}

export function clearSubmitToken(table: number) {
  try {
    localStorage.removeItem(`lg:token:${table}`)
  } catch {
    // nada que limpiar
  }
}
