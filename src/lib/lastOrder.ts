// Recuerda el último pedido de cada mesa en este navegador, para poder volver
// a ver su estado si el cliente cierra o recarga la página.

const key = (table: number) => `lg:last-order:${table}`

export function getLastOrder(table: number): string | null {
  try {
    return localStorage.getItem(key(table))
  } catch {
    return null
  }
}

export function setLastOrder(table: number, id: string) {
  try {
    localStorage.setItem(key(table), id)
  } catch {
    // Sin almacenamiento: igual se puede ver el pedido con el enlace /pedido/:id.
  }
}

export function clearLastOrder(table: number) {
  try {
    localStorage.removeItem(key(table))
  } catch {
    // nada que limpiar
  }
}
