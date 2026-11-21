<script setup lang="ts">
import { missingVars } from '../../lib/supabase'
</script>

<template>
  <section class="mt-8 border border-ink p-5" role="alert">
    <h2 class="font-display text-2xl font-semibold leading-tight">Falta conectar Supabase</h2>

    <p class="mt-2 text-[15px] text-ink-soft">
      Esta parte necesita una base de datos. Creá un archivo
      <code class="bg-paper-deep px-1">.env</code> en la raíz del proyecto con estas tres líneas
      y reiniciá el servidor:
    </p>

    <pre
      class="mt-3 overflow-x-auto bg-paper-deep p-3 text-[13px] leading-relaxed"
    >VITE_SUPABASE_URL=https://tu-proyecto.supabase.co
VITE_SUPABASE_ANON_KEY=tu-clave-publica
VITE_TENANT=nombre-del-local</pre>

    <p v-if="missingVars.length" class="mt-3 text-sm font-medium" data-missing-vars>
      Variables que faltan en esta publicación: {{ missingVars.join(', ') }}.
    </p>

    <p class="mt-2 text-sm text-ink-soft">
      En Cloudflare se cargan en <strong>Settings → Build → Variables and secrets</strong> (las variables de la sección
      «Runtime» no sirven: se leen al compilar). Después hay que volver a desplegar.
    </p>

    <p class="mt-3 text-sm text-ink-soft">
      Los pasos completos están en <code class="bg-paper-deep px-1">supabase/README.md</code>.
    </p>
  </section>
</template>
