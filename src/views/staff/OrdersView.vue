<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { Volume2, VolumeX } from '@lucide/vue'
import { friendlyError, listOrders, setOrderStatus, subscribeOrders } from '../../lib/api'
import { agoLabel, businessName, formatClock, formatPrice, minutesSince } from '../../lib/format'
import {
  PAYMENT_LABEL,
  STATUS_LABEL,
  type Order,
  type OrderItem,
  type OrderStatus
} from '../../lib/types'

const orders = ref<Order[]>([])
const loading = ref(true)
const error = ref('')
const live = ref(false)
const soundOn = ref(false)
const alertText = ref('')
const now = ref(Date.now())
const busyIds = ref<string[]>([])

let audio: AudioContext | null = null
let pollTimer: number | undefined
let tickTimer: number | undefined
let alertTimer: number | undefined
let debounceTimer: number | undefined
let unsubscribe: (() => void) | undefined

// Para avisar solo de pedidos nuevos (no de los que ya estaban al abrir el panel).
const seen = new Set<string>()
let firstLoad = true

const pending = computed(() => orders.value.filter((order) => order.status === 'pending'))
const preparing = computed(() => orders.value.filter((order) => order.status === 'preparing'))
const ready = computed(() => orders.value.filter((order) => order.status === 'ready'))
const finished = computed(() =>
  orders.value
    .filter((order) => order.status === 'delivered' || order.status === 'cancelled')
    .reverse()
)

const sections = computed(() => [
  { key: 'pending', title: 'Por confirmar', orders: pending.value },
  { key: 'preparing', title: 'En preparación', orders: preparing.value },
  { key: 'ready', title: 'Listos para entregar', orders: ready.value }
])

const hasActive = computed(() => sections.value.some((section) => section.orders.length))

const NEXT: Partial<Record<OrderStatus, { to: OrderStatus; label: string }>> = {
  pending: { to: 'preparing', label: 'Confirmar' },
  preparing: { to: 'ready', label: 'Marcar listo' },
  ready: { to: 'delivered', label: 'Marcar entregado' }
}

const sortedItems = (order: Order): OrderItem[] =>
  [...order.order_items].sort((a, b) => a.name.localeCompare(b.name))

const waiting = (order: Order) => minutesSince(order.created_at, now.value)

// Un pedido que espera hace 10 minutos o más se resalta.
const isLate = (order: Order) =>
  (order.status === 'pending' || order.status === 'preparing') && waiting(order) >= 10

/* ---------- Carga y tiempo real ---------- */

async function refresh() {
  try {
    const data = await listOrders()

    const fresh = data.filter((order) => order.status === 'pending' && !seen.has(order.id))
    data.forEach((order) => seen.add(order.id))

    if (!firstLoad && fresh.length) notify(fresh)
    firstLoad = false

    orders.value = data
    error.value = ''
  } catch (e) {
    error.value = friendlyError(e)
  } finally {
    loading.value = false
  }
}

function scheduleRefresh() {
  window.clearTimeout(debounceTimer)
  debounceTimer = window.setTimeout(refresh, 300)
}

/* ---------- Aviso de pedido nuevo ---------- */

function beep() {
  if (!audio) return
  const ctx = audio

  ;[0, 0.28].forEach((offset, index) => {
    const osc = ctx.createOscillator()
    const gain = ctx.createGain()
    const start = ctx.currentTime + offset

    osc.type = 'sine'
    osc.frequency.value = index ? 1040 : 784

    gain.gain.setValueAtTime(0.0001, start)
    gain.gain.exponentialRampToValueAtTime(0.2, start + 0.02)
    gain.gain.exponentialRampToValueAtTime(0.0001, start + 0.22)

    osc.connect(gain)
    gain.connect(ctx.destination)
    osc.start(start)
    osc.stop(start + 0.25)
  })
}

function notify(fresh: Order[]) {
  alertText.value = fresh.map((order) => `Mesa ${order.table_number}${order.customer_name ? ` (${order.customer_name})` : ''}`).join(', ')

  window.clearTimeout(alertTimer)
  alertTimer = window.setTimeout(() => {
    alertText.value = ''
  }, 8000)

  if (soundOn.value) beep()
}

// El navegador solo permite sonido después de un clic, por eso es un botón.
async function toggleSound() {
  if (soundOn.value) {
    soundOn.value = false
    return
  }

  try {
    audio ??= new AudioContext()
    await audio.resume()
    soundOn.value = true
    beep()
  } catch {
    soundOn.value = false
  }
}

watch(
  () => pending.value.length,
  (count) => {
    document.title = `${count ? `(${count}) ` : ''}Pedidos · ${businessName}`
  },
  { immediate: true }
)

/* ---------- Acciones ---------- */

async function move(order: Order, status: OrderStatus) {
  if (busyIds.value.includes(order.id)) return

  busyIds.value.push(order.id)
  const previous = order.status
  order.status = status // se refleja al instante; si falla, se revierte

  try {
    await setOrderStatus(order.id, status)
    error.value = ''
  } catch (e) {
    order.status = previous
    error.value = friendlyError(e)
  } finally {
    busyIds.value = busyIds.value.filter((id) => id !== order.id)
    void refresh()
  }
}

function cancel(order: Order) {
  if (window.confirm(`¿Cancelar el pedido de la mesa ${order.table_number}?`)) {
    void move(order, 'cancelled')
  }
}

/* ---------- Ciclo de vida ---------- */

onMounted(async () => {
  await refresh()

  unsubscribe = subscribeOrders(scheduleRefresh, (status) => {
    live.value = status === 'SUBSCRIBED'
  })

  // Respaldo por si se cae la conexión en vivo.
  pollTimer = window.setInterval(refresh, 10_000)
  tickTimer = window.setInterval(() => {
    now.value = Date.now()
  }, 30_000)
})

onUnmounted(() => {
  unsubscribe?.()
  window.clearInterval(pollTimer)
  window.clearInterval(tickTimer)
  window.clearTimeout(alertTimer)
  window.clearTimeout(debounceTimer)
  void audio?.close()
  document.title = businessName
})
</script>

<template>
  <main class="wrap max-w-6xl pb-16 pt-8">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <h1 class="font-display text-[2rem] font-semibold leading-none tracking-tight">Pedidos</h1>

      <div class="flex items-center gap-4">
        <p class="flex items-center gap-2 text-[13px] text-ink-soft">
          <span
            class="size-2 rounded-full"
            :class="live ? 'bg-open' : 'bg-ink-soft/50'"
            aria-hidden="true"
          ></span>
          {{ live ? 'En vivo' : 'Actualiza cada 10 s' }}
        </p>

        <button
          type="button"
          class="btn-line btn-small"
          :aria-pressed="soundOn"
          @click="toggleSound"
        >
          <Volume2 v-if="soundOn" class="size-4" aria-hidden="true" />
          <VolumeX v-else class="size-4" aria-hidden="true" />
          Sonido {{ soundOn ? 'activado' : 'apagado' }}
        </button>
      </div>
    </div>

    <p
      v-if="alertText"
      class="mt-5 bg-accent px-4 py-3 font-semibold text-white"
      role="alert"
    >
      Nuevo pedido: {{ alertText }}
    </p>

    <p v-if="error" class="mt-5 border border-accent px-4 py-3 text-sm text-accent-deep" role="alert">
      {{ error }}
    </p>

    <p v-if="loading" class="py-16 text-center font-display text-xl italic text-ink-soft" aria-busy="true">
      Cargando pedidos…
    </p>

    <template v-else>
      <p
        v-if="!hasActive"
        class="py-16 text-center font-display text-xl italic text-ink-soft"
      >
        No hay pedidos activos. Cuando llegue uno, aparece acá.
      </p>

      <template v-for="section in sections" :key="section.key">
        <section v-if="section.orders.length" class="pt-8" :aria-labelledby="`sec-${section.key}`">
          <h2
            :id="`sec-${section.key}`"
            class="font-display border-b border-ink pb-2.5 text-[1.5rem] font-semibold leading-none tracking-tight"
          >
            {{ section.title }}
            <span class="ml-1 text-ink-soft">({{ section.orders.length }})</span>
          </h2>

          <div class="mt-4 grid gap-4 md:grid-cols-2 xl:grid-cols-3">
            <article
              v-for="order in section.orders"
              :key="order.id"
              class="border bg-white/40 p-4"
              :class="isLate(order) ? 'border-accent' : 'border-ink'"
            >
              <header class="flex items-start justify-between gap-3">
                <div>
                  <p class="font-display text-3xl font-semibold leading-none">
                    Mesa {{ order.table_number }}
                  </p>
                  <p v-if="order.customer_name" class="mt-1.5 text-[15px] font-semibold">
                    {{ order.customer_name }}
                  </p>
                  <p class="mt-1.5 text-[13px] tabular-nums text-ink-soft">
                    {{ formatClock(order.created_at) }} · {{ agoLabel(waiting(order)) }}
                  </p>
                </div>

                <span
                  class="shrink-0 border px-2 py-1 text-xs font-semibold uppercase tracking-wide"
                  :class="
                    isLate(order)
                      ? 'border-accent bg-accent text-white'
                      : 'border-ink text-ink'
                  "
                >
                  {{ STATUS_LABEL[order.status] }}
                </span>
              </header>

              <ul class="mt-3 divide-y divide-rule border-y border-rule">
                <li v-for="(item, index) in sortedItems(order)" :key="index" class="py-2">
                  <p class="text-[15px]">
                    <span class="font-semibold tabular-nums">{{ item.quantity }}×</span>
                    {{ item.name }}
                  </p>
                  <p v-if="item.note" class="mt-0.5 text-sm italic text-accent-deep">
                    “{{ item.note }}”
                  </p>
                </li>
              </ul>

              <p class="mt-3 flex items-baseline justify-between text-sm">
                <span class="text-ink-soft">Total</span>
                <span class="font-semibold tabular-nums">{{ formatPrice(order.total) }}</span>
              </p>
              <p v-if="order.payment_method" class="mt-1 flex items-baseline justify-between text-sm">
                <span class="text-ink-soft">Paga con</span>
                <span class="font-semibold">{{ PAYMENT_LABEL[order.payment_method] }}</span>
              </p>

              <div class="mt-4 flex flex-wrap gap-2">
                <button
                  v-if="NEXT[order.status]"
                  type="button"
                  class="btn-solid btn-small"
                  :disabled="busyIds.includes(order.id)"
                  @click="move(order, NEXT[order.status]!.to)"
                >
                  {{ NEXT[order.status]!.label }}
                </button>

                <button
                  v-if="order.status === 'pending' || order.status === 'preparing'"
                  type="button"
                  class="btn-line btn-small"
                  :disabled="busyIds.includes(order.id)"
                  @click="cancel(order)"
                >
                  {{ order.status === 'pending' ? 'Rechazar' : 'Cancelar' }}
                </button>
              </div>
            </article>
          </div>
        </section>
      </template>

      <details v-if="finished.length" class="mt-10 border-t border-ink pt-4">
        <summary class="cursor-pointer text-sm font-semibold">
          Entregados y cancelados hoy ({{ finished.length }})
        </summary>

        <ul class="mt-3 divide-y divide-rule">
          <li
            v-for="order in finished"
            :key="order.id"
            class="flex items-baseline justify-between gap-3 py-2.5 text-[15px]"
          >
            <span>
              <span class="font-semibold">Mesa {{ order.table_number }}</span>
              <span v-if="order.customer_name" class="ml-2">{{ order.customer_name }}</span>
              <span class="ml-2 tabular-nums text-ink-soft">{{ formatClock(order.created_at) }}</span>
            </span>
            <span class="tabular-nums">
              <span class="mr-3 text-ink-soft">{{ STATUS_LABEL[order.status] }}</span>
              {{ formatPrice(order.total) }}
            </span>
          </li>
        </ul>
      </details>
    </template>
  </main>
</template>
