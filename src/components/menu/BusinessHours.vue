<script setup lang="ts">
import { computed, ref } from 'vue'
import menuData from '../../data/menu.json'

const expanded = ref(false)

const schedule = menuData.business.schedule

const currentDay = computed(() => {
  const weekday = new Intl.DateTimeFormat('en-US', {
    weekday: 'long',
    timeZone: schedule.timezone
  }).format(new Date())

  const days: Record<string, number> = {
    Sunday: 0,
    Monday: 1,
    Tuesday: 2,
    Wednesday: 3,
    Thursday: 4,
    Friday: 5,
    Saturday: 6
  }

  return days[weekday]
})

const today = computed(() =>
  schedule.days.find(day => day.id === currentDay.value)!
)

const currentTime = computed(() =>
  new Intl.DateTimeFormat('en-GB', {
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
    timeZone: schedule.timezone
  }).format(new Date())
)

const isOpen = computed(() => {
  if (!today.value || today.value.closed) return false

  return today.value.shifts.some(shift =>
    currentTime.value >= shift.open &&
    currentTime.value < shift.close
  )
})

const statusText = computed(() => {
  if (!today.value || today.value.closed || !today.value.shifts.length) {
    return 'Cerrado hoy'
  }

  if (isOpen.value) {
    return 'Abierto ahora'
  }

  const nextShift = today.value.shifts.find(
    shift => currentTime.value < shift.open
  )

  if (nextShift) {
    return `Próxima apertura: ${nextShift.open}`
  }

  return 'Cerrado ahora'
})
</script>

<template>
  <section class="mx-auto mt-5 w-full max-w-5xl px-5">
    <div class="rounded-2xl border border-[#eee7df] bg-white p-4">

      <div class="flex items-center justify-between gap-3">
        <div>
          <p class="text-xs uppercase tracking-wider text-[#9a8f85]">
            Horario de atención
          </p>

          <p class="mt-1 font-semibold">
            {{ today.name }}:
            <span v-if="!today.closed">
              <span
  v-for="(shift, index) in today.shifts"
  :key="index"
>
  {{ shift.open }} - {{ shift.close }}
  <span v-if="index < today.shifts.length - 1"> · </span>
</span>
            </span>
            <span v-else>Descansamos</span>
          </p>
        </div>

        <span
          class="rounded-full px-3 py-1.5 text-xs font-semibold"
          :class="isOpen
            ? 'bg-green-100 text-green-700'
            : 'bg-red-100 text-red-700'"
        >
          {{ statusText }}
        </span>
      </div>
      
      <button
        @click="expanded = !expanded"
        class="mt-4 flex w-full items-center justify-between border-t border-[#eee7df] pt-3 text-sm font-medium text-[#8c6650]"
      >
        {{ expanded ? 'Ocultar horarios' : 'Ver horarios de toda la semana' }}

        <span>{{ expanded ? '−' : '+' }}</span>
      </button>

      <div v-if="expanded" class="mt-3 space-y-3">
        <div
          v-for="day in schedule.days"
          :key="day.id"
          class="flex items-center justify-between text-sm"
          :class="day.id === currentDay ? 'font-bold text-[#604638]' : 'text-[#71675f]'"
        >
          <span>{{ day.name }}</span>

          <span v-if="day.closed">Cerrado</span>
          <span v-else class="text-right">
  <span
    v-for="(shift, index) in day.shifts"
    :key="index"
  >
    {{ shift.open }} - {{ shift.close }}
    <span v-if="index < day.shifts.length - 1"> · </span>
  </span>
</span>
        </div>
      </div>

    </div>
  </section>
</template>