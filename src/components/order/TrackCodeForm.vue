<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { Search } from '@lucide/vue'
import { getLastCode } from '../../lib/lastOrder'
import { formatCode } from '../../lib/types'

const props = withDefaults(defineProps<{ id?: string; compact?: boolean }>(), {
  id: 'track-code',
  compact: false
})

const router = useRouter()
const code = ref('')
const error = ref('')
const last = getLastCode()

// Sin I, L, O, 0 ni 1: el código nunca las usa.
const normalize = (value: string) => value.replace(/[^a-z0-9]/gi, '').toUpperCase()

function submit() {
  const clean = normalize(code.value)

  if (clean.length !== 8) {
    error.value = 'El código tiene 8 letras y números, por ejemplo K7M2-9QXA.'
    document.getElementById(props.id)?.focus()
    return
  }

  error.value = ''
  void router.push({ name: 'track', params: { code: clean } })
}
</script>

<template>
  <form class="space-y-2" novalidate @submit.prevent="submit">
    <label :for="id" class="block text-sm font-medium">Código de tu pedido</label>

    <div class="flex gap-2">
      <input
        :id="id"
        v-model="code"
        type="text"
        inputmode="text"
        autocapitalize="characters"
        autocomplete="off"
        spellcheck="false"
        maxlength="12"
        placeholder="K7M2-9QXA"
        class="field min-w-0 flex-1 font-semibold uppercase tracking-widest"
        :aria-describedby="error ? `${id}-error` : undefined"
        :aria-invalid="error ? 'true' : undefined"
      />
      <button type="submit" class="btn-solid shrink-0">
        <Search class="size-4" aria-hidden="true" />
        Ver pedido
      </button>
    </div>

    <p v-if="error" :id="`${id}-error`" class="text-sm font-medium text-accent-deep" role="alert">
      {{ error }}
    </p>

    <p v-if="last && !compact" class="text-sm text-ink-soft">
      Tu último pedido:
      <RouterLink
        :to="{ name: 'track', params: { code: last } }"
        class="font-semibold tracking-wider text-ink underline underline-offset-4"
      >
        {{ formatCode(last) }}
      </RouterLink>
    </p>
  </form>
</template>
