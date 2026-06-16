# Customising the UI

The interface is built with Svelte and compiled into `web/bundle.js` + `web/bundle.css`.
You only need to touch these files if you want to change how the UI looks or behaves.

## Quick changes (most common)

**Colours / themes** — edit `theme.js`. Every theme's accent colour lives there, used by
the HUD, kill feed, kill cam, and kill message. Add a theme by adding one line; it shows up
in the admin panel and player HUD picker automatically.

## The files

| File | What it controls |
|------|------------------|
| `theme.js`         | All theme colours (single source of truth) |
| `App.svelte`       | Wiring — routes NUI messages to the right component |
| `TabletApp.svelte` | The tablet (admin + player panels, all tabs) |
| `RedzoneHUD.svelte`| The in-world HUD pill |
| `KillFeed.svelte`  | The kill feed |
| `KillCam.svelte`   | The kill cam overlay |
| `KillMessage.svelte`| The "ELIMINATED" message |

## Rebuilding after edits

```bash
npm install      # first time only
npx vite build   # outputs to dist/ — copy dist/bundle.js and dist/bundle.css into web/
```

Tailwind-style utility classes are NOT used; styles are plain CSS in each component's
`<style>` block, and shared design tokens (fonts, surface colours, accent) come from the
CSS variables defined in `web/index.html`.
