<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { RouterLink, useRoute } from 'vue-router'
import { ArrowLeft } from '@lucide/vue'
import ConfigMissing from '../../components/ui/ConfigMissing.vue'
import PaymentInfo from '../../components/order/PaymentInfo.vue'
import WhatsAppProof from '../../components/order/WhatsAppProof.vue'
import { getOrder, loadSettings } from '../../lib/api'
import { businessName, formatClock, formatPrice } from '../../lib/format'
import { isSupabaseConfigured } from '../../lib/supabase'
import {
  PAYMENT_HINT,
  PAYMENT_LABEL,
  STATUS_LABEL,
  type OrderStatus,
  type PublicOrder,
  type Settings
} from '../../lib/types'

const route = useRoute()

const id = computed(() => String(route.params.id ?? ''))
const validId = computed(() =>
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id.value)
)

const order = ref<PublicOrder | null>(null)
const settings = ref<Settings | null>(null)
const missing = ref(false)
const offline = ref(false)

let timer: number | undefined

const STEPS: { status: OrderStatus; label: string }[] = [
  { status: 'pending', label: 'Por confirmar' },
  { status: 'preparing', label: 'En preparación' },
  { status: 'ready', label: 'Listo' },
  { status: 'delivered', label: 'Entregado' }
]

const MESSAGES: Record<OrderStatus, string> = {
  pending: 'Recibimos tu pedido. El personal lo va a confirmar en un momento.',
  preparing: 'Tu pedido se está preparando.',
  ready: '¡Tu pedido está listo! Ya te lo llevan a la mesa.',
  delivered: 'Entregado. ¡Buen provecho!',
  cancelled: 'Este pedido fue cancelado. Consultá con el personal.'
}

const stepIndex = computed(() =>
  STEPS.findIndex((step) => step.status === order.value?.status)
)

const isFinished = computed(
  () => order.value?.status === 'delivered' || order.value?.status === 'cancelled'
)

const waitingText = computed(() => {
  const current = order.value
  if (!current || !['pending', 'preparing'].includes(current.status)) return ''
  if (current.ahead === 0) return ''

  return current.ahead === 1
    ? 'Hay 1 pedido por delante del tuyo.'
    : `Hay ${current.ahead} pedidos por delante del tuyo.`
})

function stopPolling() {
  window.clearInterval(timer)
  timer = undefined
}

async function refresh() {
  if (document.visibilityState === 'hidden') return

  try {
    const result = await getOrder(id.value)
    offline.value = false

    if (!result) {
      missing.value = true
      stopPolling()
      return
    }

    order.value = result
    if (result.status === 'delivered' || result.status === 'cancelled') stopPolling()
  } catch {
    offline.value = true
  }
}

function onVisible() {
  if (document.visibilityState === 'visible' && !isFinished.value) void refresh()
}

onMounted(async () => {
  document.title = `Tu pedido · ${businessName}`

  if (!isSupabaseConfigured || !validId.value) return

  document.addEventListener('visibilitychange', onVisible)

  // Los ajustes (alias/CBU) se cargan aparte; si fallan, el pedido igual se ve.
  void loadSettings()
    .then((data) => {
      settings.value = data
    })
    .catch(() => {})

  await refresh()
  if (!missing.value && !isFinished.value) timer = window.setInterval(refresh, 5000)
})

onUnmounted(() => {
  stopPolling()
  document.removeEventListener('visibilitychange', onVisible)
})
</script>

<template>
  <div class="min-h-dvh bg-paper text-ink">
    <header class="wrap pb-6 pt-10 sm:pt-14">
      <p class="text-[13px] font-medium text-ink-soft">{{ businessName }}</p>

      <h1
        class="font-display mt-2 text-[clamp(2.75rem,12vw,5rem)] font-semibold leading-[0.92] tracking-[-0.02em]"
      >
        Tu pedido
      </h1>

      <p v-if="order" class="mt-3 text-[15px] text-ink-soft">
        Mesa {{ order.table_number }} · pedido a las
        <span class="tabular-nums">{{ formatClock(order.created_at) }}</span>
      </p>
    </header>

    <div class="wrap">
      <div class="h-[3px] bg-ink"></div>
      <div class="mt-[3px] h-px bg-ink"></div>
    </div>

    <div v-if="!isSupabaseConfigured" class="wrap"><ConfigMissing /></div>

    <div v-else-if="!validId || missing" class="wrap py-14" role="alert">
      <h2 class="font-display text-2xl font-semibold leading-tight">No encontramos este pedido</h2>
      <p class="mt-2 max-w-md text-[15px] text-ink-soft">
        Puede que el enlace esté incompleto. Si pediste recién, consultá con el personal.
      </p>
      <RouterLink :to="{ name: 'menu' }" class="btn-line mt-5">Ver la carta</RouterLink>
    </div>

    <div v-else-if="!order" class="wrap py-16 text-center" aria-busy="true">
      <p class="font-display text-xl italic text-ink-soft">
        {{ offline ? 'No pudimos cargar tu pedido. Seguimos intentando…' : 'Cargando tu pedido…' }}
      </p>
    </div>

    <main v-else class="wrap pb-14">
      <!-- Estado -->
      <section class="pt-8" aria-live="polite">
        <p
          class="font-display text-[2rem] font-semibold leading-tight tracking-tight"
          :class="order.status === 'cancelled' ? 'text-accent-deep' : ''"
        >
          {{ STATUS_LABEL[order.status] }}
        </p>
        <p class="mt-1.5 max-w-md text-[15px] text-ink-soft">{{ MESSAGES[order.status] }}</p>
        <p v-if="waitingText" class="mt-1.5 text-[15px] font-medium">{{ waitingText }}</p>

        <ol v-if="order.status !== 'cancelled'" class="mt-6 grid grid-cols-4 gap-1.5">
          <li v-for="(step, index) in STEPS" :key="step.status">
            <div
              class="h-1.5 w-full"
              :class="
                index < stepIndex
                  ? 'bg-ink'
                  : index === stepIndex
                    ? 'bg-accent'
                    : 'bg-rule'
              "
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

        <p class="flex items-baseline justify-between border-t border-ink pt-4">
          <span class="font-display text-xl font-semibold">Total</span>
          <span class="text-xl font-semibold tabular-nums">{{ formatPrice(order.total) }}</span>
        </p>
      </section>

      <div v-if="order.status !== 'cancelled' && order.payment_method" class="pt-8">
        <template v-if="order.payment_method === 'transfer'">
          <PaymentInfo :settings="settings" />
          <WhatsAppProof
            :number="settings?.whatsapp_number ?? ''"
            :table="order.table_number"
            :total="order.total"
          />
        </template>

        <section v-else class="border border-ink p-4">
          <h3 class="font-display text-xl font-semibold leading-none">Cómo pagar</h3>
          <p class="mt-2 text-[15px]">
            <strong class="font-semibold">{{ PAYMENT_LABEL[order.payment_method] }}.</strong>
            {{ PAYMENT_HINT[order.payment_method] }}
          </p>
        </section>
      </div>

      <RouterLink
        :to="{ name: 'order-menu', params: { table: order.table_number } }"
        class="btn-line mt-8"
      >
        <ArrowLeft class="size-4" aria-hidden="true" />
        Pedir algo más
      </RouterLink>
    </main>
  </div>
</template>
