<script setup lang="ts">
import { computed, ref } from 'vue'
import { Check, Copy } from '@lucide/vue'
import type { Settings } from '../../lib/types'

const props = defineProps<{ settings: Settings | null }>()

const copied = ref('')

const rows = computed(() =>
  [
    { id: 'alias', label: 'Alias', value: props.settings?.payment_alias ?? '' },
    { id: 'cbu', label: 'CBU / CVU', value: props.settings?.payment_cbu ?? '' }
  ].filter((row) => row.value)
)

async function copy(id: string, value: string) {
  try {
    await navigator.clipboard.writeText(value)
    copied.value = id

    window.setTimeout(() => {
      if (copied.value === id) copied.value = ''
    }, 2000)
  } catch {
    copied.value = ''
  }
}
</script>

<template>
  <section v-if="rows.length" class="border border-ink p-4" aria-labelledby="pay-title">
    <h3 id="pay-title" class="font-display text-xl font-semibold leading-none">Cómo pagar</h3>
    <p class="mt-2 text-sm text-ink-soft">
      Podés pagar por transferencia. Esta página no procesa pagos.
    </p>

    <dl class="mt-3 divide-y divide-rule border-y border-rule text-[15px]">
      <div v-for="row in rows" :key="row.id" class="flex items-center justify-between gap-3 py-2.5">
        <div class="min-w-0">
          <dt class="text-xs text-ink-soft">{{ row.label }}</dt>
          <dd class="break-all font-semibold tabular-nums">{{ row.value }}</dd>
        </div>

        <button
          type="button"
          class="flex size-10 shrink-0 items-center justify-center rounded-full transition-colors hover:bg-paper-deep"
          :aria-label="copied === row.id ? `${row.label} copiado` : `Copiar ${row.label}`"
          @click="copy(row.id, row.value)"
        >
          <Check v-if="copied === row.id" class="size-4 text-open" aria-hidden="true" />
          <Copy v-else class="size-4" aria-hidden="true" />
        </button>
      </div>
    </dl>

    <p v-if="settings?.payment_holder" class="mt-3 text-sm text-ink-soft">
      A nombre de <span class="font-medium text-ink">{{ settings.payment_holder }}</span>
    </p>
  </section>
</template>
