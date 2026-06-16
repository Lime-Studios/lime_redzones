<script>
  let { open = false, onstep, onclose, ondisable } = $props()
  let step = $state(0)

  // Admin walkthrough — each step points at a panel tab and explains its options.
  const steps = [
    { tab: 'zones', icon: '📍', title: 'Zones',
      body: 'Create and manage redzones here. Each zone has a name, location, radius, dome colour, kill rewards, streak rewards, respawn points, and revive cost — all editable in-game. Toggle a zone on/off without deleting it.' },
    { tab: 'gangs', icon: '👥', title: 'Gangs',
      body: 'Register gangs for the gang leaderboard. Framework gangs are auto-detected; add custom ones here for standalone setups.' },
    { tab: 'resets', icon: '🏆', title: 'Leaderboards',
      body: 'Configure weekly auto-resets for the Redzone and Global boards, set the prize for #1, and reset a board instantly. Winners are recorded in Past Winners.' },
    { tab: 'killfeed', icon: '🎥', title: 'Feed & Cam',
      body: 'Toggle the kill feed, kill cam, and "Eliminated" message, and set how long each stays on screen.' },
    { tab: 'options', icon: '⚙️', title: 'Options',
      body: 'Master switches for every feature: leaderboards, streaks, personal colours, notifications, leaderboard columns, HUD defaults, and zone render distance.' },
    { tab: 'perms', icon: '🛡️', title: 'Permissions',
      body: 'Create admin ranks with per-section access, and add admins by identifier. ACE perms and framework god/admin groups always work too.' },
    { tab: 'logs', icon: '📋', title: 'Logs',
      body: 'View admin, kill, and revive logs, send them to Discord webhooks, and auto-post leaderboard snapshots. Everything you set here saves to your database.' },
  ]
  const last = $derived(step >= steps.length - 1)

  $effect(() => { if (open) onstep?.(steps[step].tab) })

  function next() { if (last) finish(); else { step += 1; onstep?.(steps[step].tab) } }
  function back() { if (step > 0) { step -= 1; onstep?.(steps[step].tab) } }
  function finish() { step = 0; onclose?.() }
  function dontShow() { step = 0; ondisable?.() }
</script>

{#if open}
<div class="tut-back">
  <div class="tut">
    <div class="tut-head">
      <span class="tut-step">Step {step + 1} of {steps.length}</span>
      <button class="tut-skip" onclick={finish}>Skip ✕</button>
    </div>

    <div class="tut-icon">{steps[step].icon}</div>
    <h2>{steps[step].title}</h2>
    <p>{steps[step].body}</p>

    <div class="dots">
      {#each steps as _, i}<span class="dot" class:on={i === step}></span>{/each}
    </div>

    <div class="tut-actions">
      <button class="tut-btn ghost" onclick={dontShow}>Don't show again</button>
      {#if step > 0}<button class="tut-btn" onclick={back}>Back</button>{/if}
      <button class="tut-btn go" onclick={next}>{last ? 'Finish' : 'Next →'}</button>
    </div>
  </div>
</div>
{/if}

<style>
  .tut-back { position: absolute; inset: 0; z-index: 300; display: flex; align-items: center; justify-content: flex-end; padding-right: 36px; background: rgba(6,7,9,0.55); border-radius: 20px; }
  .tut { width: 330px; background: #15171b; border: 1px solid rgba(255,255,255,0.1); border-radius: 18px; padding: 18px 22px 18px; box-shadow: 0 30px 80px rgba(0,0,0,0.6); animation: rise 0.3s cubic-bezier(0.2,1,0.4,1); }
  .tut-head { display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px; }
  .tut-step { font-size: 10px; font-weight: 800; letter-spacing: 0.08em; color: var(--accent); text-transform: uppercase; }
  .tut-skip { background: none; border: none; color: rgba(255,255,255,0.45); font-size: 11px; font-weight: 700; font-family: inherit; cursor: pointer; }
  .tut-skip:hover { color: #fff; }
  .tut-icon { font-size: 34px; }
  h2 { font-size: 17px; font-weight: 900; color: #fff; margin: 4px 0 8px; }
  p { font-size: 12.5px; line-height: 1.55; color: rgba(255,255,255,0.72); min-height: 96px; }
  .dots { display: flex; gap: 5px; margin: 10px 0 14px; }
  .dot { width: 6px; height: 6px; border-radius: 50%; background: rgba(255,255,255,0.18); transition: background 0.15s, width 0.15s; }
  .dot.on { width: 18px; border-radius: 99px; background: var(--accent); }
  .tut-actions { display: flex; gap: 7px; align-items: center; }
  .tut-btn { padding: 8px 15px; border: none; border-radius: 9px; font-size: 11.5px; font-weight: 800; font-family: inherit; cursor: pointer; background: rgba(255,255,255,0.07); color: rgba(255,255,255,0.7); }
  .tut-btn.ghost { background: none; color: rgba(255,255,255,0.45); padding-left: 0; margin-right: auto; }
  .tut-btn.ghost:hover { color: rgba(255,255,255,0.8); }
  .tut-btn.go { background: var(--accent); color: var(--accent-text); }
  @keyframes rise { from { opacity: 0; transform: translateY(16px) scale(0.96); } to { opacity: 1; transform: translateY(0) scale(1); } }
</style>
