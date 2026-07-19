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
    // 'mine' is set by the client (it knows its own server id); keep whatever
    // it sent.
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
      <div class="kf-row" class:me={f.mine}>
        <span class="k-name">{f.killer}<span class="k-id">#{f.killerId ?? '?'}</span></span>
        {#if f.streak >= 3}<span class="k-streak">{f.streak}×</span>{/if}
        <span class="k-wpn" title={f.weapon}>
          <svg width="19" height="12" viewBox="0 0 26 16" fill="none"><path d="M1 5h15l2.5-2.5H24a1 1 0 0 1 1 1V6a1 1 0 0 1-1 1h-2v1.5a2 2 0 0 1-2 2h-3l-1.2 3.2a1 1 0 0 1-.94.65H11a1 1 0 0 1-.95-.68L9 11.5H2a1 1 0 0 1-1-1V5z" fill="currentColor"/></svg>
        </span>
        <span class="v-name">{f.victim && f.victim !== 'Unknown' ? f.victim : 'Unknown'}<span class="k-id">#{f.victimId && f.victimId > 0 ? f.victimId : '?'}</span></span>
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
  .kf { display: flex; flex-direction: column; gap: 5px; align-items: flex-end; transform: scale(var(--kf-scale, 1)); transform-origin: top right; }
  .kf-row {
    display: flex; align-items: center; gap: 8px;
    background: linear-gradient(90deg, rgba(8,10,8,0.72), rgba(8,10,8,0.9));
    border: 1px solid rgba(255,255,255,0.08);
    border-right: 2.5px solid var(--kf-accent);
    border-radius: 9px; padding: 5px 11px;
    font-family: var(--font); font-size: 12.5px; font-weight: 800; color: #fff;
    box-shadow: 0 6px 22px rgba(0,0,0,0.45);
    animation: kf-in 0.28s cubic-bezier(0.2, 1, 0.35, 1);
  }
  .kf-row.me { border-right-color: #fff; background: linear-gradient(90deg, rgba(20,24,14,0.8), rgba(26,32,16,0.94)); }
  @keyframes kf-in { from { opacity: 0; transform: translateX(18px); } to { opacity: 1; transform: translateX(0); } }
  .k-name { color: var(--kf-accent); display: flex; align-items: baseline; gap: 3px; }
  .v-name { color: rgba(255,255,255,0.92); display: flex; align-items: baseline; gap: 3px; }
  .k-id { font-size: 9.5px; font-weight: 900; color: rgba(255,255,255,0.38); }
  .k-wpn { color: rgba(255,255,255,0.55); display: flex; align-items: center; }
  .k-streak { background: var(--kf-accent); color: #0b0d08; font-size: 10px; font-weight: 900; border-radius: 5px; padding: 1px 6px; }
</style>
