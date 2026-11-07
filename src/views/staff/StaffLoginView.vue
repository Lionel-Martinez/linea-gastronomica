<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import ConfigMissing from '../../components/ui/ConfigMissing.vue'
import { friendlyError } from '../../lib/api'
import { signIn } from '../../lib/auth'
import { businessName } from '../../lib/format'
import { isSupabaseConfigured } from '../../lib/supabase'

const route = useRoute()
const router = useRouter()

const email = ref('')
const password = ref('')
const busy = ref(false)
const error = ref('')

async function submit() {
  if (busy.value) return

  busy.value = true
  error.value = ''

  try {
    await signIn(email.value.trim(), password.value)

    // Solo se acepta volver a rutas internas del panel.
    const target = route.query.redirect
    const redirect =
      typeof target === 'string' && target.startsWith('/staff') && !target.startsWith('//')
        ? target
        : '/staff'

    await router.replace(redirect)
  } catch (e) {
    error.value = friendlyError(e)
  } finally {
    busy.value = false
  }
}

onMounted(() => {
  document.title = `Personal · ${businessName}`
})
</script>

<template>
  <div class="min-h-dvh bg-paper text-ink">
    <div class="wrap max-w-md pb-16 pt-14 sm:pt-20">
      <p class="text-[13px] font-medium text-ink-soft">{{ businessName }}</p>

      <h1
        class="font-display mt-2 text-[clamp(3rem,14vw,4.5rem)] font-semibold leading-[0.92] tracking-[-0.02em]"
      >
        Personal
      </h1>

      <p class="font-display mt-4 text-lg italic text-ink-soft">
        Ingresá para ver los pedidos y editar la carta.
      </p>

      <ConfigMissing v-if="!isSupabaseConfigured" />

      <form v-else class="mt-8 space-y-5" @submit.prevent="submit">
        <div>
          <label for="staff-email" class="mb-1.5 block text-sm font-medium">Email</label>
          <input
            id="staff-email"
            v-model="email"
            type="email"
            required
            autocomplete="username"
            class="field"
          />
        </div>

        <div>
          <label for="staff-password" class="mb-1.5 block text-sm font-medium">Contraseña</label>
          <input
            id="staff-password"
            v-model="password"
            type="password"
            required
            autocomplete="current-password"
            class="field"
          />
        </div>

        <p v-if="error" class="text-sm font-medium text-accent-deep" role="alert">{{ error }}</p>

        <button type="submit" class="btn-solid w-full" :disabled="busy">
          {{ busy ? 'Ingresando…' : 'Ingresar' }}
        </button>
      </form>
    </div>
  </div>
</template>
