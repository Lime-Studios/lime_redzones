<script>
  let { display = false, mode = 'poly', count = 0, max = 24, minZ = 0, maxZ = 0, speed = 1 } = $props()

  const controls = $derived(mode === 'poly' ? [
    { keys: ['W','A','S','D'], label: 'Fly' },
    { keys: ['SPACE','CTRL'],  label: 'Up / Down' },
    { keys: ['⇧'],             label: 'Boost' },
    { keys: ['SCROLL'],        label: 'Speed' },
    { keys: ['E'],             label: 'Add Point' },
    { keys: ['X'],             label: 'Undo Last' },
    { keys: ['↑','↓'],         label: 'Top +/-' },
    { keys: ['⇧','↑','↓'],     label: 'Bottom +/-' },
    { keys: ['G'],             label: 'Done' },
    { keys: ['BACK'],          label: 'Cancel' },
  ] : [
    { keys: ['E'],    label: 'Place' },
    { keys: ['X'],    label: 'Undo' },
    { keys: ['G'],    label: 'Finish' },
    { keys: ['BACK'], label: 'Cancel' },
  ])

  const title = $derived(
    mode === 'poly' ? 'Zone Shape' :
    mode === 'tp'   ? 'Teleport Points' :
    mode === 'npc'  ? 'Teleport NPCs' : 'Respawn Points'
  )
</script>

{#if display}
<div class="pb-wrap">
  <div class="pb-status">
    <span class="pb-title">{title}</span>
    <span class="pb-count">{count}/{max}</span>
    {#if mode === 'poly'}
      <span class="pb-z">Bottom <b>{Math.round(minZ)}</b> · Top <b>{Math.round(maxZ)}</b></span>
      <span class="pb-z">Speed <b>{speed.toFixed(1)}x</b></span>
    {/if}
  </div>
  <div class="pb-bar">
    {#each controls as c}
      <span class="pb-item">
        {#each c.keys as k}<kbd class:mouse={k === 'LMB' || k === 'RMB' || k === 'SCROLL'}>{k}</kbd>{/each}
        <span class="pb-label">{c.label}</span>
      </span>
    {/each}
  </div>
</div>
{/if}

<style>
  .pb-wrap {
    position: fixed; bottom: 28px; left: 50%; transform: translateX(-50%);
    z-index: 150; pointer-events: none;
    display: flex; flex-direction: column; align-items: center; gap: 7px;
    font-family: var(--font);
    animation: pb-rise 0.22s cubic-bezier(0.2,1,0.4,1);
  }
  @keyframes pb-rise { from { opacity: 0; transform: translateX(-50%) translateY(10px); } to { opacity: 1; transform: translateX(-50%) translateY(0); } }
  .pb-status {
    display: flex; align-items: center; gap: 12px;
    background: rgba(10,12,10,0.85); border: 1px solid rgba(163,230,53,0.25);
    border-radius: 99px; padding: 5px 16px;
    font-size: 11.5px; font-weight: 800; color: #fff;
  }
  .pb-title { color: #A3E635; text-transform: uppercase; letter-spacing: 0.08em; font-size: 10.5px; }
  .pb-count { background: rgba(163,230,53,0.15); color: #A3E635; border-radius: 6px; padding: 1px 8px; }
  .pb-z { color: rgba(255,255,255,0.55); font-weight: 700; font-size: 11px; }
  .pb-z b { color: #fff; }
  .pb-bar {
    display: flex; align-items: center; gap: 4px;
    background: rgba(10,12,10,0.85); border: 1px solid rgba(255,255,255,0.09);
    border-radius: 12px; padding: 7px 10px;
    box-shadow: 0 12px 40px rgba(0,0,0,0.55);
  }
  .pb-item { display: flex; align-items: center; gap: 5px; padding: 0 7px; border-right: 1px solid rgba(255,255,255,0.08); }
  .pb-item:last-child { border-right: none; }
  kbd {
    background: linear-gradient(180deg, #2a2e2a, #1a1d1a); border: 1px solid rgba(255,255,255,0.18);
    border-bottom-width: 2.5px; border-radius: 5px;
    padding: 2px 7px; font-family: inherit; font-size: 10px; font-weight: 900; color: #fff;
    min-width: 12px; text-align: center;
  }
  kbd.mouse { background: linear-gradient(180deg, rgba(163,230,53,0.28), rgba(163,230,53,0.12)); border-color: rgba(163,230,53,0.4); color: #A3E635; }
  .pb-label { font-size: 11px; font-weight: 700; color: rgba(255,255,255,0.75); white-space: nowrap; }
</style>
