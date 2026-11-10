<script setup lang="ts">
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { Download, Printer, RefreshCw } from '@lucide/vue'
import { loadSettings } from '../../lib/api'
import { businessName } from '../../lib/format'
import {
  DEFAULT_QR_STYLE,
  QR_PRESETS,
  qrStyleProblem,
  qrToSvg,
  svgToDataUrl,
  svgToPngBlob,
  type QrEyes,
  type QrShape,
  type QrStyle
} from '../../lib/qrStyle'

const STYLE_KEY = 'lg:qr-style'

const baseUrl = ref(window.location.origin)
const tableCount = ref(0)
const ordering = ref(true)
const error = ref('')

// El estilo se recuerda en este navegador (se elige una vez y queda).
function readStyle(): QrStyle {
  try {
    const saved = JSON.parse(localStorage.getItem(STYLE_KEY) ?? 'null') as Partial<QrStyle> | null
    if (saved && typeof saved === 'object') return { ...DEFAULT_QR_STYLE, ...saved }
  } catch {
    // Sin almacenamiento disponible: se usa el estilo clásico.
  }
  return { ...DEFAULT_QR_STYLE }
}

const style = reactive<QrStyle>(readStyle())

watch(style, () => {
  try {
    localStorage.setItem(STYLE_KEY, JSON.stringify(style))
  } catch {
    // No es grave: el estilo solo no se recuerda.
  }
})

const problem = computed(() => qrStyleProblem(style))
// Si el estilo no es seguro para escanear, los códigos salen en el estilo clásico hasta corregirlo.
const effective = computed<QrStyle>(() => (problem.value ? DEFAULT_QR_STYLE : { ...style }))

const applyPreset = (preset: QrStyle) => Object.assign(style, preset)
const sameAsPreset = (preset: QrStyle) =>
  preset.fg === style.fg && preset.bg === style.bg && preset.shape === style.shape && preset.eyes === style.eyes

const SHAPES: { value: QrShape; label: string }[] = [
  { value: 'square', label: 'Cuadrados' },
  { value: 'rounded', label: 'Redondeados' },
  { value: 'dots', label: 'Puntos' }
]
const EYES: { value: QrEyes; label: string }[] = [
  { value: 'square', label: 'Cuadradas' },
  { value: 'rounded', label: 'Redondeadas' },
  { value: 'circle', label: 'Circulares' }
]

const print = () => window.print()

const cleanBase = computed(() => baseUrl.value.trim().replace(/\/+$/, ''))

const codes = computed(() => {
  if (!/^https?:\/\//i.test(cleanBase.value)) return []

  const base = cleanBase.value
  const make = (key: string, title: string, caption: string, url: string) => {
    const svg = qrToSvg(url, effective.value)
    return { key, title, caption, url, svg, image: svgToDataUrl(svg) }
  }

  // Primero el QR de la carta general (solo consulta) y después uno por mesa (para pedir).
  return [
    make('menu', 'Carta', 'Escaneá para ver la carta', `${base}/`),
    ...Array.from({ length: ordering.value ? tableCount.value : 0 }, (_, index) =>
      make(`t${index + 1}`, `Mesa ${index + 1}`, 'Escaneá para pedir', `${base}/mesa/${index + 1}`)
    )
  ]
})

function save(blob: Blob, name: string) {
  const link = document.createElement('a')
  link.href = URL.createObjectURL(blob)
  link.download = name
  link.click()
  window.setTimeout(() => URL.revokeObjectURL(link.href), 1000)
}

const fileName = (title: string, ext: string) =>
  `qr-${title.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]+/g, '-')}.${ext}`

const downloadSvg = (code: { title: string; svg: string }) =>
  save(new Blob([code.svg], { type: 'image/svg+xml' }), fileName(code.title, 'svg'))

async function downloadPng(code: { title: string; svg: string }) {
  try {
    save(await svgToPngBlob(code.svg), fileName(code.title, 'png'))
  } catch {
    error.value = 'No pudimos generar la imagen. Probá con el SVG.'
  }
}

async function reload() {
  error.value = ''

  try {
    const settings = await loadSettings()
    tableCount.value = settings.table_count
    ordering.value = settings.ordering_enabled
  } catch {
    error.value = 'No pudimos cargar la cantidad de mesas.'
  }
}

onMounted(() => {
  document.title = `Códigos QR · ${businessName}`
  void reload()
})
</script>

<template>
  <main class="wrap max-w-6xl pb-16 pt-8 print:max-w-none print:pt-0">
    <div class="flex flex-wrap items-center justify-between gap-3 print:hidden">
      <h1 class="font-display text-[2rem] font-semibold leading-none tracking-tight">Códigos QR</h1>
      <div class="flex gap-2">
        <button type="button" class="btn-line btn-small" @click="reload">
          <RefreshCw class="size-4" aria-hidden="true" />
          Actualizar
        </button>
        <button type="button" class="btn-line btn-small" :disabled="!codes.length" @click="print">
          <Printer class="size-4" aria-hidden="true" />
          Imprimir
        </button>
      </div>
    </div>

    <div class="mt-6 max-w-xl print:hidden">
      <label for="qr-base" class="mb-1.5 block text-sm font-medium">Dirección de la carta</label>
      <input id="qr-base" v-model="baseUrl" type="url" inputmode="url" class="field" />
      <p v-if="ordering" class="mt-3 text-sm font-medium">
        Este local tiene {{ tableCount }} mesas. Si cambiás la cantidad en Ajustes, volvé acá y se actualiza.
      </p>
      <p class="mt-1.5 text-sm text-ink-soft">
        El QR de la carta abre esta dirección y cada mesa, esta dirección + /mesa/N. Usá el dominio definitivo antes de imprimir.
      </p>
    </div>

    <fieldset class="mt-8 max-w-3xl space-y-5 border-t border-ink pt-5 print:hidden">
      <legend class="font-display pr-3 text-xl font-semibold">Estilo de los códigos</legend>
      <p class="text-sm text-ink-soft">
        Elegí colores y formas que combinen con el local. Probá siempre el QR con un celular antes de imprimir.
      </p>

      <div role="group" aria-label="Estilos listos" class="flex flex-wrap gap-2">
        <button
          v-for="preset in QR_PRESETS"
          :key="preset.id"
          type="button"
          class="btn-line btn-small"
          :aria-pressed="sameAsPreset(preset.style)"
          :class="sameAsPreset(preset.style) ? '!bg-ink !text-paper' : ''"
          @click="applyPreset(preset.style)"
        >
          <span
            class="inline-block size-3.5 rounded-full border border-current"
            :style="{ background: preset.style.fg }"
            aria-hidden="true"
          ></span>
          {{ preset.name }}
        </button>
      </div>

      <div class="grid gap-4 sm:grid-cols-2">
        <div>
          <label for="qr-fg" class="mb-1.5 block text-sm font-medium">Color del código</label>
          <input id="qr-fg" v-model="style.fg" type="color" class="h-11 w-full cursor-pointer border border-ink bg-transparent p-1" />
        </div>
        <div>
          <label for="qr-bg" class="mb-1.5 block text-sm font-medium">Color del fondo</label>
          <input id="qr-bg" v-model="style.bg" type="color" class="h-11 w-full cursor-pointer border border-ink bg-transparent p-1" />
        </div>
        <div>
          <label for="qr-shape" class="mb-1.5 block text-sm font-medium">Forma de los puntos</label>
          <select id="qr-shape" v-model="style.shape" class="field">
            <option v-for="item in SHAPES" :key="item.value" :value="item.value">{{ item.label }}</option>
          </select>
        </div>
        <div>
          <label for="qr-eyes" class="mb-1.5 block text-sm font-medium">Forma de las esquinas</label>
          <select id="qr-eyes" v-model="style.eyes" class="field">
            <option v-for="item in EYES" :key="item.value" :value="item.value">{{ item.label }}</option>
          </select>
        </div>
      </div>

      <p v-if="problem" class="text-sm font-medium text-accent-deep" role="alert" data-qr-problem>
        {{ problem }} Mientras tanto se usa el estilo clásico.
      </p>
    </fieldset>

    <p v-if="error" class="mt-5 text-sm text-accent-deep" role="alert">{{ error }}</p>

    <ul class="mt-8 grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4 print:mt-0 print:grid-cols-3">
      <li
        v-for="code in codes"
        :key="code.key"
        class="break-inside-avoid border border-ink p-3 text-center"
      >
        <p class="font-display text-2xl font-semibold leading-none">{{ code.title }}</p>
        <img :src="code.image" :alt="`QR: ${code.title}`" :data-url="code.url" class="mx-auto mt-2 w-full max-w-44" />
        <p class="mt-1 text-xs text-ink-soft">{{ code.caption }}</p>
        <div class="mt-2 flex justify-center gap-1 print:hidden">
          <button type="button" class="btn-line btn-small" :aria-label="`Descargar ${code.title} en SVG`" @click="downloadSvg(code)">
            <Download class="size-4" aria-hidden="true" />
            SVG
          </button>
          <button type="button" class="btn-line btn-small" :aria-label="`Descargar ${code.title} en PNG`" @click="downloadPng(code)">
            <Download class="size-4" aria-hidden="true" />
            PNG
          </button>
        </div>
      </li>
    </ul>
  </main>
</template>
