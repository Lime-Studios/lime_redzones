<script>
  import { accentOf } from './theme.js'
  let { display = false, killer = '', id = 0, theme = 'lime' } = $props()
  const accent = $derived(accentOf(theme))
</script>

{#if display}
<div class="kc" style:--kc-accent={accent}>
  <div class="kc-bars"><span></span><span></span></div>
  <div class="kc-hdr">
    <span class="kc-dot"></span>
    KILL CAM
  </div>
  <div class="kc-bottom">
    <span class="kc-tag">KILLED BY</span>
    <span class="kc-name">{killer || 'Enemy'}{#if id} <em>#{id}</em>{/if}</span>
    <span class="kc-pov">their point of view</span>
  </div>
</div>
{/if}

<style>
  .kc { position: fixed; inset: 0; z-index: 90; pointer-events: none; font-family: var(--font); }
  .kc-bars { position: absolute; inset: 0; display: flex; flex-direction: column; justify-content: space-between; }
  .kc-bars span { height: 9vh; }
  .kc-bars span:first-child { background: linear-gradient(rgba(0,0,0,0.9), transparent); }
  .kc-bars span:last-child { background: linear-gradient(transparent, rgba(0,0,0,0.9)); }
  .kc-hdr {
    position: absolute; top: 3vh; left: 50%; transform: translateX(-50%);
    display: flex; align-items: center; gap: 7px;
    font-size: 12px; font-weight: 900; letter-spacing: 0.25em; color: #fff;
  }
  .kc-dot { width: 8px; height: 8px; border-radius: 50%; background: #ef4444; animation: blink 1s infinite; }
  .kc-bottom {
    position: absolute; bottom: 10vh; left: 50%; transform: translateX(-50%);
    display: flex; flex-direction: column; align-items: center; gap: 3px;
  }
  .kc-tag { font-size: 11px; font-weight: 900; letter-spacing: 0.2em; color: var(--kc-accent, var(--accent)); }
  .kc-name { font-size: 30px; font-weight: 900; color: #fff; text-shadow: 0 2px 14px rgba(0,0,0,0.8); }
  .kc-name em { font-style: normal; font-size: 18px; color: var(--kc-accent, var(--accent)); }
  .kc-pov { font-size: 11px; font-weight: 600; color: rgba(255,255,255,0.6); letter-spacing: 0.05em; }
  @keyframes blink { 0%,100% { opacity: 1; } 50% { opacity: 0.3; } }
</style>
