<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import {
  ArrowUp,
  ArrowUpRight,
  Check,
  Clock,
  Copy,
  Mail,
  MapPin,
  MessageCircle,
  Phone,
  Search,
  Star,
  Wifi,
  X
} from '@lucide/vue'
import menuData from '../../data/menu.json'
import { useDialogFocus } from '../../composables/useDialogFocus'
import { loadMenu } from '../../lib/api'
import { formatPrice } from '../../lib/format'
import { isSupabaseConfigured } from '../../lib/supabase'

interface MenuCategory {
  id: string
  name: string
}

interface MenuProduct {
  id: string | number
  name: string
  description: string
  price: number
  category: string
  image: string
  featured: boolean
  available: boolean
}

interface Shift {
  open: string
  close: string
}

interface Day {
  id: number
  name: string
  closed: boolean
  shifts: Shift[]
}

type Modal = 'hours' | 'wifi' | 'opinion' | null

// URL del portafolio de quien desarrolla el menú. Si queda vacío, el enlace no se muestra.
const PORTFOLIO_URL = ''

const WEEKDAYS: Record<string, number> = {
  Sunday: 0,
  Monday: 1,
  Tuesday: 2,
  Wednesday: 3,
  Thursday: 4,
  Friday: 5,
  Saturday: 6
}

const business = menuData.business
const schedule = business.schedule
const days = schedule.days as Day[]
const wifi = business.wifi
const contact = business.contact
const social = business.social
const links = business.links

// Modalidades de atención: solo se muestran las habilitadas (con todas apagadas no se muestra nada).
const modalities = computed(() =>
  (business.modalities as { id: string; label: string; enabled: boolean }[]).filter(
    (modality) => modality.enabled
  )
)
// Datos de ejemplo (menu.json). Si hay Supabase configurado se reemplazan por los reales,
// así lo que el personal edita (precios, "Agotado") se ve también en la carta.
const allCategories = ref<MenuCategory[]>(menuData.categories)
const products = ref<MenuProduct[]>(menuData.products)
const categories = computed(() => allCategories.value.filter((category) => category.id !== 'all'))

// En la botonera solo van las categorías que tienen productos (una vacía dejaría la pantalla en blanco).
const navCategories = computed(() =>
  allCategories.value.filter(
    (category) =>
      category.id === 'all' || products.value.some((product) => product.category === category.id)
  )
)

// Fotos que no cargaron (mala conexión o enlace caído): se muestra el recuadro neutro en su lugar.
const failedImages = ref(new Set<string | number>())
const imageOk = (product: MenuProduct) => Boolean(product.image) && !failedImages.value.has(product.id)

const categoryName = (id: string) => allCategories.value.find((category) => category.id === id)?.name ?? ''

watch(navCategories, (list) => {
  if (!list.some((category) => category.id === selectedCategory.value)) selectedCategory.value = 'all'
})

async function loadLiveMenu() {
  if (!isSupabaseConfigured) return

  try {
    const live = await loadMenu()
    if (!live.products.length) return

    allCategories.value = [
      { id: 'all', name: menuData.categories.find((c) => c.id === 'all')?.name ?? 'Todo' },
      ...live.categories.map((category) => ({ id: category.id, name: category.name }))
    ]
    products.value = live.products.map((product) => ({
      id: product.id,
      name: product.name,
      description: product.description,
      price: product.price,
      category: product.category_id,
      image: product.image,
      featured: product.featured,
      available: product.available
    }))
  } catch {
    // Sin conexión o sin configurar: se queda la carta de ejemplo.
  }
}

const selectedCategory = ref('all')
const search = ref('')
const activeModal = ref<Modal>(null)
const dialogEl = ref<HTMLElement | null>(null)
useDialogFocus(
  computed(() => activeModal.value !== null),
  dialogEl
)
const copied = ref(false)
const selectedRating = ref(0)
const opinionName = ref('')
const opinionType = ref('local')
const opinionMessage = ref('')

const sendingOpinion = ref(false)
const opinionStatus = ref('')
const opinionStatusType = ref<'success' | 'error' | ''>('')

const web3formsKey = import.meta.env.VITE_WEB3FORMS_ACCESS_KEY

/* ---------- Hora y estado de apertura ---------- */

const now = ref(new Date())
let clock: number | undefined

const currentDay = computed(() => {
  const weekday = new Intl.DateTimeFormat('en-US', {
    weekday: 'long',
    timeZone: schedule.timezone
  }).format(now.value)

  return WEEKDAYS[weekday]
})

const today = computed(() => days.find((day) => day.id === currentDay.value))

const currentTime = computed(() =>
  new Intl.DateTimeFormat('en-GB', {
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
    timeZone: schedule.timezone
  }).format(now.value)
)

const openShift = computed(() => {
  if (!today.value || today.value.closed) return undefined

  return today.value.shifts.find(
    (shift) => currentTime.value >= shift.open && currentTime.value < shift.close
  )
})

const isOpen = computed(() => Boolean(openShift.value))

const statusText = computed(() => {
  if (!today.value || today.value.closed || !today.value.shifts.length) {
    return 'Hoy cerramos'
  }

  if (openShift.value) {
    return `Abierto hasta las ${openShift.value.close}`
  }

  const nextShift = today.value.shifts.find((shift) => currentTime.value < shift.open)
  return nextShift ? `Cerrado · abrimos a las ${nextShift.open}` : 'Cerrado por hoy'
})

const todayHours = computed(() => {
  if (!today.value || today.value.closed || !today.value.shifts.length) return 'Cerrado'
  return today.value.shifts.map((shift) => `${shift.open} – ${shift.close}`).join(' · ')
})

/* ---------- Carta ---------- */

const normalize = (text: string) =>
  text
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')

const visibleProducts = computed(() => {
  const term = normalize(search.value.trim())

  return products.value.filter((product) => {
    if (!term) return true

    return (
      normalize(product.name).includes(term) ||
      normalize(product.description).includes(term) ||
      normalize(categoryName(product.category)).includes(term)
    )
  })
})

const groups = computed(() =>
  categories.value
    .filter(
      (category) =>
        selectedCategory.value === 'all' || category.id === selectedCategory.value
    )
    .map((category) => ({
      ...category,
      products: visibleProducts.value.filter(
        (product) => product.category === category.id
      )
    }))
    .filter((group) => group.products.length)
)

const featuredProducts = computed(() =>
  products.value.filter((product) => product.featured && product.available)
)

const showFeatured = computed(
  () => selectedCategory.value === 'all' && !search.value && featuredProducts.value.length
)


function selectCategory(id: string, event: Event) {
  selectedCategory.value = id

  ;(event.currentTarget as HTMLElement).scrollIntoView({
    behavior: 'smooth',
    block: 'nearest',
    inline: 'center'
  })
}

function resetFilters() {
  search.value = ''
  selectedCategory.value = 'all'
}

/* ---------- Enlaces ---------- */

const mapsUrl = computed(
  () =>
    links.googleMaps ||
    `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(business.address)}`
)

const whatsappUrl = computed(() => {
  const value = contact.whatsapp.trim()

  if (!value) return ''

  // Permite ingresar un enlace completo o solamente el número.
  if (value.startsWith('http')) return value

  const phone = value.replace(/\D/g, '')
  return phone ? `https://wa.me/${phone}` : ''
})

// Acepta un enlace completo o solamente el usuario (con o sin @).
function socialUrl(value: string, base: string) {
  const handle = value.trim()

  if (!handle) return ''
  if (handle.startsWith('http')) return handle

  return base + handle.replace(/^@/, '')
}

const socialLinks = computed(() =>
  [
    { name: 'Instagram', url: socialUrl(social.instagram, 'https://instagram.com/') },
    { name: 'Facebook', url: socialUrl(social.facebook, 'https://facebook.com/') },
    { name: 'TikTok', url: socialUrl(social.tiktok, 'https://tiktok.com/@') }
  ].filter((item) => item.url)
)

/* ---------- Acciones ---------- */

async function copyWifiPassword() {
  try {
    await navigator.clipboard.writeText(wifi.password)
    copied.value = true

    window.setTimeout(() => {
      copied.value = false
    }, 2000)
  } catch {
    copied.value = false
  }
}

function scrollToTop() {
  window.scrollTo({
    top: 0,
    behavior: 'smooth'
  })
}

async function sendOpinion() {
  if (!selectedRating.value || !opinionMessage.value.trim()) {
    opinionStatus.value = 'Seleccioná una puntuación y escribí tu comentario.'
    opinionStatusType.value = 'error'
    return
  }

  if (!web3formsKey) {
    opinionStatus.value = 'El formulario todavía no está configurado.'
    opinionStatusType.value = 'error'
    return
  }

  sendingOpinion.value = true
  opinionStatus.value = ''

  try {
    const response = await fetch('https://api.web3forms.com/submit', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json'
      },
      body: JSON.stringify({
        access_key: web3formsKey,
        subject: 'Nueva opinión del menú digital',
        from_name: opinionName.value.trim() || 'Cliente anónimo',
        rating: `${selectedRating.value} estrellas`,
        opinion_type: opinionType.value,
        message: opinionMessage.value.trim()
      })
    })

    const result = await response.json()

    if (!response.ok || !result.success) {
      throw new Error(result.message || 'No se pudo enviar la opinión.')
    }

    opinionStatus.value = '¡Gracias! Tu opinión fue enviada correctamente.'
    opinionStatusType.value = 'success'

    opinionName.value = ''
    opinionType.value = 'local'
    opinionMessage.value = ''
    selectedRating.value = 0
  } catch (error) {
    opinionStatus.value =
      error instanceof Error
        ? error.message
        : 'Ocurrió un error al enviar tu opinión.'

    opinionStatusType.value = 'error'
  } finally {
    sendingOpinion.value = false
  }
}

/* ---------- Ventana inferior ---------- */

const modalTitle = computed(() => {
  if (activeModal.value === 'hours') return 'Horarios'
  if (activeModal.value === 'wifi') return 'Wi-Fi'
  return 'Tu opinión'
})

function closeModal() {
  activeModal.value = null
}

function onKeydown(event: KeyboardEvent) {
  if (event.key === 'Escape') closeModal()
}

watch(activeModal, (value) => {
  // Evita que la página de fondo se desplace mientras la ventana está abierta.
  document.body.style.overflow = value ? 'hidden' : ''

  if (value !== 'opinion') opinionStatus.value = ''
})

onMounted(() => {
  document
    .querySelector('meta[name="description"]')
    ?.setAttribute(
      'content',
      `Carta digital de ${business.name}: productos y precios, horarios, Wi-Fi y contacto.`
    )
  void loadLiveMenu()
  document.title = `${business.name} · Menú`
  clock = window.setInterval(() => {
    now.value = new Date()
  }, 60_000)
  window.addEventListener('keydown', onKeydown)
})

onUnmounted(() => {
  window.clearInterval(clock)
  window.removeEventListener('keydown', onKeydown)
  document.body.style.overflow = ''
})
</script>

<template>
  <div class="min-h-dvh bg-paper text-ink">
    <!-- Cabecera -->
    <header class="wrap pb-7 pt-10 sm:pt-16">
      <p class="flex items-center gap-2 text-[13px] font-medium">
        <span
          class="size-2 rounded-full"
          :class="isOpen ? 'bg-open' : 'bg-ink-soft/50'"
          aria-hidden="true"
        ></span>
        {{ statusText }}
      </p>

      <h1
        class="font-display mt-5 text-balance text-[clamp(3rem,13vw,6rem)] font-semibold leading-[0.92] tracking-[-0.02em]"
      >
        {{ business.name }}
      </h1>

      <p class="font-display mt-5 max-w-md text-xl italic leading-snug text-ink-soft">
        {{ business.description }}
      </p>

      <a
        :href="mapsUrl"
        target="_blank"
        rel="noopener noreferrer"
        class="-ml-1 mt-3 inline-flex min-h-11 items-center gap-1.5 px-1 text-sm font-medium underline decoration-rule underline-offset-4 transition-colors hover:decoration-ink"
      >
        <MapPin class="size-4 shrink-0" aria-hidden="true" />
        {{ business.address }}
      </a>

      <ul
        v-if="modalities.length"
        class="mt-4 flex flex-wrap gap-x-2 gap-y-1.5"
        aria-label="Modalidades de atención"
      >
        <li
          v-for="modality in modalities"
          :key="modality.id"
          class="border border-ink px-2.5 py-1 text-xs font-semibold uppercase tracking-wide"
        >
          {{ modality.label }}
        </li>
      </ul>
    </header>

    <!-- Accesos rápidos -->
    <div class="wrap">
      <div class="h-[3px] bg-ink"></div>
      <div class="mt-[3px] h-px bg-ink"></div>

      <nav class="flex divide-x divide-rule" aria-label="Accesos rápidos">
        <a
          v-if="whatsappUrl"
          :href="whatsappUrl"
          target="_blank"
          rel="noopener noreferrer"
          class="action"
        >
          <MessageCircle class="size-5" aria-hidden="true" />
          WhatsApp
        </a>

        <button type="button" class="action" @click="activeModal = 'hours'">
          <Clock class="size-5" aria-hidden="true" />
          Horarios
        </button>

        <button v-if="wifi.available" type="button" class="action" @click="activeModal = 'wifi'">
          <Wifi class="size-5" aria-hidden="true" />
          Wi-Fi
        </button>

        <button type="button" class="action" @click="activeModal = 'opinion'">
          <Star class="size-5" aria-hidden="true" />
          Opinión
        </button>
      </nav>

      <div class="h-px bg-rule"></div>
    </div>

    <!-- Buscador -->
    <div class="wrap pt-6" role="search">
      <label class="flex min-h-11 items-center gap-3 border-b border-ink pb-1">
        <Search class="size-[18px] shrink-0 text-ink-soft" aria-hidden="true" />
        <span class="sr-only">Buscar en la carta</span>
        <input
          v-model="search"
          type="search"
          placeholder="Buscar en la carta"
          class="min-h-11 w-full bg-transparent py-2 text-base outline-none placeholder:text-ink-soft/80"
        />
      </label>
    </div>

    <!-- Categorías -->
    <nav
      class="sticky top-0 z-20 mt-2 border-b border-rule bg-paper"
      aria-label="Categorías de la carta"
    >
      <div class="wrap">
        <div class="no-scrollbar -mx-1 flex gap-6 overflow-x-auto px-1">
          <button
            v-for="category in navCategories"
            :key="category.id"
            type="button"
            class="relative min-w-11 shrink-0 py-3.5 text-sm font-medium transition-colors"
            :class="selectedCategory === category.id ? 'text-ink' : 'text-ink-soft hover:text-ink'"
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
      <!-- Favoritos -->
      <section v-if="showFeatured" class="pt-9">
        <h2 class="font-display text-[1.75rem] font-semibold leading-none tracking-tight">
          Favoritos de la casa
        </h2>

        <div
          tabindex="0"
          role="region"
          aria-label="Favoritos de la casa"
          class="no-scrollbar -mx-5 mt-5 flex snap-x snap-mandatory scroll-px-5 gap-4 overflow-x-auto px-5 pb-1 sm:-mx-8 sm:scroll-px-8 sm:px-8"
        >
          <article
            v-for="product in featuredProducts"
            :key="product.id"
            class="w-[46%] shrink-0 snap-start sm:w-52"
          >
            <img
              v-if="imageOk(product)"
              :src="product.image"
              alt=""
              loading="lazy"
              @error="failedImages.add(product.id)"
              class="aspect-[4/5] w-full rounded-[3px] bg-paper-deep object-cover"
            />
            <div v-else class="aspect-[4/5] w-full rounded-[3px] bg-paper-deep" aria-hidden="true"></div>
            <h3 class="font-display mt-3 text-lg font-medium leading-snug">
              {{ product.name }}
            </h3>
            <p class="mt-0.5 text-sm font-semibold tabular-nums text-accent">
              {{ formatPrice(product.price) }}
            </p>
          </article>
        </div>
      </section>

      <!-- Carta por categorías -->
      <section
        v-for="group in groups"
        :key="group.id"
        class="pt-10"
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
              v-if="imageOk(product)"
              :src="product.image"
              alt=""
              loading="lazy"
              @error="failedImages.add(product.id)"
              class="size-[72px] shrink-0 rounded-[3px] bg-paper-deep object-cover"
              :class="product.available ? '' : 'opacity-45 grayscale'"
            />
            <div v-else class="size-[72px] shrink-0 rounded-[3px] bg-paper-deep" aria-hidden="true"></div>

            <div class="min-w-0 flex-1">
              <div class="flex items-baseline gap-2">
                <h3
                  class="font-display text-[1.1875rem] font-medium leading-snug"
                  :class="product.available ? '' : 'text-ink-soft'"
                >
                  {{ product.name }}
                </h3>
                <span class="leader" aria-hidden="true"></span>
                <span
                  v-if="product.available"
                  class="whitespace-nowrap font-semibold tabular-nums"
                >
                  {{ formatPrice(product.price) }}
                </span>
                <span
                  v-else
                  class="whitespace-nowrap border border-accent px-1.5 py-0.5 text-xs font-semibold uppercase tracking-wide text-accent-deep"
                >
                  Agotado
                </span>
              </div>

              <p
                class="mt-1 text-[15px] leading-snug text-ink-soft"
                :class="product.available ? '' : 'opacity-70'"
              >
                {{ product.description }}
              </p>
            </div>
          </article>
        </div>
      </section>

      <!-- Sin resultados -->
      <div v-if="!groups.length" class="py-16 text-center">
        <p class="font-display text-xl italic text-ink-soft">
          No encontramos nada con esa búsqueda.
        </p>
        <button
          type="button"
          class="mt-4 text-sm font-semibold text-accent underline underline-offset-4 hover:text-accent-deep"
          @click="resetFilters"
        >
          Ver toda la carta
        </button>
      </div>

      <p class="pt-10 text-center text-xs text-ink-soft">Precios en pesos argentinos.</p>
    </main>

    <!-- Pie -->
    <footer class="mt-8 border-t-[3px] border-ink">
      <div class="wrap py-10">
        <div class="grid gap-10 sm:grid-cols-2">
          <div>
            <h2 class="font-display text-2xl font-semibold leading-tight">
              {{ business.name }}
            </h2>

            <a
              :href="mapsUrl"
              target="_blank"
              rel="noopener noreferrer"
              class="mt-1 inline-flex min-h-11 items-start gap-1.5 py-2.5 text-[15px] underline decoration-rule underline-offset-4 transition-colors hover:decoration-ink"
            >
              <MapPin class="mt-0.5 size-4 shrink-0" aria-hidden="true" />
              {{ business.address }}
            </a>

            <p class="mt-3 text-[15px] text-ink-soft">
              Hoy, {{ today?.name }}:
              <span class="font-medium tabular-nums text-ink">{{ todayHours }}</span>
            </p>

            <button type="button" class="btn-solid mt-6" @click="activeModal = 'opinion'">
              <Star class="size-4" aria-hidden="true" />
              Dejanos tu opinión
            </button>
          </div>

          <div
            v-if="whatsappUrl || contact.phone || contact.email || socialLinks.length || links.googleReviews"
          >
            <h2 class="font-display text-2xl font-semibold leading-tight">Contacto</h2>

            <ul class="mt-3 space-y-2.5 text-[15px]">
              <li v-if="whatsappUrl">
                <a
                  :href="whatsappUrl"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="inline-flex min-h-11 items-center gap-2 underline decoration-rule underline-offset-4 transition-colors hover:decoration-ink"
                >
                  <MessageCircle class="size-4" aria-hidden="true" />
                  Escribinos por WhatsApp
                </a>
              </li>

              <li v-if="contact.phone">
                <a
                  :href="`tel:${contact.phone}`"
                  class="inline-flex min-h-11 items-center gap-2 underline decoration-rule underline-offset-4 transition-colors hover:decoration-ink"
                >
                  <Phone class="size-4" aria-hidden="true" />
                  {{ contact.phone }}
                </a>
              </li>

              <li v-if="contact.email">
                <a
                  :href="`mailto:${contact.email}`"
                  class="inline-flex min-h-11 items-center gap-2 break-all underline decoration-rule underline-offset-4 transition-colors hover:decoration-ink"
                >
                  <Mail class="size-4 shrink-0" aria-hidden="true" />
                  {{ contact.email }}
                </a>
              </li>

              <li v-if="links.googleReviews">
                <a
                  :href="links.googleReviews"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="inline-flex min-h-11 items-center gap-2 underline decoration-rule underline-offset-4 transition-colors hover:decoration-ink"
                >
                  <Star class="size-4" aria-hidden="true" />
                  Opiniones en Google
                </a>
              </li>
            </ul>

            <p v-if="socialLinks.length" class="mt-5 flex flex-wrap gap-x-5 gap-y-2 text-[15px]">
              <a
                v-for="item in socialLinks"
                :key="item.name"
                :href="item.url"
                target="_blank"
                rel="noopener noreferrer"
                class="inline-flex min-h-11 items-center gap-1 font-medium text-accent underline-offset-4 hover:underline"
              >
                {{ item.name }}
                <ArrowUpRight class="size-4" aria-hidden="true" />
              </a>
            </p>
          </div>
        </div>

        <div
          class="mt-12 flex flex-col items-start justify-between gap-5 border-t border-rule pt-6 text-xs text-ink-soft sm:flex-row sm:items-center"
        >
          <p>
            Diseño y desarrollo por
            <a
              v-if="PORTFOLIO_URL"
              :href="PORTFOLIO_URL"
              target="_blank"
              rel="noopener noreferrer"
              class="font-semibold text-ink underline decoration-rule underline-offset-4 hover:decoration-ink"
            >
              LM Studio
            </a>
            <span v-else class="font-semibold text-ink">LM Studio</span>
            · © {{ new Date().getFullYear() }}
          </p>

          <button
            type="button"
            class="inline-flex min-h-11 items-center gap-1.5 text-sm font-medium text-ink transition-colors hover:text-accent"
            @click="scrollToTop"
          >
            <ArrowUp class="size-4" aria-hidden="true" />
            Volver al comienzo
          </button>
        </div>
      </div>
    </footer>

    <!-- Ventana inferior -->
    <Transition name="sheet">
      <div
        v-if="activeModal"
        class="fixed inset-0 z-50 flex items-end justify-center bg-ink/50 sm:items-center sm:p-6"
        @click.self="closeModal"
      >
        <section
          ref="dialogEl"
          tabindex="-1"
          class="sheet-panel max-h-[88dvh] w-full max-w-md overflow-y-auto rounded-t-[14px] bg-paper p-6 shadow-2xl sm:rounded-[6px]"
          role="dialog"
          aria-modal="true"
          aria-labelledby="sheet-title"
        >
          <div class="mb-5 flex items-center justify-between gap-4 border-b border-ink pb-3">
            <h2 id="sheet-title" class="font-display text-[1.625rem] font-semibold leading-none">
              {{ modalTitle }}
            </h2>

            <button
              type="button"
              aria-label="Cerrar ventana"
              class="-mr-2 flex size-10 items-center justify-center rounded-full transition-colors hover:bg-paper-deep"
              @click="closeModal"
            >
              <X class="size-5" aria-hidden="true" />
            </button>
          </div>

          <!-- Horarios -->
          <ul v-if="activeModal === 'hours'">
            <li
              v-for="day in days"
              :key="day.id"
              class="flex items-baseline gap-2 py-2 text-[15px]"
              :class="day.id === currentDay ? 'font-semibold text-ink' : 'text-ink-soft'"
            >
              <span>
                {{ day.name }}
                <span v-if="day.id === currentDay" class="ml-1.5 text-xs font-semibold text-accent">
                  Hoy
                </span>
              </span>

              <span class="leader" aria-hidden="true"></span>

              <span v-if="day.closed || !day.shifts.length">Cerrado</span>
              <span v-else class="flex flex-col items-end tabular-nums">
                <span v-for="(shift, index) in day.shifts" :key="index">
                  {{ shift.open }} – {{ shift.close }}
                </span>
              </span>
            </li>
          </ul>

          <!-- Wi-Fi -->
          <div v-else-if="activeModal === 'wifi'">
            <dl class="divide-y divide-rule border-y border-rule text-[15px]">
              <div class="flex items-baseline justify-between gap-4 py-3">
                <dt class="text-ink-soft">Red</dt>
                <dd class="break-all text-right font-semibold">{{ wifi.name }}</dd>
              </div>

              <div class="flex items-baseline justify-between gap-4 py-3">
                <dt class="text-ink-soft">Clave</dt>
                <dd class="break-all text-right font-semibold tabular-nums">{{ wifi.password }}</dd>
              </div>
            </dl>

            <button type="button" class="btn-solid mt-5 w-full" @click="copyWifiPassword">
              <Check v-if="copied" class="size-4" aria-hidden="true" />
              <Copy v-else class="size-4" aria-hidden="true" />
              {{ copied ? 'Clave copiada' : 'Copiar clave' }}
            </button>
          </div>

          <!-- Opinión -->
          <form v-else class="space-y-5" @submit.prevent="sendOpinion">
            <div>
              <p class="mb-1 text-sm font-medium">¿Cómo fue tu experiencia?</p>

              <div class="-ml-1 flex" role="group" aria-label="Puntuación">
                <button
                  v-for="star in 5"
                  :key="star"
                  type="button"
                  class="p-1"
                  :aria-label="`${star} ${star === 1 ? 'estrella' : 'estrellas'}`"
                  :aria-pressed="star <= selectedRating"
                  @click="selectedRating = star"
                >
                  <Star
                    class="size-8 transition-colors"
                    :class="star <= selectedRating ? 'fill-accent text-accent' : 'text-ink/25'"
                    aria-hidden="true"
                  />
                </button>
              </div>
            </div>

            <div>
              <label for="opinion-name" class="mb-1.5 block text-sm font-medium">
                Tu nombre (opcional)
              </label>
              <input
                id="opinion-name"
                v-model="opinionName"
                type="text"
                placeholder="¿Cómo te llamás?"
                class="field"
              />
            </div>

            <div>
              <label for="opinion-type" class="mb-1.5 block text-sm font-medium">
                ¿Sobre qué querés opinar?
              </label>
              <select id="opinion-type" v-model="opinionType" class="field">
                <option value="local">El local</option>
                <option value="comida">La comida y las bebidas</option>
                <option value="atencion">La atención</option>
                <option value="sugerencia">Una sugerencia</option>
              </select>
            </div>

            <div>
              <label for="opinion-message" class="mb-1.5 block text-sm font-medium">
                Tu comentario
              </label>
              <textarea
                id="opinion-message"
                v-model="opinionMessage"
                rows="4"
                required
                placeholder="Contanos tu experiencia..."
                class="field resize-y"
              ></textarea>
            </div>

            <button type="submit" :disabled="sendingOpinion" class="btn-solid w-full">
              {{ sendingOpinion ? 'Enviando...' : 'Enviar opinión' }}
            </button>

            <p
              v-if="opinionStatus"
              role="status"
              class="text-sm font-medium"
              :class="opinionStatusType === 'success' ? 'text-open' : 'text-accent-deep'"
            >
              {{ opinionStatus }}
            </p>
          </form>
        </section>
      </div>
    </Transition>
  </div>
</template>
