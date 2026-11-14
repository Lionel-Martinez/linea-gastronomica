/** Prepara una foto elegida del celular o la compu: la achica y la comprime antes de subirla. */

const MAX_SIDE = 1000
const MAX_BYTES = 1_000_000 // el depósito de Supabase rechaza más de 1 MB

export const IMAGE_TYPES = 'image/jpeg,image/png,image/webp'

function toBlob(canvas: HTMLCanvasElement, type: string, quality: number) {
  return new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, type, quality))
}

/** Devuelve la foto achicada (lado mayor de 1000 px) y comprimida a menos de 1 MB. */
export async function prepareImage(file: File): Promise<{ blob: Blob; ext: 'webp' | 'jpg' }> {
  if (!file.type.startsWith('image/')) throw new Error('not_image')

  let bitmap: ImageBitmap
  try {
    bitmap = await createImageBitmap(file, { imageOrientation: 'from-image' })
  } catch {
    throw new Error('image_unreadable')
  }

  const scale = Math.min(1, MAX_SIDE / Math.max(bitmap.width, bitmap.height))
  const canvas = document.createElement('canvas')
  canvas.width = Math.max(1, Math.round(bitmap.width * scale))
  canvas.height = Math.max(1, Math.round(bitmap.height * scale))

  const ctx = canvas.getContext('2d')
  if (!ctx) throw new Error('image_unreadable')

  // Fondo blanco: las fotos con transparencia no quedan negras al pasar a JPG.
  ctx.fillStyle = '#fff'
  ctx.fillRect(0, 0, canvas.width, canvas.height)
  ctx.drawImage(bitmap, 0, 0, canvas.width, canvas.height)
  bitmap.close()

  // WebP pesa menos; si el navegador no lo sabe generar, se usa JPG.
  for (const type of ['image/webp', 'image/jpeg'] as const) {
    for (const quality of [0.85, 0.7, 0.55]) {
      const blob = await toBlob(canvas, type, quality)
      if (!blob || blob.type !== type) break // este formato no está disponible
      if (blob.size <= MAX_BYTES) return { blob, ext: type === 'image/webp' ? 'webp' : 'jpg' }
    }
  }

  throw new Error('image_too_big')
}
