/** Utilidades de ubicación del navegador (siempre con permiso explícito de la persona). */

export interface Point {
  lat: number
  lng: number
  accuracy: number | null
}

export const geolocationSupported = () => typeof navigator !== 'undefined' && 'geolocation' in navigator

/** Mensaje claro para cada motivo por el que el navegador no dio la ubicación. */
export function geoErrorMessage(error: unknown): string {
  const code = (error as GeolocationPositionError | undefined)?.code

  if (code === 1) return 'No diste permiso de ubicación. Podés habilitarlo en los ajustes del navegador.'
  if (code === 2) return 'No pudimos detectar la ubicación. Probá en un lugar con mejor señal.'
  if (code === 3) return 'La ubicación tardó demasiado. Probá de nuevo.'
  return 'Este navegador no permite compartir la ubicación.'
}

/** Pide la ubicación una sola vez. */
export function getPosition(): Promise<Point> {
  return new Promise((resolve, reject) => {
    if (!geolocationSupported()) return reject(new Error('unsupported'))

    navigator.geolocation.getCurrentPosition(
      (pos) =>
        resolve({ lat: pos.coords.latitude, lng: pos.coords.longitude, accuracy: pos.coords.accuracy ?? null }),
      reject,
      { enableHighAccuracy: true, timeout: 15_000, maximumAge: 10_000 }
    )
  })
}

/** "a unos 600 m" / "a unos 1,2 km". */
export function distanceLabel(meters: number): string {
  if (meters < 50) return 'a menos de 50 m'
  if (meters < 1000) return `a unos ${Math.round(meters / 50) * 50} m`
  return `a unos ${(meters / 1000).toLocaleString('es-AR', { maximumFractionDigits: 1 })} km`
}

/** "hace 12 s" / "hace 3 min". */
export function ageLabel(seconds: number): string {
  if (seconds < 10) return 'recién'
  if (seconds < 60) return `hace ${Math.round(seconds / 5) * 5} s`
  return `hace ${Math.round(seconds / 60)} min`
}
