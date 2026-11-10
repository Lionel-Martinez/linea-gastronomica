<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { RouterLink, useRoute } from 'vue-router'
import { ArrowLeft, Check, Copy, MapPin, MessageCircle } from '@lucide/vue'
import ConfigMissing from '../../components/ui/ConfigMissing.vue'
import DriverMap from '../../components/order/DriverMap.vue'
import PaymentInfo from '../../components/order/PaymentInfo.vue'
import TrackCodeForm from '../../components/order/TrackCodeForm.vue'
import WhatsAppProof from '../../components/order/WhatsAppProof.vue'
import { getDeliveryCode, getOrderByCode, loadSettings } from '../../lib/api'
import { businessName, formatClock, formatPrice } from '../../lib/format'
import { ageLabel, distanceLabel, geoErrorMessage, getPosition, geolocationSupported } from '../../lib/geo'
import { getName, setLastCode } from '../../lib/lastOrder'
import { isSupabaseConfigured } from '../../lib/supabase'
import {
  formatCode,
  MODALITY_LABEL,
  PAYMENT_HINT_REMOTE,
  PAYMENT_LABEL,
  STATUS_LABEL,
  type OrderStatus,
  type Settings,
  type TrackedOrder
} from '../../lib/types'

const route = useRoute()

const code = computed(() => String(route.params.code ?? '').replace(/[^a-z0-9]/gi, '').toUpperCase())
const validCode = computed(() => code.value.length === 8)
const isNew = computed(() => route.query.nuevo === '1')

const order = ref<TrackedOrder | null>(null)
const settings = ref<Settings | null>(null)
const missing = ref(false)
const offline = ref(false)
const copied = ref(false)
const deliveryCode = ref<string | null>(null)
let codeFetched = false

// Posición del propio cliente, solo para mostrarla en su mapa: nunca se envía a ningún lado.
const mine = ref<{ lat: number; lng: number } | null>(null)
const mineError = ref('')
const fetchedAt = ref(Date.now())
const clock = ref(Date.now())

let timer: number | undefined
let clockTimer: number | undefined

const STEPS = computed<{ status: OrderStatus; label: string }[]>(() =>
  order.value?.modality === 'delivery'
    ? [
        { status: 'pending', label: 'Por confirmar' },
        { status: 'preparing', label: 'En preparación' },
        { status: 'ready', label: 'Listo' },
        { status: 'on_the_way', label: 'En camino' },
        { status: 'delivered', label: 'Entregado' }
      ]
    : [
        { status: 'pending', label: 'Por confirmar' },
        { status: 'preparing', label: 'En preparación' },
        { status: 'ready', label: 'Listo para retirar' },
        { status: 'delivered', label: 'Retirado' }
      ]
)

const message = computed(() => {
  const current = order.value
  if (!current) return ''
  const delivery = current.modality === 'delivery'

  const map: Record<OrderStatus, string> = {
    pending: 'Recibimos tu pedido. El local lo va a confirmar en un momento.',
    preparing: 'Tu pedido se está preparando.',
    ready: delivery
      ? 'Tu pedido está listo. Está esperando que salga el repartidor.'
      : '¡Tu pedido está listo! Ya podés pasar a retirarlo.',
    on_the_way: 'Tu pedido salió. Ya está en camino.',
    delivered: delivery ? 'Entregado. ¡Buen provecho!' : 'Retirado. ¡Buen provecho!',
    cancelled: 'Este pedido fue cancelado. Consultá con el local.'
  }

  return map[current.status]
})

const stepIndex = computed(() => STEPS.value.findIndex((step) => step.status === order.value?.status))

const isFinished = computed(
  () => order.value?.status === 'delivered' || order.value?.status === 'cancelled'
)

const waitingText = computed(() => {
  const current = order.value
  if (!current || !['pending', 'preparing'].includes(current.status) || current.ahead === 0) return ''

  return current.ahead === 1
    ? 'Hay 1 pedido por delante del tuyo.'
    : `Hay ${current.ahead} pedidos por delante del tuyo.`
})

const runText = computed(() => {
  const run = order.value?.run
  if (!run) return ''
  if (run.before === 0) return '¡Sos la próxima parada! Ya podés salir a esperar al repartidor.'

  return `Tu entrega es la ${run.position} de ${run.total}. ${
    run.before === 1 ? 'Falta 1 entrega' : `Faltan ${run.before} entregas`
  } antes de la tuya.`
})

// Segundos desde que el repartidor mandó su último punto (suma lo que pasó desde que lo pedimos).
const driverAge = computed(() => {
  const driver = order.value?.driver
  if (!driver) return 0
  return driver.age_seconds + Math.max(0, Math.round((clock.value - fetchedAt.value) / 1000))
})

const STALE_AFTER = 180

const driverText = computed(() => {
  const driver = order.value?.driver
  if (!driver) return ''

  return driver.distance_m === null
    ? 'El repartidor ya está en camino hacia tu entrega.'
    : `El repartidor está ${distanceLabel(driver.distance_m)} de tu entrega.`
})

async function showMine() {
  mineError.value = ''

  try {
    const point = await getPosition()
    mine.value = { lat: point.lat, lng: point.lng }
  } catch (e) {
    mineError.value = geoErrorMessage(e)
  }
}

const etaText = computed(() => {
  const current = order.value
  if (!current?.eta_at || isFinished.value) return ''
  return `Hora estimada: ${formatClock(current.eta_at)}`
})

const subtotal = computed(() => (order.value ? order.value.total - order.value.delivery_fee : 0))

const hint = computed(() => {
  const current = order.value
  if (!current?.payment_method) return ''
  return PAYMENT_HINT_REMOTE[current.modality][current.payment_method] ?? ''
})

// Mensaje armado para avisarle al local; el cliente solo lo envía.
const orderHref = computed(() => {
  const current = order.value
  const number = settings.value?.whatsapp_number
  if (!current || !number) return ''

  const name = getName()
  const lines = current.items.map((item) => `${item.quantity}× ${item.name}`).join(', ')
  const text =
    `Hola, hice un pedido para ${current.modality === 'delivery' ? 'delivery' : 'retirar'}. ` +
    `Código: ${formatCode(current.tracking_code)}${name ? ` (${name})` : ''}. ` +
    `${lines}. Total: ${formatPrice(current.total)}.`

  return `https://wa.me/${number}?text=${encodeURIComponent(text)}`
})

function stopPolling() {
  window.clearInterval(timer)
  timer = undefined
}

async function refresh() {
  if (document.visibilityState === 'hidden' || !validCode.value) return

  try {
    const result = await getOrderByCode(code.value)
    offline.value = false

    if (!result) {
      missing.value = true
      order.value = null
      stopPolling()
      return
    }

    missing.value = false
    fetchedAt.value = Date.now()
    order.value = result
    setLastCode(result.tracking_code)

    // Código de entrega (si el local lo usa): se pide una sola vez, no cambia.
    if (result.modality === 'delivery' && !codeFetched && result.status !== 'delivered' && result.status !== 'cancelled') {
      codeFetched = true
      getDeliveryCode(result.tracking_code)
        .then((value) => (deliveryCode.value = value))
        .catch(() => (codeFetched = false))
    }
    if (result.status === 'delivered' || result.status === 'cancelled') deliveryCode.value = null
    if (result.status === 'delivered' || result.status === 'cancelled') stopPolling()
  } catch {
    offline.value = true
  }
}

// Cuando el repartidor avisa que está cerca, el celular vibra una vez.
watch(
  () => order.value?.near,
  (near, before) => {
    if (near && !before) {
      try {
        navigator.vibrate?.([200, 100, 200])
      } catch {
        // No todos los navegadores lo permiten.
      }
    }
  }
)

async function copyCode() {
  try {
    await navigator.clipboard.writeText(formatCode(code.value))
    copied.value = true
    window.setTimeout(() => (copied.value = false), 2000)
  } catch {
    copied.value = false
  }
}

function onVisible() {
  if (document.visibilityState === 'visible' && !isFinished.value) void refresh()
}

async function start() {
  stopPolling()
  order.value = null
  missing.value = false

  if (!isSupabaseConfigured || !validCode.value) return

  await refresh()
  if (!missing.value && !isFinished.value) timer = window.setInterval(refresh, 5000)
}

watch(code, () => void start())

onMounted(() => {
  document.title = `Seguí tu pedido · ${businessName}`
  document.addEventListener('visibilitychange', onVisible)
  clockTimer = window.setInterval(() => (clock.value = Date.now()), 5000)

  if (isSupabaseConfigured) {
    // Los ajustes (alias/CBU, WhatsApp) se cargan aparte; si fallan, el pedido igual se ve.
    void loadSettings()
      .then((data) => {
        settings.value = data
      })
      .catch(() => {})
  }

  void start()
})

onUnmounted(() => {
  stopPolling()
  window.clearInterval(clockTimer)
  document.removeEventListener('visibilitychange', onVisible)
})
</script>

<template>
  <div class="min-h-dvh bg-paper text-ink">
    <header class="wrap pb-6 pt-10 sm:pt-14">
      <p class="text-[13px] font-medium text-ink-soft">{{ businessName }}</p>

      <h1
        class="font-display mt-2 text-[clamp(2.5rem,11vw,4.5rem)] font-semibold leading-[0.92] tracking-[-0.02em]"
      >
        Seguí tu pedido
      </h1>

      <p v-if="order" class="mt-3 flex flex-wrap items-center gap-x-3 gap-y-1 text-[15px] text-ink-soft">
        <span>
          {{ MODALITY_LABEL[order.modality] }} · pedido a las
          <span class="tabular-nums">{{ formatClock(order.created_at) }}</span>
        </span>
      </p>
    </header>

    <div class="wrap">
      <div class="h-[3px] bg-ink"></div>
      <div class="mt-[3px] h-px bg-ink"></div>
    </div>

    <div v-if="!isSupabaseConfigured" class="wrap"><ConfigMissing /></div>

    <!-- Sin código o código incorrecto -->
    <main v-else-if="!validCode || missing" class="wrap py-12">
      <div v-if="validCode && missing" role="alert">
        <h2 class="font-display text-2xl font-semibold leading-tight">No encontramos ese pedido</h2>
        <p class="mt-2 max-w-md text-[15px] text-ink-soft">
          Revisá que el código esté bien escrito. Si pediste hace poco, consultá con el local.
        </p>
      </div>
      <template v-else>
        <h2 class="font-display text-2xl font-semibold leading-tight">Ingresá tu código</h2>
        <p class="mt-2 max-w-md text-[15px] text-ink-soft">
          Lo recibiste al hacer el pedido. Con él ves en qué está, sin necesidad de iniciar sesión.
        </p>
      </template>

      <div class="mt-6 max-w-md">
        <TrackCodeForm />
      </div>

      <RouterLink :to="{ name: 'menu' }" class="btn-line mt-8">
        <ArrowLeft class="size-4" aria-hidden="true" />
        Volver a la carta
      </RouterLink>
    </main>

    <main v-else-if="!order" class="wrap py-16 text-center" aria-busy="true">
      <p class="font-display text-xl italic text-ink-soft">
        {{ offline ? 'No pudimos cargar tu pedido. Seguimos intentando…' : 'Cargando tu pedido…' }}
      </p>
    </main>

    <main v-else class="wrap pb-14">
      <!-- Código -->
      <section class="pt-8" aria-labelledby="code-title">
        <p v-if="isNew" class="mb-3 border border-ink bg-paper-deep px-4 py-3 text-[15px]" role="status">
          <strong class="font-semibold">¡Pedido enviado!</strong>
          Guardá este código: con él seguís tu pedido desde cualquier celular.
        </p>

        <h2 id="code-title" class="text-sm font-medium text-ink-soft">Tu código</h2>
        <div class="mt-1 flex items-center gap-2">
          <p
            class="font-display text-[2.25rem] font-semibold leading-none tracking-[0.12em] tabular-nums"
            data-testid="tracking-code"
          >
            {{ formatCode(order.tracking_code) }}
          </p>
          <button
            type="button"
            class="flex size-11 shrink-0 items-center justify-center rounded-full transition-colors hover:bg-paper-deep"
            :aria-label="copied ? 'Código copiado' : 'Copiar código'"
            @click="copyCode"
          >
            <Check v-if="copied" class="size-5 text-open" aria-hidden="true" />
            <Copy v-else class="size-5" aria-hidden="true" />
          </button>
        </div>

        <div v-if="deliveryCode && !isFinished" class="mt-4 border border-ink p-3" data-testid="delivery-code-box">
          <h3 class="text-sm font-medium text-ink-soft">Código de entrega</h3>
          <p
            class="font-display mt-1 text-[2rem] font-semibold leading-none tracking-[0.2em] tabular-nums"
            data-testid="delivery-code"
          >
            {{ deliveryCode }}
          </p>
          <p class="mt-2 text-sm text-ink-soft">
            Decíselo al repartidor cuando te lo entregue. No lo compartas antes: es lo que asegura que el pedido
            llega a vos.
          </p>
        </div>

        <a
          v-if="orderHref && !isFinished"
          :href="orderHref"
          target="_blank"
          rel="noopener noreferrer"
          class="btn-line mt-4 w-full sm:w-auto"
        >
          <MessageCircle class="size-4" aria-hidden="true" />
          Avisar al local por WhatsApp
        </a>
      </section>

      <!-- Estado -->
      <section class="pt-9" aria-live="polite">
        <p
          class="font-display text-[2rem] font-semibold leading-tight tracking-tight"
          :class="order.status === 'cancelled' ? 'text-accent-deep' : ''"
        >
          {{ STATUS_LABEL[order.status] }}
        </p>
        <p class="mt-1.5 max-w-md text-[15px] text-ink-soft">{{ message }}</p>
        <p v-if="waitingText" class="mt-1.5 text-[15px] font-medium">{{ waitingText }}</p>
        <p v-if="etaText" class="mt-1.5 text-[15px] font-medium tabular-nums">{{ etaText }}</p>

        <p
          v-if="order.near"
          class="mt-4 flex items-start gap-2 bg-accent px-4 py-3 font-semibold text-white"
          role="alert"
        >
          <MapPin class="mt-0.5 size-5 shrink-0" aria-hidden="true" />
          ¡El delivery está cerca! Podés salir a esperarlo.
        </p>

        <ol v-if="order.status !== 'cancelled'" class="mt-6 flex gap-1.5">
          <li v-for="(step, index) in STEPS" :key="step.status" class="min-w-0 flex-1">
            <div
              class="h-1.5 w-full"
              :class="index < stepIndex ? 'bg-ink' : index === stepIndex ? 'bg-accent' : 'bg-rule'"
            ></div>
            <p
              class="mt-2 text-xs leading-tight"
              :class="index === stepIndex ? 'font-semibold text-ink' : 'text-ink-soft'"
              :aria-current="index === stepIndex ? 'step' : undefined"
            >
              {{ step.label }}
            </p>
          </li>
        </ol>

        <p v-if="offline" class="mt-4 text-sm text-ink-soft" role="status">
          Sin conexión. Seguimos intentando actualizar.
        </p>
      </section>

      <!-- Reparto: en qué parada va -->
      <section
        v-if="order.status === 'on_the_way' && order.run"
        class="pt-9"
        aria-labelledby="run-title"
      >
        <h2
          id="run-title"
          class="font-display border-b border-ink pb-2.5 text-[1.75rem] font-semibold leading-none tracking-tight"
        >
          Recorrido del repartidor
        </h2>
        <p class="mt-3 text-[15px] font-medium">{{ runText }}</p>

        <ol class="mt-4 divide-y divide-rule border-y border-rule">
          <li
            v-for="(stop, index) in order.run.stops"
            :key="index"
            class="flex items-center gap-3 py-3 text-[15px]"
            :class="stop.done ? 'text-ink-soft' : ''"
          >
            <span
              class="flex size-7 shrink-0 items-center justify-center rounded-full border text-sm font-semibold tabular-nums"
              :class="stop.mine ? 'border-accent bg-accent text-white' : 'border-ink/40'"
            >
              {{ index + 1 }}
            </span>
            <span class="min-w-0 flex-1" :class="stop.done ? 'line-through' : ''">
              {{ stop.place || 'Sin dato' }}
            </span>
            <span v-if="stop.mine" class="shrink-0 text-xs font-semibold uppercase tracking-wide text-accent-deep">
              Tu entrega
            </span>
            <span v-else-if="stop.done" class="shrink-0 text-xs text-ink-soft">Entregado</span>
          </li>
        </ol>

        <p class="mt-3 text-xs text-ink-soft">
          Mostramos solo la calle de cada parada, sin números ni nombres.
        </p>
      </section>

      <!-- Dónde está el repartidor (solo cuando este pedido es la próxima parada) -->
      <section
        v-if="order.status === 'on_the_way' && order.driver"
        class="pt-9"
        aria-labelledby="map-title"
      >
        <h2
          id="map-title"
          class="font-display border-b border-ink pb-2.5 text-[1.75rem] font-semibold leading-none tracking-tight"
        >
          Dónde está tu delivery
        </h2>

        <p class="mt-3 text-[15px] font-medium" data-testid="driver-text">{{ driverText }}</p>
        <p class="mt-1 text-sm text-ink-soft">
          Última actualización {{ ageLabel(driverAge) }}.
          <template v-if="driverAge > STALE_AFTER">
            Hace un rato que no recibimos señal del repartidor; mostramos su último punto.
          </template>
        </p>

        <div class="mt-4">
          <DriverMap :lat="order.driver.lat" :lng="order.driver.lng" :mine="mine" />
        </div>

        <button
          v-if="geolocationSupported() && !mine"
          type="button"
          class="btn-line btn-small mt-3"
          @click="showMine"
        >
          <MapPin class="size-4" aria-hidden="true" />
          Mostrar mi ubicación en el mapa
        </button>
        <p v-if="mineError" class="mt-2 text-sm text-accent-deep" role="alert">{{ mineError }}</p>
        <p class="mt-2 text-xs text-ink-soft">
          Solo ves al repartidor cuando tu pedido es la próxima parada. Tu ubicación en el mapa no se envía a nadie.
        </p>
      </section>

      <!-- Detalle -->
      <section class="pt-10" aria-labelledby="detail-title">
        <h2
          id="detail-title"
          class="font-display border-b border-ink pb-2.5 text-[1.75rem] font-semibold leading-none tracking-tight"
        >
          Detalle
        </h2>

        <ul class="divide-y divide-rule">
          <li v-for="(item, index) in order.items" :key="index" class="py-3.5">
            <div class="flex items-baseline gap-2">
              <span class="font-display text-[1.1875rem] font-medium leading-snug">
                {{ item.quantity }} × {{ item.name }}
              </span>
              <span class="leader" aria-hidden="true"></span>
              <span class="whitespace-nowrap font-semibold tabular-nums">
                {{ formatPrice(item.unit_price * item.quantity) }}
              </span>
            </div>
            <p v-if="item.note" class="mt-1 text-sm italic text-ink-soft">“{{ item.note }}”</p>
          </li>
        </ul>

        <dl v-if="order.delivery_fee > 0" class="space-y-1 border-t border-rule pt-3 text-[15px]">
          <div class="flex items-baseline justify-between">
            <dt class="text-ink-soft">Productos</dt>
            <dd class="tabular-nums">{{ formatPrice(subtotal) }}</dd>
          </div>
          <div class="flex items-baseline justify-between">
            <dt class="text-ink-soft">Envío{{ order.zone_name ? ` (${order.zone_name})` : '' }}</dt>
            <dd class="tabular-nums">{{ formatPrice(order.delivery_fee) }}</dd>
          </div>
        </dl>

        <p class="mt-2 flex items-baseline justify-between border-t border-ink pt-4">
          <span class="font-display text-xl font-semibold">Total</span>
          <span class="text-xl font-semibold tabular-nums">{{ formatPrice(order.total) }}</span>
        </p>
      </section>

      <div v-if="order.status !== 'cancelled' && order.payment_method" class="pt-8">
        <template v-if="order.payment_method === 'transfer'">
          <PaymentInfo :settings="settings" />
          <WhatsAppProof
            :number="settings?.whatsapp_number ?? ''"
            :code="formatCode(order.tracking_code)"
            :total="order.total"
          />
        </template>

        <section v-else class="border border-ink p-4">
          <h3 class="font-display text-xl font-semibold leading-none">Cómo pagar</h3>
          <p class="mt-2 text-[15px]">
            <strong class="font-semibold">{{ PAYMENT_LABEL[order.payment_method] }}.</strong>
            {{ hint }}
          </p>
        </section>
      </div>

      <div class="mt-8 flex flex-wrap gap-3">
        <RouterLink :to="{ name: 'remote-order' }" class="btn-line">
          <ArrowLeft class="size-4" aria-hidden="true" />
          Pedir algo más
        </RouterLink>
        <RouterLink :to="{ name: 'menu' }" class="btn-line">Ver la carta</RouterLink>
      </div>
    </main>
  </div>
</template>
