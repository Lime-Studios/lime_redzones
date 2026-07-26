// Edit colours here to restyle the whole UI. Add a theme by adding an
// entry — it appears everywhere (HUD, kill feed, kill cam, panel) automatically.

export const THEMES = {
  lime:    { accent: '#A3E635', text: '#0a0b0d' },
  crimson: { accent: '#EF4444', text: '#ffffff' },
  cyan:    { accent: '#22D3EE', text: '#06181c' },
  amber:   { accent: '#F59E0B', text: '#1a1205' },
  violet:  { accent: '#A78BFA', text: '#15102b' },
  mono:    { accent: '#E5E7EB', text: '#0a0b0d' },
  // Admin-defined global theme. Colours are overwritten at runtime by
  // setCustomTheme() when the server syncs the admin's picks.
  custom:  { accent: '#A3E635', text: '#0a0b0d' },
}

export const THEME_IDS = Object.keys(THEMES)
// Ids the admin can pick from the preset row (custom is edited, not listed).
export const PRESET_THEME_IDS = THEME_IDS.filter(id => id !== 'custom')

// Overwrite the 'custom' theme at runtime (admin theme builder → server sync).
export function setCustomTheme(accent, text) {
  if (typeof accent === 'string' && /^#[0-9a-fA-F]{6}$/.test(accent)) {
    THEMES.custom.accent = accent
    THEMES.custom.text = (typeof text === 'string' && /^#[0-9a-fA-F]{6}$/.test(text))
      ? text : bestTextOn(accent)
  }
}

// Accent colour for a theme id (falls back to lime).
export const accentOf = (id) => (THEMES[id] ?? THEMES.lime).accent

// Text colour for a theme id (used on the HUD blade).
export const textOf = (id) => (THEMES[id] ?? THEMES.lime).text

// Resolve a "match HUD" style: if the value is 'inherit', use the HUD's theme.
export const resolveTheme = (value, hudTheme) => (value === 'inherit' ? hudTheme : value)

// --- helpers for the theme builder -------------------------------------

// Parse #rrggbb → [r,g,b].
export function hexToRgb(hex) {
  const h = (hex || '').replace('#', '')
  return [parseInt(h.slice(0, 2), 16) || 0, parseInt(h.slice(2, 4), 16) || 0, parseInt(h.slice(4, 6), 16) || 0]
}

// rgba() string at a given alpha for building soft/border tints.
export function rgba(hex, a) {
  const [r, g, b] = hexToRgb(hex)
  return `rgba(${r},${g},${b},${a})`
}

// Lighten a hex toward white by t (0..1) — used for --accent-strong.
export function lighten(hex, t) {
  const [r, g, b] = hexToRgb(hex)
  const m = (c) => Math.round(c + (255 - c) * t)
  return `#${[m(r), m(g), m(b)].map(c => c.toString(16).padStart(2, '0')).join('')}`
}

// Pick black or white text for readable contrast on an accent fill.
export function bestTextOn(hex) {
  const [r, g, b] = hexToRgb(hex)
  // Relative luminance (sRGB). Bright accents get dark text, dark get white.
  const lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255
  return lum > 0.6 ? '#0a0b0d' : '#ffffff'
}

// Full set of :root CSS-var overrides for an accent+text pair. Applying these
// to document.documentElement recolours the tablet AND every HUD element.
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
