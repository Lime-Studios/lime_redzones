<script>
  import { accentOf } from './theme.js'
  let { pos = null, moveMode = false, scale = 1, theme = 'lime' } = $props()
  let feed = $state([])
  let dragPos = $state(null)
  let el

  const accent = $derived(accentOf(theme))
  // Position is stored as the TOP-RIGHT corner (feed is right-aligned).
  const effPos = $derived(dragPos ?? pos ?? { x: 98, y: 16 })

  export function push(entry) {
    const id = Date.now() + Math.random()
    const dur = entry.duration ?? 6000
    feed = [{ id, ...entry }, ...feed].slice(0, 6)
    setTimeout(() => { feed = feed.filter(f => f.id !== id) }, dur)
  }

  function onDown(e) {
    if (!moveMode) return
    e.preventDefault()
    const move = (ev) => {
      dragPos = {
        x: Math.max(2, Math.min(98, (ev.clientX / window.innerWidth) * 100)),
        y: Math.max(2, Math.min(96, (ev.clientY / window.innerHeight) * 100)),
      }
    }
    window.addEventListener('mousemove', move)
    const up = () => window.removeEventListener('mousemove', move)
    window.addEventListener('mouseup', up, { once: true })
  }

  function done() {
    fetch('https://lime_redzones/saveKillfeedPos', { method: 'POST', body: JSON.stringify(dragPos ?? effPos) })
  }

  const demo = [
    { id: 'd1', killer: 'FOCO', killerId: 1, victim: 'Enemy', victimId: '??', weapon: 'Pistol', streak: 1 },
    { id: 'd2', killer: 'Viper', killerId: 7, victim: 'Ghost', victimId: 23, weapon: 'Carbine Rifle', streak: 4 },
  ]
  const rows = $derived(moveMode && !feed.length ? demo : feed)
</script>

{#if rows.length || moveMode}
<div class="wrap" class:move={moveMode}
  style:right={(100 - effPos.x) + '%'} style:top={effPos.y + '%'}
  style:--kf-accent={accent} style:--kf-scale={scale}>
  {#if moveMode}
    <div class="move-hdr" onmousedown={onDown} role="presentation">
      <svg width="13" height="13" viewBox="0 0 24 24" fill="none"><path d="M12 2v20M2 12h20M12 2l-3 3m3-3l3 3M12 22l-3-3m3 3l3-3" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>
      Drag to move
      <button class="done" onclick={done}>Done</button>
    </div>
  {/if}
  <div class="kf">
    {#each rows as f (f.id)}
      <div class="kf-row">
        <span class="seg killer">
          <span class="nm">{f.killer}</span>
          <span class="id">#{f.killerId ?? '?'}</span>
          <span class="wpn" title={f.weapon}>
            <svg width="20" height="13" viewBox="0 0 26 16" fill="none"><path d="M1 5h15l2.5-2.5H24a1 1 0 0 1 1 1V6a1 1 0 0 1-1 1h-2v1.5a2 2 0 0 1-2 2h-3l-1.2 3.2a1 1 0 0 1-.94.65H11a1 1 0 0 1-.95-.68L9 11.5H2a1 1 0 0 1-1-1V5z" fill="currentColor"/></svg>
          </span>
        </span>
        <span class="div"></span>
        <span class="seg enemy">
          <svg class="skull" width="13" height="13" viewBox="0 0 24 24" fill="none"><path d="M12 2C7 2 4 5.5 4 10c0 2.4 1 4 2.5 5.2V18a1.5 1.5 0 0 0 1.5 1.5h1V21a1 1 0 0 0 1 1h4a1 1 0 0 0 1-1v-1.5h1A1.5 1.5 0 0 0 18 18v-2.8C19.5 14 20.5 12.4 20.5 10 20.5 5.5 17 2 12 2z" stroke="currentColor" stroke-width="1.8"/><circle cx="9" cy="11" r="1.6" fill="currentColor"/><circle cx="15" cy="11" r="1.6" fill="currentColor"/></svg>
          <span class="nm dim">ENEMY</span>
          <span class="id">#{f.victimId ?? '??'}</span>
        </span>
        {#if f.streak >= 3}<span class="streak">×{f.streak}</span>{/if}
      </div>
    {/each}
  </div>
</div>
{/if}

<style>
  .wrap {
    position: fixed; z-index: 95;
    display: flex; flex-direction: column; align-items: flex-end; gap: 6px;
    pointer-events: none; font-family: var(--font);
    transform: translateY(0) scale(var(--kf-scale, 1));
    transform-origin: top right;
  }
  .wrap.move { pointer-events: auto; }
  .move-hdr {
    display: flex; align-items: center; gap: 6px;
    background: rgba(10,11,13,0.95);
    border: 1px dashed var(--kf-accent);
    border-radius: 8px; padding: 6px 8px 6px 10px;
    font-size: 11px; font-weight: 700; color: #fff;
    cursor: grab; user-select: none;
  }
  .move-hdr:active { cursor: grabbing; }
  .done {
    background: var(--kf-accent); color: #0a0b0d; border: none;
    border-radius: 6px; padding: 3px 12px; margin-left: 4px;
    font-size: 11px; font-weight: 800; font-family: inherit; cursor: pointer;
  }
  .kf { display: flex; flex-direction: column; gap: 6px; align-items: flex-end; }
  .kf-row {
    display: flex; align-items: stretch; height: 32px;
    background: linear-gradient(180deg, rgba(22,24,28,0.95), rgba(13,14,17,0.95));
    border: 1px solid rgba(255,255,255,0.1);
    border-radius: 7px; overflow: hidden; font-size: 12.5px;
    box-shadow: 0 3px 12px rgba(0,0,0,0.4);
    animation: si 0.25s cubic-bezier(0.2,1,0.4,1);
  }
  .seg { display: flex; align-items: center; gap: 6px; padding: 0 11px; }
  .seg.killer { padding-right: 8px; }
  .nm { font-weight: 800; color: #fff; }
  .nm.dim { color: rgba(255,255,255,0.7); font-weight: 700; }
  .id { font-size: 10.5px; font-weight: 800; color: var(--kf-accent); }
  .wpn { display: flex; align-items: center; color: #fff; margin-left: 3px; padding-left: 8px; border-left: 1px solid rgba(255,255,255,0.1); height: 100%; }
  .div { width: 1px; background: rgba(255,255,255,0.12); }
  .seg.enemy { background: rgba(0,0,0,0.28); }
  .skull { color: #ef4444; flex-shrink: 0; }
  .streak { display: flex; align-items: center; padding: 0 10px; background: var(--kf-accent); color: #0a0b0d; font-weight: 900; font-size: 11.5px; }
  @keyframes si { from { opacity: 0; transform: translateX(28px); } to { opacity: 1; transform: translateX(0); } }
</style>
