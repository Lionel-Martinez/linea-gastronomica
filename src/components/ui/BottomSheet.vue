<script setup lang="ts">
import { onUnmounted, ref, toRef, watch } from 'vue'
import { X } from '@lucide/vue'
import { useDialogFocus } from '../../composables/useDialogFocus'

const props = defineProps<{
  open: boolean
  title: string
}>()

const emit = defineEmits<{ close: [] }>()

const panel = ref<HTMLElement | null>(null)
useDialogFocus(toRef(props, 'open'), panel)

function onKeydown(event: KeyboardEvent) {
  if (event.key === 'Escape') emit('close')
}

watch(
  () => props.open,
  (open) => {
    // Evita que la página de fondo se desplace mientras la ventana está abierta.
    document.body.style.overflow = open ? 'hidden' : ''

    if (open) window.addEventListener('keydown', onKeydown)
    else window.removeEventListener('keydown', onKeydown)
  },
  { immediate: true }
)

onUnmounted(() => {
  document.body.style.overflow = ''
  window.removeEventListener('keydown', onKeydown)
})
</script>

<template>
  <Transition name="sheet">
    <div
      v-if="open"
      class="fixed inset-0 z-50 flex items-end justify-center bg-ink/50 sm:items-center sm:p-6"
      @click.self="emit('close')"
    >
      <section
        ref="panel"
        tabindex="-1"
        class="sheet-panel max-h-[90dvh] w-full max-w-md overflow-y-auto rounded-t-[14px] bg-paper p-6 shadow-2xl sm:rounded-[6px]"
        role="dialog"
        aria-modal="true"
        :aria-label="title"
      >
        <div class="mb-5 flex items-center justify-between gap-4 border-b border-ink pb-3">
          <h2 class="font-display text-[1.625rem] font-semibold leading-none">
            {{ title }}
          </h2>

          <button
            type="button"
            aria-label="Cerrar ventana"
            class="-mr-2 flex size-10 items-center justify-center rounded-full transition-colors hover:bg-paper-deep"
            @click="emit('close')"
          >
            <X class="size-5" aria-hidden="true" />
          </button>
        </div>

        <slot />
      </section>
    </div>
  </Transition>
</template>
