<script setup lang="ts">
import { Minus, Plus } from '@lucide/vue'

defineProps<{
  qty: number
  name: string
}>()

defineEmits<{
  inc: []
  dec: []
}>()
</script>

<template>
  <div class="inline-flex shrink-0 items-center border border-ink">
    <button
      type="button"
      class="flex size-10 items-center justify-center transition-colors hover:bg-paper-deep"
      :aria-label="`Quitar uno: ${name}`"
      @click="$emit('dec')"
    >
      <Minus class="size-4" aria-hidden="true" />
    </button>

    <span class="min-w-8 text-center text-[15px] font-semibold tabular-nums" aria-live="polite">
      {{ qty }}
    </span>

    <button
      type="button"
      class="flex size-10 items-center justify-center transition-colors hover:bg-paper-deep"
      :aria-label="`Agregar uno más: ${name}`"
      @click="$emit('inc')"
    >
      <Plus class="size-4" aria-hidden="true" />
    </button>
  </div>
</template>
