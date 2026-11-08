<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { RouterLink } from 'vue-router'
import { friendlyError, loadSettings, saveSettings } from '../../lib/api'
import { businessName } from '../../lib/format'
import { refreshPanel } from '../../lib/panel'
import { PAYMENT_LABEL, PAYMENT_METHODS, type PaymentMethod } from '../../lib/types'

const form = reactive({
  table_count: 10,
  payment_alias: '',
  payment_cbu: '',
  payment_holder: '',
  ordering_enabled: true,
  payment_methods: ['transfer', 'cash'] as PaymentMethod[],
  whatsapp_number: ''
})
const loading = ref(true)
const saving = ref(false)
const error = ref('')
const saved = ref(false)
const savedTables = ref(0)

async function submit() {
  if (saving.value) return

  const tables = Math.trunc(Number(form.table_count))
  if (!Number.isFinite(tables) || tables < 1 || tables > 200) {
    error.value = 'La cantidad de mesas tiene que estar entre 1 y 200.'
    return
  }

  const cbu = form.payment_cbu.replace(/\s/g, '')
  if (cbu && !/^\d{22}$/.test(cbu)) {
    error.value = 'El CBU/CVU tiene que tener 22 números.'
    return
  }

  const whatsapp = form.whatsapp_number.replace(/[\s+()-]/g, '')
  if (whatsapp && !/^\d{8,15}$/.test(whatsapp)) {
    error.value = 'El WhatsApp tiene que tener entre 8 y 15 números, con código de país. Ej.: 5493878123456.'
    return
  }

  if (form.ordering_enabled && !form.payment_methods.length) {
    error.value = 'Elegí al menos una forma de pago, o desactivá los pedidos.'
    return
  }

  saving.value = true
  saved.value = false
  error.value = ''

  try {
    await saveSettings({
      table_count: tables,
      payment_alias: form.payment_alias.trim(),
      payment_cbu: cbu,
      payment_holder: form.payment_holder.trim(),
      ordering_enabled: form.ordering_enabled,
      payment_methods: PAYMENT_METHODS.filter((method) => form.payment_methods.includes(method)),
      whatsapp_number: whatsapp
    })

    // Se vuelve a leer de la base: lo que se muestra es lo que realmente quedó guardado.
    const fresh = await loadSettings()
    if (fresh.table_count !== tables || fresh.ordering_enabled !== form.ordering_enabled) {
      throw new Error('not_saved')
    }

    Object.assign(form, fresh, { payment_methods: [...fresh.payment_methods] })
    savedTables.value = fresh.table_count
    saved.value = true
    void refreshPanel()
  } catch (e) {
    error.value = friendlyError(e)
  } finally {
    saving.value = false
  }
}

onMounted(async () => {
  document.title = `Ajustes · ${businessName}`

  try {
    const data = await loadSettings()
    Object.assign(form, data, { payment_methods: [...data.payment_methods] })
  } catch (e) {
    error.value = friendlyError(e)
  } finally {
    loading.value = false
  }
})
</script>

<template>
  <main class="wrap max-w-6xl pb-16 pt-8">
    <h1 class="font-display text-[2rem] font-semibold leading-none tracking-tight">Ajustes</h1>

    <p v-if="loading" class="py-16 text-center font-display text-xl italic text-ink-soft" aria-busy="true">
      Cargando…
    </p>

    <form v-else class="mt-8 max-w-xl space-y-6" @submit.prevent="submit">
      <fieldset class="space-y-2">
        <legend class="font-display pr-3 text-xl font-semibold">Pedidos desde la mesa</legend>
        <label class="flex items-start gap-3 text-[15px]">
          <input v-model="form.ordering_enabled" type="checkbox" class="mt-1 size-4 accent-accent" />
          <span>
            Recibir pedidos desde el QR de cada mesa
            <span class="mt-0.5 block text-sm text-ink-soft">
              Si lo desactivás, el local queda solo con la carta digital (que sigue siendo editable):
              no se pueden hacer pedidos y desaparecen la pantalla de pedidos y los QR de mesa.
            </span>
          </span>
        </label>
      </fieldset>

      <div class="border-t border-ink pt-5">
        <label for="s-tables" class="mb-1.5 block text-sm font-medium">Cantidad de mesas</label>
        <input id="s-tables" v-model.number="form.table_count" type="number" min="1" max="200" class="field" />
        <p class="mt-1.5 text-sm text-ink-soft">
          Los pedidos solo se aceptan para mesas de 1 a este número. Los QR de cada mesa están en
          <RouterLink :to="{ name: 'staff-qr' }" class="underline underline-offset-4">Códigos QR</RouterLink>.
        </p>
      </div>

      <fieldset class="space-y-3 border-t border-ink pt-5">
        <legend class="font-display pr-3 text-xl font-semibold">Formas de pago</legend>
        <p class="text-sm text-ink-soft">
          El cliente elige una al pedir. No hay pago online: se cobra en el local o por transferencia.
        </p>
        <label v-for="method in PAYMENT_METHODS" :key="method" class="flex items-center gap-3 text-[15px]">
          <input v-model="form.payment_methods" type="checkbox" :value="method" class="size-4 accent-accent" />
          {{ PAYMENT_LABEL[method] }}
        </label>
      </fieldset>

      <fieldset class="space-y-4 border-t border-ink pt-5">
        <legend class="font-display pr-3 text-xl font-semibold">Datos para transferencias</legend>
        <p class="text-sm text-ink-soft">Se muestran al cliente solo si elige pagar por transferencia.</p>

        <div>
          <label for="s-alias" class="mb-1.5 block text-sm font-medium">Alias</label>
          <input id="s-alias" v-model="form.payment_alias" type="text" maxlength="40" class="field" />
        </div>

        <div>
          <label for="s-cbu" class="mb-1.5 block text-sm font-medium">CBU / CVU</label>
          <input id="s-cbu" v-model="form.payment_cbu" type="text" inputmode="numeric" class="field" />
        </div>

        <div>
          <label for="s-holder" class="mb-1.5 block text-sm font-medium">Titular</label>
          <input id="s-holder" v-model="form.payment_holder" type="text" maxlength="80" class="field" />
        </div>

        <div>
          <label for="s-wa" class="mb-1.5 block text-sm font-medium">WhatsApp del local (para comprobantes)</label>
          <input
            id="s-wa"
            v-model="form.whatsapp_number"
            type="tel"
            inputmode="numeric"
            placeholder="5493878123456"
            class="field"
          />
          <p class="mt-1.5 text-sm text-ink-soft">
            Con código de país, sin + ni espacios. Argentina: 549 + código de área + número.
            El cliente ve un botón para enviar el comprobante a este número.
          </p>
        </div>
      </fieldset>

      <p v-if="error" class="text-sm font-medium text-accent-deep" role="alert">{{ error }}</p>
      <p v-if="saved" class="text-sm font-medium text-open" role="status">
        Cambios guardados. El local tiene {{ savedTables }} mesas.
        <RouterLink :to="{ name: 'staff-qr' }" class="underline underline-offset-4">Ver los códigos QR</RouterLink>
      </p>

      <button type="submit" class="btn-solid w-full sm:w-auto" :disabled="saving">
        {{ saving ? 'Guardando…' : 'Guardar cambios' }}
      </button>
    </form>
  </main>
</template>
