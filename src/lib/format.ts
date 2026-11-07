import menuData from '../data/menu.json'

export const businessName = menuData.business.name

const priceFormatter = new Intl.NumberFormat('es-AR', {
  style: 'currency',
  currency: menuData.business.currency,
  minimumFractionDigits: 0,
  maximumFractionDigits: 2
})

export const formatPrice = (value: number) => priceFormatter.format(value)

const clockFormatter = new Intl.DateTimeFormat('es-AR', {
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23',
  timeZone: menuData.business.schedule.timezone
})

export const formatClock = (iso: string) => clockFormatter.format(new Date(iso))

export function minutesSince(iso: string, now: number = Date.now()) {
  return Math.max(0, Math.floor((now - new Date(iso).getTime()) / 60_000))
}

export function agoLabel(minutes: number) {
  if (minutes < 1) return 'recién'
  if (minutes < 60) return `hace ${minutes} min`
  return `hace ${Math.floor(minutes / 60)} h ${minutes % 60} min`
}
