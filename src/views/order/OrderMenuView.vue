<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { RouterLink, useRoute, useRouter } from 'vue-router'
import { ChevronRight, Plus } from '@lucide/vue'
import BottomSheet from '../../components/ui/BottomSheet.vue'
import ConfigMissing from '../../components/ui/ConfigMissing.vue'
import QtyStepper from '../../components/ui/QtyStepper.vue'
import PaymentInfo from '../../components/order/PaymentInfo.vue'
import { useCart } from '../../composables/useCart'
import {
  createOrder,
  friendlyError,
  getTableOrders,
  isProductUnavailable,
  loadMenu
} from '../../lib/api'
import { businessName, formatClock, formatPrice } from '../../lib/format'
import { clearSubmitToken, getName, setName, submitToken } from '../../lib/lastOrder'
import { isSupabaseConfigured } from '../../lib/supabase'
import {
  PAYMENT_HINT,
  PAYMENT_LABEL,
  PAYMENT_METHODS,
  STATUS_LABEL,
  type Category,
  type PaymentMethod,
  type Product,
  type Settings,
  type TableOrder
} from '../../lib/types'

const route = useRoute()
const router = useRouter()

// Número de mesa tomado de la URL (/mesa/5). 0 = inválido.
const tableNumber = computed(() => {
  const value = Number(route.params.table)
  return Number.isInteger(value) && value >= 1 ? value : 0
})

const categories = ref<Category[]>([])
const products = ref<Product[]>([])
const settings = ref<Settings | null>(null)
const loading = ref(isSupabaseConfigured)
const loadError = ref('')
const notice = ref('')

const { lines, count, total, qtyOf, add, inc, dec, clear, reconcile, payload } =
  useCart(tableNumber)

const tableValid = computed(
  () =>
    tableNumber.value >= 1 &&
    tableNumber.value <= (settings.value?.table_count ?? 0)
)

/* ---------- Carga de la carta ---------- */

async function load() {
  if (!isSupabaseConfigured) return

  try {
    const data = await loadMenu()

    categories.value = data.categories
    products.value = data.products
    settings.value = data.settings
    loadError.value = ''

    // Local sin pedidos activados (plan solo-carta): se muestra la carta normal.
    if (!data.settings.ordering_enabled) {
      await router.replace({ name: 'menu' })
      return
    }

    const removed = reconcile(data.products)
    if (removed.length) {
      notice.value = `Quitamos de tu pedido lo que ya no está disponible: ${removed.join(', ')}.`
    }
  } catch (error) {
    loadError.value = friendlyError(error)
  } finally {
    loading.value = false
  }
}

function retry() {
  loading.value = true
  void load()
}

/* ---------- Pedidos de esta mesa (también desde otro celular) ---------- */

const tableOrders = ref<TableOrder[]>([])

async function checkTableOrders() {
  if (!tableNumber.value || !isSupabaseConfigured) {
    tableOrders.value = []
    return
  }

  try {
    tableOrders.value = await getTableOrders(tableNumber.value)
  } catch {
    // Sin conexión: simplemente no mostramos la lista.
  }
}

const itemsText = (order: TableOrder) =>
  order.items.map((item) => `${item.quantity}× ${item.name}`).join(', ')

/* ---------- Carta ---------- */

const selectedCategory = ref('all')

const navCategories = computed(() =>
  categories.value.filter((category) =>
    products.value.some((product) => product.category_id === category.id)
  )
)

const groups = computed(() =>
  navCategories.value
    .filter(
      (category) =>
        selectedCategory.value === 'all' || category.id === selectedCategory.value
    )
    .map((category) => ({
      ...category,
      products: products.value.filter((product) => product.category_id === category.id)
    }))
)

function selectCategory(id: string, event: Event) {
  selectedCategory.value = id

  ;(event.currentTarget as HTMLElement).scrollIntoView({
    behavior: 'smooth',
    block: 'nearest',
    inline: 'center'
  })
}

/* ---------- Envío del pedido ---------- */

const sheetOpen = ref(false)
const sending = ref(false)
const customerName = ref(getName())
const method = ref<PaymentMethod | ''>('')

// Formas de pago que el local aceptó en Ajustes, en orden fijo.
const enabledMethods = computed(() =>
  PAYMENT_METHODS.filter((m) => settings.value?.payment_methods.includes(m))
)

// Con una sola opción se elige sola; si la elegida deja de estar disponible, se limpia.
watch(
  enabledMethods,
  (list) => {
    if (method.value && !list.includes(method.value)) method.value = ''
    if (!method.value && list.length === 1) method.value = list[0]!
  },
  { immediate: true }
)
const sendError = ref('')

function openCart() {
  sendError.value = ''
  sheetOpen.value = true
  void load() // actualiza disponibilidad antes de confirmar
}

async function send() {
  if (!lines.value.length || sending.value) return

  const name = customerName.value.trim()
  if (name.length < 2) {
    sendError.value = 'Escribí tu nombre (al menos 2 letras) para que el personal sepa de quién es el pedido.'
    document.getElementById('customer-name')?.focus()
    return
  }

  if (!method.value) {
    sendError.value = 'Elegí cómo vas a pagar.'
    return
  }

  sending.value = true
  sendError.value = ''

  try {
    // El mismo token en cada reintento evita que un corte de conexión duplique el pedido.
    const id = await createOrder(tableNumber.value, payload(), name, submitToken(tableNumber.value), method.value)

    setName(name)
    clearSubmitToken(tableNumber.value)
    clear()
    sheetOpen.value = false

    await router.push({ name: 'order-status', params: { id } })
  } catch (error) {
    sendError.value = friendlyError(error)

    if (isProductUnavailable(error)) await load()
  } finally {
    sending.value = false
  }
}

watch(count, (value) => {
  if (value === 0) sheetOpen.value = false
})

watch(tableNumber, () => {
  void checkTableOrders()
})

/* ---------- Ciclo de vida ---------- */

function onVisible() {
  if (document.visibilityState === 'visible') {
    void load()
    void checkTableOrders()
  }
}

onMounted(() => {
  document.title = `Mesa ${tableNumber.value || ''} · ${businessName}`.replace('  ', ' ')

  void load()
  void checkTableOrders()
  document.addEventListener('visibilitychange', onVisible)
})

onUnmounted(() => {
  document.removeEventListener('visibilitychange', onVisible)
})
</script>

<template>
  <div class="min-h-dvh bg-paper text-ink" :class="{ 'pb-28': count > 0 }">
    <!-- Cabecera -->
    <header class="wrap pb-6 pt-10 sm:pt-14">
      <p class="text-[13px] font-medium text-ink-soft">{{ businessName }}</p>

      <h1
        class="font-display mt-2 text-[clamp(3rem,14vw,5.5rem)] font-semibold leading-[0.92] tracking-[-0.02em]"
      >
        <template v-if="tableNumber">Mesa {{ tableNumber }}</template>
        <template v-else>Pedido</template>
      </h1>

      <p class="font-display mt-4 max-w-md text-lg italic leading-snug text-ink-soft">
        Elegí lo que quieras y enviá el pedido desde acá.
      </p>
    </header>

    <div class="wrap">
      <div class="h-[3px] bg-ink"></div>
      <div class="mt-[3px] h-px bg-ink"></div>
    </div>

    <!-- Estados: sin configurar, cargando, error, mesa inválida -->
    <div v-if="!isSupabaseConfigured" class="wrap">
      <ConfigMissing />
    </div>

    <div v-else-if="loading" class="wrap py-16 text-center" aria-busy="true">
      <p class="font-display text-xl italic text-ink-soft">Cargando la carta…</p>
    </div>

    <div v-else-if="loadError && !products.length" class="wrap py-14 text-center" role="alert">
      <p class="font-display text-xl italic text-ink-soft">{{ loadError }}</p>
      <button type="button" class="btn-line mt-5" @click="retry">Reintentar</button>
    </div>

    <div v-else-if="!tableValid" class="wrap py-14" role="alert">
      <h2 class="font-display text-2xl font-semibold leading-tight">Esta mesa no existe</h2>
      <p class="mt-2 max-w-md text-[15px] text-ink-soft">
        No encontramos la mesa «{{ route.params.table }}». Pedile al personal que revise el código
        QR de tu mesa. Mientras tanto, podés mirar la carta sin pedir.
      </p>
      <RouterLink :to="{ name: 'menu' }" class="btn-line mt-5">Ver la carta</RouterLink>
    </div>

    <!-- Carta con pedido -->
    <template v-else>
      <section v-if="tableOrders.length" class="wrap pt-6" aria-labelledby="table-orders-title">
        <h2 id="table-orders-title" class="font-display text-xl font-semibold leading-none">
          Pedidos de esta mesa
        </h2>

        <ul class="mt-3 space-y-2">
          <li v-for="order in tableOrders" :key="order.id">
            <RouterLink
              :to="{ name: 'order-status', params: { id: order.id } }"
              class="block border border-ink bg-paper-deep px-4 py-3 transition-colors hover:bg-rule/40"
            >
              <span class="flex items-center justify-between gap-3">
                <span class="text-[15px]">
                  <strong class="font-semibold">{{ STATUS_LABEL[order.status] }}</strong>
                  <span class="ml-2 tabular-nums text-ink-soft">{{ formatClock(order.created_at) }}</span>
                </span>
                <span class="inline-flex shrink-0 items-center gap-1 text-sm font-semibold">
                  Ver estado
                  <ChevronRight class="size-4" aria-hidden="true" />
                </span>
              </span>
              <span class="mt-1 block text-sm text-ink-soft">{{ itemsText(order) }}</span>
            </RouterLink>
          </li>
        </ul>
      </section>

      <div v-if="notice" class="wrap pt-6">
        <p class="border border-accent px-4 py-3 text-[15px] text-accent-deep" role="status">
          {{ notice }}
        </p>
      </div>

      <nav
        class="sticky top-0 z-20 mt-4 border-b border-rule bg-paper"
        aria-label="Categorías de la carta"
      >
        <div class="wrap">
          <div class="no-scrollbar -mx-1 flex gap-6 overflow-x-auto px-1">
            <button
              v-for="category in [{ id: 'all', name: 'Todos' }, ...navCategories]"
              :key="category.id"
              type="button"
              class="relative shrink-0 py-3.5 text-sm font-medium transition-colors"
              :class="
                selectedCategory === category.id ? 'text-ink' : 'text-ink-soft hover:text-ink'
              "
              :aria-pressed="selectedCategory === category.id"
              @click="selectCategory(category.id, $event)"
            >
              {{ category.name }}
              <span
                v-if="selectedCategory === category.id"
                class="absolute inset-x-0 -bottom-px h-0.5 bg-accent"
              ></span>
            </button>
          </div>
        </div>
      </nav>

      <main class="wrap pb-6">
        <section
          v-for="group in groups"
          :key="group.id"
          class="pt-9"
          :aria-labelledby="`cat-${group.id}`"
        >
          <h2
            :id="`cat-${group.id}`"
            class="font-display border-b border-ink pb-2.5 text-[1.75rem] font-semibold leading-none tracking-tight"
          >
            {{ group.name }}
          </h2>

          <div class="md:grid md:grid-cols-2 md:gap-x-12">
            <article
              v-for="product in group.products"
              :key="product.id"
              class="flex gap-4 py-4"
            >
              <img
                v-if="product.image"
                :src="product.image"
                alt=""
                loading="lazy"
                class="size-[72px] shrink-0 rounded-[3px] bg-paper-deep object-cover"
                :class="{ grayscale: !product.available }"
              />
              <div
                v-else
                class="font-display flex size-[72px] shrink-0 items-center justify-center rounded-[3px] bg-paper-deep text-2xl text-ink-soft"
                aria-hidden="true"
              >
                {{ product.name.charAt(0) }}
              </div>

              <div class="min-w-0 flex-1">
                <div class="flex items-baseline gap-2" :class="{ 'opacity-60': !product.available }">
                  <h3 class="font-display text-[1.1875rem] font-medium leading-snug">
                    {{ product.name }}
                  </h3>
                  <span class="leader" aria-hidden="true"></span>
                  <span class="whitespace-nowrap font-semibold tabular-nums">
                    {{ formatPrice(product.price) }}
                  </span>
                </div>

                <p
                  v-if="product.description"
                  class="mt-1 text-[15px] leading-snug text-ink-soft"
                  :class="{ 'opacity-60': !product.available }"
                >
                  {{ product.description }}
                </p>

                <div class="mt-2.5 flex justify-end">
                  <span
                    v-if="!product.available"
                    class="border border-ink-soft/50 px-2.5 py-1.5 text-xs font-semibold uppercase tracking-wide text-ink-soft"
                  >
                    Agotado
                  </span>

                  <QtyStepper
                    v-else-if="qtyOf(product.id) > 0"
                    :qty="qtyOf(product.id)"
                    :name="product.name"
                    @inc="inc(product.id)"
                    @dec="dec(product.id)"
                  />

                  <button
                    v-else
                    type="button"
                    class="btn-line btn-small"
                    :aria-label="`Agregar ${product.name} al pedido`"
                    @click="add(product)"
                  >
                    <Plus class="size-4" aria-hidden="true" />
                    Agregar
                  </button>
                </div>
              </div>
            </article>
          </div>
        </section>

        <p v-if="!groups.length" class="py-16 text-center font-display text-xl italic text-ink-soft">
          Por ahora no hay productos en la carta.
        </p>

        <p class="pt-10 text-center text-xs text-ink-soft">Precios en pesos argentinos.</p>
      </main>
    </template>

    <!-- Barra del pedido -->
    <div
      v-if="count > 0 && tableValid"
      class="fixed inset-x-0 bottom-0 z-30 border-t border-ink bg-paper pb-[env(safe-area-inset-bottom)]"
    >
      <div class="wrap py-3">
        <button type="button" class="btn-solid w-full justify-between" @click="openCart">
          <span>Ver pedido · {{ count }} {{ count === 1 ? 'producto' : 'productos' }}</span>
          <span class="tabular-nums">{{ formatPrice(total) }}</span>
        </button>
      </div>
    </div>

    <!-- Hoja del pedido -->
    <BottomSheet :open="sheetOpen" title="Tu pedido" @close="sheetOpen = false">
      <ul class="divide-y divide-rule border-b border-rule">
        <li v-for="line in lines" :key="line.productId" class="py-4">
          <div class="flex items-baseline gap-2">
            <span class="font-display text-lg font-medium leading-snug">{{ line.name }}</span>
            <span class="leader" aria-hidden="true"></span>
            <span class="whitespace-nowrap font-semibold tabular-nums">
              {{ formatPrice(line.price * line.qty) }}
            </span>
          </div>

          <div class="mt-2.5 flex items-center justify-between gap-3">
            <input
              v-model="line.note"
              type="text"
              maxlength="200"
              placeholder="Aclaración (opcional)"
              :aria-label="`Aclaración para ${line.name}`"
              class="field min-w-0 flex-1 !py-2 text-sm"
            />
            <QtyStepper
              :qty="line.qty"
              :name="line.name"
              @inc="inc(line.productId)"
              @dec="dec(line.productId)"
            />
          </div>
        </li>
      </ul>

      <p class="flex items-baseline justify-between py-4">
        <span class="font-display text-xl font-semibold">Total</span>
        <span class="text-xl font-semibold tabular-nums">{{ formatPrice(total) }}</span>
      </p>

      <div class="border-t border-rule pt-4">
        <label for="customer-name" class="mb-1.5 block text-sm font-medium">Tu nombre</label>
        <input
          id="customer-name"
          v-model="customerName"
          type="text"
          maxlength="60"
          autocomplete="given-name"
          placeholder="Para que el personal sepa de quién es"
          class="field"
        />
      </div>

      <div class="mt-4 border-t border-rule pt-4" role="group" aria-labelledby="pay-method-label">
        <p id="pay-method-label" class="mb-2 text-sm font-medium">¿Cómo vas a pagar?</p>

        <p v-if="!enabledMethods.length" class="text-sm text-accent-deep">
          El local todavía no configuró formas de pago. Consultá con el personal.
        </p>

        <div class="grid grid-cols-2 gap-2">
          <label
            v-for="option in enabledMethods"
            :key="option"
            class="flex cursor-pointer items-center justify-center border px-3 py-3 text-[15px] font-semibold transition-colors"
            :class="
              method === option
                ? 'border-ink bg-ink text-paper'
                : 'border-ink/40 hover:border-ink'
            "
          >
            <input v-model="method" type="radio" name="payment-method" :value="option" class="sr-only" />
            {{ PAYMENT_LABEL[option] }}
          </label>
        </div>

        <p v-if="method" class="mt-2 text-sm text-ink-soft">{{ PAYMENT_HINT[method] }}</p>
      </div>

      <div v-if="method === 'transfer'" class="mt-4">
        <PaymentInfo :settings="settings" />
      </div>

      <p v-if="sendError" class="mt-4 text-sm font-medium text-accent-deep" role="alert">
        {{ sendError }}
      </p>

      <button type="button" class="btn-solid mt-5 w-full" :disabled="sending" @click="send">
        {{ sending ? 'Enviando…' : `Enviar pedido · ${formatPrice(total)}` }}
      </button>

      <p class="mt-3 text-center text-xs text-ink-soft">
        El personal va a confirmar tu pedido en un momento.
      </p>
    </BottomSheet>
  </div>
</template>
