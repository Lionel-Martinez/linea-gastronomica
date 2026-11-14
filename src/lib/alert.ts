/** Aviso al cliente: vibración y un tono corto. Todo es opcional: si el celular no lo permite, no pasa nada. */
export function alertNearby() {
  try {
    navigator.vibrate?.([300, 120, 300, 120, 300])
  } catch {
    // No todos los navegadores lo permiten.
  }

  try {
    const Ctx = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext
    if (!Ctx) return

    const ctx = new Ctx()
    // Dos tonos cortos y suaves (el navegador puede bloquearlos si la persona no tocó la página).
    ;[0, 0.28].forEach((delay, index) => {
      const osc = ctx.createOscillator()
      const gain = ctx.createGain()
      const start = ctx.currentTime + delay

      osc.type = 'sine'
      osc.frequency.value = index === 0 ? 660 : 880
      gain.gain.setValueAtTime(0.0001, start)
      gain.gain.exponentialRampToValueAtTime(0.25, start + 0.03)
      gain.gain.exponentialRampToValueAtTime(0.0001, start + 0.22)
      osc.connect(gain).connect(ctx.destination)
      osc.start(start)
      osc.stop(start + 0.25)
    })

    window.setTimeout(() => void ctx.close().catch(() => {}), 900)
  } catch {
    // Sin audio disponible.
  }
}
