import { readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { defineConfig, type Plugin } from 'vite'
import vue from '@vitejs/plugin-vue'
import tailwindcss from '@tailwindcss/vite'

// Ediciones del producto. Se elige con el modo: `vite build --mode panel` (ver package.json).
const EDITIONS = ['carta', 'panel', 'mesa', 'delivery', 'completo'] as const
type Edition = (typeof EDITIONS)[number]

const pick = (_mode: string): Edition => 'carta' // edición fija de este proyecto
// La edición Carta no habla con ningún servidor: sus cabeceras de seguridad lo reflejan.
function headersFor(edition: Edition): Plugin {
  let outDir = ''
  return {
    name: 'edition-headers',
    configResolved: (config) => {
      outDir = resolve(config.root, config.build.outDir)
    },
    closeBundle() {
      if (edition !== 'carta') return
      const file = resolve(outDir, '_headers')
      const text = readFileSync(file, 'utf8')
        .replace(' https://*.supabase.co wss://*.supabase.co https://challenges.cloudflare.com', '')
        .replace(' https://challenges.cloudflare.com', '')
        .replace('frame-src https://challenges.cloudflare.com; ', '')
      writeFileSync(file, text)
    }
  }
}

// El compilador saca del código las pantallas que una edición no usa, pero igual deja sus archivos sueltos.
// Este paso, al terminar la compilación, borra todo archivo de /assets al que ya no llega nada desde la
// página principal: el sitio publicado lleva solo lo de su edición.
function dropUnreachable(): Plugin {
  let outDir = ''

  return {
    name: 'drop-unreachable-files',
    apply: 'build',
    configResolved: (config) => {
      outDir = resolve(config.root, config.build.outDir)
    },
    closeBundle() {
      if (process.env.KEEP_ALL) return

      const assets = resolve(outDir, 'assets')
      const files = new Set(readdirSync(assets))
      const reachable = new Set<string>()
      const queue: string[] = []
      const html = readFileSync(resolve(outDir, 'index.html'), 'utf8')

      for (const match of html.matchAll(/assets\/([\w.-]+)/g)) queue.push(match[1])

      while (queue.length) {
        const name = queue.pop() as string
        if (reachable.has(name) || !files.has(name)) continue
        reachable.add(name)

        if (!/\.(js|css)$/.test(name)) continue
        const text = readFileSync(resolve(assets, name), 'utf8')
        for (const match of text.matchAll(/[\w.-]+\.[a-z0-9]+/gi)) {
          if (files.has(match[0]) && !reachable.has(match[0])) queue.push(match[0])
        }
      }

      for (const name of files) if (!reachable.has(name)) rmSync(resolve(assets, name))
    }
  }
}

export default defineConfig(({ mode }) => {
  const edition = pick(mode)

  return {
    plugins: [vue(), tailwindcss(), dropUnreachable(), headersFor(edition)],
    // Cada función se fija como true/false al compilar: así el código que no se usa se descarta del sitio.
    define: {
      __EDITION__: JSON.stringify(edition),
      __HAS_BACKEND__: String(edition !== 'carta'),
      __HAS_PUBLIC_MENU__: String(edition !== 'delivery'),
      __HAS_TABLE_ORDERING__: String(edition === 'mesa' || edition === 'completo'),
      __HAS_REMOTE_ORDERING__: String(edition === 'delivery' || edition === 'completo'),
      __HAS_QR_PAGE__: String(edition !== 'delivery')
    },
    build: { outDir: 'dist' }
  }
})
