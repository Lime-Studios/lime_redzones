<script>
  import { accentOf } from './theme.js'
  let { theme = 'lime', scale = 1, pos = null, moveMode = false } = $props()
  let msg = $state(null)
  let dragPos = $state(null)
  let timer

  const accent = $derived(accentOf(theme))
  const effPos = $derived(dragPos ?? pos ?? { x: 50, y: 26 })

  export function show(victim, weapon, streak) {
    msg = { victim, weapon, streak, id: Date.now() }
    clearTimeout(timer)
    timer = setTimeout(() => { msg = null }, 2600)
  }

  function onDown(e) {
    if (!moveMode) return
    e.preventDefault()
    const move = (ev) => {
      dragPos = {
        x: Math.max(5, Math.min(95, (ev.clientX / window.innerWidth) * 100)),
        y: Math.max(5, Math.min(92, (ev.clientY / window.innerHeight) * 100)),
      }
    }
    window.addEventListener('mousemove', move)
    window.addEventListener('mouseup', () => window.removeEventListener('mousemove', move), { once: true })
  }
  function done() {
    fetch('https://lime_redzones/saveKillMsgPos', { method: 'POST', body: JSON.stringify(dragPos ?? effPos) })
  }

  const preview = { victim: 'Enemy', weapon: 'Pistol', streak: 3 }
  const shown = $derived(moveMode ? preview : msg)
</script>

{#if shown}
{#key (msg?.id ?? 'preview')}
<div class="km" class:move={moveMode}
  style:left={effPos.x + '%'} style:top={effPos.y + '%'}
  style:--km-accent={accent} style:transform={`translateX(-50%) scale(${scale})`}
  onmousedown={onDown} role="presentation">
  <div class="km-tag">ELIMINATED</div>
  <div class="km-victim">{shown.victim}</div>
  <div class="km-meta">
    <span class="km-weapon">{shown.weapon}</span>
    {#if shown.streak >= 2}<span class="km-streak">STREAK ×{shown.streak}</span>{/if}
  </div>
  {#if moveMode}<button class="km-done" onclick={done}>Done</button>{/if}
</div>
{/key}
{/if}

<style>
  .km {
    position: fixed; z-index: 96; pointer-events: none; text-align: center;
    font-family: var(--font); transform-origin: center top;
    animation: pop 0.3s cubic-bezier(0.2, 1.3, 0.5, 1);
  }
  .km.move { pointer-events: auto; cursor: grab; }
  .km.move:active { cursor: grabbing; }
  .km-tag { font-size: 14px; font-weight: 900; letter-spacing: 0.35em; color: var(--km-accent); text-shadow: 0 2px 10px rgba(0,0,0,0.7); margin-bottom: 2px; }
  .km-victim { font-size: 42px; font-weight: 900; color: #fff; text-shadow: 0 3px 16px rgba(0,0,0,0.85); line-height: 1; }
  .km-meta { display: flex; gap: 10px; justify-content: center; margin-top: 7px; }
  .km-weapon, .km-streak { font-size: 11px; font-weight: 800; letter-spacing: 0.08em; padding: 3px 10px; border-radius: 99px; background: rgba(14,15,18,0.85); border: 1px solid rgba(255,255,255,0.12); color: rgba(255,255,255,0.85); }
  .km-streak { background: var(--km-accent); border-color: transparent; color: #0a0b0d; }
  .km-done { pointer-events: auto; margin-top: 10px; background: var(--km-accent); color: #0a0b0d; border: none; border-radius: 99px; padding: 6px 22px; font-size: 12px; font-weight: 900; font-family: inherit; cursor: pointer; }
  @keyframes pop { from { opacity: 0; transform: translateX(-50%) scale(0.8); } to { opacity: 1; } }
</style>
