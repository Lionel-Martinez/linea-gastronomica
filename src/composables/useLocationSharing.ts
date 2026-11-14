import { onUnmounted, ref } from 'vue'
import { friendlyError, updateRunPosition } from '../lib/api'
import { geoErrorMessage, geolocationSupported, type Point } from '../lib/geo'

const SEND_EVERY_MS = 10_000

/**
 * Comparte la posición del celular del repartidor con el reparto indicado.
 * Solo funciona con la pantalla encendida y esta página abierta (límite de los navegadores);
 * por eso mantiene la pantalla despierta mientras comparte y, si el celular se bloqueó o la
 * página quedó en segundo plano, retoma sola apenas vuelve a verse.
 */
export function useLocationSharing() {
  const sharingRun = ref<string | null>(null)
  const error = ref('')
  const lastSentAt = ref<number | null>(null)
  const accuracy = ref<number | null>(null)
  /** true si se cortó mientras la pantalla estuvo apagada o la página oculta. */
  const interrupted = ref(false)

  let watchId: number | null = null
  let timer: number | undefined
  let latest: Point | null = null
  let wakeLock: WakeLockSentinel | null = null
  let lastFixAt = Date.now()
  let sendNext = true // la primera posición nueva sale enseguida

  async function keepAwake() {
    try {
      wakeLock = (await navigator.wakeLock?.request('screen')) ?? null
    } catch {
      wakeLock = null // no todos los navegadores lo permiten
    }
  }

  // Al ocultarse la página se pierde la ubicación y el bloqueo de pantalla: al volver se retoma todo.
  function onVisible() {
    if (!sharingRun.value) return

    if (document.visibilityState === 'hidden') {
      interrupted.value = true
      return
    }

    void keepAwake()
    latest = null // la posición guardada quedó vieja
    sendNext = true
    beginWatch()
  }

  async function send() {
    const run = sharingRun.value
    if (!run) return

    // Si hace más de 30 s que el celular no da posición nueva, se reinicia la búsqueda.
    if (Date.now() - lastFixAt > 30_000 && document.visibilityState === 'visible') {
      lastFixAt = Date.now()
      beginWatch()
    }

    if (!latest) return

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
    interrupted.value = false
    document.removeEventListener('visibilitychange', onVisible)
    void wakeLock?.release().catch(() => {})
    wakeLock = null
  }

  function beginWatch() {
    if (watchId !== null) navigator.geolocation.clearWatch(watchId)

    watchId = navigator.geolocation.watchPosition(
      (pos) => {
        latest = {
          lat: pos.coords.latitude,
          lng: pos.coords.longitude,
          accuracy: pos.coords.accuracy ?? null
        }
        accuracy.value = latest.accuracy
        lastFixAt = Date.now()
        interrupted.value = false

        // El primer punto sale enseguida; después cada 10 segundos.
        if (sendNext) {
          sendNext = false
          void send()
        }
      },
      (e) => {
        error.value = geoErrorMessage(e)
        if (e.code === 1) stop() // sin permiso no tiene sentido seguir
      },
      { enableHighAccuracy: true, maximumAge: 5_000, timeout: 20_000 }
    )
  }

  function start(run: string) {
    if (!geolocationSupported()) {
      error.value = geoErrorMessage(undefined)
      return
    }

    stop()
    error.value = ''
    sharingRun.value = run
    lastFixAt = Date.now()
    sendNext = true

    beginWatch()

    timer = window.setInterval(send, SEND_EVERY_MS)
    document.addEventListener('visibilitychange', onVisible)
    void keepAwake()
  }

  onUnmounted(stop)

  return { sharingRun, error, lastSentAt, accuracy, interrupted, start, stop }
}
