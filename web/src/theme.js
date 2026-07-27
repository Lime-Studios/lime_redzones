export const THEMES = {
  lime:    { accent: '#A3E635', text: '#0a0b0d' },
  crimson: { accent: '#EF4444', text: '#ffffff' },
  cyan:    { accent: '#22D3EE', text: '#06181c' },
  amber:   { accent: '#F59E0B', text: '#1a1205' },
  violet:  { accent: '#A78BFA', text: '#15102b' },
  mono:    { accent: '#E5E7EB', text: '#0a0b0d' },
  custom:  { accent: '#A3E635', text: '#0a0b0d' },
}

export const THEME_IDS = Object.keys(THEMES)
export const PRESET_THEME_IDS = THEME_IDS.filter(id => id !== 'custom')

export function setCustomTheme(accent, text) {
  if (typeof accent === 'string' && /^#[0-9a-fA-F]{6}$/.test(accent)) {
    THEMES.custom.accent = accent
    THEMES.custom.text = (typeof text === 'string' && /^#[0-9a-fA-F]{6}$/.test(text))
      ? text : bestTextOn(accent)
  }
}

export const isHex = (v) => typeof v === 'string' && /^#[0-9a-fA-F]{6}$/.test(v)

export const accentOf = (id) => (isHex(id) ? id : (THEMES[id] ?? THEMES.lime).accent)

export const textOf = (id) => (isHex(id) ? bestTextOn(id) : (THEMES[id] ?? THEMES.lime).text)

export function hslToHex(h, s, l) {
  const a = s * Math.min(l, 1 - l)
  const f = (n) => {
    const k = (n + h / 30) % 12
    const c = l - a * Math.max(-1, Math.min(k - 3, 9 - k, 1))
    return Math.round(255 * c).toString(16).padStart(2, '0')
  }
  return `#${f(0)}${f(8)}${f(4)}`
}

export function hexToHue(hex) {
  const [r, g, b] = hexToRgb(hex).map((c) => c / 255)
  const max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min
  if (d === 0) return 0
  let h
  if (max === r) h = ((g - b) / d) % 6
  else if (max === g) h = (b - r) / d + 2
  else h = (r - g) / d + 4
  return Math.round(((h * 60) + 360) % 360)
}

export const resolveTheme = (value, hudTheme) => (value === 'inherit' ? hudTheme : value)

export function hexToRgb(hex) {
  const h = (hex || '').replace('#', '')
  return [parseInt(h.slice(0, 2), 16) || 0, parseInt(h.slice(2, 4), 16) || 0, parseInt(h.slice(4, 6), 16) || 0]
}

export function rgba(hex, a) {
  const [r, g, b] = hexToRgb(hex)
  return `rgba(${r},${g},${b},${a})`
}

export function lighten(hex, t) {
  const [r, g, b] = hexToRgb(hex)
  const m = (c) => Math.round(c + (255 - c) * t)
  return `#${[m(r), m(g), m(b)].map(c => c.toString(16).padStart(2, '0')).join('')}`
}

export function bestTextOn(hex) {
  const [r, g, b] = hexToRgb(hex)
  const lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255
  return lum > 0.6 ? '#0a0b0d' : '#ffffff'
}

export function accentVars(accent, text) {
  const t = text || bestTextOn(accent)
  return {
    '--accent': accent,
    '--accent-strong': lighten(accent, 0.25),
    '--accent-soft': rgba(accent, 0.12),
    '--accent-border': rgba(accent, 0.25),
    '--accent-text': t,
  }
}
