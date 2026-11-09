<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { deleteZone, friendlyError, loadZones, saveZone } from '../../lib/api'
import type { DeliveryZone } from '../../lib/types'

interface Row {
  id: string | null
  name: string
  fee: string
  active: boolean
  dirty: boolean
}

const rows = ref<Row[]>([])
const loading = ref(true)
const busy = ref(false)
const error = ref('')
const draft = ref({ name: '', fee: '' })

const toRow = (zone: DeliveryZone): Row => ({
  id: zone.id,
  name: zone.name,
  fee: String(zone.fee),
  active: zone.active,
  dirty: false
})

async function reload() {
  try {
    rows.value = (await loadZones()).map(toRow)
    error.value = ''
  } catch (e) {
    error.value = friendlyError(e)
  } finally {
    loading.value = false
  }
}

function parseFee(value: string): number | null {
  const fee = Number(value.replace(',', '.'))
  return Number.isFinite(fee) && fee >= 0 && fee <= 1_000_000 ? fee : null
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

function save(row: Row) {
  const fee = parseFee(row.fee)
  const name = row.name.trim()

  if (!name || fee === null) {
    error.value = 'Cada zona necesita un nombre y un precio de envío válido (0 si es gratis).'
    return
  }

  return run(() => saveZone({ id: row.id, name, fee, active: row.active }))
}

function add() {
  const fee = parseFee(draft.value.fee)
  const name = draft.value.name.trim()

  if (!name || fee === null) {
    error.value = 'Escribí el nombre de la zona y el precio de envío (0 si es gratis).'
    return
  }

  return run(async () => {
    await saveZone({ id: null, name, fee, active: true, sort_order: rows.value.length + 1 })
    draft.value = { name: '', fee: '' }
  })
}

function remove(row: Row) {
  if (!row.id) return
  if (!window.confirm(`¿Eliminar la zona «${row.name}»? Los pedidos ya hechos no cambian.`)) return

  const id = row.id
  return run(() => deleteZone(id))
}

onMounted(reload)
</script>

<template>
  <fieldset class="space-y-3 border-t border-ink pt-5">
    <legend class="font-display pr-3 text-xl font-semibold">Zonas de envío</legend>
    <p class="text-sm text-ink-soft">
      Cada zona tiene su propio precio. El cliente elige la suya al pedir delivery y ve el costo antes de confirmar.
      Una zona desactivada deja de aparecer, sin borrarse.
    </p>

    <p v-if="loading" class="text-sm text-ink-soft" aria-busy="true">Cargando zonas…</p>

    <ul v-else class="space-y-3">
      <li v-for="(row, index) in rows" :key="row.id ?? index" class="border border-ink/40 p-3" data-zone>
        <div class="grid grid-cols-[1fr_7rem] gap-2">
          <div>
            <label :for="`zone-name-${index}`" class="mb-1 block text-xs text-ink-soft">Zona</label>
            <input
              :id="`zone-name-${index}`"
              v-model="row.name"
              type="text"
              maxlength="60"
              class="field !py-2"
              @input="row.dirty = true"
            />
          </div>
          <div>
            <label :for="`zone-fee-${index}`" class="mb-1 block text-xs text-ink-soft">Envío ($)</label>
            <input
              :id="`zone-fee-${index}`"
              v-model="row.fee"
              type="text"
              inputmode="decimal"
              class="field !py-2"
              @input="row.dirty = true"
            />
          </div>
        </div>

        <div class="mt-3 flex flex-wrap items-center justify-between gap-2">
          <label class="flex min-h-11 items-center gap-2 text-sm">
            <input v-model="row.active" type="checkbox" class="size-4 accent-accent" @change="row.dirty = true" />
            Activa
          </label>

          <div class="flex gap-2">
            <button type="button" class="btn-solid btn-small" :disabled="busy || !row.dirty" @click="save(row)">
              Guardar
            </button>
            <button type="button" class="btn-line btn-small" :disabled="busy" @click="remove(row)">
              Eliminar
            </button>
          </div>
        </div>
      </li>

      <li v-if="!rows.length" class="text-sm text-ink-soft">
        Todavía no cargaste zonas. Sin zonas, nadie puede pedir delivery.
      </li>
    </ul>

    <div class="border border-ink p-3">
      <p class="mb-2 text-sm font-medium">Agregar zona</p>
      <div class="grid grid-cols-[1fr_7rem] gap-2">
        <div>
          <label for="zone-new-name" class="mb-1 block text-xs text-ink-soft">Zona</label>
          <input
            id="zone-new-name"
            v-model="draft.name"
            type="text"
            maxlength="60"
            placeholder="Centro, Barrio Norte…"
            class="field !py-2"
          />
        </div>
        <div>
          <label for="zone-new-fee" class="mb-1 block text-xs text-ink-soft">Envío ($)</label>
          <input id="zone-new-fee" v-model="draft.fee" type="text" inputmode="decimal" class="field !py-2" />
        </div>
      </div>
      <button type="button" class="btn-line btn-small mt-3" :disabled="busy" @click="add">Agregar</button>
    </div>

    <p v-if="error" class="text-sm font-medium text-accent-deep" role="alert">{{ error }}</p>
  </fieldset>
</template>
