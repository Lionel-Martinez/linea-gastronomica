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
export function submitToken(table: number | string): string {
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

export function clearSubmitToken(table: number | string) {
  try {
    localStorage.removeItem(`lg:token:${table}`)
  } catch {
    // nada que limpiar
  }
}

/* ---------- Datos de contacto para pedidos a distancia ---------- */
// Se guardan solo en este celular, para no escribirlos de nuevo en el próximo pedido.

export interface Contact {
  phone: string
  zone: string
  street: string
  number: string
  reference: string
}

const EMPTY_CONTACT: Contact = { phone: '', zone: '', street: '', number: '', reference: '' }

export function getContact(): Contact {
  try {
    const parsed = JSON.parse(localStorage.getItem('lg:contact') ?? '{}') as Partial<Contact>
    return {
      phone: typeof parsed.phone === 'string' ? parsed.phone : '',
      zone: typeof parsed.zone === 'string' ? parsed.zone : '',
      street: typeof parsed.street === 'string' ? parsed.street : '',
      number: typeof parsed.number === 'string' ? parsed.number : '',
      reference: typeof parsed.reference === 'string' ? parsed.reference : ''
    }
  } catch {
    return { ...EMPTY_CONTACT }
  }
}

export function setContact(contact: Contact) {
  try {
    localStorage.setItem('lg:contact', JSON.stringify(contact))
  } catch {
    // Sin almacenamiento: tendrá que escribirlos de nuevo.
  }
}

/** Borra de este celular el nombre, los datos de entrega y el último código de seguimiento. */
export function forgetMyData() {
  for (const key of ['lg:name', 'lg:contact', 'lg:last-code']) {
    try {
      localStorage.removeItem(key)
    } catch {
      // nada que borrar
    }
  }
}

export const hasSavedData = () =>
  getName() !== '' || Object.values(getContact()).some((value) => value !== '') || getLastCode() !== ''

/* ---------- Último código de seguimiento ---------- */

export function getLastCode(): string {
  try {
    return localStorage.getItem('lg:last-code') ?? ''
  } catch {
    return ''
  }
}

export function setLastCode(code: string) {
  try {
    localStorage.setItem('lg:last-code', code)
  } catch {
    // nada que hacer
  }
}
