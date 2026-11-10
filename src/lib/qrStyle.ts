import QRCode from 'qrcode'

/** Estilo del código QR: colores y formas, para que combine con la identidad del local. */
export type QrShape = 'square' | 'rounded' | 'dots'
export type QrEyes = 'square' | 'rounded' | 'circle'

export interface QrStyle {
  fg: string
  bg: string
  shape: QrShape
  eyes: QrEyes
}

export const DEFAULT_QR_STYLE: QrStyle = { fg: '#1a1a1a', bg: '#ffffff', shape: 'square', eyes: 'square' }

export const QR_PRESETS: { id: string; name: string; style: QrStyle }[] = [
  { id: 'classic', name: 'Clásico', style: DEFAULT_QR_STYLE },
  { id: 'cafe', name: 'Café', style: { fg: '#3b2314', bg: '#fbf5ec', shape: 'rounded', eyes: 'rounded' } },
  { id: 'verde', name: 'Verde', style: { fg: '#14532d', bg: '#f0fdf4', shape: 'dots', eyes: 'rounded' } },
  { id: 'bordo', name: 'Bordó', style: { fg: '#7f1d1d', bg: '#fff7f5', shape: 'rounded', eyes: 'circle' } },
  { id: 'noche', name: 'Azul noche', style: { fg: '#1e293b', bg: '#f1f5f9', shape: 'dots', eyes: 'circle' } }
]

const HEX = /^#[0-9a-f]{6}$/i

const channel = (value: number) => {
  const v = value / 255
  return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4
}

export function luminance(hex: string) {
  const n = parseInt(hex.slice(1), 16)
  return 0.2126 * channel((n >> 16) & 255) + 0.7152 * channel((n >> 8) & 255) + 0.0722 * channel(n & 255)
}

export function contrastRatio(a: string, b: string) {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x)
  return (hi + 0.05) / (lo + 0.05)
}

/**
 * Un QR tiene que leerse con cualquier celular: hace falta buen contraste.
 * Devuelve el motivo si el estilo no es seguro, o null si está bien.
 */
export function qrStyleProblem(style: QrStyle): string | null {
  if (!HEX.test(style.fg) || !HEX.test(style.bg)) return 'Elegí colores válidos.'

  if (luminance(style.fg) >= luminance(style.bg)) {
    return 'Usá un color oscuro para el código y uno claro para el fondo: muchos celulares no leen los QR invertidos.'
  }

  const ratio = contrastRatio(style.fg, style.bg)
  if (ratio < 4) {
    return `Contraste muy bajo (${ratio.toFixed(1)}:1): el QR se leería mal. Usá un color más oscuro sobre uno más claro (mínimo 4:1).`
  }

  return null
}

type Matrix = { size: number; get: (row: number, col: number) => number }

const inFinder = (x: number, y: number, size: number) =>
  (x < 7 && y < 7) || (x >= size - 7 && y < 7) || (x < 7 && y >= size - 7)

const f = (n: number) => Number(n.toFixed(3))

/** Ojo del QR (el cuadrado grande de cada esquina): 7×7 con un anillo y un centro de 3×3. */
function eye(x: number, y: number, kind: QrEyes, fg: string, bg: string) {
  if (kind === 'circle') {
    return (
      `<circle cx="${x + 3.5}" cy="${y + 3.5}" r="3.5" fill="${fg}"/>` +
      `<circle cx="${x + 3.5}" cy="${y + 3.5}" r="2.5" fill="${bg}"/>` +
      `<circle cx="${x + 3.5}" cy="${y + 3.5}" r="1.5" fill="${fg}"/>`
    )
  }

  const outer = kind === 'rounded' ? 1.8 : 0
  const inner = kind === 'rounded' ? 1 : 0
  return (
    `<rect x="${x}" y="${y}" width="7" height="7" rx="${outer}" fill="${fg}"/>` +
    `<rect x="${x + 1}" y="${y + 1}" width="5" height="5" rx="${f(outer * 0.6)}" fill="${bg}"/>` +
    `<rect x="${x + 2}" y="${y + 2}" width="3" height="3" rx="${inner}" fill="${fg}"/>`
  )
}

/** Dibuja el QR como SVG (nítido a cualquier tamaño, ideal para imprimir). */
export function qrToSvg(text: string, style: QrStyle, margin = 2): string {
  const qr = QRCode.create(text, { errorCorrectionLevel: 'M' })
  const matrix = qr.modules as unknown as Matrix
  const size = matrix.size
  const total = size + margin * 2

  let modules = ''
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      if (!matrix.get(y, x) || inFinder(x, y, size)) continue

      const px = x + margin
      const py = y + margin

      if (style.shape === 'dots') modules += `<circle cx="${f(px + 0.5)}" cy="${f(py + 0.5)}" r="0.5"/>`
      else if (style.shape === 'rounded') modules += `<rect x="${px}" y="${py}" width="1" height="1" rx="0.32"/>`
      else modules += `<rect x="${px}" y="${py}" width="1.02" height="1.02"/>`
    }
  }

  const eyes =
    eye(margin, margin, style.eyes, style.fg, style.bg) +
    eye(margin + size - 7, margin, style.eyes, style.fg, style.bg) +
    eye(margin, margin + size - 7, style.eyes, style.fg, style.bg)

  return (
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${total} ${total}" shape-rendering="geometricPrecision">` +
    `<rect width="${total}" height="${total}" fill="${style.bg}"/>` +
    `<g fill="${style.fg}">${modules}</g>${eyes}</svg>`
  )
}

export const svgToDataUrl = (svg: string) => `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`

/** Convierte el SVG en una imagen PNG (para quienes lo necesitan en ese formato). */
export function svgToPngBlob(svg: string, pixels = 1024): Promise<Blob> {
  return new Promise((resolve, reject) => {
    const image = new Image()
    image.onload = () => {
      const canvas = document.createElement('canvas')
      canvas.width = pixels
      canvas.height = pixels
      const ctx = canvas.getContext('2d')
      if (!ctx) return reject(new Error('canvas'))
      ctx.imageSmoothingEnabled = false
      ctx.drawImage(image, 0, 0, pixels, pixels)
      canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error('blob'))), 'image/png')
    }
    image.onerror = () => reject(new Error('image'))
    image.src = svgToDataUrl(svg)
  })
}
