import { nextTick, onUnmounted, watch, type Ref } from 'vue'

const FOCUSABLE =
  'a[href],button:not([disabled]),input:not([disabled]):not([type=hidden]),select:not([disabled]),textarea:not([disabled]),[tabindex]:not([tabindex="-1"])'

/**
 * Manejo de foco para ventanas modales, para quien navega con teclado o lector de pantalla:
 * al abrir, el foco entra a la ventana; Tab y Shift+Tab no salen de ella; al cerrar,
 * el foco vuelve al botón que la abrió.
 */
export function useDialogFocus(open: Ref<boolean>, container: Ref<HTMLElement | null>) {
  let opener: HTMLElement | null = null

  const focusables = () =>
    [...(container.value?.querySelectorAll<HTMLElement>(FOCUSABLE) ?? [])].filter(
      (el) => el.offsetParent !== null || el === document.activeElement
    )

  function onKeydown(event: KeyboardEvent) {
    if (event.key !== 'Tab' || !container.value) return

    const list = focusables()
    if (!list.length) {
      event.preventDefault()
      return
    }

    const first = list[0]!
    const last = list[list.length - 1]!
    const active = document.activeElement as HTMLElement | null
    const inside = active ? container.value.contains(active) : false

    if (!inside) {
      event.preventDefault()
      first.focus()
    } else if (event.shiftKey && active === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && active === last) {
      event.preventDefault()
      first.focus()
    }
  }

  watch(open, async (isOpen) => {
    if (isOpen) {
      opener = document.activeElement as HTMLElement | null
      document.addEventListener('keydown', onKeydown)

      await nextTick()
      ;(focusables()[0] ?? container.value)?.focus()
    } else {
      document.removeEventListener('keydown', onKeydown)
      opener?.focus?.()
      opener = null
    }
  })

  onUnmounted(() => document.removeEventListener('keydown', onKeydown))
}
