<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { BellRing, Check, MessageCircle } from '@lucide/vue'
import {
  friendlyError,
  listOrders,
  markNear,
  setOrderStatus,
  startRun,
  subscribeOrders
} from '../../lib/api'
import { businessName, formatClock, formatPrice, whatsappNumber } from '../../lib/format'
import { PAYMENT_LABEL, type Order } from '../../lib/types'

const orders = ref<Order[]>([])
const loading = ref(true)
const error = ref('')
const busy = ref(false)
const selected = ref<string[]>([]) // el orden en que se tocan es el orden de las paradas

let pollTimer: number | undefined
let debounceTimer: number | undefined
let unsubscribe: (() => void) | undefined

const ready = computed(() =>
  orders.value.filter((order) => order.modality === 'delivery' && order.status === 'ready')
)

// Los repartos en curso, cada uno con sus paradas en orden.
const runs = computed(() => {
  const groups = new Map<string, Order[]>()

  for (const order of orders.value) {
    if (order.modality !== 'delivery' || order.status !== 'on_the_way' || !order.run_id) continue
    groups.set(order.run_id, [...(groups.get(order.run_id) ?? []), order])
  }

  return [...groups.entries()].map(([id, stops]) => ({
    id,
    stops: stops.sort((a, b) => (a.stop_position ?? 0) - (b.stop_position ?? 0))
  }))
})

const address = (order: Order) =>
  [`${order.delivery_street} ${order.delivery_number}`.trim(), order.zone_name]
    .filter(Boolean)
    .join(' · ')

const position = (id: string) => selected.value.indexOf(id) + 1

function toggle(id: string) {
  selected.value = selected.value.includes(id)
    ? selected.value.filter((item) => item !== id)
    : [...selected.value, id]
}

const nearHref = (order: Order) => {
  const text =
    `Hola${order.customer_name ? ` ${order.customer_name}` : ''}, estoy cerca con tu pedido de ` +
    `${businessName}. Podés salir a esperarme.`

  return `https://wa.me/${whatsappNumber(order.customer_phone)}?text=${encodeURIComponent(text)}`
}

async function refresh() {
  try {
    orders.value = await listOrders()
    // Se descartan los elegidos que ya no están listos (los tomó otra persona, por ejemplo).
    selected.value = selected.value.filter((id) => ready.value.some((order) => order.id === id))
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

async function run(action: () => Promise<void>) {
  if (busy.value) return
  busy.value = true

  try {
    await action()
    error.value = ''
  } catch (e) {
    error.value = friendlyError(e)
  } finally {
    busy.value = false
    void refresh()
  }
}

const depart = () =>
  run(async () => {
    await startRun([...selected.value])
    selected.value = []
  })

const near = (order: Order) => run(() => markNear(order.id))
const deliver = (order: Order) => run(() => setOrderStatus(order.id, 'delivered'))

onMounted(async () => {
  document.title = `Reparto · ${businessName}`
  await refresh()

  unsubscribe = subscribeOrders(scheduleRefresh, () => {})
  pollTimer = window.setInterval(refresh, 10_000)
})

onUnmounted(() => {
  unsubscribe?.()
  window.clearInterval(pollTimer)
  window.clearTimeout(debounceTimer)
  document.title = businessName
})
</script>

<template>
  <main class="wrap max-w-3xl pb-24 pt-8">
    <h1 class="font-display text-[2rem] font-semibold leading-none tracking-tight">Reparto</h1>

    <p v-if="error" class="mt-5 border border-accent px-4 py-3 text-sm text-accent-deep" role="alert">
      {{ error }}
    </p>

    <p v-if="loading" class="py-16 text-center font-display text-xl italic text-ink-soft" aria-busy="true">
      Cargando…
    </p>

    <template v-else>
      <!-- En camino -->
      <section
        v-for="(group, index) in runs"
        :key="group.id"
        class="pt-8"
        :aria-labelledby="`run-${group.id}`"
      >
        <h2
          :id="`run-${group.id}`"
          class="font-display border-b border-ink pb-2.5 text-[1.5rem] font-semibold leading-none tracking-tight"
        >
          En camino{{ runs.length > 1 ? ` · salida ${index + 1}` : '' }}
          <span class="ml-1 text-ink-soft">({{ group.stops.length }})</span>
        </h2>

        <ol class="mt-4 space-y-4">
          <li
            v-for="(order, stopIndex) in group.stops"
            :key="order.id"
            class="border border-ink bg-white/40 p-4"
            data-stop
          >
            <div class="flex items-start gap-3">
              <span
                class="flex size-9 shrink-0 items-center justify-center rounded-full border border-ink text-base font-semibold tabular-nums"
                :class="stopIndex === 0 ? 'bg-ink text-paper' : ''"
              >
                {{ stopIndex + 1 }}
              </span>

              <div class="min-w-0 flex-1">
                <p class="font-display text-2xl font-semibold leading-tight">{{ order.customer_name }}</p>
                <p class="mt-1 text-[15px] font-semibold">{{ address(order) || 'Dirección borrada' }}</p>
                <p v-if="order.delivery_reference" class="text-sm italic text-accent-deep">
                  “{{ order.delivery_reference }}”
                </p>
                <p class="mt-2 text-sm text-ink-soft tabular-nums">
                  {{ order.customer_phone }}
                  <template v-if="order.eta_at"> · estimada {{ formatClock(order.eta_at) }}</template>
                </p>
                <p class="mt-1 text-sm">
                  <strong class="font-semibold">{{ formatPrice(order.total) }}</strong>
                  ·
                  {{ order.payment_method ? PAYMENT_LABEL[order.payment_method] : '' }}
                  <template v-if="order.payment_method === 'cash' && order.cash_change_from">
                    (paga con {{ formatPrice(order.cash_change_from) }})
                  </template>
                  <template v-else-if="order.payment_method === 'transfer'"> (transferencia)</template>
                </p>
              </div>
            </div>

            <div class="mt-4 flex flex-wrap gap-2">
              <button
                type="button"
                class="btn-line btn-small"
                :disabled="busy || Boolean(order.near_at)"
                @click="near(order)"
              >
                <BellRing class="size-4" aria-hidden="true" />
                {{ order.near_at ? 'Aviso enviado' : 'Estoy cerca' }}
              </button>

              <a
                v-if="order.customer_phone"
                :href="nearHref(order)"
                target="_blank"
                rel="noopener noreferrer"
                class="btn-line btn-small"
              >
                <MessageCircle class="size-4" aria-hidden="true" />
                Avisar por WhatsApp
              </a>

              <button type="button" class="btn-solid btn-small" :disabled="busy" @click="deliver(order)">
                <Check class="size-4" aria-hidden="true" />
                Entregado
              </button>
            </div>
          </li>
        </ol>
      </section>

      <!-- Listos para salir -->
      <section class="pt-8" aria-labelledby="ready-title">
        <h2
          id="ready-title"
          class="font-display border-b border-ink pb-2.5 text-[1.5rem] font-semibold leading-none tracking-tight"
        >
          Listos para salir
          <span class="ml-1 text-ink-soft">({{ ready.length }})</span>
        </h2>

        <p v-if="!ready.length" class="py-8 text-center font-display text-lg italic text-ink-soft">
          No hay pedidos de delivery listos. Cuando marques uno como listo en Pedidos, aparece acá.
        </p>

        <template v-else>
          <p class="mt-3 text-sm text-ink-soft">
            Tocá los pedidos en el orden en que vas a entregarlos y después tocá «Salir a repartir».
          </p>

          <ul class="mt-3 space-y-3">
            <li v-for="order in ready" :key="order.id">
              <label
                class="flex min-h-11 cursor-pointer items-start gap-3 border p-4 transition-colors"
                :class="selected.includes(order.id) ? 'border-ink bg-paper-deep' : 'border-ink/40 hover:border-ink'"
              >
                <input
                  type="checkbox"
                  class="sr-only"
                  :checked="selected.includes(order.id)"
                  @change="toggle(order.id)"
                />
                <span
                  class="flex size-8 shrink-0 items-center justify-center rounded-full border text-sm font-semibold tabular-nums"
                  :class="selected.includes(order.id) ? 'border-ink bg-ink text-paper' : 'border-ink/40'"
                  aria-hidden="true"
                >
                  {{ selected.includes(order.id) ? position(order.id) : '' }}
                </span>

                <span class="min-w-0 flex-1">
                  <span class="block font-semibold">{{ order.customer_name }}</span>
                  <span class="block text-[15px]">{{ address(order) }}</span>
                  <span class="block text-sm text-ink-soft tabular-nums">
                    {{ formatPrice(order.total) }}
                    <template v-if="order.payment_method"> · {{ PAYMENT_LABEL[order.payment_method] }}</template>
                  </span>
                </span>

                <span v-if="selected.includes(order.id)" class="sr-only">
                  Parada {{ position(order.id) }}
                </span>
              </label>
            </li>
          </ul>

          <button
            type="button"
            class="btn-solid mt-5 w-full sm:w-auto"
            :disabled="busy || !selected.length"
            @click="depart"
          >
            Salir a repartir ({{ selected.length }})
          </button>
        </template>
      </section>
    </template>
  </main>
</template>
