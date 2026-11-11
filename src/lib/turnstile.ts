// Turnstile (Cloudflare): "no soy un robot" casi siempre invisible.
// Solo se usa si el local lo activó (VITE_TURNSTILE_SITEKEY). Si no, los pedidos van directo como siempre.

const SITE_KEY = (import.meta.env.VITE_TURNSTILE_SITEKEY as string | undefined)?.trim() || ''

export const turnstileEnabled = Boolean(SITE_KEY)

interface TurnstileApi {
  render: (el: HTMLElement, options: Record<string, unknown>) => string
  remove: (id: string) => void
}

let loading: Promise<TurnstileApi> | null = null

function loadScript(): Promise<TurnstileApi> {
  const api = (window as unknown as { turnstile?: TurnstileApi }).turnstile
  if (api) return Promise.resolve(api)

  loading ??= new Promise<TurnstileApi>((resolve, reject) => {
    const script = document.createElement('script')
    script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit'
    script.async = true
    script.onload = () => {
      const loaded = (window as unknown as { turnstile?: TurnstileApi }).turnstile
      if (loaded) resolve(loaded)
      else reject(new Error('turnstile_failed'))
    }
    script.onerror = () => {
      loading = null
      reject(new Error('turnstile_failed'))
    }
    document.head.appendChild(script)
  })

  return loading
}

/** Pide un token de un solo uso. Si Cloudflare necesita un desafío, aparece en un cuadro sobre la pantalla. */
export async function getTurnstileToken(): Promise<string> {
  const api = await loadScript()

  return new Promise<string>((resolve, reject) => {
    const box = document.createElement('div')
    box.setAttribute('role', 'dialog')
    box.setAttribute('aria-label', 'Verificación de seguridad')
    box.style.cssText =
      'position:fixed;left:50%;bottom:1.5rem;transform:translateX(-50%);z-index:60;background:#fff;padding:0.5rem;border-radius:0.75rem;box-shadow:0 4px 24px rgba(0,0,0,.25)'
    box.hidden = true
    document.body.appendChild(box)

    let id = ''
    let done = false
    const finish = (fn: () => void) => {
      if (done) return
      done = true
      window.clearTimeout(timer)
      try {
        if (id) api.remove(id)
      } catch {
        /* ya no existe */
      }
      box.remove()
      fn()
    }
    const timer = window.setTimeout(() => finish(() => reject(new Error('turnstile_failed'))), 60_000)

    id = api.render(box, {
      sitekey: SITE_KEY,
      appearance: 'interaction-only',
      language: 'es',
      callback: (token: string) => finish(() => resolve(token)),
      'error-callback': () => finish(() => reject(new Error('turnstile_failed'))),
      'timeout-callback': () => finish(() => reject(new Error('turnstile_failed'))),
      'before-interactive-callback': () => {
        box.hidden = false
      }
    })
  })
}
