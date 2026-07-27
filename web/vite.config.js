import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'

// Builds src/ back over web/bundle.js + web/bundle.css.
// index.html loads it with a plain <script> tag, so the output must be a
// self-contained IIFE with fixed filenames — not vite's default ES modules.
export default defineConfig({
  plugins: [svelte()],
  build: {
    outDir: '.',
    emptyOutDir: false,          // web/ also holds index.html and fonts/
    cssCodeSplit: false,
    target: 'chrome108',         // CEF build shipped with FiveM
    lib: {
      entry: 'src/main.js',
      formats: ['iife'],
      name: 'LimeRedzonesUI',
      fileName: () => 'bundle.js',
    },
    rollupOptions: {
      output: {
        assetFileNames: (asset) =>
          asset.names?.some((n) => n.endsWith('.css')) ? 'bundle.css' : '[name][extname]',
      },
    },
  },
})
