<script setup lang="ts">
import { onMounted, onUnmounted, ref, watch } from 'vue'
import type { Map as LeafletMap, Marker } from 'leaflet'

const props = defineProps<{
  lat: number
  lng: number
  /** Ubicación del propio cliente (opcional, solo se usa en su pantalla). */
  mine?: { lat: number; lng: number } | null
}>()

// Proveedor de mapas configurable: el mapa estándar de OpenStreetMap sirve para probar,
// pero tiene condiciones de uso. Para producción conviene un proveedor con plan propio.
const TILES = import.meta.env.VITE_MAP_TILES_URL || 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
const ATTRIBUTION =
  import.meta.env.VITE_MAP_ATTRIBUTION ||
  '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'

const el = ref<HTMLDivElement | null>(null)
const failed = ref(false)

let map: LeafletMap | null = null
let driver: Marker | null = null
let me: Marker | null = null
let leaflet: typeof import('leaflet') | null = null

const dot = (kind: 'driver' | 'me') =>
  leaflet!.divIcon({
    className: '',
    html: `<span class="map-dot map-dot--${kind}"></span>`,
    iconSize: [22, 22],
    iconAnchor: [11, 11]
  })

function fit() {
  if (!map || !leaflet) return

  if (props.mine) {
    map.fitBounds(
      leaflet.latLngBounds([props.lat, props.lng], [props.mine.lat, props.mine.lng]),
      { padding: [40, 40], maxZoom: 17, animate: true }
    )
  } else {
    map.setView([props.lat, props.lng], Math.max(map.getZoom(), 16), { animate: true })
  }
}

onMounted(async () => {
  try {
    // El mapa se carga recién cuando hace falta: el resto de la página no paga su peso.
    const [L] = await Promise.all([import('leaflet'), import('leaflet/dist/leaflet.css')])
    leaflet = L.default ?? L
    if (!el.value) return

    map = leaflet.map(el.value, { zoomControl: true, attributionControl: true }).setView([props.lat, props.lng], 16)
    leaflet.tileLayer(TILES, { attribution: ATTRIBUTION, maxZoom: 19 }).addTo(map)

    driver = leaflet.marker([props.lat, props.lng], { icon: dot('driver'), keyboard: false }).addTo(map)
    if (props.mine) me = leaflet.marker([props.mine.lat, props.mine.lng], { icon: dot('me'), keyboard: false }).addTo(map)
    fit()
  } catch {
    failed.value = true
  }
})

// El punto se mueve cuando llega una posición nueva.
watch(
  () => [props.lat, props.lng],
  () => {
    driver?.setLatLng([props.lat, props.lng])
    if (!props.mine) map?.panTo([props.lat, props.lng], { animate: true })
  }
)

watch(
  () => props.mine,
  (value) => {
    if (!map || !leaflet) return
    me?.remove()
    me = value ? leaflet.marker([value.lat, value.lng], { icon: dot('me'), keyboard: false }).addTo(map) : null
    fit()
  }
)

onUnmounted(() => {
  map?.remove()
  map = null
})
</script>

<template>
  <div>
    <div
      v-show="!failed"
      ref="el"
      class="driver-map h-72 w-full border border-ink bg-paper-deep"
      role="group"
      :aria-label="mine ? 'Mapa con la posición del repartidor y la tuya' : 'Mapa con la posición del repartidor'"
    ></div>
    <p v-if="failed" class="border border-ink p-4 text-sm text-ink-soft">
      No pudimos cargar el mapa. La distancia de arriba sigue actualizándose.
    </p>
  </div>
</template>

<style>
.map-dot {
  display: block;
  width: 22px;
  height: 22px;
  border-radius: 9999px;
  border: 3px solid #fff;
  box-shadow: 0 0 0 2px rgb(0 0 0 / 0.55);
}
.map-dot--driver {
  background: var(--color-accent, #c2410c);
}
.map-dot--me {
  background: #1d4ed8;
}
.driver-map .leaflet-control-attribution {
  font-size: 11px;
}
</style>
