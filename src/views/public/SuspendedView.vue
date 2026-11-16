<script setup lang="ts">
// Pantalla que reemplaza todo el sitio cuando el servicio está suspendido.
</script>

<template>
  <main class="mx-auto flex min-h-screen max-w-md flex-col justify-center px-6 py-12 text-center" data-suspended>
    <h1 class="font-display text-3xl font-semibold">Servicio suspendido</h1>
    <p class="mt-4 text-ink-soft">
      Este sitio no está disponible por el momento. Si necesitás hacer un pedido, comunicate directamente con el local.
    </p>
    <p class="mt-8 text-sm text-ink-soft">
      ¿Sos el encargado? Comunicate con
      <a class="underline" href="https://lm-studio.com.ar" target="_blank" rel="noopener">LM Studio</a>
      para regularizar el servicio.
    </p>
  </main>
</template>
