<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { RouterLink } from 'vue-router'
import { friendlyError, loadSettings, saveSettings } from '../../lib/api'
import { businessName } from '../../lib/format'
import BlockedPhones from '../../components/staff/BlockedPhones.vue'
import ZonesEditor from '../../components/staff/ZonesEditor.vue'
import { refreshPanel } from '../../lib/panel'
import { effectivePlan, hasRemoteOrdering, hasTableOrdering, planMismatch, PLAN_LABEL, PLAN_SUMMARY } from '../../lib/plans'
import { PAYMENT_LABEL, PAYMENT_METHODS, type PaymentMethod, type Plan } from '../../lib/types'

const form = reactive({
  table_count: 10,
  payment_alias: '',
  payment_cbu: '',
  payment_holder: '',
  ordering_enabled: true,
  payment_methods: ['transfer', 'cash'] as PaymentMethod[],
  whatsapp_number: '',
  pickup_enabled: false,
  delivery_enabled: false,
  retention_days: 15 as 7 | 15 | 30,
  stops_visibility: 'street' as 'street' | 'zone',
  delivery_code_enabled: false,
  max_active_per_table: 3,
  max_pending_per_phone: 5,
  max_orders_per_phone_hour: 3,
  max_remote_per_hour: 20,
  near_radius_m: 300 as 150 | 300 | 500,
  plan: 'full' as Plan
})
const dbMismatch = ref(false)
/** Lo que se muestra sigue a la edición publicada, aunque la base tenga otro plan. */
function applyEdition(dbPlan: Plan) {
  dbMismatch.value = planMismatch(dbPlan)
  form.plan = effectivePlan(dbPlan)
}
const loading = ref(true)
const saving = ref(false)
const error = ref('')
const saved = ref(false)
const savedTables = ref(0)

async function submit() {
  if (saving.value) return

  const tables = Math.trunc(Number(form.table_count))
  if (!Number.isFinite(tables) || tables < 1 || tables > 200) {
    error.value = 'La cantidad de mesas tiene que estar entre 1 y 200.'
    return
  }

  const cbu = form.payment_cbu.replace(/\s/g, '')
  if (cbu && !/^\d{22}$/.test(cbu)) {
    error.value = 'El CBU/CVU tiene que tener 22 números.'
    return
  }

  const whatsapp = form.whatsapp_number.replace(/[\s+()-]/g, '')
  if (whatsapp && !/^\d{8,15}$/.test(whatsapp)) {
    error.value = 'El WhatsApp tiene que tener entre 8 y 15 números, con código de país. Ej.: 5493878123456.'
    return
  }

  const takesOrders = form.ordering_enabled || form.pickup_enabled || form.delivery_enabled
  if (takesOrders && !form.payment_methods.length) {
    error.value = 'Elegí al menos una forma de pago, o desactivá los pedidos.'
    return
  }

  if (form.delivery_enabled && !form.payment_methods.some((m) => m === 'transfer' || m === 'cash')) {
    error.value = 'Para delivery tiene que estar habilitada la transferencia o el efectivo.'
    return
  }

  const limits = [
    ['mesa', form.max_active_per_table, 20],
    ['pendientes por teléfono', form.max_pending_per_phone, 20],
    ['pedidos por teléfono por hora', form.max_orders_per_phone_hour, 20],
    ['pedidos del local por hora', form.max_remote_per_hour, 200]
  ] as const
  const badLimit = limits.find(([, value, max]) => !Number.isInteger(Number(value)) || Number(value) < 1 || Number(value) > max)
  if (badLimit) {
    error.value = `El límite de ${badLimit[0]} tiene que ser un número entre 1 y ${badLimit[2]}.`
    return
  }

  saving.value = true
  saved.value = false
  error.value = ''

  try {
    await saveSettings({
      table_count: tables,
      payment_alias: form.payment_alias.trim(),
      payment_cbu: cbu,
      payment_holder: form.payment_holder.trim(),
      ordering_enabled: form.ordering_enabled,
      payment_methods: PAYMENT_METHODS.filter((method) => form.payment_methods.includes(method)),
      whatsapp_number: whatsapp,
      pickup_enabled: form.pickup_enabled,
      delivery_enabled: form.delivery_enabled,
      retention_days: Number(form.retention_days) as 7 | 15 | 30,
      stops_visibility: form.stops_visibility,
      delivery_code_enabled: form.delivery_code_enabled,
      max_active_per_table: Math.trunc(Number(form.max_active_per_table)),
      max_pending_per_phone: Math.trunc(Number(form.max_pending_per_phone)),
      max_orders_per_phone_hour: Math.trunc(Number(form.max_orders_per_phone_hour)),
      max_remote_per_hour: Math.trunc(Number(form.max_remote_per_hour)),
      near_radius_m: Number(form.near_radius_m) as 150 | 300 | 500
    })

    // Se vuelve a leer de la base: lo que se muestra es lo que realmente quedó guardado.
    const fresh = await loadSettings()
    if (
      fresh.table_count !== tables ||
      fresh.ordering_enabled !== form.ordering_enabled ||
      fresh.pickup_enabled !== form.pickup_enabled ||
      fresh.delivery_enabled !== form.delivery_enabled
    ) {
      throw new Error('not_saved')
    }

    Object.assign(form, fresh, { payment_methods: [...fresh.payment_methods] })
    applyEdition(fresh.plan)
    savedTables.value = fresh.table_count
    saved.value = true
    void refreshPanel()
  } catch (e) {
    error.value = friendlyError(e)
  } finally {
    saving.value = false
  }
}

onMounted(async () => {
  document.title = `Ajustes · ${businessName}`

  try {
    const data = await loadSettings()
    Object.assign(form, data, { payment_methods: [...data.payment_methods] })
    applyEdition(data.plan)
  } catch (e) {
    error.value = friendlyError(e)
  } finally {
    loading.value = false
  }
})
</script>

<template>
  <main class="wrap max-w-6xl pb-16 pt-8">
    <h1 class="font-display text-[2rem] font-semibold leading-none tracking-tight">Ajustes</h1>

    <p v-if="loading" class="py-16 text-center font-display text-xl italic text-ink-soft" aria-busy="true">
      Cargando…
    </p>

    <form v-else class="mt-8 max-w-xl space-y-6" @submit.prevent="submit">
      <div class="border border-ink/40 p-4" data-plan>
        <p class="text-sm text-ink-soft">Plan contratado</p>
        <p class="font-display text-xl font-semibold">{{ PLAN_LABEL[form.plan] }}</p>
        <p class="mt-1 text-sm text-ink-soft">{{ PLAN_SUMMARY[form.plan] }}</p>
        <p class="mt-2 text-sm text-ink-soft">Para cambiar de plan, consultá con LM Studio.</p>
        <p v-if="dbMismatch" class="mt-2 text-sm font-medium text-accent-deep" data-plan-mismatch>
          La base de datos todavía tiene otro plan. Avisá a LM Studio para que lo deje igual a esta edición.
        </p>
      </div>

      <fieldset v-if="hasTableOrdering(form.plan)" class="space-y-2">
        <legend class="font-display pr-3 text-xl font-semibold">Pedidos desde la mesa</legend>
        <label class="flex items-start gap-3 text-[15px]">
          <input v-model="form.ordering_enabled" type="checkbox" class="mt-1 size-4 accent-accent" />
          <span>
            Recibir pedidos desde el QR de cada mesa
            <span class="mt-0.5 block text-sm text-ink-soft">
              Si lo desactivás, el local queda solo con la carta digital (que sigue siendo editable):
              no se pueden hacer pedidos y desaparecen la pantalla de pedidos y los QR de mesa.
            </span>
          </span>
        </label>
      </fieldset>

      <fieldset v-if="hasTableOrdering(form.plan) || hasRemoteOrdering(form.plan)" class="space-y-3 border-t border-ink pt-5" data-limits>
        <legend class="font-display pr-3 text-xl font-semibold">Límites contra pedidos falsos</legend>
        <p class="text-sm text-ink-soft">
          Cuando se alcanza un límite, el sistema rechaza el pedido nuevo y le pide al cliente que consulte con el local.
        </p>
        <div class="grid gap-3 sm:grid-cols-2">
          <div v-if="hasTableOrdering(form.plan)">
            <label for="s-lim-table" class="mb-1.5 block text-sm font-medium">Pedidos en curso por mesa</label>
            <input id="s-lim-table" v-model.number="form.max_active_per_table" type="number" inputmode="numeric" min="1" max="20" class="field" />
          </div>
          <template v-if="hasRemoteOrdering(form.plan) && (form.pickup_enabled || form.delivery_enabled)">
            <div>
              <label for="s-lim-pending" class="mb-1.5 block text-sm font-medium">Sin confirmar por teléfono</label>
              <input id="s-lim-pending" v-model.number="form.max_pending_per_phone" type="number" inputmode="numeric" min="1" max="20" class="field" />
            </div>
            <div>
              <label for="s-lim-phone-hour" class="mb-1.5 block text-sm font-medium">Pedidos por teléfono por hora</label>
              <input id="s-lim-phone-hour" v-model.number="form.max_orders_per_phone_hour" type="number" inputmode="numeric" min="1" max="20" class="field" />
            </div>
            <div>
              <label for="s-lim-local-hour" class="mb-1.5 block text-sm font-medium">Retiro y delivery por hora (total)</label>
              <input id="s-lim-local-hour" v-model.number="form.max_remote_per_hour" type="number" inputmode="numeric" min="1" max="200" class="field" />
            </div>
          </template>
        </div>
      </fieldset>

 <fieldset v-if="hasRemoteOrdering(form.plan)" class="space-y-3 border-t border-ink pt-5">
        <legend class="font-display pr-3 text-xl font-semibold">Pedidos desde casa</legend>
        <p class="text-sm text-ink-soft">
          El cliente arma el pedido en la carta, lo retira o pide delivery, y lo sigue con un código.
          Se prende por separado de los pedidos en la mesa.
        </p>

        <label class="flex items-start gap-3 text-[15px]">
          <input v-model="form.pickup_enabled" type="checkbox" class="mt-1 size-4 accent-accent" />
          <span>Retiro en el local</span>
        </label>

        <label class="flex items-start gap-3 text-[15px]">
          <input v-model="form.delivery_enabled" type="checkbox" class="mt-1 size-4 accent-accent" />
          <span>
            Delivery a domicilio
            <span class="mt-0.5 block text-sm text-ink-soft">
              Cargá abajo las zonas de envío con su precio. En delivery solo se acepta transferencia o efectivo.
            </span>
          </span>
        </label>

        <label v-if="form.delivery_enabled" class="flex items-start gap-3 text-[15px]">
          <input v-model="form.delivery_code_enabled" type="checkbox" class="mt-1 size-4 accent-accent" />
          <span>
            Código de entrega
            <span class="mt-0.5 block text-sm text-ink-soft">
              Cada delivery nuevo tiene un código de 4 dígitos que ve el cliente. El repartidor lo escribe para
              marcar «Entregado». Si el cliente no lo tiene, se entrega confirmando su nombre y queda registrado.
            </span>
          </span>
        </label>

        <div v-if="form.pickup_enabled || form.delivery_enabled" class="space-y-4 pt-1">
          <div v-if="form.delivery_enabled">
            <label for="s-near" class="mb-1.5 block text-sm font-medium">
              Avisar «el delivery está cerca» a una distancia de
            </label>
            <select id="s-near" v-model.number="form.near_radius_m" class="field">
              <option :value="150">150 metros</option>
              <option :value="300">300 metros</option>
              <option :value="500">500 metros</option>
            </select>
            <p class="mt-1.5 text-sm text-ink-soft">
              Se avisa solo, en línea recta hasta la dirección. Funciona si el cliente compartió su ubicación.
            </p>
          </div>
          <div>
            <label for="s-retention" class="mb-1.5 block text-sm font-medium">
              Borrar teléfono y dirección de los clientes después de
            </label>
            <select id="s-retention" v-model.number="form.retention_days" class="field">
              <option :value="7">7 días</option>
              <option :value="15">15 días</option>
              <option :value="30">30 días</option>
            </select>
            <p class="mt-1.5 text-sm text-ink-soft">
              Se cuenta desde que el pedido termina. El pedido, los productos y el total se conservan.
            </p>
          </div>

          <div v-if="form.delivery_enabled">
            <label for="s-stops" class="mb-1.5 block text-sm font-medium">
              Qué ve el cliente de las otras paradas del reparto
            </label>
            <select id="s-stops" v-model="form.stops_visibility" class="field">
              <option value="street">La calle (sin número)</option>
              <option value="zone">Solo la zona</option>
            </select>
          </div>

          <p v-if="!form.whatsapp_number.trim()" class="text-sm text-accent-deep">
            Cargá el WhatsApp del local (más abajo) para que los clientes puedan avisar sus pedidos.
          </p>
        </div>
      </fieldset>

      <div v-if="hasTableOrdering(form.plan)" class="border-t border-ink pt-5">
        <label for="s-tables" class="mb-1.5 block text-sm font-medium">Cantidad de mesas</label>
        <input id="s-tables" v-model.number="form.table_count" type="number" min="1" max="200" class="field" />
        <p class="mt-1.5 text-sm text-ink-soft">
          Los pedidos solo se aceptan para mesas de 1 a este número. Los QR de cada mesa están en
          <RouterLink :to="{ name: 'staff-qr' }" class="underline underline-offset-4">Códigos QR</RouterLink>.
        </p>
      </div>

      <fieldset class="space-y-3 border-t border-ink pt-5">
        <legend class="font-display pr-3 text-xl font-semibold">Formas de pago</legend>
        <p class="text-sm text-ink-soft">
          El cliente elige una al pedir. No hay pago online: se cobra en el local o por transferencia.
        </p>
        <label v-for="method in PAYMENT_METHODS" :key="method" class="flex items-center gap-3 text-[15px]">
          <input v-model="form.payment_methods" type="checkbox" :value="method" class="size-4 accent-accent" />
          {{ PAYMENT_LABEL[method] }}
        </label>
      </fieldset>

      <fieldset class="space-y-4 border-t border-ink pt-5">
        <legend class="font-display pr-3 text-xl font-semibold">Datos para transferencias</legend>
        <p class="text-sm text-ink-soft">Se muestran al cliente solo si elige pagar por transferencia.</p>

        <div>
          <label for="s-alias" class="mb-1.5 block text-sm font-medium">Alias</label>
          <input id="s-alias" v-model="form.payment_alias" type="text" maxlength="40" class="field" />
        </div>

        <div>
          <label for="s-cbu" class="mb-1.5 block text-sm font-medium">CBU / CVU</label>
          <input id="s-cbu" v-model="form.payment_cbu" type="text" inputmode="numeric" class="field" />
        </div>

        <div>
          <label for="s-holder" class="mb-1.5 block text-sm font-medium">Titular</label>
          <input id="s-holder" v-model="form.payment_holder" type="text" maxlength="80" class="field" />
        </div>

        <div>
          <label for="s-wa" class="mb-1.5 block text-sm font-medium">WhatsApp del local (para comprobantes)</label>
          <input
            id="s-wa"
            v-model="form.whatsapp_number"
            type="tel"
            inputmode="numeric"
            placeholder="5493878123456"
            class="field"
          />
          <p class="mt-1.5 text-sm text-ink-soft">
            Con código de país, sin + ni espacios. Argentina: 549 + código de área + número.
            El cliente ve un botón para enviar el comprobante a este número.
          </p>
        </div>
      </fieldset>

      <p v-if="error" class="text-sm font-medium text-accent-deep" role="alert">{{ error }}</p>
      <p v-if="saved" class="text-sm font-medium text-open" role="status">
        Cambios guardados. El local tiene {{ savedTables }} mesas.
        <RouterLink :to="{ name: 'staff-qr' }" class="underline underline-offset-4">Ver los códigos QR</RouterLink>
      </p>

      <button type="submit" class="btn-solid w-full sm:w-auto" :disabled="saving">
        {{ saving ? 'Guardando…' : 'Guardar cambios' }}
      </button>
    </form>

    <div v-if="!loading" class="mt-10 max-w-xl space-y-8">
      <ZonesEditor v-if="hasRemoteOrdering(form.plan) && form.delivery_enabled" />
      <BlockedPhones v-if="hasRemoteOrdering(form.plan) && (form.pickup_enabled || form.delivery_enabled)" />
    </div>
  </main>
</template>
