<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { ImageOff, Pencil, Plus } from '@lucide/vue'
import BottomSheet from '../../components/ui/BottomSheet.vue'
import {
  deleteProduct,
  friendlyError,
  loadMenu,
  saveProduct,
  setProductAvailable,
  type ProductInput
} from '../../lib/api'
import { businessName, formatPrice } from '../../lib/format'
import type { Category, Product } from '../../lib/types'

const categories = ref<Category[]>([])
const products = ref<Product[]>([])
const loading = ref(true)
const error = ref('')
const saving = ref(false)
const formError = ref('')
const sheetOpen = ref(false)
const priceText = ref('')

const form = reactive<ProductInput>(blank())

function blank(): ProductInput {
  return {
    id: null,
    category_id: '',
    name: '',
    description: '',
    price: 0,
    image: '',
    available: true,
    featured: false
  }
}

const groups = computed(() =>
  categories.value
    .map((category) => ({
      category,
      items: products.value.filter((product) => product.category_id === category.id)
    }))
    .filter((group) => group.items.length)
)

async function load() {
  try {
    const data = await loadMenu()
    categories.value = data.categories
    products.value = data.products
    error.value = ''
  } catch (e) {
    error.value = friendlyError(e)
  } finally {
    loading.value = false
  }
}

function openNew() {
  Object.assign(form, blank(), { category_id: categories.value[0]?.id ?? '' })
  priceText.value = ''
  formError.value = ''
  sheetOpen.value = true
}

function openEdit(product: Product) {
  Object.assign(form, {
    id: product.id,
    category_id: product.category_id,
    name: product.name,
    description: product.description,
    price: product.price,
    image: product.image,
    available: product.available,
    featured: product.featured
  })
  priceText.value = String(product.price)
  formError.value = ''
  sheetOpen.value = true
}

function parsePrice(text: string) {
  // Acepta "4500", "4500,50" y "4500.50".
  const value = Number(text.trim().replace(',', '.'))
  return Number.isFinite(value) ? value : NaN
}

async function submit() {
  if (saving.value) return

  const price = parsePrice(priceText.value)
  const image = form.image.trim()

  if (!form.name.trim()) {
    formError.value = 'Ponele un nombre al producto.'
    return
  }
  if (!form.category_id) {
    formError.value = 'Elegí una categoría.'
    return
  }
  if (!Number.isFinite(price) || price < 0) {
    formError.value = 'Ingresá un precio válido.'
    return
  }
  if (image && !/^(https?:\/\/|\/)/i.test(image)) {
    formError.value = 'La imagen tiene que ser un enlace que empiece con http:// o https://.'
    return
  }

  saving.value = true
  formError.value = ''

  try {
    await saveProduct({
      ...form,
      name: form.name.trim(),
      description: form.description.trim(),
      price,
      image
    })
    sheetOpen.value = false
    await load()
  } catch (e) {
    formError.value = friendlyError(e)
  } finally {
    saving.value = false
  }
}

async function toggle(product: Product) {
  const next = !product.available
  product.available = next // se refleja al instante; si falla, se revierte

  try {
    await setProductAvailable(product.id, next)
    error.value = ''
  } catch (e) {
    product.available = !next
    error.value = friendlyError(e)
  }
}

async function remove() {
  if (!form.id || saving.value) return
  if (!window.confirm(`¿Eliminar "${form.name}"? Los pedidos anteriores se conservan.`)) return

  saving.value = true

  try {
    await deleteProduct(form.id)
    sheetOpen.value = false
    await load()
  } catch (e) {
    formError.value = friendlyError(e)
  } finally {
    saving.value = false
  }
}

onMounted(() => {
  document.title = `Productos · ${businessName}`
  void load()
})
</script>

<template>
  <main class="wrap pb-16 pt-8">
    <div class="flex items-center justify-between gap-3">
      <h1 class="font-display text-[2rem] font-semibold leading-none tracking-tight">Productos</h1>
      <button type="button" class="btn-solid btn-small" :disabled="!categories.length" @click="openNew">
        <Plus class="size-4" aria-hidden="true" />
        Nuevo
      </button>
    </div>

    <p v-if="error" class="mt-5 border border-accent px-4 py-3 text-sm text-accent-deep" role="alert">
      {{ error }}
    </p>

    <p v-if="loading" class="py-16 text-center font-display text-xl italic text-ink-soft" aria-busy="true">
      Cargando productos…
    </p>

    <p
      v-else-if="!groups.length && !error"
      class="py-16 text-center font-display text-xl italic text-ink-soft"
    >
      Todavía no hay productos. Cargá los datos iniciales o creá el primero.
    </p>

    <section
      v-for="group in groups"
      :key="group.category.id"
      class="pt-8"
      :aria-labelledby="`cat-${group.category.id}`"
    >
      <h2
        :id="`cat-${group.category.id}`"
        class="font-display border-b border-ink pb-2.5 text-[1.5rem] font-semibold leading-none tracking-tight"
      >
        {{ group.category.name }}
      </h2>

      <ul class="divide-y divide-rule">
        <li v-for="product in group.items" :key="product.id" class="flex items-center gap-3 py-3">
          <div class="size-14 shrink-0 overflow-hidden bg-paper-deep">
            <img
              v-if="product.image"
              :src="product.image"
              alt=""
              class="size-full object-cover"
              loading="lazy"
            />
            <div v-else class="grid size-full place-items-center text-ink-soft">
              <ImageOff class="size-5" aria-hidden="true" />
            </div>
          </div>

          <div class="min-w-0 flex-1">
            <p
              class="truncate font-display text-[1.0625rem] font-medium leading-snug"
              :class="product.available ? '' : 'text-ink-soft line-through'"
            >
              {{ product.name }}
            </p>
            <p class="text-sm font-semibold tabular-nums">{{ formatPrice(product.price) }}</p>
          </div>

          <button
            type="button"
            class="btn-line btn-small shrink-0"
            :aria-pressed="product.available"
            :aria-label="`${product.name}: ${product.available ? 'disponible' : 'agotado'}`"
            @click="toggle(product)"
          >
            {{ product.available ? 'Disponible' : 'Agotado' }}
          </button>

          <button
            type="button"
            class="btn-line btn-small shrink-0 !px-2.5"
            :aria-label="`Editar ${product.name}`"
            @click="openEdit(product)"
          >
            <Pencil class="size-4" aria-hidden="true" />
          </button>
        </li>
      </ul>
    </section>

    <BottomSheet :open="sheetOpen" :title="form.id ? 'Editar producto' : 'Nuevo producto'" @close="sheetOpen = false">
      <form class="space-y-4" @submit.prevent="submit">
        <div>
          <label for="p-name" class="mb-1.5 block text-sm font-medium">Nombre</label>
          <input id="p-name" v-model="form.name" type="text" maxlength="80" class="field" />
        </div>

        <div>
          <label for="p-desc" class="mb-1.5 block text-sm font-medium">Descripción</label>
          <textarea id="p-desc" v-model="form.description" rows="2" maxlength="240" class="field"></textarea>
        </div>

        <div class="grid grid-cols-2 gap-3">
          <div>
            <label for="p-price" class="mb-1.5 block text-sm font-medium">Precio</label>
            <input id="p-price" v-model="priceText" type="text" inputmode="decimal" placeholder="4500" class="field" />
          </div>

          <div>
            <label for="p-cat" class="mb-1.5 block text-sm font-medium">Categoría</label>
            <select id="p-cat" v-model="form.category_id" class="field">
              <option v-for="category in categories" :key="category.id" :value="category.id">
                {{ category.name }}
              </option>
            </select>
          </div>
        </div>

        <div>
          <label for="p-img" class="mb-1.5 block text-sm font-medium">Imagen (enlace)</label>
          <input
            id="p-img"
            v-model="form.image"
            type="url"
            inputmode="url"
            placeholder="https://…"
            class="field"
          />
        </div>

        <div class="flex flex-wrap gap-x-6 gap-y-2">
          <label class="flex items-center gap-2 text-[15px]">
            <input v-model="form.available" type="checkbox" class="size-4 accent-accent" />
            Disponible
          </label>
          <label class="flex items-center gap-2 text-[15px]">
            <input v-model="form.featured" type="checkbox" class="size-4 accent-accent" />
            Destacado
          </label>
        </div>

        <p v-if="formError" class="text-sm font-medium text-accent-deep" role="alert">{{ formError }}</p>

        <div class="flex flex-wrap gap-2 pt-1">
          <button type="submit" class="btn-solid flex-1" :disabled="saving">
            {{ saving ? 'Guardando…' : 'Guardar' }}
          </button>
          <button v-if="form.id" type="button" class="btn-line" :disabled="saving" @click="remove">
            Eliminar
          </button>
        </div>
      </form>
    </BottomSheet>
  </main>
</template>
