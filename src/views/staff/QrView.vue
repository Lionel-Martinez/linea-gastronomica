<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { Printer } from '@lucide/vue'
import QRCode from 'qrcode'
import { loadSettings } from '../../lib/api'
import { businessName } from '../../lib/format'

const baseUrl = ref(window.location.origin)
const tableCount = ref(0)
const codes = ref<{ key: string; title: string; caption: string; url: string; image: string }[]>([])
const error = ref('')

const print = () => window.print()

const cleanBase = computed(() => baseUrl.value.trim().replace(/\/+$/, ''))

async function build() {
  if (!tableCount.value || !/^https?:\/\//i.test(cleanBase.value)) {
    codes.value = []
    return
  }

  const base = cleanBase.value
  const make = async (key: string, title: string, caption: string, url: string) => ({
    key,
    title,
    caption,
    url,
    image: await QRCode.toDataURL(url, { margin: 1, width: 360, errorCorrectionLevel: 'M' })
  })

  // Primero el QR de la carta general (solo consulta) y después uno por mesa (para pedir).
  const list = await Promise.all([
    make('menu', 'Carta', 'Escaneá para ver la carta', `${base}/`),
    ...Array.from({ length: tableCount.value }, (_, index) =>
      make(`t${index + 1}`, `Mesa ${index + 1}`, 'Escaneá para pedir', `${base}/mesa/${index + 1}`)
    )
  ])

  // Si el enlace cambió mientras se generaban, se descarta este resultado.
  if (base === cleanBase.value) codes.value = list
}

watch(cleanBase, () => void build())

onMounted(async () => {
  document.title = `Códigos QR · ${businessName}`

  try {
    tableCount.value = (await loadSettings()).table_count
    await build()
  } catch {
    error.value = 'No pudimos cargar la cantidad de mesas.'
  }
})
</script>

<template>
  <main class="wrap pb-16 pt-8 print:max-w-none print:pt-0">
    <div class="flex flex-wrap items-center justify-between gap-3 print:hidden">
      <h1 class="font-display text-[2rem] font-semibold leading-none tracking-tight">Códigos QR</h1>
      <button type="button" class="btn-line btn-small" :disabled="!codes.length" @click="print">
        <Printer class="size-4" aria-hidden="true" />
        Imprimir
      </button>
    </div>

    <div class="mt-6 max-w-xl print:hidden">
      <label for="qr-base" class="mb-1.5 block text-sm font-medium">Dirección de la carta</label>
      <input id="qr-base" v-model="baseUrl" type="url" inputmode="url" class="field" />
      <p class="mt-1.5 text-sm text-ink-soft">
        El QR de la carta abre esta dirección y cada mesa, esta dirección + /mesa/N. Usá el dominio definitivo antes de imprimir.
      </p>
    </div>

    <p v-if="error" class="mt-5 text-sm text-accent-deep" role="alert">{{ error }}</p>

    <ul class="mt-8 grid grid-cols-2 gap-4 sm:grid-cols-3 print:mt-0 print:grid-cols-3">
      <li
        v-for="code in codes"
        :key="code.key"
        class="break-inside-avoid border border-ink p-3 text-center"
      >
        <p class="font-display text-2xl font-semibold leading-none">{{ code.title }}</p>
        <img :src="code.image" :alt="`QR: ${code.title}`" :data-url="code.url" class="mx-auto mt-2 w-full max-w-44" />
        <p class="mt-1 text-xs text-ink-soft">{{ code.caption }}</p>
      </li>
    </ul>
  </main>
</template>
