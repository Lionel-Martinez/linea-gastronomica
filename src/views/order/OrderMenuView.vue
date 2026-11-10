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
  createRemoteOrder,
  friendlyError,
  getTableOrders,
  isProductUnavailable,
  loadMenu,
  loadZones
} from '../../lib/api'
import { businessName, formatClock, formatPrice } from '../../lib/format'
import { geoErrorMessage, geolocationSupported, getPosition } from '../../lib/geo'
import {
  clearSubmitToken,
  forgetMyData,
  getContact,
  hasSavedData,
  getName,
  setContact,
  setLastCode,
  setName,
  submitToken
} from '../../lib/lastOrder'
import { isSupabaseConfigured } from '../../lib/supabase'
import {
  MODALITY_LABEL,
  PAYMENT_HINT,
  PAYMENT_HINT_REMOTE,
  PAYMENT_LABEL,
  PAYMENT_METHODS,
  STATUS_LABEL,
  type Category,
  type DeliveryZone,
  type PaymentMethod,
  type Product,
  type Settings,
  type TableOrder
} from '../../lib/types'

const route = useRoute()
const router = useRouter()

// /pedir = pedido a distancia (retiro o delivery); /mesa/N = pedido desde la mesa.
const remote = computed(() => route.name === 'remote-order')

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

const cartKey = computed<number | string>(() => (remote.value ? 'remote' : tableNumber.value))

const { lines, count, total, qtyOf, add, inc, dec, clear, reconcile, payload } = useCart(cartKey)

const tableValid = computed(
  () =>
    remote.value ||
    (tableNumber.value >= 1 && tableNumber.value <= (settings.value?.table_count ?? 0))
)

const zones = ref<DeliveryZone[]>([])

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
    const canOrder = remote.value
      ? data.settings.pickup_enabled || data.settings.delivery_enabled
      : data.settings.ordering_enabled

    if (!canOrder) {
      await router.replace({ name: 'menu' })
      return
    }

    if (remote.value && data.settings.delivery_enabled) {
      zones.value = (await loadZones()).filter((zone) => zone.active)
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
  if (remote.value || !tableNumber.value || !isSupabaseConfigured) {
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

// Pedido a distancia: cómo lo recibe y los datos de contacto y entrega.
const saved = getContact()
const modality = ref<'pickup' | 'delivery' | ''>('')
const phone = ref(saved.phone)
const zoneId = ref(saved.zone)
const street = ref(saved.street)
const streetNumber = ref(saved.number)
const reference = ref(saved.reference)
const cashFrom = ref('')

// «Olvidar mis datos»: borra lo que este celular recuerda (útil en celulares compartidos).
const canForget = ref(hasSavedData())
const forgotten = ref(false)

function forgetData() {
  forgetMyData()
  customerName.value = ''
  phone.value = ''
  zoneId.value = ''
  street.value = ''
  streetNumber.value = ''
  reference.value = ''
  canForget.value = false
  forgotten.value = true
}

// Ubicación opcional para delivery: deja que el repartidor avise solo cuando está cerca.
const destPoint = ref<{ lat: number; lng: number; accuracy: number | null } | null>(null)
const locating = ref(false)
const locError = ref('')

async function useMyLocation() {
  if (locating.value) return
  locating.value = true
  locError.value = ''

  try {
    destPoint.value = await getPosition()
  } catch (e) {
    destPoint.value = null
    locError.value = geoErrorMessage(e)
  } finally {
    locating.value = false
  }
}

const enabledModalities = computed(() =>
  (['pickup', 'delivery'] as const).filter((m) =>
    m === 'pickup' ? settings.value?.pickup_enabled : settings.value?.delivery_enabled
  )
)

watch(
  enabledModalities,
  (list) => {
    if (!remote.value) return
    if (modality.value && !list.includes(modality.value)) modality.value = ''
    if (!modality.value && list.length === 1) modality.value = list[0]!
  },
  { immediate: true }
)

const selectedZone = computed(() => zones.value.find((zone) => zone.id === zoneId.value) ?? null)
const fee = computed(() => (remote.value && modality.value === 'delivery' ? (selectedZone.value?.fee ?? 0) : 0))
const grandTotal = computed(() => total.value + fee.value)

// Formas de pago que el local aceptó en Ajustes, en orden fijo.
// En delivery solo transferencia y efectivo (tarjeta y QR necesitarían posnet portátil).
const enabledMethods = computed(() =>
  PAYMENT_METHODS.filter(
    (m) =>
      settings.value?.payment_methods.includes(m) &&
      !(remote.value && modality.value === 'delivery' && m !== 'transfer' && m !== 'cash')
  )
)

const methodHint = computed(() => {
  if (!method.value) return ''
  if (!remote.value) return PAYMENT_HINT[method.value]
  return (
    PAYMENT_HINT_REMOTE[modality.value || 'pickup'][method.value] ?? PAYMENT_HINT[method.value]
  )
})

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

function fail(message: string, focusId?: string) {
  sendError.value = message
  if (focusId) document.getElementById(focusId)?.focus()
}

async function send() {
  if (!lines.value.length || sending.value) return

  const name = customerName.value.trim()
  if (name.length < 2) {
    return fail(
      remote.value
        ? 'Escribí tu nombre (al menos 2 letras) para que el local sepa de quién es el pedido.'
        : 'Escribí tu nombre (al menos 2 letras) para que el personal sepa de quién es el pedido.',
      'customer-name'
    )
  }

  const phoneDigits = phone.value.replace(/\D/g, '')
  const street_ = street.value.trim()
  const number_ = streetNumber.value.trim()
  let cash: number | null = null

  if (remote.value) {
    if (!modality.value) return fail('Elegí cómo lo recibís: retirar o delivery.')

    if (phoneDigits.length < 8 || phoneDigits.length > 15) {
      return fail('Escribí un teléfono válido, con código de área (entre 8 y 15 números).', 'customer-phone')
    }

    if (modality.value === 'delivery') {
      if (!selectedZone.value) return fail('Elegí tu zona de entrega.', 'delivery-zone')
      if (street_.length < 2) return fail('Escribí la calle de la entrega.', 'delivery-street')
      if (!number_) return fail('Escribí el número (o «s/n»).', 'delivery-number')
    }
  }

  if (!method.value) return fail('Elegí cómo vas a pagar.')

  if (remote.value && modality.value === 'delivery' && method.value === 'cash' && cashFrom.value.trim()) {
    cash = Number(cashFrom.value.replace(',', '.'))
    if (!Number.isFinite(cash) || cash < grandTotal.value) {
      return fail('El monto con el que pagás tiene que cubrir el total del pedido.', 'cash-from')
    }
  }

  sending.value = true
  sendError.value = ''

  try {
    if (remote.value) {
      // El mismo token en cada reintento evita que un corte de conexión duplique el pedido.
      const created = await createRemoteOrder({
        modality: modality.value as 'pickup' | 'delivery',
        items: payload(),
        name,
        phone: phoneDigits,
        method: method.value,
        token: submitToken('remote'),
        zone: modality.value === 'delivery' ? zoneId.value : null,
        street: street_,
        number: number_,
        reference: reference.value.trim(),
        cashFrom: cash,
        destLat: modality.value === 'delivery' ? (destPoint.value?.lat ?? null) : null,
        destLng: modality.value === 'delivery' ? (destPoint.value?.lng ?? null) : null
      })

      setName(name)
      setContact({
        phone: phone.value.trim(),
        zone: zoneId.value,
        street: street_,
        number: number_,
        reference: reference.value.trim()
      })
      setLastCode(created.tracking_code)
      clearSubmitToken('remote')
      clear()
      sheetOpen.value = false

      await router.push({ name: 'track', params: { code: created.tracking_code }, query: { nuevo: '1' } })
      return
    }

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
  document.title = remote.value
    ? `Pedí desde casa · ${businessName}`
    : `Mesa ${tableNumber.value || ''} · ${businessName}`.replace('  ', ' ')

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
        <template v-if="remote">Pedí desde casa</template>
        <template v-else-if="tableNumber">Mesa {{ tableNumber }}</template>
        <template v-else>Pedido</template>
      </h1>

      <p class="font-display mt-4 max-w-md text-lg italic leading-snug text-ink-soft">
        {{
          remote
            ? 'Elegí lo que quieras, retiralo o pedí delivery, y seguí tu pedido con un código.'
            : 'Elegí lo que quieras y enviá el pedido desde acá.'
        }}
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

      <dl v-if="fee > 0 || (remote && modality === 'delivery' && selectedZone)" class="space-y-1 pt-4 text-[15px]">
        <div class="flex items-baseline justify-between">
          <dt class="text-ink-soft">Productos</dt>
          <dd class="tabular-nums">{{ formatPrice(total) }}</dd>
        </div>
        <div class="flex items-baseline justify-between">
          <dt class="text-ink-soft">Envío ({{ selectedZone?.name }})</dt>
          <dd class="tabular-nums">{{ formatPrice(fee) }}</dd>
        </div>
      </dl>

      <p class="flex items-baseline justify-between py-4">
        <span class="font-display text-xl font-semibold">Total</span>
        <span class="text-xl font-semibold tabular-nums">{{ formatPrice(grandTotal) }}</span>
      </p>

      <!-- Pedido a distancia: cómo lo recibe y datos de contacto -->
      <template v-if="remote">
        <div class="border-t border-rule pt-4" role="group" aria-labelledby="modality-label">
          <p id="modality-label" class="mb-2 text-sm font-medium">¿Cómo lo recibís?</p>

          <div class="grid grid-cols-2 gap-2">
            <label
              v-for="option in enabledModalities"
              :key="option"
              class="flex cursor-pointer items-center justify-center border px-3 py-3 text-[15px] font-semibold transition-colors"
              :class="modality === option ? 'border-ink bg-ink text-paper' : 'border-ink/40 hover:border-ink'"
            >
              <input v-model="modality" type="radio" name="modality" :value="option" class="sr-only" />
              {{ MODALITY_LABEL[option] }}
            </label>
          </div>
        </div>

        <div class="mt-4">
          <label for="customer-phone" class="mb-1.5 block text-sm font-medium">Tu teléfono</label>
          <input
            id="customer-phone"
            v-model="phone"
            type="tel"
            inputmode="tel"
            autocomplete="tel"
            maxlength="25"
            placeholder="Con código de área, ej. 387 555 1234"
            class="field"
          />
        </div>

        <template v-if="modality === 'delivery'">
          <div class="mt-4">
            <label for="delivery-zone" class="mb-1.5 block text-sm font-medium">Zona de entrega</label>
            <select id="delivery-zone" v-model="zoneId" class="field">
              <option value="" disabled>Elegí tu zona</option>
              <option v-for="zone in zones" :key="zone.id" :value="zone.id">
                {{ zone.name }} · envío {{ formatPrice(zone.fee) }}
              </option>
            </select>
            <p v-if="!zones.length" class="mt-1.5 text-sm text-accent-deep">
              El local todavía no cargó zonas de entrega. Consultá con el local.
            </p>
          </div>

          <div class="mt-4 grid grid-cols-[1fr_7rem] gap-3">
            <div>
              <label for="delivery-street" class="mb-1.5 block text-sm font-medium">Calle</label>
              <input
                id="delivery-street"
                v-model="street"
                type="text"
                maxlength="80"
                autocomplete="address-line1"
                class="field"
              />
            </div>
            <div>
              <label for="delivery-number" class="mb-1.5 block text-sm font-medium">Número</label>
              <input id="delivery-number" v-model="streetNumber" type="text" maxlength="10" class="field" />
            </div>
          </div>

          <div class="mt-4">
            <label for="delivery-ref" class="mb-1.5 block text-sm font-medium">Referencia (opcional)</label>
            <input
              id="delivery-ref"
              v-model="reference"
              type="text"
              maxlength="120"
              placeholder="Portón negro, esquina con…, timbre"
              class="field"
            />
          </div>

          <div v-if="geolocationSupported()" class="mt-4 border border-ink/40 p-3">
            <p class="text-sm font-medium">Ubicación de la entrega (opcional)</p>
            <p class="mt-1 text-sm text-ink-soft">
              Si la compartís, el repartidor te avisa solo cuando está cerca y ves a qué distancia viene.
              Se usa únicamente para este pedido.
            </p>

            <p v-if="destPoint" class="mt-2 text-sm font-semibold text-open" role="status">
              Ubicación guardada<template v-if="destPoint.accuracy"> (precisión de unos {{ Math.round(destPoint.accuracy) }} m)</template>.
              <button type="button" class="ml-1 font-normal underline underline-offset-4" @click="destPoint = null">
                Quitar
              </button>
            </p>

            <button v-else type="button" class="btn-line btn-small mt-3" :disabled="locating" @click="useMyLocation">
              {{ locating ? 'Buscando tu ubicación…' : 'Usar mi ubicación' }}
            </button>

            <p v-if="locError" class="mt-2 text-sm text-accent-deep" role="alert">{{ locError }}</p>
          </div>
        </template>
      </template>

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

        <p v-if="method" class="mt-2 text-sm text-ink-soft">{{ methodHint }}</p>
      </div>

      <div v-if="remote && modality === 'delivery' && method === 'cash'" class="mt-4">
        <label for="cash-from" class="mb-1.5 block text-sm font-medium">¿Con cuánto pagás? (opcional)</label>
        <input
          id="cash-from"
          v-model="cashFrom"
          type="text"
          inputmode="numeric"
          placeholder="Para que lleven el vuelto"
          class="field"
        />
      </div>

      <div v-if="method === 'transfer'" class="mt-4">
        <PaymentInfo :settings="settings" />
      </div>

      <p v-if="sendError" class="mt-4 text-sm font-medium text-accent-deep" role="alert">
        {{ sendError }}
      </p>

      <button type="button" class="btn-solid mt-5 w-full" :disabled="sending" @click="send">
        {{ sending ? 'Enviando…' : `Enviar pedido · ${formatPrice(grandTotal)}` }}
      </button>

      <p class="mt-3 text-center text-xs text-ink-soft">
        {{
          remote
            ? 'El local va a confirmar tu pedido. Después podés seguirlo con el código que te damos.'
            : 'El personal va a confirmar tu pedido en un momento.'
        }}
      </p>

      <p v-if="remote" class="mt-3 text-xs leading-relaxed text-ink-soft">
        Privacidad: usamos tu teléfono y tu dirección solo para este pedido y se borran
        {{ settings?.retention_days ?? 15 }} días después de terminado. Quien tenga tu código ve el
        estado del pedido, pero no tus datos. Si va en delivery, los demás clientes de la misma salida
        ven {{ settings?.stops_visibility === 'zone' ? 'tu zona' : 'la calle de tu entrega (sin número)' }}.
        Si compartís tu ubicación, se borra junto con tus demás datos y nadie la ve en pantalla.
      </p>

      <p v-if="remote && (canForget || forgotten)" class="mt-2 text-xs text-ink-soft">
        <button v-if="canForget" type="button" class="min-h-11 underline underline-offset-4" @click="forgetData">
          Olvidar mis datos guardados en este celular
        </button>
        <span v-else role="status">Listo: este celular ya no recuerda tus datos.</span>
      </p>
    </BottomSheet>
  </div>
</template>
