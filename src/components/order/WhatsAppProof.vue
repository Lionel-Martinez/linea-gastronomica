<script setup lang="ts">
import { computed } from 'vue'
import { MessageCircle } from '@lucide/vue'
import { formatPrice } from '../../lib/format'
import { getName } from '../../lib/lastOrder'

const props = defineProps<{
  number: string
  table: number
  total: number
}>()

// Abre WhatsApp con el mensaje armado; el cliente adjunta la captura del comprobante.
const href = computed(() => {
  const name = getName()
  const text =
    `Hola, te envío el comprobante de mi pedido de la mesa ${props.table}` +
    `${name ? ` (${name})` : ''}. Total: ${formatPrice(props.total)}.`

  return `https://wa.me/${props.number}?text=${encodeURIComponent(text)}`
})
</script>

<template>
  <a
    v-if="number"
    :href="href"
    target="_blank"
    rel="noopener noreferrer"
    class="btn-line mt-4 w-full"
  >
    <MessageCircle class="size-4" aria-hidden="true" />
    Enviar comprobante por WhatsApp
  </a>
</template>
