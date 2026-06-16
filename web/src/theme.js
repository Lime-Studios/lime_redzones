// ════════════════════════════════════════════════════════════
//  THEME CONFIG — edit colours here to restyle the whole UI.
//
//  Each theme has an accent colour (and a text colour for the HUD
//  blade, which sits on top of the accent). Add a theme by adding
//  an entry here — it appears everywhere automatically.
// ════════════════════════════════════════════════════════════

export const THEMES = {
  lime:    { accent: '#A3E635', text: '#0a0b0d' },
  crimson: { accent: '#EF4444', text: '#ffffff' },
  cyan:    { accent: '#22D3EE', text: '#06181c' },
  amber:   { accent: '#F59E0B', text: '#1a1205' },
  violet:  { accent: '#A78BFA', text: '#15102b' },
  mono:    { accent: '#E5E7EB', text: '#0a0b0d' },
}

export const THEME_IDS = Object.keys(THEMES)

// Accent colour for a theme id (falls back to lime).
export const accentOf = (id) => (THEMES[id] ?? THEMES.lime).accent

// Text colour for a theme id (used on the HUD blade).
export const textOf = (id) => (THEMES[id] ?? THEMES.lime).text

// Resolve a "match HUD" style: if the value is 'inherit', use the HUD's theme.
export const resolveTheme = (value, hudTheme) => (value === 'inherit' ? hudTheme : value)
