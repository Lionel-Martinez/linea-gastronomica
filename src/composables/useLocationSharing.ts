import { onUnmounted, ref } from 'vue'
import { friendlyError, updateRunPosition } from '../lib/api'
import { geoErrorMessage, geolocationSupported, type Point } from '../lib/geo'

const SEND_EVERY_MS = 10_000

/**
 * Comparte la posición del celular del repartidor con el reparto indicado.
 * Solo funciona con la pantalla encendida y esta página abierta (límite de los navegadores);
 * por eso mantiene la pantalla despierta mientras comparte.
 */
export function useLocationSharing() {
  const sharingRun = ref<string | null>(null)
  const error = ref('')
  const lastSentAt = ref<number | null>(null)
  const accuracy = ref<number | null>(null)

  let watchId: number | null = null
  let timer: number | undefined
  let latest: Point | null = null
  let wakeLock: WakeLockSentinel | null = null

  async function keepAwake() {
    try {
      wakeLock = (await navigator.wakeLock?.request('screen')) ?? null
    } catch {
      wakeLock = null // no todos los navegadores lo permiten
    }
  }

  // El navegador suelta el bloqueo si la pestaña se oculta: se vuelve a pedir al volver.
  function onVisible() {
    if (document.visibilityState === 'visible' && sharingRun.value) void keepAwake()
  }

  async function send() {
    const run = sharingRun.value
    if (!run || !latest) return

    try {
      await updateRunPosition(run, latest.lat, latest.lng, latest.accuracy)
      lastSentAt.value = Date.now()
      error.value = ''
    } catch (e) {
      error.value = friendlyError(e)
    }
  }

  function stop() {
    if (watchId !== null) navigator.geolocation.clearWatch(watchId)
    watchId = null
    window.clearInterval(timer)
    timer = undefined
    latest = null
    sharingRun.value = null
    lastSentAt.value = null
    document.removeEventListener('visibilitychange', onVisible)
    void wakeLock?.release().catch(() => {})
    wakeLock = null
  }

  function start(run: string) {
    if (!geolocationSupported()) {
      error.value = geoErrorMessage(undefined)
      return
    }

    stop()
    error.value = ''
    sharingRun.value = run

    watchId = navigator.geolocation.watchPosition(
      (pos) => {
        latest = {
          lat: pos.coords.latitude,
          lng: pos.coords.longitude,
          accuracy: pos.coords.accuracy ?? null
        }
        accuracy.value = latest.accuracy

        // El primer punto sale enseguida; después cada 10 segundos.
        if (lastSentAt.value === null) void send()
      },
      (e) => {
        error.value = geoErrorMessage(e)
        if (e.code === 1) stop() // sin permiso no tiene sentido seguir
      },
      { enableHighAccuracy: true, maximumAge: 5_000, timeout: 20_000 }
    )

    timer = window.setInterval(send, SEND_EVERY_MS)
    document.addEventListener('visibilitychange', onVisible)
    void keepAwake()
  }

  onUnmounted(stop)

  return { sharingRun, error, lastSentAt, accuracy, start, stop }
}
