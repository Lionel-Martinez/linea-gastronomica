<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { blockPhone, friendlyError, listBlockedPhones, unblockPhone } from '../../lib/api'
import type { BlockedPhone } from '../../lib/types'

const phones = ref<BlockedPhone[]>([])
const loading = ref(true)
const busy = ref(false)
const error = ref('')
const phone = ref('')
const note = ref('')

async function reload() {
  try {
    phones.value = await listBlockedPhones()
    error.value = ''
  } catch (e) {
    error.value = friendlyError(e)
  } finally {
    loading.value = false
  }
}

async function run(action: () => Promise<void>) {
  if (busy.value) return
  busy.value = true
  error.value = ''

  try {
    await action()
    await reload()
  } catch (e) {
    error.value = friendlyError(e)
  } finally {
    busy.value = false
  }
}

function add() {
  const digits = phone.value.replace(/\D/g, '')

  if (digits.length < 8 || digits.length > 15) {
    error.value = 'Escribí un teléfono válido, con código de área (entre 8 y 15 números).'
    return
  }

  return run(async () => {
    await blockPhone(digits, note.value.trim().slice(0, 80))
    phone.value = ''
    note.value = ''
  })
}

const remove = (item: BlockedPhone) => run(() => unblockPhone(item.phone))

onMounted(reload)
</script>

<template>
  <fieldset class="space-y-3 border-t border-ink pt-5">
    <legend class="font-display pr-3 text-xl font-semibold">Teléfonos bloqueados</legend>
    <p class="text-sm text-ink-soft">
      Un teléfono bloqueado no puede hacer pedidos desde casa (se compara con o sin +54 y 9). También se
      bloquea desde la tarjeta de un pedido.
    </p>

    <p v-if="loading" class="text-sm text-ink-soft" aria-busy="true">Cargando…</p>

    <ul v-else class="divide-y divide-rule border-y border-rule">
      <li v-for="item in phones" :key="item.phone" class="flex items-center justify-between gap-3 py-2.5">
        <span class="min-w-0 text-[15px]">
          <span class="font-semibold tabular-nums">{{ item.phone }}</span>
          <span v-if="item.note" class="ml-2 text-ink-soft">{{ item.note }}</span>
        </span>
        <button type="button" class="btn-line btn-small shrink-0" :disabled="busy" @click="remove(item)">
          Desbloquear
        </button>
      </li>
      <li v-if="!phones.length" class="py-2.5 text-sm text-ink-soft">No hay teléfonos bloqueados.</li>
    </ul>

    <div class="grid gap-2 sm:grid-cols-[1fr_1fr_auto] sm:items-end">
      <div>
        <label for="block-phone" class="mb-1 block text-xs text-ink-soft">Teléfono</label>
        <input id="block-phone" v-model="phone" type="tel" inputmode="tel" class="field !py-2" />
      </div>
      <div>
        <label for="block-note" class="mb-1 block text-xs text-ink-soft">Nota (opcional)</label>
        <input id="block-note" v-model="note" type="text" maxlength="80" class="field !py-2" />
      </div>
      <button type="button" class="btn-line btn-small" :disabled="busy" @click="add">Bloquear</button>
    </div>

    <p v-if="error" class="text-sm font-medium text-accent-deep" role="alert">{{ error }}</p>
  </fieldset>
</template>
