<script setup lang="ts">
import { onMounted, onUnmounted } from 'vue'
import SuspendedView from './views/public/SuspendedView.vue'
import { checkSuspension, recheckSuspensionIfStale, suspension } from './lib/suspension'

function onVisible() {
  if (document.visibilityState === 'visible') recheckSuspensionIfStale()
}

onMounted(() => {
  void checkSuspension()
  document.addEventListener('visibilitychange', onVisible)
})
onUnmounted(() => document.removeEventListener('visibilitychange', onVisible))
</script>

<template>
  <SuspendedView v-if="suspension.suspended" />
  <RouterView v-else-if="suspension.checked" />
</template>
