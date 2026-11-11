// Cloudflare Pages Function: recibe el pedido, verifica Turnstile y recién ahí lo crea en Supabase.
// Variables (Cloudflare Pages → Settings → Variables and Secrets):
//   TURNSTILE_SECRET   clave secreta de Turnstile (Secret)
//   SUPABASE_URL       https://xxxx.supabase.co
//   SUPABASE_ANON_KEY  la clave pública (publishable/anon) del proyecto
//   ORDER_GATE         el mismo texto que se guardó en la base como 'order_gate' (Secret)

interface Env {
  TURNSTILE_SECRET: string
  SUPABASE_URL: string
  SUPABASE_ANON_KEY: string
  ORDER_GATE: string
}

const RPC = { table: 'create_order', remote: 'create_remote_order' } as const

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json', 'cache-control': 'no-store' }
  })

export const onRequestPost = async ({ request, env }: { request: Request; env: Env }) => {
  if (!env.TURNSTILE_SECRET || !env.SUPABASE_URL || !env.SUPABASE_ANON_KEY || !env.ORDER_GATE) {
    return json({ message: 'server_misconfigured' }, 500)
  }

  // Solo se aceptan pedidos que salen de esta misma web.
  const origin = request.headers.get('origin')
  if (origin && origin !== new URL(request.url).origin) return json({ message: 'bad_origin' }, 403)

  const raw = await request.text()
  if (raw.length > 20_000) return json({ message: 'too_large' }, 413)

  let body: { kind?: string; args?: Record<string, unknown>; turnstile?: string }
  try {
    body = JSON.parse(raw)
  } catch {
    return json({ message: 'bad_request' }, 400)
  }

  const kind = body.kind === 'table' || body.kind === 'remote' ? body.kind : null
  if (!kind || !body.args || typeof body.args !== 'object' || Array.isArray(body.args)) {
    return json({ message: 'bad_request' }, 400)
  }
  if (typeof body.turnstile !== 'string' || !body.turnstile) {
    return json({ message: 'turnstile_failed' }, 403)
  }

  // 1) ¿Es una persona? Cloudflare lo confirma con la clave secreta.
  const form = new FormData()
  form.append('secret', env.TURNSTILE_SECRET)
  form.append('response', body.turnstile)
  const ip = request.headers.get('CF-Connecting-IP')
  if (ip) form.append('remoteip', ip)

  let human = false
  try {
    const check = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
      method: 'POST',
      body: form
    })
    human = ((await check.json()) as { success?: boolean }).success === true
  } catch {
    return json({ message: 'turnstile_unavailable' }, 502)
  }
  if (!human) return json({ message: 'turnstile_failed' }, 403)

  // 2) Se crea el pedido. La clave de la compuerta va al final, para que nadie pueda pisarla.
  const reply = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/${RPC[kind]}`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      apikey: env.SUPABASE_ANON_KEY,
      authorization: `Bearer ${env.SUPABASE_ANON_KEY}`
    },
    body: JSON.stringify({ ...body.args, p_gate: env.ORDER_GATE })
  })

  return new Response(await reply.text(), {
    status: reply.status,
    headers: { 'content-type': 'application/json', 'cache-control': 'no-store' }
  })
}
