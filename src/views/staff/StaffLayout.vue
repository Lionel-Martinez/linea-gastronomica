<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { RouterLink, RouterView, useRoute, useRouter } from 'vue-router'
import { LogOut } from '@lucide/vue'
import { onSignedOut, sessionEmail, signOut } from '../../lib/auth'
import { businessName } from '../../lib/format'
import { panel, refreshPanel } from '../../lib/panel'

const router = useRouter()
const route = useRoute()
const email = ref('')

let stopListening: (() => void) | undefined

// Sin pedidos activados (plan solo-carta) no hay pantalla de pedidos; los ajustes son solo de encargados.
const links = computed(() =>
  [
    { name: 'staff-orders', label: 'Pedidos', show: panel.ordering },
    { name: 'staff-products', label: 'Productos', show: true },
    { name: 'staff-settings', label: 'Ajustes', show: panel.manager },
    { name: 'staff-qr', label: 'Códigos QR', show: true }
  ].filter((link) => link.show)
)

watch(
  () => [panel.ready, panel.ordering, route.name] as const,
  ([ready, ordering, name]) => {
    if (ready && !ordering && name === 'staff-orders') {
      void router.replace({ name: 'staff-products' })
    }
  },
  { immediate: true }
)

async function logout() {
  await signOut()
  await router.replace({ name: 'staff-login' })
}

onMounted(async () => {
  email.value = await sessionEmail()
  void refreshPanel()

  // Si la sesión vence o se cierra en otra pestaña, volvemos al login.
  stopListening = onSignedOut(() => {
    void router.replace({ name: 'staff-login' })
  })
})

onUnmounted(() => stopListening?.())
</script>

<template>
  <div class="min-h-dvh bg-paper text-ink">
    <header class="border-b-[3px] border-ink print:hidden">
      <div class="wrap max-w-6xl flex items-center justify-between gap-4 py-4">
        <div class="min-w-0">
          <p class="truncate text-[13px] font-medium text-ink-soft">{{ businessName }}</p>
          <p class="font-display text-2xl font-semibold leading-none">Personal</p>
        </div>

        <div class="flex shrink-0 items-center gap-3">
          <span class="hidden max-w-48 truncate text-sm text-ink-soft sm:block">{{ email }}</span>
          <button type="button" class="btn-line btn-small" @click="logout">
            <LogOut class="size-4" aria-hidden="true" />
            Salir
          </button>
        </div>
      </div>

      <nav class="wrap max-w-6xl" aria-label="Secciones del panel">
        <div class="no-scrollbar -mx-1 flex gap-6 overflow-x-auto px-1">
          <RouterLink
            v-for="link in links"
            :key="link.name"
            :to="{ name: link.name }"
            class="relative shrink-0 py-3 text-sm font-medium text-ink-soft transition-colors hover:text-ink"
            exact-active-class="!text-ink after:absolute after:inset-x-0 after:-bottom-px after:h-0.5 after:bg-accent"
          >
            {{ link.label }}
          </RouterLink>
        </div>
      </nav>
    </header>

    <RouterView />
  </div>
</template>
