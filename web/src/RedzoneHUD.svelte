<script>
  import { accentOf, textOf } from './theme.js'
  let { display = false, zoneName = 'Redzone', kills = 0, deaths = 0, streak = 0, nextReward = null, moveMode = false, pos = null, theme = 'lime', preset = 'top', scale = 1 } = $props()

  const accent = $derived(accentOf(theme))
  const accentText = $derived(textOf(theme))
  const PRESETS = {
    top:          { x: 50, y: 8,  t: 'translateX(-50%)' },
    'top-left':   { x: 14, y: 8,  t: 'none' },
    'top-right':  { x: 86, y: 8,  t: 'translateX(-100%)' },
    bottom:       { x: 50, y: 92, t: 'translate(-50%,-100%)' },
    left:         { x: 3,  y: 50, t: 'translateY(-50%)' },
    right:        { x: 97, y: 50, t: 'translate(-100%,-50%)' },
  }
  const presetPos = $derived(PRESETS[preset] ?? PRESETS.top)

  let dragging = $state(false)
  let dragPos = $state(null)
  let el
  $effect(() => { if (!moveMode) dragPos = null })

  const effPos = $derived(dragPos ?? pos)
  const rewardText = $derived(
    nextReward
      ? `${nextReward.streak} → ${nextReward.name === 'money' ? '$' + nextReward.amount : nextReward.name}`
      : null
  )

  function onDown(e) {
    if (!moveMode) return
    dragging = true
    const rect = el.getBoundingClientRect()
    const offX = e.clientX - rect.left, offY = e.clientY - rect.top
    function onMove(ev) {
      dragPos = { x: ((ev.clientX - offX + rect.width / 2) / window.innerWidth) * 100, y: ((ev.clientY - offY + rect.height / 2) / window.innerHeight) * 100 }
    }
    function onUp() {
      dragging = false
      window.removeEventListener('mousemove', onMove); window.removeEventListener('mouseup', onUp)
    }
    window.addEventListener('mousemove', onMove); window.addEventListener('mouseup', onUp)
  }
  function saveDone() {
    const p = dragPos ?? pos ?? { x: 50, y: 8 }
    fetch('https://lime_redzones/saveHudPos', { method: 'POST', body: JSON.stringify(p) })
  }
</script>

{#if display || moveMode}
<div
  class="hud" class:moving={moveMode}
  bind:this={el}
  style:left={effPos ? effPos.x + '%' : presetPos.x + '%'}
  style:top={effPos ? effPos.y + '%' : presetPos.y + '%'}
  style:transform={effPos ? 'translate(-50%,-50%)' : presetPos.t}
  style:--hud-accent={accent}
  style:--hud-text={accentText}
  style:--hud-scale={scale}
  onmousedown={onDown}
  role="presentation"
>
  <div class="strip" class:drag={dragging}>
    <div class="blade">
      <span class="blade-label">REDZONE</span>
      <span class="blade-name">{moveMode ? 'DRAG ME' : zoneName}</span>
    </div>
    <div class="stats">
      <div class="stat"><span class="s-num">{kills}</span><span class="s-lbl">K</span></div>
      <span class="sep">/</span>
      <div class="stat"><span class="s-num">{deaths}</span><span class="s-lbl">D</span></div>
      <span class="sep">/</span>
      <div class="stat streak" class:hot={streak >= 3}>
        <svg width="11" height="11" viewBox="0 0 24 24" fill="none"><path d="M13 2L4 14h6l-1 8 9-12h-6l1-8z" fill="currentColor"/></svg>
        <span class="s-num">{streak}</span>
      </div>
    </div>
    {#if rewardText}
      <div class="next"><span class="next-lbl">NEXT</span><span class="next-val">{rewardText}</span></div>
    {/if}
  </div>
  {#if moveMode}<button class="done" onclick={saveDone}>Done</button>{/if}
</div>
{/if}

<style>
  .hud { position: fixed; pointer-events: none; z-index: 100; font-family: var(--font); display: flex; flex-direction: column; align-items: center; gap: 8px; }
  .hud.moving { pointer-events: auto; cursor: grab; }
  .hud.moving .strip { outline: 2px dashed var(--hud-accent, var(--accent)); outline-offset: 3px; }
  .strip.drag { cursor: grabbing; }
  .strip { display: flex; align-items: stretch; background: linear-gradient(180deg, rgba(16,17,20,0.95), rgba(10,11,13,0.95)); border: 1px solid rgba(255,255,255,0.08); border-radius: 999px; overflow: hidden; height: 40px; }
  .blade { position: relative; display: flex; flex-direction: column; justify-content: center; padding: 0 22px 0 18px; background: var(--hud-accent, var(--accent)); clip-path: polygon(0 0, 100% 0, calc(100% - 14px) 100%, 0 100%); margin-right: -6px; }
  .blade-label { font-size: 7px; font-weight: 900; letter-spacing: 0.22em; color: var(--hud-text, #0a0b0d); opacity: 0.55; line-height: 1; }
  .blade-name { font-size: 13px; font-weight: 900; color: var(--hud-text, #0a0b0d); text-transform: uppercase; letter-spacing: 0.01em; line-height: 1.15; max-width: 150px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .stats { display: flex; align-items: center; gap: 9px; padding: 0 16px; }
  .stat { display: flex; align-items: baseline; gap: 3px; }
  .s-num { font-size: 17px; font-weight: 900; color: #fff; font-variant-numeric: tabular-nums; line-height: 1; }
  .s-lbl { font-size: 9px; font-weight: 800; color: rgba(255,255,255,0.35); }
  .sep { color: rgba(255,255,255,0.15); font-weight: 300; font-size: 15px; }
  .stat.streak { color: rgba(255,255,255,0.45); align-items: center; }
  .stat.streak.hot { color: var(--hud-accent, var(--accent)); }
  .stat.streak.hot .s-num { color: var(--hud-accent, var(--accent)); }
  .next { display: flex; flex-direction: column; justify-content: center; gap: 1px; padding: 0 18px 0 14px; border-left: 1px solid rgba(255,255,255,0.07); }
  .next-lbl { font-size: 7.5px; font-weight: 900; letter-spacing: 0.2em; color: var(--hud-accent, var(--accent)); line-height: 1; }
  .next-val { font-size: 11.5px; font-weight: 800; color: #fff; white-space: nowrap; line-height: 1.2; }
  .done { pointer-events: auto; padding: 7px 22px; background: var(--hud-accent, var(--accent)); border: none; border-radius: 999px; color: var(--hud-text, #0a0b0d); font-size: 12px; font-weight: 900; font-family: inherit; cursor: pointer; }
</style>
