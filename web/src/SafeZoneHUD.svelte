<script>
  let {
    display = false, name = '', speedLimit = 0,
    invincible = true, weapons = 'holster', phase = true,
    scale = 1, pos = null, moveMode = false,
  } = $props()

  const ICON = {
    shield: 'M12 3l7 3v5.2c0 4.6-3 8-7 9.8-4-1.8-7-5.2-7-9.8V6z',
    check: 'M9 12.2l2.1 2.1L15.4 10',
    weapon: 'M3 9h12l2-2h4v3h-2v1.6a2 2 0 0 1-2 2h-2.4l-1 2.6H10l-1-2.6H4a1 1 0 0 1-1-1z',
    speed: 'M12 20a8 8 0 1 1 8-8M12 12l4.5-3.2',
    phase: 'M8 4a5 5 0 1 0 0 10M16 20a5 5 0 1 0 0-10M9.5 12h5',
  }

  const WEAPONS = {
    holster: { label: 'Weapons holstered', muted: false },
    blockfire: { label: 'Firing blocked', muted: false },
    off: { label: 'Weapons allowed', muted: true },
  }

  const chips = $derived.by(() => {
    const out = []
    if (invincible) out.push({ label: 'Protected', icon: ICON.check, muted: false })
    const w = WEAPONS[weapons] ?? WEAPONS.holster
    out.push({ label: w.label, icon: ICON.weapon, muted: w.muted })
    if (speedLimit > 0) out.push({ label: `${speedLimit} MPH`, icon: ICON.speed, muted: false })
    if (phase) out.push({ label: 'Phasing', icon: ICON.phase, muted: false })
    return out
  })

  let dragging = $state(false)
  let dragPos = $state(null)
  let el = $state(null)
  $effect(() => { if (!moveMode) dragPos = null })

  const effPos = $derived(dragPos ?? pos)

  function onDown(e) {
    if (!moveMode) return
    dragging = true
    const rect = el.getBoundingClientRect()
    const offX = e.clientX - rect.left, offY = e.clientY - rect.top
    const onMove = (ev) => {
      dragPos = {
        x: ((ev.clientX - offX + rect.width / 2) / window.innerWidth) * 100,
        y: ((ev.clientY - offY + rect.height / 2) / window.innerHeight) * 100,
      }
    }
    const onUp = () => {
      dragging = false
      window.removeEventListener('mousemove', onMove)
      window.removeEventListener('mouseup', onUp)
    }
    window.addEventListener('mousemove', onMove)
    window.addEventListener('mouseup', onUp, { once: false })
  }

  function saveDone() {
    const p = dragPos ?? pos ?? { x: 50, y: 4 }
    fetch('https://lime_redzones/saveSzPos', { method: 'POST', body: JSON.stringify(p) })
  }
</script>

{#if display || moveMode}
<div
  class="sz" class:moving={moveMode}
  bind:this={el}
  style:left={effPos ? effPos.x + '%' : '50%'}
  style:top={effPos ? effPos.y + '%' : '4%'}
  style:transform={(effPos ? 'translate(-50%,-50%)' : 'translateX(-50%)') + ` scale(${scale})`}
  onmousedown={onDown}
  role="presentation"
>
  <div class="card" class:drag={dragging}>
    <span class="glyph">
      <span class="pulse"></span>
      <svg width="17" height="17" viewBox="0 0 24 24" fill="none" aria-hidden="true">
        <path d={ICON.shield} stroke="currentColor" stroke-width="1.9" stroke-linejoin="round"/>
        <path d={ICON.check} stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>
      </svg>
    </span>

    <span class="meta">
      <span class="eyebrow">Safe Zone</span>
      <span class="name">{moveMode ? 'Drag me' : (name || 'Safe Zone')}</span>
    </span>

    {#if chips.length && !moveMode}
      <span class="rule"></span>
      <span class="chips">
        {#each chips as c (c.label)}
          <span class="chip" class:muted={c.muted}>
            <svg width="11" height="11" viewBox="0 0 24 24" fill="none" aria-hidden="true">
              <path d={c.icon} stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>
            </svg>
            {c.label}
          </span>
        {/each}
      </span>
    {/if}
  </div>
  {#if moveMode}<button class="done" onclick={saveDone}>Done</button>{/if}
</div>
{/if}

<style>
  .sz {
    --sz: #34D399;
    --sz-dim: rgba(52, 211, 153, 0.55);
    position: fixed; z-index: 90; pointer-events: none;
    font-family: var(--font);
    display: flex; flex-direction: column; align-items: center; gap: 9px;
    transform-origin: top center;
    animation: sz-in 0.4s cubic-bezier(0.16, 1, 0.3, 1);
  }
  .sz.moving { pointer-events: auto; cursor: grab; }
  .sz.moving .card { outline: 2px dashed var(--sz); outline-offset: 4px; }
  .card.drag { cursor: grabbing; }

  @keyframes sz-in {
    from { opacity: 0; transform: translateY(-10px) scale(0.97); }
    to   { opacity: 1; }
  }

  .card {
    position: relative;
    display: flex; align-items: center; gap: 11px;
    padding: 7px 15px 7px 8px;
    border-radius: 15px;
    background:
      radial-gradient(120% 180% at 0% 50%, rgba(52,211,153,0.13), transparent 58%),
      linear-gradient(150deg, rgba(14,20,17,0.93), rgba(9,11,10,0.95));
    border: 1px solid rgba(52,211,153,0.2);
    box-shadow:
      0 14px 40px rgba(0,0,0,0.5),
      0 1px 0 rgba(255,255,255,0.05) inset,
      0 0 26px -12px rgba(52,211,153,0.55);
    backdrop-filter: blur(16px) saturate(150%);
    -webkit-backdrop-filter: blur(16px) saturate(150%);
    overflow: hidden;
  }
  .card::before {
    content: '';
    position: absolute; inset: 0 auto auto 0; height: 1px; width: 100%;
    background: linear-gradient(90deg, transparent, rgba(52,211,153,0.65) 22%, rgba(255,255,255,0.28) 50%, rgba(52,211,153,0.65) 78%, transparent);
    opacity: 0.75;
  }

  .glyph {
    position: relative; flex-shrink: 0;
    display: grid; place-items: center;
    width: 32px; height: 32px; border-radius: 11px;
    background: linear-gradient(160deg, rgba(52,211,153,0.22), rgba(52,211,153,0.07));
    border: 1px solid rgba(52,211,153,0.28);
    color: var(--sz);
  }
  .pulse {
    position: absolute; inset: -1px; border-radius: inherit;
    border: 1px solid var(--sz);
    animation: sz-pulse 2.8s cubic-bezier(0.4, 0, 0.2, 1) infinite;
  }
  @keyframes sz-pulse {
    0%   { opacity: 0.55; transform: scale(1); }
    70%  { opacity: 0;    transform: scale(1.35); }
    100% { opacity: 0;    transform: scale(1.35); }
  }

  .meta { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
  .eyebrow {
    font-size: 7.5px; font-weight: 900; line-height: 1;
    letter-spacing: 0.22em; text-transform: uppercase;
    color: var(--sz-dim);
  }
  .name {
    font-size: 13.5px; font-weight: 800; line-height: 1.1;
    color: #F2FBF6; letter-spacing: 0.005em;
    max-width: 210px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  }

  .rule {
    width: 1px; align-self: stretch; margin: 2px 1px;
    background: linear-gradient(180deg, transparent, rgba(255,255,255,0.13), transparent);
  }

  .chips { display: flex; align-items: center; gap: 6px; }
  .chip {
    display: inline-flex; align-items: center; gap: 5px;
    height: 21px; padding: 0 9px 0 7px;
    border-radius: 7px;
    background: rgba(52,211,153,0.1);
    border: 1px solid rgba(52,211,153,0.18);
    color: #C9F2DF;
    font-size: 10px; font-weight: 800; letter-spacing: 0.02em;
    white-space: nowrap; font-variant-numeric: tabular-nums;
  }
  .chip svg { color: var(--sz); }
  .chip.muted {
    background: rgba(255,255,255,0.04);
    border-color: rgba(255,255,255,0.09);
    color: rgba(255,255,255,0.5);
  }
  .chip.muted svg { color: rgba(255,255,255,0.4); }

  .done {
    pointer-events: auto; padding: 7px 22px; border: none; border-radius: 999px;
    background: var(--sz); color: #06180d;
    font-size: 12px; font-weight: 900; font-family: inherit; cursor: pointer;
    box-shadow: 0 6px 18px -6px rgba(52,211,153,0.8);
  }
</style>
