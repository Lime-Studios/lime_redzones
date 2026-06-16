import App from './App.svelte'
import { mount } from 'svelte'

function start() {
  mount(App, { target: document.body })
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', start)
} else {
  start()
}
