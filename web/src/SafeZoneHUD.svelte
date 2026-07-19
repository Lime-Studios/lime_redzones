<script>
  let { display = false, name = '', speedLimit = 0 } = $props()
</script>

{#if display}
<div class="sz-badge">
  <svg width="15" height="15" viewBox="0 0 24 24" fill="none"><path d="M12 2l7 4v5c0 5-3.5 9-7 11-3.5-2-7-6-7-11V6l7-4z" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/><path d="M9 12l2 2 4-4" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>
  <span>Safe Zone{#if name} · {name}{/if}</span>
  {#if speedLimit > 0}<span class="sz-limit">{speedLimit} MPH</span>{/if}
</div>
{/if}

<style>
  .sz-badge {
    position: fixed; top: 5%; left: 50%; transform: translateX(-50%);
    z-index: 90; pointer-events: none; display: flex; align-items: center; gap: 8px;
    background: rgba(10,14,11,0.82); border: 1px solid rgba(87,241,135,0.35);
    color: #57F187; padding: 8px 18px; border-radius: 99px;
    font-family: var(--font); font-size: 13px; font-weight: 800; letter-spacing: 0.02em;
    box-shadow: 0 10px 30px rgba(0,0,0,0.5);
    animation: rise 0.25s cubic-bezier(0.2,1,0.4,1);
  }
  @keyframes rise { from { opacity: 0; transform: translateX(-50%) translateY(-8px); } to { opacity: 1; transform: translateX(-50%) translateY(0); } }
  .sz-limit { background: rgba(87,241,135,0.15); border: 1px solid rgba(87,241,135,0.3); border-radius: 6px; padding: 1px 7px; font-size: 10.5px; letter-spacing: 0.04em; }
</style>
