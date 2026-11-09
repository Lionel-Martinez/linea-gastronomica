<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { RouterLink } from 'vue-router'
import { Ban, MapPin, MessageCircle, Phone, Volume2, VolumeX } from '@lucide/vue'
import {
  blockPhone,
  friendlyError,
  listOrders,
  setOrderEta,
  setOrderStatus,
  subscribeOrders
} from '../../lib/api'
import {
  agoLabel,
  businessName,
  formatClock,
  formatPrice,
  minutesSince,
  whatsappNumber
} from '../../lib/format'
import {
  formatCode,
  MODALITY_LABEL,
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

const byStatus = (status: OrderStatus) => orders.value.filter((order) => order.status === status)

const pending = computed(() => byStatus('pending'))
const finished = computed(() =>
  orders.value
    .filter((order) => order.status === 'delivered' || order.status === 'cancelled')
    .reverse()
)

const sections = computed(() => [
  { key: 'pending', title: 'Por confirmar', orders: byStatus('pending') },
  { key: 'preparing', title: 'En preparación', orders: byStatus('preparing') },
  { key: 'ready', title: 'Listos para entregar', orders: byStatus('ready') },
  { key: 'on_the_way', title: 'En camino', orders: byStatus('on_the_way') }
])

const hasActive = computed(() => sections.value.some((section) => section.orders.length))

/** "Mesa 4", "Retiro" o "Delivery". */
const titleOf = (order: Order) =>
  order.modality === 'dine_in'
    ? `Mesa ${order.table_number}`
    : order.modality === 'pickup'
      ? 'Retiro'
      : MODALITY_LABEL.delivery

const isRemote = (order: Order) => order.modality !== 'dine_in'

// Qué botón principal corresponde: los delivery listos salen a repartir desde "Reparto".
function nextAction(order: Order): { to: OrderStatus; label: string } | null {
  switch (order.status) {
    case 'pending':
      return { to: 'preparing', label: 'Confirmar' }
    case 'preparing':
      return { to: 'ready', label: 'Marcar listo' }
    case 'ready':
      if (order.modality === 'delivery') return null
      return { to: 'delivered', label: order.modality === 'pickup' ? 'Marcar retirado' : 'Marcar entregado' }
    case 'on_the_way':
      return { to: 'delivered', label: 'Marcar entregado' }
    default:
      return null
  }
}

const canCancel = (order: Order) =>
  order.status === 'pending' ||
  order.status === 'preparing' ||
  (isRemote(order) && (order.status === 'ready' || order.status === 'on_the_way'))

const sortedItems = (order: Order): OrderItem[] =>
  [...order.order_items].sort((a, b) => a.name.localeCompare(b.name))

const waiting = (order: Order) => minutesSince(order.created_at, now.value)

// Un pedido que espera hace 10 minutos o más se resalta.
const isLate = (order: Order) =>
  (order.status === 'pending' || order.status === 'preparing') && waiting(order) >= 10

const address = (order: Order) =>
  [`${order.delivery_street} ${order.delivery_number}`.trim(), order.zone_name]
    .filter(Boolean)
    .join(' · ')

const whatsappHref = (order: Order) => {
  const text =
    `Hola${order.customer_name ? ` ${order.customer_name}` : ''}, te escribimos de ${businessName} ` +
    `por tu pedido${order.tracking_code ? ` ${formatCode(order.tracking_code)}` : ''}.`

  return `https://wa.me/${whatsappNumber(order.customer_phone)}?text=${encodeURIComponent(text)}`
}

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
  alertText.value = fresh
    .map((order) => `${titleOf(order)}${order.customer_name ? ` (${order.customer_name})` : ''}`)
    .join(', ')

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
  if (window.confirm(`¿Cancelar el pedido (${titleOf(order)}${order.customer_name ? `, ${order.customer_name}` : ''})?`)) {
    void move(order, 'cancelled')
  }
}

async function block(order: Order) {
  if (!order.customer_phone) return

  const label = order.customer_name ? `${order.customer_name} (${order.customer_phone})` : order.customer_phone
  if (!window.confirm(`¿Bloquear el teléfono de ${label}? No va a poder hacer más pedidos desde casa.`)) return

  try {
    await blockPhone(order.customer_phone, order.customer_name.slice(0, 80))
    error.value = ''
  } catch (e) {
    error.value = friendlyError(e)
  }
}

const ETA_OPTIONS = [
  { value: '', label: 'Elegir…' },
  { value: 'clear', label: 'Quitar la hora' },
  { value: '15', label: 'En 15 min' },
  { value: '30', label: 'En 30 min' },
  { value: '45', label: 'En 45 min' },
  { value: '60', label: 'En 1 hora' },
  { value: '90', label: 'En 1 h 30 min' }
]

async function changeEta(order: Order, event: Event) {
  const select = event.target as HTMLSelectElement
  const value = select.value
  select.value = ''
  if (!value) return

  try {
    await setOrderEta(order.id, value === 'clear' ? null : new Date(Date.now() + Number(value) * 60_000))
    error.value = ''
  } catch (e) {
    error.value = friendlyError(e)
  } finally {
    void refresh()
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
              :data-modality="order.modality"
            >
              <header class="flex items-start justify-between gap-3">
                <div class="min-w-0">
                  <p class="font-display text-3xl font-semibold leading-none">
                    {{ titleOf(order) }}
                  </p>
                  <p v-if="order.customer_name" class="mt-1.5 text-[15px] font-semibold">
                    {{ order.customer_name }}
                  </p>
                  <p class="mt-1.5 text-[13px] tabular-nums text-ink-soft">
                    {{ formatClock(order.created_at) }} · {{ agoLabel(waiting(order)) }}
                    <template v-if="order.tracking_code"> · {{ formatCode(order.tracking_code) }}</template>
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

              <!-- Retiro y delivery: contacto y dirección -->
              <div v-if="isRemote(order)" class="mt-3 space-y-1 border-t border-rule pt-3 text-[15px]">
                <p v-if="order.customer_phone" class="flex items-center gap-2">
                  <Phone class="size-4 shrink-0 text-ink-soft" aria-hidden="true" />
                  <span class="tabular-nums">{{ order.customer_phone }}</span>
                </p>
                <p v-else class="text-sm text-ink-soft">Teléfono borrado por privacidad.</p>

                <template v-if="order.modality === 'delivery'">
                  <p v-if="address(order)" class="font-semibold">{{ address(order) }}</p>
                  <p v-else class="text-sm text-ink-soft">Dirección borrada por privacidad.</p>
                  <p v-if="order.delivery_reference" class="text-sm italic text-accent-deep">
                    “{{ order.delivery_reference }}”
                  </p>
                  <a
                    v-if="order.dest_lat !== null && order.dest_lng !== null"
                    :href="`https://www.google.com/maps?q=${order.dest_lat},${order.dest_lng}`"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="inline-flex min-h-11 items-center gap-1.5 text-sm font-medium underline underline-offset-4"
                  >
                    <MapPin class="size-4" aria-hidden="true" />
                    Ver la ubicación que compartió el cliente
                  </a>
                </template>

                <div v-if="order.customer_phone" class="flex flex-wrap gap-2 pt-1">
                  <a
                    :href="whatsappHref(order)"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="btn-line btn-small"
                  >
                    <MessageCircle class="size-4" aria-hidden="true" />
                    WhatsApp
                  </a>
                  <button type="button" class="btn-line btn-small" @click="block(order)">
                    <Ban class="size-4" aria-hidden="true" />
                    Bloquear
                  </button>
                </div>
              </div>

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

              <p v-if="order.delivery_fee > 0" class="mt-3 flex items-baseline justify-between text-sm">
                <span class="text-ink-soft">Envío</span>
                <span class="tabular-nums">{{ formatPrice(order.delivery_fee) }}</span>
              </p>
              <p class="mt-2 flex items-baseline justify-between text-sm">
                <span class="text-ink-soft">Total</span>
                <span class="font-semibold tabular-nums">{{ formatPrice(order.total) }}</span>
              </p>
              <p v-if="order.payment_method" class="mt-1 flex items-baseline justify-between text-sm">
                <span class="text-ink-soft">Paga con</span>
                <span class="font-semibold">
                  {{ PAYMENT_LABEL[order.payment_method] }}
                  <template v-if="order.cash_change_from">
                    (con {{ formatPrice(order.cash_change_from) }})
                  </template>
                </span>
              </p>

              <div v-if="isRemote(order)" class="mt-3">
                <label :for="`eta-${order.id}`" class="mb-1 block text-xs text-ink-soft">
                  Hora estimada
                  <span v-if="order.eta_at" class="font-semibold text-ink tabular-nums">
                    · {{ formatClock(order.eta_at) }}
                  </span>
                </label>
                <select
                  :id="`eta-${order.id}`"
                  class="field !py-2 text-sm"
                  :value="''"
                  @change="changeEta(order, $event)"
                >
                  <option v-for="option in ETA_OPTIONS" :key="option.value" :value="option.value">
                    {{ option.label }}
                  </option>
                </select>
              </div>

              <div class="mt-4 flex flex-wrap items-center gap-2">
                <button
                  v-if="nextAction(order)"
                  type="button"
                  class="btn-solid btn-small"
                  :disabled="busyIds.includes(order.id)"
                  @click="move(order, nextAction(order)!.to)"
                >
                  {{ nextAction(order)!.label }}
                </button>

                <RouterLink
                  v-else-if="order.status === 'ready' && order.modality === 'delivery'"
                  :to="{ name: 'staff-run' }"
                  class="btn-solid btn-small"
                >
                  Armar el reparto
                </RouterLink>

                <button
                  v-if="canCancel(order)"
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
              <span class="font-semibold">{{ titleOf(order) }}</span>
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
