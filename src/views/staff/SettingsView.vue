<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { friendlyError, loadSettings, saveSettings } from '../../lib/api'
import { businessName } from '../../lib/format'

const form = reactive({ table_count: 10, payment_alias: '', payment_cbu: '', payment_holder: '' })
const loading = ref(true)
const saving = ref(false)
const error = ref('')
const saved = ref(false)

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

  saving.value = true
  saved.value = false
  error.value = ''

  try {
    await saveSettings({
      table_count: tables,
      payment_alias: form.payment_alias.trim(),
      payment_cbu: cbu,
      payment_holder: form.payment_holder.trim()
    })
    form.table_count = tables
    form.payment_cbu = cbu
    saved.value = true
  } catch (e) {
    error.value = friendlyError(e)
  } finally {
    saving.value = false
  }
}

onMounted(async () => {
  document.title = `Ajustes · ${businessName}`

  try {
    Object.assign(form, await loadSettings())
  } catch (e) {
    error.value = friendlyError(e)
  } finally {
    loading.value = false
  }
})
</script>

<template>
  <main class="wrap max-w-xl pb-16 pt-8">
    <h1 class="font-display text-[2rem] font-semibold leading-none tracking-tight">Ajustes</h1>

    <p v-if="loading" class="py-16 text-center font-display text-xl italic text-ink-soft" aria-busy="true">
      Cargando…
    </p>

    <form v-else class="mt-8 space-y-6" @submit.prevent="submit">
      <div>
        <label for="s-tables" class="mb-1.5 block text-sm font-medium">Cantidad de mesas</label>
        <input id="s-tables" v-model.number="form.table_count" type="number" min="1" max="200" class="field" />
        <p class="mt-1.5 text-sm text-ink-soft">Los pedidos solo se aceptan para mesas de 1 a este número.</p>
      </div>

      <fieldset class="space-y-4 border-t border-ink pt-5">
        <legend class="font-display pr-3 text-xl font-semibold">Datos para el pago</legend>
        <p class="text-sm text-ink-soft">Se muestran al cliente al pedir. No hay pago online.</p>

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
      </fieldset>

      <p v-if="error" class="text-sm font-medium text-accent-deep" role="alert">{{ error }}</p>
      <p v-if="saved" class="text-sm font-medium text-open" role="status">Cambios guardados.</p>

      <button type="submit" class="btn-solid w-full sm:w-auto" :disabled="saving">
        {{ saving ? 'Guardando…' : 'Guardar cambios' }}
      </button>
    </form>
  </main>
</template>
