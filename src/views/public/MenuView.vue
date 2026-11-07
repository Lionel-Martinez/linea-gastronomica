<script setup lang="ts">
import { computed, ref } from 'vue'
import menuData from '../../data/menu.json'

const selectedCategory = ref('all')
const search = ref('')
const activeModal = ref<'hours' | 'opinion' | null>(null)
const copied = ref(false)
const selectedRating = ref(0)
const opinionName = ref('')
const opinionType = ref('local')
const opinionMessage = ref('')

const sendingOpinion = ref(false)
const opinionStatus = ref('')
const opinionStatusType = ref<'success' | 'error' | ''>('')

const web3formsKey = import.meta.env.VITE_WEB3FORMS_ACCESS_KEY

const schedule = menuData.business.schedule
const wifi = menuData.business.wifi
const contact = menuData.business.contact
const social = menuData.business.social
const links = menuData.business.links

const products = computed(() => {
  return menuData.products.filter((product) => {
    const matchesCategory =
      selectedCategory.value === 'all' ||
      product.category === selectedCategory.value

    const matchesSearch =
      product.name.toLowerCase().includes(search.value.toLowerCase())

    return matchesCategory && matchesSearch && product.available
  })
})

const featuredProducts = computed(() =>
  menuData.products.filter((product) => product.featured && product.available)
)

const formatPrice = (price: number) =>
  new Intl.NumberFormat('es-AR', {
    style: 'currency',
    currency: menuData.business.currency,
    maximumFractionDigits: 0
  }).format(price)

const currentDay = computed(() => {
  const weekday = new Intl.DateTimeFormat('en-US', {
    weekday: 'long',
    timeZone: schedule.timezone
  }).format(new Date())

  const days: Record<string, number> = {
    Sunday: 0,
    Monday: 1,
    Tuesday: 2,
    Wednesday: 3,
    Thursday: 4,
    Friday: 5,
    Saturday: 6
  }

  return days[weekday]
})

const today = computed(() =>
  schedule.days.find(day => day.id === currentDay.value)
)

const currentTime = computed(() =>
  new Intl.DateTimeFormat('en-GB', {
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
    timeZone: schedule.timezone
  }).format(new Date())
)

const isOpen = computed(() => {
  if (!today.value || today.value.closed) return false

  return today.value.shifts.some(shift =>
    currentTime.value >= shift.open &&
    currentTime.value < shift.close
  )
})

const mapsUrl = computed(() =>
  links.googleMaps ||
  `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(menuData.business.address)}`
)

const whatsappUrl = computed(() => {
  const value = contact.whatsapp.trim()

  if (!value) return ''

  // Permite ingresar un enlace completo o solamente el número.
  if (value.startsWith('http')) return value

  const phone = value.replace(/\D/g, '')
  return phone ? `https://wa.me/${phone}` : ''
})

const socialLinks = computed(() =>
  [
    { name: 'Instagram', url: social.instagram },
    { name: 'Facebook', url: social.facebook },
    { name: 'TikTok', url: social.tiktok }
  ].filter(item => item.url.trim())
)

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

</script>

<template>
  <main class="min-h-screen bg-[#f5eee3] text-[#38291f]">
    <div class="mx-auto max-w-xl">

      <!-- Encabezado -->
      <header class="px-5 pb-7 pt-12 text-center">
        <div class="mx-auto mb-4 flex h-24 w-24 items-center justify-center rounded-full border-2 border-[#98552b] bg-[#fffaf3] text-5xl text-[#98552b]">
          ☕
        </div>

        <h1 class="text-4xl font-bold tracking-tight">
          {{ menuData.business.name }}
        </h1>

        <p class="mx-auto mt-3 max-w-sm text-sm leading-relaxed text-[#806d5d]">
          {{ menuData.business.description }}
        </p>
      </header>

      <!-- Información del establecimiento -->
      <section class="space-y-3 px-4">
        <!-- Contacto y redes sociales -->
<div
  v-if="whatsappUrl || contact.phone || contact.email || socialLinks.length || links.googleReviews"
  class="space-y-3"
>
  <!-- WhatsApp -->
  <a
    v-if="whatsappUrl"
    :href="whatsappUrl"
    target="_blank"
    rel="noopener noreferrer"
    class="flex items-center justify-between rounded-2xl bg-[#477b52] p-4 text-white transition hover:bg-[#386441]"
  >
    <div>
      <p class="text-[11px] font-bold uppercase tracking-wider text-white/75">
        Contactanos
      </p>
      <p class="mt-1 font-semibold">Escribinos por WhatsApp</p>
    </div>
    <span class="text-2xl">↗</span>
  </a>

  <!-- Otros datos de contacto -->
  <div
    v-if="contact.phone || contact.email"
    class="space-y-2 rounded-2xl border border-[#e8d8c5] bg-[#fffaf3] p-4"
  >
    <p class="text-[11px] font-bold uppercase tracking-wider text-[#8e7764]">
      Contacto
    </p>

    <a
      v-if="contact.phone"
      :href="`tel:${contact.phone}`"
      class="block text-sm font-medium text-[#604b3a] hover:text-[#914d22]"
    >
      ☎ {{ contact.phone }}
    </a>

    <a
      v-if="contact.email"
      :href="`mailto:${contact.email}`"
      class="block break-all text-sm font-medium text-[#604b3a] hover:text-[#914d22]"
    >
      ✉ {{ contact.email }}
    </a>
  </div>

  <!-- Redes sociales -->
  <div
    v-if="socialLinks.length"
    class="rounded-2xl border border-[#e8d8c5] bg-[#fffaf3] p-4"
  >
    <p class="mb-3 text-[11px] font-bold uppercase tracking-wider text-[#8e7764]">
      Seguinos en redes
    </p>

    <div class="flex flex-wrap gap-2">
      <a
        v-for="item in socialLinks"
        :key="item.name"
        :href="item.url"
        target="_blank"
        rel="noopener noreferrer"
        class="rounded-full bg-[#f0e3d1] px-4 py-2 text-sm font-semibold text-[#89502d] transition hover:bg-[#e9d6bf]"
      >
        {{ item.name }} ↗
      </a>
    </div>
  </div>

  <!-- Opiniones de Google -->
  <a
    v-if="links.googleReviews"
    :href="links.googleReviews"
    target="_blank"
    rel="noopener noreferrer"
    class="flex items-center justify-between rounded-2xl border border-[#e8d8c5] bg-[#fffaf3] p-4 transition hover:bg-white"
  >
    <div>
      <p class="text-[11px] font-bold uppercase tracking-wider text-[#8e7764]">
        Reseñas
      </p>
      <p class="mt-1 text-sm font-semibold">
        Opiniones en Google
      </p>
    </div>
    <span class="text-lg text-[#a45d30]">↗</span>
  </a>
</div>

<!-- Wi-Fi -->
<div
  v-if="wifi.available"
  class="flex items-center gap-3 rounded-2xl border border-[#e8d8c5] bg-[#fffaf3] p-4"
>
  <span class="text-2xl text-[#a45d30]">◉</span>

  <div class="min-w-0 flex-1">
    <p class="text-[11px] font-bold uppercase tracking-wider text-[#8e7764]">
      Wi-Fi
    </p>

    <p class="break-all text-sm font-semibold">
      {{ wifi.name }} · clave: {{ wifi.password }}
    </p>
  </div>

  <button
    type="button"
    @click="copyWifiPassword"
    class="shrink-0 rounded-lg bg-[#f0e3d1] px-3 py-2 text-xs font-semibold text-[#89502d] hover:bg-[#e9d6bf]"
  >
    {{ copied ? '✓' : 'Copiar' }}
  </button>
</div>



       <!-- Horarios -->
<button
  type="button"
  @click="activeModal = 'hours'"
  class="flex w-full items-center gap-3 rounded-2xl border border-[#e8d8c5] bg-[#fffaf3] p-4 text-left transition hover:bg-white"
>
  <span class="text-2xl text-[#a45d30]">◷</span>

  <div class="min-w-0 flex-1">
    <p class="text-[11px] font-bold uppercase tracking-wider text-[#8e7764]">
      Hoy, {{ today?.name }}
    </p>

    <p class="mt-0.5 font-bold">
      <template v-if="today && !today.closed && today.shifts.length">
        <span
          v-for="(shift, index) in today.shifts"
          :key="index"
        >
          {{ shift.open }} – {{ shift.close }}
          <span v-if="index < today.shifts.length - 1"> · </span>
        </span>
      </template>

      <template v-else>
        Cerrado
      </template>
    </p>

    <p
      class="mt-1 text-xs font-medium"
      :class="isOpen ? 'text-green-700' : 'text-red-700'"
    >
      {{ isOpen ? 'Abierto ahora' : 'Cerrado ahora' }}
    </p>
  </div>

  <span class="flex h-10 w-10 items-center justify-center rounded-full bg-[#f0e3d1] text-lg">
    ⌄
  </span>
</button>

        <!-- Opiniones -->
        <button
          type="button"
          @click="activeModal = 'opinion'"
          class="flex w-full items-center justify-center gap-3 rounded-2xl bg-[#914d22] px-4 py-5 font-semibold text-white transition hover:bg-[#783e1b]"
        >
          <span class="text-xl">▢</span>
          Dejanos tu opinión
        </button>

        <!-- Ubicación -->
        <a
          :href="mapsUrl"
          target="_blank"
          rel="noopener noreferrer"
          class="flex items-center gap-3 rounded-2xl border border-[#e8d8c5] bg-[#fffaf3] p-4 transition hover:bg-white"
        >
          <span class="text-xl text-[#a45d30]">⌖</span>
          <span class="text-sm font-medium">{{ menuData.business.address }}</span>
        </a>
      </section>

      <!-- Buscador -->
      <section class="px-4 pb-3 pt-7">
        <div class="flex items-center gap-3 rounded-2xl border border-[#e8d8c5] bg-[#fffaf3] px-4 py-3">
          <span class="text-lg text-[#8e7764]">⌕</span>

          <input
            v-model="search"
            type="search"
            placeholder="Buscá un café, una medialuna..."
            class="w-full bg-transparent text-sm outline-none placeholder:text-[#9b8877]"
          />
        </div>
      </section>

      <!-- Categorías -->
      <nav class="sticky top-0 z-20 bg-[#f5eee3]/95 px-4 py-3 backdrop-blur">
        <div class="flex gap-2 overflow-x-auto pb-1">
          <button
            v-for="category in menuData.categories"
            :key="category.id"
            type="button"
            @click="selectedCategory = category.id"
            class="shrink-0 rounded-full border px-5 py-2.5 text-sm font-semibold transition"
            :class="selectedCategory === category.id
              ? 'border-[#914d22] bg-[#914d22] text-white'
              : 'border-[#e5d2bc] bg-transparent text-[#604b3a] hover:bg-[#eee1d1]'"
          >
            {{ category.name }}
          </button>
        </div>
      </nav>

      <!-- Destacados -->
      <section
        v-if="selectedCategory === 'all' && !search"
        class="px-4 pb-5 pt-5"
      >
        <p class="text-xs font-bold uppercase tracking-widest text-[#a16b45]">
          Selección especial
        </p>

        <h2 class="mb-4 mt-1 text-2xl font-bold">
          Favoritos de la casa
        </h2>

        <div class="grid grid-cols-2 gap-3 sm:grid-cols-3">
          <article
            v-for="product in featuredProducts"
            :key="product.id"
            class="overflow-hidden rounded-2xl border border-[#e8d8c5] bg-[#fffaf3]"
          >
            <img
              :src="product.image"
              :alt="product.name"
              class="h-32 w-full object-cover"
            />

            <div class="p-3">
              <h3 class="font-semibold">{{ product.name }}</h3>
              <p class="mt-1 font-bold text-[#a45d30]">
                {{ formatPrice(product.price) }}
              </p>
            </div>
          </article>
        </div>
      </section>

      <!-- Catálogo -->
      <section class="px-4 pb-12 pt-5">
        <div class="mb-5">
          <p class="text-xs font-bold uppercase tracking-widest text-[#a16b45]">
            Nuestro menú
          </p>

          <h2 class="mt-1 text-2xl font-bold">
            {{ selectedCategory === 'all'
              ? 'Todos nuestros productos'
              : menuData.categories.find(c => c.id === selectedCategory)?.name }}
          </h2>
        </div>

        <div v-if="products.length" class="space-y-3">
          <article
            v-for="product in products"
            :key="product.id"
            class="flex gap-3 rounded-2xl border border-[#e8d8c5] bg-[#fffaf3] p-3"
          >
            <img
              :src="product.image"
              :alt="product.name"
              class="h-24 w-24 shrink-0 rounded-xl object-cover sm:h-28 sm:w-28"
            />

            <div class="flex min-w-0 flex-1 flex-col justify-center">
              <div class="flex items-start justify-between gap-2">
                <h3 class="font-bold">
                  {{ product.name }}
                </h3>

                <span class="shrink-0 font-bold text-[#a45d30]">
                  {{ formatPrice(product.price) }}
                </span>
              </div>

              <p class="mt-1 text-sm leading-relaxed text-[#806d5d]">
                {{ product.description }}
              </p>
            </div>
          </article>
        </div>

        <p v-else class="py-12 text-center text-sm text-[#806d5d]">
          No encontramos productos con esa búsqueda.
        </p>

        <p class="mt-7 text-center text-xs text-[#917d6a]">
          Precios en pesos argentinos.
        </p>
      </section>

      <!-- Footer -->
      <footer class="border-t border-[#e8d8c5] px-5 py-8 text-center">
  <button
    type="button"
    @click="scrollToTop"
    class="mb-7 inline-flex items-center gap-2 rounded-full border border-[#e5d2bc] px-5 py-2.5 text-sm font-semibold text-[#604b3a] transition hover:bg-[#eee1d1]"
  >
    <span>↑</span>
    Volver al comienzo
  </button>

  <div class="border-t border-[#e8d8c5] pt-6">
    <p class="text-xs uppercase tracking-widest text-[#917d6a]">
      Menú digital
    </p>

    <h2 class="mt-2 text-lg font-bold">
      {{ menuData.business.name }}
    </h2>

    <p class="mt-5 text-xs text-[#917d6a]">
      Diseño y desarrollo por
    </p>

    <p class="mt-1 text-xl font-bold text-[#914d22]">
      LM Studio
    </p>

    <p class="mt-2 text-sm text-[#806d5d]">
      Creamos soluciones digitales para tu negocio.
    </p>

    <a
      href="URL_DE_TU_PORTAFOLIO"
      target="_blank"
      rel="noopener noreferrer"
      class="mt-4 inline-block text-sm font-semibold text-[#914d22] underline underline-offset-4 hover:text-[#783e1b]"
    >
      Conocé nuestro portafolio ↗
    </a>

    <p class="mt-7 text-xs text-[#a18d7a]">
      © {{ new Date().getFullYear() }} LM Studio · Todos los derechos reservados
    </p>
  </div>
</footer>
    </div>

    <!-- Modales superpuestos -->
    <div
      v-if="activeModal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/55 p-4"
      @click.self="activeModal = null"
    >
      <section
        class="max-h-[85vh] w-full max-w-md overflow-y-auto rounded-3xl bg-[#fffaf3] p-6 shadow-2xl"
        role="dialog"
        aria-modal="true"
      >
        <!-- Encabezado del modal -->
        <div class="mb-6 flex items-center justify-between">
          <h2 class="text-xl font-bold">
            {{ activeModal === 'hours'
              ? 'Horarios de atención'
              : 'Dejanos tu opinión' }}
          </h2>

          <button
            type="button"
            @click="activeModal = null"
            aria-label="Cerrar ventana"
            class="flex h-9 w-9 items-center justify-center rounded-full bg-[#f0e3d1] text-xl hover:bg-[#e9d6bf]"
          >
            ×
          </button>
        </div>

        <!-- Modal de horarios -->
        <div v-if="activeModal === 'hours'" class="space-y-2">
          <div
            v-for="day in schedule.days"
            :key="day.id"
            class="flex items-center justify-between rounded-xl px-3 py-3 text-sm"
            :class="day.id === currentDay
              ? 'bg-[#f0e3d1] font-bold text-[#914d22]'
              : 'text-[#604b3a]'"
          >
            <span>
              {{ day.name }}
              <span v-if="day.id === currentDay">(Hoy)</span>
            </span>

            <span v-if="day.closed">Cerrado</span>
            <div v-else class="flex flex-col items-end gap-1">
  <span v-for="(shift, index) in day.shifts" :key="index">
    {{ shift.open }} – {{ shift.close }}
  </span>
</div>
          </div>
        </div>

        <!-- Modal de opiniones -->
<form
  v-else
  class="space-y-4"
  @submit.prevent="sendOpinion"
>
  <div>
    <p class="mb-2 text-sm font-medium">
      ¿Cómo fue tu experiencia?
    </p>

    <div class="flex gap-2">
      <button
        v-for="star in 5"
        :key="star"
        type="button"
        @click="selectedRating = star"
        class="text-3xl transition"
        :class="star <= selectedRating
          ? 'text-[#d28b32]'
          : 'text-[#d9c9b8]'"
        :aria-label="`${star} estrellas`"
      >
        ★
      </button>
    </div>
  </div>

  <div>
    <label for="opinion-name" class="mb-1 block text-sm font-medium">
      Tu nombre (opcional)
    </label>

    <input
      id="opinion-name"
      v-model="opinionName"
      type="text"
      placeholder="¿Cómo te llamás?"
      class="w-full rounded-xl border border-[#e8d8c5] bg-white px-3 py-3 text-sm outline-none focus:border-[#a45d30]"
    />
  </div>

  <div>
    <label for="opinion-type" class="mb-1 block text-sm font-medium">
      ¿Sobre qué querés opinar?
    </label>

    <select
      id="opinion-type"
      v-model="opinionType"
      class="w-full rounded-xl border border-[#e8d8c5] bg-white px-3 py-3 text-sm outline-none focus:border-[#a45d30]"
    >
      <option value="local">El local</option>
      <option value="comida">La comida y las bebidas</option>
      <option value="atencion">La atención</option>
      <option value="sugerencia">Una sugerencia</option>
    </select>
  </div>

  <div>
    <label for="opinion-message" class="mb-1 block text-sm font-medium">
      Tu comentario
    </label>

    <textarea
      id="opinion-message"
      v-model="opinionMessage"
      rows="4"
      required
      placeholder="Contanos tu experiencia..."
      class="w-full resize-y rounded-xl border border-[#e8d8c5] bg-white px-3 py-3 text-sm outline-none focus:border-[#a45d30]"
    ></textarea>
  </div>

  <button
    type="submit"
    :disabled="sendingOpinion"
    class="w-full rounded-xl bg-[#914d22] px-4 py-3 font-semibold text-white transition hover:bg-[#783e1b] disabled:cursor-not-allowed disabled:opacity-60"
  >
    {{ sendingOpinion ? 'Enviando...' : 'Enviar opinión' }}
  </button>

  <p
    v-if="opinionStatus"
    class="text-sm"
    :class="opinionStatusType === 'success' ? 'text-green-700' : 'text-red-700'"
  >
    {{ opinionStatus }}
  </p>
</form>
      </section>
    </div>
  </main>
</template>
