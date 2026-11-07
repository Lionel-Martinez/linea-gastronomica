<template>
  <section class="mt-8 border border-ink p-5" role="alert">
    <h2 class="font-display text-2xl font-semibold leading-tight">Falta conectar Supabase</h2>

    <p class="mt-2 text-[15px] text-ink-soft">
      Esta parte necesita una base de datos. Creá un archivo
      <code class="bg-paper-deep px-1">.env</code> en la raíz del proyecto con estas dos líneas
      y reiniciá el servidor:
    </p>

    <pre
      class="mt-3 overflow-x-auto bg-paper-deep p-3 text-[13px] leading-relaxed"
    >VITE_SUPABASE_URL=https://tu-proyecto.supabase.co
VITE_SUPABASE_ANON_KEY=tu-clave-publica</pre>

    <p class="mt-3 text-sm text-ink-soft">
      Los pasos completos están en <code class="bg-paper-deep px-1">supabase/README.md</code>.
    </p>
  </section>
</template>
