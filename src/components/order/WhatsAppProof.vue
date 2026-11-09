<script setup lang="ts">
import { computed } from 'vue'
import { MessageCircle } from '@lucide/vue'
import { formatPrice } from '../../lib/format'
import { getName } from '../../lib/lastOrder'

const props = defineProps<{
  number: string
  total: number
  /** Pedido en mesa. */
  table?: number
  /** Pedido a distancia: se identifica con su código. */
  code?: string
}>()

// Abre WhatsApp con el mensaje armado; el cliente adjunta la captura del comprobante.
const href = computed(() => {
  const name = getName()
  const which = props.code ? `mi pedido ${props.code}` : `mi pedido de la mesa ${props.table}`
  const text =
    `Hola, te envío el comprobante de ${which}` +
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
