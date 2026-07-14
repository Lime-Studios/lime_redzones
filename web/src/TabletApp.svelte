<script>
  import { THEME_IDS, accentOf } from './theme.js'
  import Tutorial from './Tutorial.svelte'
  let { display = false, mode = 'player', tab = 'rzleaderboard',
        zones = {}, gangs = {}, settings = {}, personalColor = null,
        lbData = { players: [], gangs: [], globalPlayers: [], totals: {} },
        placementDraft = null, myIds = null, perms = null, options = {}, logs = [], logCategory = 'admin', logConfig = null, prizeHistory = [], firstTime = false, stats = {},
        hudTheme = 'lime', hudPreset = 'top', hudScale = 1, killfeedScale = 1, killfeedTheme = 'inherit', killmsgScale = 1, killmsgTheme = 'inherit',
        onclose } = $props()

  const O = $derived(options ?? {})
  const P = $derived(perms ?? { zones: true, gangs: true, leaderboards: true, options: true, killfeed: true })

  let activeTab = $state('rzleaderboard')
  let lbTab = $state('players')
  let lbSearch = $state('')
  let lbSort = $state('rank')  // rank | name | kills-high | kills-low | kd-high
  let editing = $state(null)
  let clock = $state('')
  let selTheme = $state('lime')
  let selPreset = $state('top')
  let hudScaleVal = $state(1)
  let kfScaleVal = $state(1)
  let kfThemeVal = $state('inherit')
  let kmScaleVal = $state(1)
  let kmThemeVal = $state('inherit')
  let logCat = $state('admin')
  let confirmWipe = $state(false)
  let manualTut = $state(false)
  let lc = $state(null)

  const fmtTime = (t) => { try { return new Date((t ?? 0) * 1000).toLocaleString() } catch { return '' } }
  const stripMd = (s) => (s ?? '').replace(/\*\*/g, '').replace(/`/g, '')

  let tabInit = $state(false)
  $effect(() => {
    if (display && !tabInit) {
      activeTab = tab || (mode === 'admin' ? 'dash' : 'hub')
      tabInit = true
    }
    if (!display) tabInit = false
  })
  let styleInit = $state(false)
  $effect(() => {
    if (display && !styleInit) { selTheme = hudTheme; selPreset = hudPreset; hudScaleVal = hudScale || 1; kfScaleVal = killfeedScale || 1; kfThemeVal = killfeedTheme || 'inherit'; kmScaleVal = killmsgScale || 1; kmThemeVal = killmsgTheme || 'inherit'; styleInit = true }
    if (!display) styleInit = false
  })
  $effect(() => { if (!display) { editing = null; lbTab = 'players' } })
  let idRequested = $state(false)
  let hubLoaded = $state(false)
  $effect(() => {
    if (display && (effectiveTab === 'hub' || effectiveTab === 'dash' || effectiveTab === 'resets') && !hubLoaded) {
      hubLoaded = true; post('requestPrizeHistory')
      if (effectiveTab === 'dash') post('requestStats')
    }
    if (effectiveTab !== 'resets') confirmWipe = false
    if (!display) hubLoaded = false
  })
  $effect(() => {
    if (display && !idRequested && !myIds) { idRequested = true; post('getMyIdentifier') }
    if (!display) idRequested = false
  })
  let tutDismissed = $state(false)
  $effect(() => { if (!display) tutDismissed = false })
  const showTutorial = $derived(display && firstTime === true && !tutDismissed && !manualTut)


  function tutStep(tab) { if (tab) activeTab = tab }
  function tutClose() { tutDismissed = true; manualTut = false }            // skip/finish — reappears next fresh login
  function tutDisable() { tutDismissed = true; manualTut = false; post('tutorialSeen') }  // don't show again — persisted
  $effect(() => {
    if (placementDraft && display) { editing = placementDraft; activeTab = 'zones' }
  })
  $effect(() => {
    if (!display) return
    const tick = () => { const d = new Date(); clock = `${String(d.getHours()).padStart(2,'0')}:${String(d.getMinutes()).padStart(2,'0')}` }
    tick()
    const iv = setInterval(tick, 10000)
    const onKey = (e) => { if (e.key === 'Escape') (editing ? (editing = null) : onclose?.()) }
    window.addEventListener('keydown', onKey)
    return () => { clearInterval(iv); window.removeEventListener('keydown', onKey) }
  })

  const post = (cb, data = {}) =>
    fetch(`https://lime_redzones/${cb}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) })
      .then(r => r.json()).catch(() => ({}))

  const zoneList = $derived(Object.values(zones ?? {}))
  const gangList = $derived(Object.entries(gangs ?? {}).map(([name, g]) => ({ name, label: g.label })))
  const adminList = $derived(settings?.admins ?? [])
  const DAYS = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday']

  const lbCols = $derived(lbData.totals?.cols ?? { kills: true, deaths: true, kd: true })
  const gangLbOn = $derived(lbData.totals?.gangLb !== false)
  const lbRaw = $derived(
    effectiveTab === 'leaderboard' ? lbData.globalPlayers
    : lbTab === 'gangs' ? lbData.gangs
    : lbData.players
  )

  // My identifier(s) so I can highlight + find my own row.
  const myKey = $derived(myIds ? (myIds.identifier || myIds.license) : null)
  const isMe = (item) => myKey && (item.id === myKey || item.id === myIds?.license || item.id === myIds?.identifier)

  // The raw list is already rank-ordered (by kills). Tag each with its true rank first.
  const lbRanked = $derived((lbRaw ?? []).map((it, idx) => ({ ...it, _rank: idx + 1 })))

  const lbList = $derived.by(() => {
    let list = lbRanked
    const q = lbSearch.trim().toLowerCase()
    if (q) list = list.filter(it => String(it.name ?? it.label ?? '').toLowerCase().includes(q))
    const arr = [...list]
    if (lbSort === 'name')       arr.sort((a, b) => String(a.name ?? a.label ?? '').localeCompare(String(b.name ?? b.label ?? '')))
    else if (lbSort === 'kills-high') arr.sort((a, b) => (b.kills ?? 0) - (a.kills ?? 0))
    else if (lbSort === 'kills-low')  arr.sort((a, b) => (a.kills ?? 0) - (b.kills ?? 0))
    else if (lbSort === 'kd-high')    arr.sort((a, b) => ((b.kills??0)/Math.max(1,b.deaths??0)) - ((a.kills??0)/Math.max(1,a.deaths??0)))
    // 'rank' keeps original order
    return arr
  })

  // My current standing (for the HUB).
  const myStanding = $derived(lbRanked.find(isMe) ?? null)
  const myWins = $derived((prizeHistory ?? []).filter(w => myKey && (w.identifier === myKey || w.identifier === myIds?.license || w.identifier === myIds?.identifier)))
  const fmtDate = (t) => { try { return new Date((t ?? 0) * 1000).toLocaleDateString() } catch { return '' } }
  const resetInfo = $derived(effectiveTab === 'leaderboard' ? lbData.totals?.globalReset : lbData.totals?.reset)
  const lbGrid = $derived('44px 1fr' + (lbCols?.kills ? ' 75px' : '') + (lbCols?.deaths ? ' 75px' : '') + (lbCols?.kd ? ' 65px' : ''))

  const initial = (n) => (n ?? '?')[0].toUpperCase()
  const kd = (k, d) => (d > 0 ? (k / d) : k).toFixed(2)

  let hue = $state(0), sat = $state(100), val = $state(100), opacity = $state(80)
  let colorInit = $state(false)
  $effect(() => {
    if (display && personalColor?.hex && !colorInit) {
      const [h, s, v] = hexToHsv(personalColor.hex)
      hue = h; sat = s; val = v; opacity = personalColor.a ?? 80; colorInit = true
    }
    if (!display) colorInit = false
  })
  function hsvToHex(h, s, v) {
    s /= 100; v /= 100
    const f = (n) => { const k = (n + h / 60) % 6; const c = v - v * s * Math.max(0, Math.min(k, 4 - k, 1)); return Math.round(c * 255).toString(16).padStart(2, '0') }
    return ('#' + f(5) + f(3) + f(1)).toUpperCase()
  }
  function hexToHsv(hx) {
    const r = parseInt(hx.slice(1,3),16)/255, g = parseInt(hx.slice(3,5),16)/255, b = parseInt(hx.slice(5,7),16)/255
    const mx = Math.max(r,g,b), mn = Math.min(r,g,b), d = mx - mn
    let h = 0
    if (d !== 0) {
      if (mx === r) h = ((g - b) / d) % 6
      else if (mx === g) h = (b - r) / d + 2
      else h = (r - g) / d + 4
      h = Math.round(h * 60); if (h < 0) h += 360
    }
    return [h, Math.round(mx === 0 ? 0 : (d / mx) * 100), Math.round(mx * 100)]
  }
  const pickedHex = $derived(hsvToHex(hue, sat, val))
  const hueColor = $derived(hsvToHex(hue, 100, 100))
  function onHexType(e) {
    let v = e.target.value.trim(); if (!v.startsWith('#')) v = '#' + v
    if (/^#[0-9a-fA-F]{6}$/.test(v)) { const [h, s, vl] = hexToHsv(v.toUpperCase()); hue = h; sat = s; val = vl }
  }

  let newGangName = $state(''), newGangLabel = $state('')
  let newAdminId = $state(''), newAdminRank = $state('')
  let rs = $state({ enabled: false, day: 0, hour: 18, prizeName: 'money', prizeAmount: 0 })
  let grs = $state({ enabled: false, day: 0, hour: 18, prizeName: 'money', prizeAmount: 0 })
  let ranks = $state([])
  let opts = $state({
    rewardNotify: true, streakAnnounce: true, renderDistance: 120,
    leaderboardEnabled: true, globalLbEnabled: true, gangLbEnabled: true,
    streaksEnabled: true, personalColorEnabled: true, personalColorHue: true, personalColorOpacity: true,
    killFeedEnabled: true, killCamEnabled: true, killMessageEnabled: true, killFeedDuration: 6000, killCamDuration: 5000, hudDefaultTheme: 'lime', hudDefaultPreset: 'top',
    lbCols: { kills: true, deaths: true, kd: true },
  })
  let settingsKey = $state(null)
  $effect(() => {
    if (!settings) return
    // Only re-sync on a fresh server push, never on local edits (would self-trigger).
    if (settings === settingsKey) return
    settingsKey = settings
    if (settings.reset) rs = { ...settings.reset }
    if (settings.globalReset) grs = { ...settings.globalReset }
    if (settings.options) {
      const def = {
        rewardNotify: true, streakAnnounce: true, renderDistance: 120,
        leaderboardEnabled: true, globalLbEnabled: true, gangLbEnabled: true,
        streaksEnabled: true, personalColorEnabled: true, personalColorHue: true, personalColorOpacity: true,
        killFeedEnabled: true, killCamEnabled: true, killMessageEnabled: true, killFeedDuration: 6000, killCamDuration: 5000, hudDefaultTheme: 'lime', hudDefaultPreset: 'top',
        lbCols: { kills: true, deaths: true, kd: true },
      }
      opts = { ...def, ...settings.options, lbCols: { ...def.lbCols, ...(settings.options.lbCols ?? {}) } }
    }
    if (settings.ranks) ranks = JSON.parse(JSON.stringify(settings.ranks))
  })
  const rankNames = $derived(ranks.map(r => r.name))

  let logCfgKey = $state(null)
  $effect(() => {
    if (logConfig && logConfig !== logCfgKey) {
      logCfgKey = logConfig
      lc = JSON.parse(JSON.stringify({
        enabled: logConfig.enabled !== false,
        categories: { admin: true, kills: false, revives: true, ...(logConfig.categories ?? {}) },
        webhooks: { admin: '', kills: '', revives: '', leaderboardRz: '', leaderboardGlobal: '', ...(logConfig.webhooks ?? {}) },
        leaderboardPost: { enabled: false, board: 'redzone', interval: 30, top: 10, ...(logConfig.leaderboardPost ?? {}) },
      }))
    }
  })

  let logsLoaded = $state(false)
  $effect(() => {
    if (display && effectiveTab === 'logs' && !logsLoaded) {
      logsLoaded = true
      post('requestLogs', { category: logCat })
      post('requestLogConfig')
    }
    if (!display || effectiveTab !== 'logs') logsLoaded = false
  })

  const blankZone = () => ({
    id: null, name: '', coords: { x: 0, y: 0, z: 0 }, radius: 60,
    colorHex: '#FF0000', colorA: 80, blipSprite: 310, blipColor: 1,
    rewardItems: [{ name: 'money', amount: 500 }], streakRewards: [],
    reviveCost: 10000, reviveInside: true, reviveDelay: 8000, teleportAway: 30, exits: [], enabled: true,
  })
  function startEdit(z) {
    editing = JSON.parse(JSON.stringify(z ?? blankZone()))
    editing.rewardItems ??= []; editing.streakRewards ??= []; editing.exits ??= []
  }
  async function grabPos(target) {
    const pos = await post('getMyPosition')
    if (pos?.x !== undefined) { if (target === 'coords') editing.coords = pos; else if (editing.exits.length < 5) editing.exits.push(pos) }
  }
  function saveZone() { post('saveZone', editing); editing = null }
  function saveGang() {
    if (!newGangName.trim()) return
    post('saveGang', { name: newGangName.trim(), label: newGangLabel.trim() || newGangName.trim() })
    newGangName = ''; newGangLabel = ''
  }

  const THEME_LIST = THEME_IDS.map(id => ({ id, c: accentOf(id) }))
  const PRESET_LIST = ['top', 'top-left', 'top-right', 'bottom', 'left', 'right']

  const playerNavAll = [
    { id: 'hub',           label: 'Hub',            icon: 'M3 12l9-9 9 9M5 10v10h14V10' },
    { id: 'rzleaderboard', label: 'RZ Leaderboard', icon: 'M8 21h8M12 17v4M7 4h10v6a5 5 0 0 1-10 0V4z', need: 'leaderboardEnabled' },
    { id: 'leaderboard',   label: 'Leaderboard',    icon: 'M3 13h4v8H3zM10 5h4v16h-4zM17 9h4v12h-4z', need: 'globalLbEnabled' },
    { id: 'color',         label: 'Zone Colour',    icon: 'M12 2a10 10 0 1 0 10 10c0-1-1-2-2-2h-2a2 2 0 0 1-2-2c0-1 1-2 2-2h1a2 2 0 0 0 2-2c0-1-4-2-9-2z', need: 'personalColorEnabled' },
    { id: 'hud',           label: 'HUD',            icon: 'M3 5h18v12H3zM8 21h8' },
  ]
  const adminNavAll = [
    { id: 'dash',     label: 'Dashboard',    icon: 'M3 3h8v8H3zM13 3h8v5h-8zM13 10h8v11h-8zM3 13h8v8H3z' },
    { id: 'zones',    label: 'Zones',        icon: 'M12 21s-7-5.5-7-11a7 7 0 0 1 14 0c0 5.5-7 11-7 11z', perm: 'zones' },
    { id: 'gangs',    label: 'Gangs',        icon: 'M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8z', perm: 'gangs' },
    { id: 'resets',   label: 'Leaderboards', icon: 'M3 12a9 9 0 1 0 9-9M3 12l3-3M3 12l3 3', perm: 'leaderboards' },
    { id: 'killfeed', label: 'Feed & Cam',   icon: 'M2 6h20v12H2zM8 10l4 2-4 2z', perm: 'killfeed' },
    { id: 'options',  label: 'Options',      icon: 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z', perm: 'options' },
    { id: 'perms',    label: 'Permissions',  icon: 'M12 2l7 4v5c0 5-3.5 9-7 11-3.5-2-7-6-7-11V6l7-4z', perm: 'options' },
    { id: 'logs',     label: 'Logs',         icon: 'M4 4h16v16H4zM8 9h8M8 13h8M8 17h5', perm: 'options' },
  ]
  const nav = $derived(
    mode === 'admin'
      ? adminNavAll.filter(n => !n.perm || P[n.perm])
      : playerNavAll.filter(n => !n.need || O[n.need] !== false)
  )
  // $derived (not $effect) so an invalid tab can't cause an update loop.
  const effectiveTab = $derived(
    nav.find(n => n.id === activeTab) ? activeTab : (nav[0]?.id ?? activeTab)
  )
  const canAdmin = $derived(mode === 'admin')
</script>

{#if display}
<div class="blocker" role="button" tabindex="-1" onclick={onclose} onkeydown={() => {}}></div>

<div class="tablet">
  <div class="statusbar">
    <span class="sb-left">
      {#if canAdmin}
        <button class="sb-back" onclick={() => post('openPlayerTablet')}>
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none"><path d="M15 18l-6-6 6-6" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/></svg>
          Back
        </button>
      {/if}
      <span class="sb-clock">{clock}</span>
    </span>
    <span class="sb-brand">
      <svg width="13" height="13" viewBox="0 0 24 24" fill="none"><path d="M12 3c-4 0-8 3-8 9 0 5 4 9 8 9s8-4 8-9c0-6-4-9-8-9zM12 3c2-1 4-1 5 0" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>
      Lime OS
      {#if mode === 'admin'}<span class="sb-admin">ADMIN</span>{/if}
    </span>
    <span class="sb-right">
      <svg width="13" height="13" viewBox="0 0 24 24" fill="none"><path d="M2 9c5.5-5.5 14.5-5.5 20 0M5 12.5c3.9-3.9 10.1-3.9 14 0M8.5 16c2-2 5-2 7 0M12 19.5h.01" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>
      <button class="sb-help" onclick={() => manualTut = true} aria-label="Show tutorial" title="Show tutorial"><svg width="13" height="13" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="9" stroke="currentColor" stroke-width="2"/><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.7.3-1 .8-1 1.5v.2M12 17h.01" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg></button>
      <button class="sb-close" onclick={onclose} aria-label="Close"><svg width="11" height="11" viewBox="0 0 24 24" fill="none"><path d="M18 6L6 18M6 6l12 12" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"/></svg></button>
    </span>
  </div>

  <Tutorial open={showTutorial || manualTut} mode={mode} onstep={tutStep} onclose={tutClose} ondisable={tutDisable} />

  <div class="tbody">
    <div class="nav">
      {#each nav as n}
        <button class="nav-item" class:on={effectiveTab === n.id} onclick={() => activeTab = n.id}>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none"><path d={n.icon} stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>
          <span>{n.label}</span>
        </button>
      {/each}
      {#if mode === 'player'}
        <button class="nav-item admin-entry" onclick={() => post('openAdminPanel')}>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none"><path d="M12 2l7 4v5c0 5-3.5 9-7 11-3.5-2-7-6-7-11V6l7-4z" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/></svg>
          <span>Admin Panel</span>
        </button>
      {/if}
    </div>

    <div class="content">
      {#if effectiveTab === 'hub'}
        <div class="page-head"><h1>Hub</h1></div>
        <p class="sub">Your redzone profile at a glance.</p>

        <div class="hub-grid">
          <div class="hub-card big">
            <span class="hub-label">Your Rank</span>
            <span class="hub-big">{myStanding ? '#' + myStanding._rank : '—'}</span>
            <span class="hub-sub">{myStanding ? 'Redzone leaderboard' : 'No kills yet — get in a zone!'}</span>
          </div>
          <div class="hub-card">
            <span class="hub-label">Kills</span>
            <span class="hub-num">{myStanding?.kills ?? 0}</span>
          </div>
          <div class="hub-card">
            <span class="hub-label">Deaths</span>
            <span class="hub-num">{myStanding?.deaths ?? 0}</span>
          </div>
          <div class="hub-card">
            <span class="hub-label">K/D</span>
            <span class="hub-num">{kd(myStanding?.kills ?? 0, myStanding?.deaths ?? 0)}</span>
          </div>
          <div class="hub-card">
            <span class="hub-label">Wins</span>
            <span class="hub-num">{myWins.length}</span>
          </div>
        </div>

        <div class="block">
          <div class="frow between">
            <b class="blk-title">🏆 Your Past Prizes</b>
            <button class="btn" onclick={() => post('requestPrizeHistory')}>Refresh</button>
          </div>
          {#if myWins.length === 0}
            <p class="hint">You haven't won a weekly reset yet. Top the leaderboard to claim a prize!</p>
          {:else}
            {#each myWins.slice(0, 10) as w (w.time + (w.board ?? ''))}
              <div class="frow inset">
                <span class="win-board" class:global={w.board === 'global'}>{w.board === 'global' ? 'GLOBAL' : 'RZ'}</span>
                <span class="grow">{w.kills} kills · <span class="dim">{fmtDate(w.time)}</span></span>
                <span class="win-prize">{w.prize?.name === 'money' ? '$' + w.prize.amount : (w.prize?.amount + '× ' + w.prize?.name)}</span>
              </div>
            {/each}
          {/if}
        </div>

        <div class="block">
          <b class="blk-title">⚡ Quick Actions</b>
          <div class="hub-actions">
            <button class="btn go" onclick={() => activeTab = 'rzleaderboard'}>View Leaderboard</button>
            <button class="btn" onclick={() => activeTab = 'hud'}>Customise HUD</button>
            <button class="btn" onclick={() => activeTab = 'color'}>Zone Colour</button>
          </div>
        </div>

      {:else if effectiveTab === 'rzleaderboard' || effectiveTab === 'leaderboard'}
        <div class="page-head">
          <h1>{effectiveTab === 'leaderboard' ? 'Global Leaderboard' : 'Redzone Leaderboard'}</h1>
          <div class="stat-pills">
            <span class="pill">Kills <b>{(effectiveTab === 'leaderboard' ? lbData.totals?.globalKills : lbData.totals?.kills) ?? 0}</b></span>
            <span class="pill">Deaths <b>{(effectiveTab === 'leaderboard' ? lbData.totals?.globalDeaths : lbData.totals?.deaths) ?? 0}</b></span>
          </div>
        </div>
        {#if effectiveTab === 'rzleaderboard'}
        <div class="seg">
          <button class:on={lbTab === 'players'} onclick={() => lbTab = 'players'}>Players</button>
          {#if gangLbOn}<button class:on={lbTab === 'gangs'} onclick={() => lbTab = 'gangs'}>Gangs</button>{/if}
        </div>
        {/if}
        {#if resetInfo?.enabled}
          <div class="reset-line">Resets {resetInfo.label}{#if resetInfo.prize} · 🏆 {resetInfo.prize.name === 'money' ? '$' + resetInfo.prize.amount : resetInfo.prize.amount + 'x ' + resetInfo.prize.name}{/if}</div>
        {/if}

        <div class="lb-tools">
          <div class="lb-search">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none"><circle cx="11" cy="11" r="7" stroke="currentColor" stroke-width="2"/><path d="M21 21l-4-4" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>
            <input placeholder={lbTab === 'gangs' ? 'Search gangs…' : 'Search players…'} bind:value={lbSearch} />
            {#if lbSearch}<button class="lb-clear" onclick={() => lbSearch = ''} aria-label="Clear">✕</button>{/if}
          </div>
          <select class="lb-sort" bind:value={lbSort}>
            <option value="rank">Rank</option>
            <option value="kills-high">Kills: High → Low</option>
            <option value="kills-low">Kills: Low → High</option>
            <option value="kd-high">Best K/D</option>
            <option value="name">Name A → Z</option>
          </select>
        </div>

        <div class="lb">
          <div class="lb-head" style:grid-template-columns={lbGrid}>
            <span>#</span><span>{lbTab === 'gangs' ? 'GANG' : 'PLAYER'}</span>
            {#if lbCols.kills}<span class="c">KILLS</span>{/if}
            {#if lbCols.deaths}<span class="c">DEATHS</span>{/if}
            {#if lbCols.kd}<span class="c">K/D</span>{/if}
          </div>
          {#if lbList.length === 0}<div class="empty">{lbSearch ? 'No matches.' : 'No data yet.'}</div>{/if}
          {#each lbList as item, i (item.id ?? item.label ?? i)}
            {@const name = lbTab === 'gangs' ? item.label : item.name}
            {@const rank = item._rank ?? (i + 1)}
            <div class="lb-row" class:first={rank === 1} class:me={lbTab !== 'gangs' && isMe(item)} style:grid-template-columns={lbGrid}>
              <span class="rank" class:r1={rank===1} class:r2={rank===2} class:r3={rank===3}>{rank}</span>
              <span class="who"><span class="av">{initial(name)}</span>{name ?? 'Unknown'}{#if lbTab !== 'gangs' && isMe(item)}<span class="you-tag">YOU</span>{/if}</span>
              {#if lbCols.kills}<span class="c">{item.kills ?? 0}</span>{/if}
              {#if lbCols.deaths}<span class="c">{item.deaths ?? 0}</span>{/if}
              {#if lbCols.kd}<span class="c bold">{kd(item.kills ?? 0, item.deaths ?? 0)}</span>{/if}
            </div>
          {/each}
        </div>

        <div class="block" style="margin-top:4px">
          <div class="frow between">
            <b class="blk-title">🏆 Past Winners</b>
            <button class="btn" onclick={() => post('requestPrizeHistory')}>Load</button>
          </div>
          {#if (prizeHistory ?? []).length === 0}
            <p class="hint">No past winners yet. Win a weekly reset to appear here!</p>
          {:else}
            {#each (prizeHistory ?? []).slice(0, 12) as w (w.time + (w.name ?? ''))}
              <div class="frow inset">
                <span class="win-board" class:global={w.board === 'global'}>{w.board === 'global' ? 'GLOBAL' : 'RZ'}</span>
                <span class="grow"><b>{w.name}</b> · {w.kills} kills</span>
                <span class="win-prize">{w.prize?.name === 'money' ? '$' + w.prize.amount : (w.prize?.amount + '× ' + w.prize?.name)}</span>
              </div>
            {/each}
          {/if}
        </div>

      {:else if effectiveTab === 'color'}
        <div class="page-head"><h1>Zone Colour</h1></div>
        <p class="sub">Personal override — only you see this colour on zone domes.</p>
        <div class="cpick">
          <div class="cprev" style:background={pickedHex} style:opacity={Math.max(0.3, opacity/255)}></div>
          {#if O.personalColorHue !== false}
          <label class="cs"><span>Hue</span><input class="track hue" type="range" min="0" max="360" bind:value={hue} /></label>
          <label class="cs"><span>Saturation</span><input class="track" type="range" min="0" max="100" bind:value={sat} style:background={`linear-gradient(90deg, #fff, ${hueColor})`} /></label>
          <label class="cs"><span>Brightness</span><input class="track" type="range" min="0" max="100" bind:value={val} style:background={`linear-gradient(90deg, #000, ${hueColor})`} /></label>
          {/if}
          {#if O.personalColorOpacity !== false}
          <label class="cs"><span>Opacity <em>{opacity}</em></span><input class="track" type="range" min="0" max="255" bind:value={opacity} style:background={`linear-gradient(90deg, transparent, ${pickedHex})`} /></label>
          {/if}
          <div class="hexrow">
            <input class="hexfield" value={pickedHex} oninput={onHexType} maxlength="7" spellcheck="false" placeholder="#FF0000" />
            <button class="btn ghost" onclick={() => post('savePersonalColor', { reset: true })}>Reset</button>
            <button class="btn go" onclick={() => post('savePersonalColor', { hex: pickedHex, a: +opacity })}>Apply</button>
          </div>
        </div>

      {:else if effectiveTab === 'hud'}
        <div class="page-head"><h1>HUD</h1></div>

        <div class="block">
          <b class="blk-title">Theme</b>
          <div class="themes">
            {#each THEME_LIST as t}
              <button class="theme-chip" class:on={selTheme === t.id} onclick={() => { selTheme = t.id; post('saveHudTheme', { theme: t.id, preset: selPreset, scale: hudScaleVal }) }}>
                <span class="theme-dot" style:background={t.c}></span>{t.id}
              </button>
            {/each}
          </div>
        </div>

        <div class="block">
          <b class="blk-title">HUD Preview</b>
          <div class="hud-stage">
            <div class="hud-mini" style:--mini-accent={THEME_LIST.find(t=>t.id===selTheme)?.c ?? '#A3E635'} style:transform={`translateX(-50%) scale(${hudScaleVal})`}>
              <span class="hm-blade">REDZONE</span>
              <span class="hm-stats">3 / 1 / 2</span>
            </div>
          </div>
          <div class="presets">
            {#each PRESET_LIST as pr}
              <button class="preset-chip" class:on={selPreset === pr} onclick={() => { selPreset = pr; post('saveHudTheme', { theme: selTheme, preset: pr, scale: hudScaleVal }) }}>{pr.replace('-', ' ')}</button>
            {/each}
          </div>
        </div>

        <div class="block">
          <b class="blk-title">Size</b>
          <label class="f"><span>HUD scale <em>{Math.round(hudScaleVal * 100)}%</em></span>
            <input class="track" type="range" min="0.6" max="1.6" step="0.05" bind:value={hudScaleVal} onchange={() => post('saveHudTheme', { theme: selTheme, preset: selPreset, scale: hudScaleVal })} />
          </label>
          <div class="hud-actions">
            <button class="btn go" onclick={() => post('startHudMove')}><svg width="13" height="13" viewBox="0 0 24 24" fill="none"><path d="M12 2v20M2 12h20" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg> Drag freely</button>
            <button class="btn" onclick={() => post('resetHudPos')}>Reset to preset</button>
          </div>
          <p class="hint">Drag mode closes the tablet — move the HUD, then click Done.</p>
        </div>

        {#if O.killFeedEnabled !== false}
        <div class="block">
          <b class="blk-title">Kill Feed</b>
          <label class="f"><span>Theme</span>
            <select bind:value={kfThemeVal} onchange={() => post('saveKillfeedStyle', { scale: kfScaleVal, theme: kfThemeVal })}>
              <option value="inherit">Match HUD</option>
              {#each THEME_LIST as t}<option value={t.id}>{t.id}</option>{/each}
            </select>
          </label>
          <label class="f"><span>Size <em>{Math.round(kfScaleVal * 100)}%</em></span>
            <input class="track" type="range" min="0.6" max="1.6" step="0.05" bind:value={kfScaleVal} onchange={() => post('saveKillfeedStyle', { scale: kfScaleVal, theme: kfThemeVal })} />
          </label>
          <div class="hud-actions">
            <button class="btn go" onclick={() => post('startKfMove')}><svg width="13" height="13" viewBox="0 0 24 24" fill="none"><path d="M12 2v20M2 12h20" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg> Move kill feed</button>
            <button class="btn" onclick={() => post('resetKfPos')}>Reset</button>
          </div>
          <p class="hint">A drag handle appears on the feed — drag it, then click Done.</p>
        </div>
        {/if}

        {#if O.killMessageEnabled !== false}
        <div class="block">
          <b class="blk-title">"Eliminated" Message</b>
          <label class="f"><span>Theme</span>
            <select bind:value={kmThemeVal} onchange={() => post('saveKillMsgStyle', { scale: kmScaleVal, theme: kmThemeVal })}>
              <option value="inherit">Match HUD</option>
              {#each THEME_LIST as t}<option value={t.id}>{t.id}</option>{/each}
            </select>
          </label>
          <label class="f"><span>Size <em>{Math.round(kmScaleVal * 100)}%</em></span>
            <input class="track" type="range" min="0.6" max="1.6" step="0.05" bind:value={kmScaleVal} onchange={() => post('saveKillMsgStyle', { scale: kmScaleVal, theme: kmThemeVal })} />
          </label>
          <div class="hud-actions">
            <button class="btn go" onclick={() => post('startKmMove')}><svg width="13" height="13" viewBox="0 0 24 24" fill="none"><path d="M12 2v20M2 12h20" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg> Move message</button>
            <button class="btn" onclick={() => post('resetKmPos')}>Reset</button>
          </div>
          <p class="hint">A preview appears — drag it where you want, then click Done.</p>
        </div>
        {/if}
      {/if}

      {#if effectiveTab === 'dash'}
        <div class="page-head"><h1>Dashboard</h1></div>
        <p class="sub">Live overview of your redzones and activity.</p>

        <div class="hub-grid">
          <div class="hub-card big">
            <span class="hub-label">Active Zones</span>
            <span class="hub-big">{stats.activeZones ?? 0}<span class="hub-of">/ {stats.totalZones ?? 0}</span></span>
            <span class="hub-sub">{stats.totalZones ? 'redzones configured' : 'No zones yet — create one'}</span>
          </div>
          <div class="hub-card"><span class="hub-label">Players Tracked</span><span class="hub-num">{stats.playersTracked ?? 0}</span></div>
          <div class="hub-card"><span class="hub-label">Total Kills</span><span class="hub-num">{stats.totalKills ?? 0}</span></div>
          <div class="hub-card"><span class="hub-label">Total Deaths</span><span class="hub-num">{stats.totalDeaths ?? 0}</span></div>
          <div class="hub-card"><span class="hub-label">Gangs</span><span class="hub-num">{stats.gangs ?? 0}</span></div>
          <div class="hub-card"><span class="hub-label">Admins</span><span class="hub-num">{stats.admins ?? 0}</span></div>
        </div>

        <div class="block">
          <b class="blk-title">📍 Zones</b>
          {#if (stats.zoneList ?? []).length === 0}
            <p class="hint">No zones created yet. Head to the Zones tab to make your first redzone.</p>
          {:else}
            <div class="lb-head" style="grid-template-columns: 1fr auto auto; padding: 4px 10px;">
              <span>ZONE</span><span class="c">KILLS</span><span class="c">STATUS</span>
            </div>
            {#each stats.zoneList as z (z.id)}
              <div class="frow inset" style="display:grid; grid-template-columns: 1fr auto auto; gap:10px; align-items:center;">
                <span class="grow"><b>{z.name}</b></span>
                <span class="c">{z.kills ?? 0}</span>
                <span class="zstat" class:on={z.enabled}>{z.enabled ? 'ON' : 'OFF'}</span>
              </div>
            {/each}
          {/if}
        </div>

        <div class="block">
          <b class="blk-title">🏆 Top Players</b>
          {#if (stats.topPlayers ?? []).length === 0}
            <p class="hint">No kills recorded yet.</p>
          {:else}
            {#each stats.topPlayers.slice(0, 5) as p, i (p.name + i)}
              <div class="frow inset">
                <span class="rank" class:r1={i===0} class:r2={i===1} class:r3={i===2}>{i + 1}</span>
                <span class="grow"><b>{p.name}</b></span>
                <span class="win-prize">{p.kills} kills</span>
              </div>
            {/each}
          {/if}
        </div>

        <div class="block">
          <b class="blk-title">⚡ Quick Actions</b>
          <div class="hub-actions">
            <button class="btn go" onclick={() => activeTab = 'zones'}>Manage Zones</button>
            <button class="btn" onclick={() => activeTab = 'resets'}>Leaderboards</button>
            <button class="btn" onclick={() => activeTab = 'logs'}>View Logs</button>
            <button class="btn" onclick={() => post('requestStats')}>Refresh</button>
          </div>
        </div>

      {:else if effectiveTab === 'zones'}
        <div class="page-head"><h1>Zones</h1><button class="btn go" onclick={() => startEdit(null)}>+ Create Redzone</button></div>
        <div class="ztable">
          <div class="zt-head"><span>NAME</span><span>RADIUS</span><span>ENABLED</span><span class="r">ACTIONS</span></div>
          {#if zoneList.length === 0}<div class="empty">No zones yet.</div>{/if}
          {#each zoneList as z (z.id)}
            <div class="zt-row">
              <span class="zname"><span class="zdot" style:background={z.colorHex ?? '#FF0000'}></span>{z.name}</span>
              <span class="dim">{z.radius}m</span>
              <span><button class="sw sm" class:on={z.enabled} onclick={() => post('toggleZone', { id: z.id, enabled: !z.enabled })} aria-label="Toggle"><i></i></button></span>
              <span class="r acts">
                <button class="ib" title="Teleport" onclick={() => post('teleportToZone', { id: z.id })}><svg width="12" height="12" viewBox="0 0 24 24" fill="none"><path d="M12 2v8m0 0l3-3m-3 3L9 7" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><circle cx="12" cy="17" r="4" stroke="currentColor" stroke-width="2"/></svg></button>
                <button class="ib" title="Edit" onclick={() => startEdit(z)}><svg width="12" height="12" viewBox="0 0 24 24" fill="none"><path d="M17 3a2.8 2.8 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5L17 3z" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/></svg></button>
                <button class="ib red" title="Delete" onclick={() => post('deleteZone', { id: z.id })}><svg width="12" height="12" viewBox="0 0 24 24" fill="none"><path d="M3 6h18M8 6V4a1 1 0 0 1 1-1h6a1 1 0 0 1 1 1v2m3 0v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg></button>
              </span>
            </div>
          {/each}
        </div>

      {:else if effectiveTab === 'gangs'}
        <div class="page-head"><h1>Gangs</h1></div>
        <div class="block">
          <div class="frow">
            <label class="f grow"><span>Internal name</span><input bind:value={newGangName} placeholder="ballas" /></label>
            <label class="f grow"><span>Display label</span><input bind:value={newGangLabel} placeholder="Ballas" /></label>
            <button class="btn go end" onclick={saveGang}>Add</button>
          </div>
          <p class="hint">Framework gangs auto-detect — this is for standalone servers.</p>
        </div>
        {#each gangList as g (g.name)}
          <div class="block row"><b class="gl">{g.label}</b><span class="dim grow">{g.name}</span><button class="ib red" onclick={() => post('deleteGang', { name: g.name })}><svg width="12" height="12" viewBox="0 0 24 24" fill="none"><path d="M3 6h18M8 6V4a1 1 0 0 1 1-1h6a1 1 0 0 1 1 1v2m3 0v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg></button></div>
        {/each}

      {:else if effectiveTab === 'resets'}
        <div class="page-head"><h1>Leaderboards</h1></div>
        {#each [{ which: 'reset', label: 'Redzone Leaderboard', cfg: rs }, { which: 'globalReset', label: 'Global Leaderboard', cfg: grs }] as s}
          <div class="block">
            <div class="frow between"><b>{s.label} — Weekly Reset</b><button class="sw" class:on={s.cfg.enabled} onclick={() => s.cfg.enabled = !s.cfg.enabled} aria-label="Toggle"><i></i></button></div>
            <div class="frow">
              <label class="f"><span>Day</span><select bind:value={s.cfg.day}>{#each DAYS as d, i}<option value={i}>{d}</option>{/each}</select></label>
              <label class="f w70"><span>Hour</span><input type="number" min="0" max="23" bind:value={s.cfg.hour} /></label>
              <label class="f grow"><span>Prize item</span><input bind:value={s.cfg.prizeName} placeholder="money" /></label>
              <label class="f w90"><span>Amount</span><input type="number" min="0" bind:value={s.cfg.prizeAmount} /></label>
            </div>
            <div class="frow">
              <button class="btn go" onclick={() => post('saveResetSettings', { which: s.which, cfg: s.cfg })}>Save</button>
              <button class="btn red" onclick={() => post('resetLeaderboard', { which: s.which === 'globalReset' ? 'global' : 'zone' })}>Reset Now</button>
            </div>
          </div>
        {/each}
        <p class="hint">Prize goes to #1 by kills. Offline winners receive it on next join.</p>

        <div class="block">
          <div class="frow between">
            <b class="blk-title">🏆 Past Winners</b>
            <button class="btn" onclick={() => post('requestPrizeHistory')}>Refresh</button>
          </div>
          {#if (prizeHistory ?? []).length === 0}
            <p class="hint">No recorded winners yet.</p>
          {:else}
            {#each (prizeHistory ?? []).slice(0, 8) as w (w.time + (w.name ?? ''))}
              <div class="frow inset">
                <span class="win-board" class:global={w.board === 'global'}>{w.board === 'global' ? 'GLOBAL' : 'RZ'}</span>
                <span class="grow"><b>{w.name}</b> · {w.kills} kills</span>
                <span class="win-prize">{w.prize?.name === 'money' ? '$' + w.prize.amount : (w.prize?.amount + '× ' + w.prize?.name)}</span>
              </div>
            {/each}
            {#if (prizeHistory ?? []).length > 8}<p class="hint">+ {(prizeHistory.length - 8)} more…</p>{/if}
            <button class="btn red" onclick={() => { if (confirmWipe) { post('wipePrizeHistory'); confirmWipe = false } else confirmWipe = true }}>
              {confirmWipe ? 'Click again to confirm wipe' : '🗑 Wipe Past Winners'}
            </button>
            {#if confirmWipe}<button class="btn" onclick={() => confirmWipe = false}>Cancel</button>{/if}
          {/if}
        </div>

      {:else if effectiveTab === 'killfeed'}
        <div class="page-head"><h1>Kill Feed &amp; Cam</h1></div>
        <div class="block">
          <div class="frow between"><div><b>Kill feed</b><p class="hint">Show a feed of redzone kills to all players.</p></div><button class="sw" class:on={opts.killFeedEnabled} onclick={() => opts.killFeedEnabled = !opts.killFeedEnabled} aria-label="Toggle"><i></i></button></div>
          {#if opts.killFeedEnabled}
            <label class="f"><span>Kill feed duration <em>{(((opts.killFeedDuration ?? 6000))/1000).toFixed(1)}s</em></span><input class="track" type="range" min="2000" max="20000" step="500" bind:value={opts.killFeedDuration} /></label>
          {/if}
          <div class="frow between"><div><b>Kill cam</b><p class="hint">Spectate your killer's POV after dying in a zone.</p></div><button class="sw" class:on={opts.killCamEnabled} onclick={() => opts.killCamEnabled = !opts.killCamEnabled} aria-label="Toggle"><i></i></button></div>
          {#if opts.killCamEnabled}
            <label class="f"><span>Kill cam duration <em>{(((opts.killCamDuration ?? 5000))/1000).toFixed(1)}s</em></span><input class="track" type="range" min="2000" max="15000" step="500" bind:value={opts.killCamDuration} /></label>
          {/if}
          <div class="frow between"><div><b>"Eliminated" message</b><p class="hint">Big on-screen message shown to you when you get a kill.</p></div><button class="sw" class:on={opts.killMessageEnabled} onclick={() => opts.killMessageEnabled = !opts.killMessageEnabled} aria-label="Toggle"><i></i></button></div>
          <button class="btn go end" onclick={() => post('saveOptions', opts)}>Save</button>
        </div>
        <p class="hint">Players reposition the kill feed from their own HUD tab when it's enabled.</p>

      {:else if effectiveTab === 'perms'}
        <div class="page-head"><h1>Permissions</h1></div>
        <div class="block">
          <b class="blk-title">Ranks</b>
          <p class="hint">Define what each admin rank can access. Ace god perms always have full access.</p>
          {#each ranks as r, ri}
            <div class="rank-card">
              <div class="frow between"><input class="rank-name" bind:value={r.name} placeholder="Rank name" /><button class="ib red" onclick={() => ranks.splice(ri, 1)}>✕</button></div>
              <div class="perm-grid">
                {#each [['zones','Zones'],['gangs','Gangs'],['leaderboards','Leaderboards'],['killfeed','Feed & Cam'],['options','Options']] as pk}
                  <button class="perm-chip" class:on={r.perms[pk[0]]} onclick={() => r.perms[pk[0]] = !r.perms[pk[0]]}>{pk[1]}</button>
                {/each}
              </div>
            </div>
          {/each}
          <div class="frow"><button class="btn dash" onclick={() => ranks.push({ name: 'New Rank', perms: { zones: false, gangs: false, leaderboards: true, options: false, killfeed: false } })}>+ Add Rank</button><button class="btn go" onclick={() => post('saveRanks', { ranks })}>Save Ranks</button></div>
        </div>
        <div class="block">
          <b class="blk-title">Admins</b>
          <p class="hint">Add license: or citizenid identifiers. Assign a rank to limit their panel access.</p>
          {#each adminList as a (typeof a === 'object' ? a.id : a)}
            <div class="frow inset">
              <span class="dim grow mono">{typeof a === 'object' ? a.id : a}</span>
              {#if typeof a === 'object' && a.rank}<span class="rank-tag">{a.rank}</span>{/if}
              <button class="ib red" onclick={() => post('removeAdminId', { identifier: typeof a === 'object' ? a.id : a })}>✕</button>
            </div>
          {/each}
          <div class="frow">
            <input class="grow" bind:value={newAdminId} placeholder="license:abc… or citizenid" />
            <select bind:value={newAdminRank} style="width:130px"><option value="">Full access</option>{#each rankNames as rn}<option value={rn}>{rn}</option>{/each}</select>
            <button class="btn go" onclick={() => { if (newAdminId.trim()) { post('addAdminId', { identifier: newAdminId.trim(), rank: newAdminRank || null }); newAdminId = '' } }}>Add</button>
          </div>
          {#if myIds}<p class="hint mono">You: {myIds.license} · {myIds.identifier}</p>{:else}<button class="btn dash" onclick={() => post('getMyIdentifier')}>Show my identifiers</button>{/if}
        </div>

      {:else if effectiveTab === 'options'}
        <div class="page-head"><h1>Options</h1></div>
        <div class="block">
          <b class="blk-title">Features</b>
          {#each [
            { k: 'leaderboardEnabled', t: 'Redzone leaderboard', d: 'Players can open the RZ leaderboard.' },
            { k: 'globalLbEnabled', t: 'Global leaderboard', d: 'Track kills outside redzones.' },
            { k: 'gangLbEnabled', t: 'Gang leaderboard', d: 'Track and show gang rankings.' },
            { k: 'streaksEnabled', t: 'Streak rewards', d: 'Pay out streak thresholds.' },
            { k: 'personalColorEnabled', t: 'Personal zone colour', d: 'Players can set their own dome colour.' },
            { k: 'killFeedEnabled', t: 'Kill feed', d: 'Show the redzone kill feed.' },
            { k: 'killCamEnabled', t: 'Kill cam', d: 'Spectate killer on death.' },
            { k: 'rewardNotify', t: 'Reward notifications', d: 'Notify on every kill reward.' },
            { k: 'streakAnnounce', t: 'Streak announcements', d: 'Announce streak unlocks.' },
          ] as f}
            <div class="frow between"><div><b>{f.t}</b><p class="hint">{f.d}</p></div><button class="sw" class:on={opts[f.k]} onclick={() => opts[f.k] = !opts[f.k]} aria-label="Toggle"><i></i></button></div>
          {/each}
        </div>
        <div class="block">
          <b class="blk-title">Personal Colour Controls</b>
          <div class="frow between"><div><b>Hue / colour picker</b></div><button class="sw" class:on={opts.personalColorHue} onclick={() => opts.personalColorHue = !opts.personalColorHue} aria-label="Toggle"><i></i></button></div>
          <div class="frow between"><div><b>Opacity slider</b></div><button class="sw" class:on={opts.personalColorOpacity} onclick={() => opts.personalColorOpacity = !opts.personalColorOpacity} aria-label="Toggle"><i></i></button></div>
        </div>
        <div class="block">
          <b class="blk-title">Leaderboard Columns</b>
          <div class="frow between"><div><b>Kills</b></div><button class="sw" class:on={opts.lbCols?.kills} onclick={() => opts.lbCols = { ...opts.lbCols, kills: !opts.lbCols?.kills }} aria-label="Toggle"><i></i></button></div>
          <div class="frow between"><div><b>Deaths</b></div><button class="sw" class:on={opts.lbCols?.deaths} onclick={() => opts.lbCols = { ...opts.lbCols, deaths: !opts.lbCols?.deaths }} aria-label="Toggle"><i></i></button></div>
          <div class="frow between"><div><b>K/D</b></div><button class="sw" class:on={opts.lbCols?.kd} onclick={() => opts.lbCols = { ...opts.lbCols, kd: !opts.lbCols?.kd }} aria-label="Toggle"><i></i></button></div>
        </div>
        <div class="block">
          <b class="blk-title">HUD Defaults (server-wide)</b>
          <label class="f"><span>Default theme</span><select bind:value={opts.hudDefaultTheme}>{#each THEME_LIST as t}<option value={t.id}>{t.id}</option>{/each}</select></label>
          <label class="f"><span>Default position preset</span><select bind:value={opts.hudDefaultPreset}>{#each PRESET_LIST as pr}<option value={pr}>{pr}</option>{/each}</select></label>
          <p class="hint">Players who haven't customised use these defaults.</p>
        </div>
        <div class="block">
          <b class="blk-title">Rendering</b>
          <label class="f"><span>Zone render distance <em>{opts.renderDistance}m past edge</em></span><input class="track" type="range" min="50" max="500" step="10" bind:value={opts.renderDistance} /></label>
          <p class="hint">How far beyond a zone's radius the dome starts rendering for players.</p>
        </div>
        <button class="btn go end" onclick={() => post('saveOptions', opts)}>Save Options</button>

      {:else if effectiveTab === 'logs'}
        <div class="page-head"><h1>Logs</h1></div>
        <div class="seg">
          <button class:on={logCat === 'admin'} onclick={() => { logCat = 'admin'; post('requestLogs', { category: 'admin' }) }}>Admin</button>
          <button class:on={logCat === 'kills'} onclick={() => { logCat = 'kills'; post('requestLogs', { category: 'kills' }) }}>Kills</button>
          <button class:on={logCat === 'revives'} onclick={() => { logCat = 'revives'; post('requestLogs', { category: 'revives' }) }}>Revives</button>
          <button class="seg-refresh" onclick={() => post('requestLogs', { category: logCat })} title="Refresh">↻</button>
        </div>

        <div class="logs">
          {#if (logs ?? []).length === 0}<div class="empty">No log entries yet.</div>{/if}
          {#each logs ?? [] as e (e.time + (e.title ?? ''))}
            <div class="log-row">
              <div class="log-top"><b>{e.title}</b><span class="log-time">{fmtTime(e.time)}</span></div>
              {#if e.description}<div class="log-desc">{stripMd(e.description)}</div>{/if}
              {#if e.fields}<div class="log-fields">{#each e.fields as f}<span class="log-field">{f.name}: <b>{f.value}</b></span>{/each}</div>{/if}
            </div>
          {/each}
        </div>

        <div class="block">
          <b class="blk-title">Log Settings</b>
          {#if lc}
            <div class="frow between"><div><b>Logging enabled</b><p class="hint">Master switch for all logging.</p></div><button class="sw" class:on={lc.enabled} onclick={() => lc.enabled = !lc.enabled} aria-label="Toggle"><i></i></button></div>
            <div class="frow between"><div><b>Admin actions</b></div><button class="sw" class:on={lc.categories.admin} onclick={() => lc.categories = { ...lc.categories, admin: !lc.categories.admin }} aria-label="Toggle"><i></i></button></div>
            <div class="frow between"><div><b>Kills</b><p class="hint">High volume — off by default.</p></div><button class="sw" class:on={lc.categories.kills} onclick={() => lc.categories = { ...lc.categories, kills: !lc.categories.kills }} aria-label="Toggle"><i></i></button></div>
            <div class="frow between"><div><b>Revives</b></div><button class="sw" class:on={lc.categories.revives} onclick={() => lc.categories = { ...lc.categories, revives: !lc.categories.revives }} aria-label="Toggle"><i></i></button></div>

            <b class="blk-title" style="margin-top:6px">Discord Webhooks</b>
            <label class="f"><span>Admin</span><input bind:value={lc.webhooks.admin} placeholder="https://discord.com/api/webhooks/…" /></label>
            <label class="f"><span>Kills</span><input bind:value={lc.webhooks.kills} placeholder="webhook URL" /></label>
            <label class="f"><span>Revives</span><input bind:value={lc.webhooks.revives} placeholder="webhook URL" /></label>
            <label class="f"><span>Redzone leaderboard</span><input bind:value={lc.webhooks.leaderboardRz} placeholder="webhook URL" /></label>
            <label class="f"><span>Global leaderboard</span><input bind:value={lc.webhooks.leaderboardGlobal} placeholder="webhook URL" /></label>

            <b class="blk-title" style="margin-top:6px">Public Leaderboard Auto-Post</b>
            <div class="frow between"><div><b>Enabled</b><p class="hint">Posts a leaderboard snapshot on a timer.</p></div><button class="sw" class:on={lc.leaderboardPost.enabled} onclick={() => lc.leaderboardPost = { ...lc.leaderboardPost, enabled: !lc.leaderboardPost.enabled }} aria-label="Toggle"><i></i></button></div>
            <div class="frow">
              <label class="f"><span>Board</span><select bind:value={lc.leaderboardPost.board}><option value="redzone">Redzone</option><option value="global">Global</option></select></label>
              <label class="f w90"><span>Every (min)</span><input type="number" min="5" bind:value={lc.leaderboardPost.interval} /></label>
              <label class="f w90"><span>Top N</span><input type="number" min="3" max="25" bind:value={lc.leaderboardPost.top} /></label>
            </div>
            <div class="frow">
              <button class="btn" onclick={() => post('postLeaderboardNow', { board: 'redzone' })}>📤 Send Redzone now</button>
              <button class="btn" onclick={() => post('postLeaderboardNow', { board: 'global' })}>📤 Send Global now</button>
            </div>
            <button class="btn go end" onclick={() => post('saveLogConfig', lc)}>Save Log Settings</button>
            <p class="hint">Save your webhooks first, then use "Send now" to post an instant snapshot. Full admin required.</p>
          {:else}
            <button class="btn dash" onclick={() => post('requestLogConfig')}>Load log settings</button>
          {/if}
        </div>
      {/if}
    </div>
  </div>

  {#if editing}
  <div class="editor">
    <div class="e-head"><b>{editing.id ? 'Edit Redzone' : 'Create New Redzone'}</b><button class="ib" onclick={() => editing = null} aria-label="Close"><svg width="12" height="12" viewBox="0 0 24 24" fill="none"><path d="M18 6L6 18M6 6l12 12" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/></svg></button></div>
    <div class="e-body">
      <label class="f"><span>Redzone Name</span><input bind:value={editing.name} placeholder="e.g., Humane Labs" maxlength="40" /></label>
      <div class="f"><span>Coordinates</span><div class="frow"><input type="number" step="0.01" bind:value={editing.coords.x} /><input type="number" step="0.01" bind:value={editing.coords.y} /><input type="number" step="0.01" bind:value={editing.coords.z} /><button class="ib lime" onclick={() => grabPos('coords')} title="Use my position"><svg width="13" height="13" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="3" stroke="currentColor" stroke-width="2"/><path d="M12 2v4m0 12v4M2 12h4m12 0h4" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg></button></div></div>
      <label class="f"><span>Radius <em>{editing.radius}m</em></span><input class="track" type="range" min="10" max="300" bind:value={editing.radius} /></label>
      <div class="f"><span>Zone Colour (Global) <em>{editing.colorHex}</em></span><div class="frow"><input class="hexfield" bind:value={editing.colorHex} maxlength="7" spellcheck="false" /><input class="track grow" type="range" min="0" max="255" bind:value={editing.colorA} title="Opacity" /><span class="zdot big" style:background={editing.colorHex}></span></div></div>

      <div class="e-sec">Respawn Points <span class="dim">({editing.exits.length}/5)</span></div>
      {#each editing.exits as e, i}
        <div class="frow inset"><span class="dim grow">{(+e.x).toFixed(1)}, {(+e.y).toFixed(1)}, {(+e.z).toFixed(1)}</span><button class="ib red" onclick={() => editing.exits.splice(i, 1)}>✕</button></div>
      {/each}
      {#if editing.exits.length < 5}
        <div class="frow"><button class="btn dash" onclick={() => grabPos('exit')}>+ Add my position</button><button class="btn go" onclick={() => post('startPlacement', { draft: JSON.parse(JSON.stringify(editing)) })}><svg width="12" height="12" viewBox="0 0 24 24" fill="none"><path d="M12 21s-7-5.5-7-11a7 7 0 0 1 14 0c0 5.5-7 11-7 11z" stroke="currentColor" stroke-width="2"/></svg> Place in world (E)</button></div>
      {/if}
      <label class="f"><span>Fallback teleport distance <em>{editing.teleportAway}m</em></span><input class="track" type="range" min="5" max="200" bind:value={editing.teleportAway} /></label>

      <div class="e-sec">Kill Rewards</div>
      {#each editing.rewardItems as item, i}
        <div class="frow inset">
          <input class="grow" bind:value={item.name} placeholder="item ('money' = cash)" />
          {#if item.rand}
            <input class="w70" type="number" min="1" bind:value={item.min} placeholder="min" /><span class="dim">–</span><input class="w70" type="number" min="1" bind:value={item.max} placeholder="max" />
          {:else}
            <input class="w90" type="number" min="1" bind:value={item.amount} />
          {/if}
          <button class="ib" class:lime={item.rand} title="Random amount" onclick={() => { item.rand = !item.rand; if (item.rand) { item.min ??= 1; item.max ??= item.amount ?? 5 } }}><svg width="12" height="12" viewBox="0 0 24 24" fill="none"><rect x="3" y="3" width="18" height="18" rx="4" stroke="currentColor" stroke-width="2"/><circle cx="8.5" cy="8.5" r="1.4" fill="currentColor"/><circle cx="15.5" cy="15.5" r="1.4" fill="currentColor"/><circle cx="15.5" cy="8.5" r="1.4" fill="currentColor"/><circle cx="8.5" cy="15.5" r="1.4" fill="currentColor"/></svg></button>
          <button class="ib red" onclick={() => editing.rewardItems.splice(i, 1)}>✕</button>
        </div>
      {/each}
      <button class="btn dash" onclick={() => editing.rewardItems.push({ name: '', amount: 1 })}>+ Add Item</button>

      <div class="e-sec">Streak Rewards</div>
      {#each editing.streakRewards as sr, i}
        <div class="frow inset"><input class="w70" type="number" min="1" bind:value={sr.streak} title="Streak" /><input class="grow" bind:value={sr.name} placeholder="item" /><input class="w90" type="number" min="1" bind:value={sr.amount} /><button class="ib red" onclick={() => editing.streakRewards.splice(i, 1)}>✕</button></div>
      {/each}
      <button class="btn dash" onclick={() => editing.streakRewards.push({ streak: 3, name: '', amount: 1 })}>+ Add Streak Reward</button>

      <div class="e-sec">Revive</div>
      <div class="frow">
        <div class="f"><span>Paid revive</span><button class="sw" class:on={editing.reviveInside} onclick={() => editing.reviveInside = !editing.reviveInside} aria-label="Toggle"><i></i></button></div>
        <label class="f grow"><span>Cost ($)</span><input type="number" min="0" bind:value={editing.reviveCost} disabled={!editing.reviveInside} /></label>
        <label class="f grow"><span>Delay <em>{(editing.reviveDelay/1000).toFixed(1)}s</em></span><input class="track" type="range" min="1000" max="30000" step="500" bind:value={editing.reviveDelay} /></label>
      </div>
      <div class="frow"><div class="f"><span>Zone enabled</span><button class="sw" class:on={editing.enabled} onclick={() => editing.enabled = !editing.enabled} aria-label="Toggle"><i></i></button></div></div>
    </div>
    <div class="e-foot"><button class="btn" onclick={() => editing = null}>Cancel</button><button class="btn go" onclick={saveZone}>Save Redzone</button></div>
  </div>
  {/if}
</div>
{/if}

<style>
  .blocker { position: fixed; inset: 0; background: rgba(6,7,9,0.7); z-index: 199; pointer-events: auto; }
  .tablet { position: fixed; inset: 0; margin: auto; width: 850px; height: 620px; display: flex; flex-direction: column; background: #0b0c0e; border: 14px solid #060708; outline: 1.5px solid rgba(255,255,255,0.13); border-radius: 34px; overflow: hidden; z-index: 200; pointer-events: auto; font-family: var(--font); box-shadow: 0 40px 110px rgba(0,0,0,0.8), inset 0 0 0 1px rgba(255,255,255,0.03); }
  .tablet::before { content: ''; position: absolute; top: -9px; left: 50%; transform: translateX(-50%); width: 7px; height: 7px; border-radius: 50%; background: radial-gradient(circle at 35% 35%, #2a3340, #0a0d12 70%); box-shadow: 0 0 0 2px #060708, inset 0 0 2px rgba(120,160,255,0.4); z-index: 10; }
  .tablet::after { content: ''; position: absolute; bottom: 5px; left: 50%; transform: translateX(-50%); width: 110px; height: 4px; border-radius: 99px; background: rgba(255,255,255,0.25); z-index: 10; }

  .statusbar { display: flex; align-items: center; justify-content: space-between; padding: 8px 22px 7px; flex-shrink: 0; }
  .sb-left { display: flex; align-items: center; gap: 12px; }
  .sb-back { display: flex; align-items: center; gap: 4px; padding: 4px 11px 4px 8px; background: rgba(255,255,255,0.06); border: 1px solid rgba(255,255,255,0.1); border-radius: 99px; color: #fff; font-size: 11px; font-weight: 700; font-family: inherit; cursor: pointer; }
  .sb-back:hover { background: var(--accent); color: var(--accent-text); border-color: transparent; }
  .sb-clock { font-size: 12.5px; font-weight: 700; color: #fff; letter-spacing: 0.02em; font-variant-numeric: tabular-nums; }
  .sb-brand { display: flex; align-items: center; gap: 6px; font-size: 11px; font-weight: 800; letter-spacing: 0.02em; color: var(--accent); }
  .sb-admin { background: var(--accent); color: var(--accent-text); border-radius: 4px; padding: 1px 6px; font-size: 8.5px; letter-spacing: 0.1em; }
  .sb-right { display: flex; align-items: center; gap: 10px; color: var(--text-2); }
  .sb-close { width: 22px; height: 22px; border-radius: 50%; background: rgba(255,255,255,0.06); border: none; display: flex; align-items: center; justify-content: center; color: var(--text-2); cursor: pointer; }
  .sb-close:hover { background: var(--danger-soft); color: var(--danger); }
  .sb-help { width: 22px; height: 22px; border-radius: 50%; background: rgba(255,255,255,0.06); border: none; display: flex; align-items: center; justify-content: center; color: var(--text-2); cursor: pointer; }
  .sb-help:hover { background: var(--accent-soft); color: var(--accent); }

  .tbody { flex: 1; display: flex; min-height: 0; }
  .nav { width: 150px; flex-shrink: 0; padding: 14px 10px; display: flex; flex-direction: column; gap: 4px; border-right: 1px solid rgba(255,255,255,0.05); background: rgba(255,255,255,0.015); }
  .nav-item { display: flex; align-items: center; gap: 9px; padding: 10px 12px; border: none; border-radius: 11px; background: transparent; color: var(--text-3); font-size: 12px; font-weight: 700; font-family: inherit; cursor: pointer; transition: background 0.12s, color 0.12s; text-align: left; }
  .nav-item.on { background: var(--accent); color: var(--accent-text); }
  .nav-item:not(.on):hover { background: rgba(255,255,255,0.04); color: var(--text-2); }
  .nav-item.admin-entry { margin-top: auto; border: 1px dashed var(--accent-border); color: var(--accent); }
  .nav-item.admin-entry:hover { background: var(--accent-soft); color: var(--accent); }

  .content { flex: 1; overflow-y: auto; padding: 18px 22px 26px; display: flex; flex-direction: column; gap: 10px; scroll-behavior: smooth; }
  .content::-webkit-scrollbar, .e-body::-webkit-scrollbar { width: 8px; }
  .content::-webkit-scrollbar-track, .e-body::-webkit-scrollbar-track { background: transparent; margin: 8px 0; }
  .content::-webkit-scrollbar-thumb, .e-body::-webkit-scrollbar-thumb { background: rgba(255,255,255,0.14); border-radius: 99px; border: 2px solid transparent; background-clip: padding-box; }
  .content::-webkit-scrollbar-thumb:hover, .e-body::-webkit-scrollbar-thumb:hover { background: var(--accent); background-clip: padding-box; }

  .page-head { display: flex; align-items: center; justify-content: space-between; }
  h1 { font-size: 19px; font-weight: 900; color: #fff; letter-spacing: -0.02em; }
  .sub { font-size: 12px; color: var(--text-2); margin-top: -4px; }
  .hint { font-size: 11px; color: rgba(255,255,255,0.5); line-height: 1.5; }
  .frow.between > div > b, .block > .frow b { color: #fff; font-size: 13px; font-weight: 700; }
  .block > b:not(.blk-title) { color: #fff; }
  .dim { font-size: 11.5px; color: rgba(255,255,255,0.5); }
  .empty { padding: 24px; text-align: center; font-size: 12px; color: var(--text-3); }

  .stat-pills { display: flex; gap: 6px; }
  .pill { font-size: 11px; color: var(--text-2); background: rgba(255,255,255,0.04); border: 1px solid rgba(255,255,255,0.06); border-radius: 99px; padding: 5px 12px; }
  .pill b { color: var(--accent); font-weight: 900; }
  .seg { display: inline-flex; gap: 3px; align-self: flex-start; background: rgba(255,255,255,0.03); border: 1px solid rgba(255,255,255,0.06); border-radius: 99px; padding: 3px; }
  .seg button { padding: 6px 16px; border: none; border-radius: 99px; background: transparent; color: var(--text-3); font-size: 11.5px; font-weight: 800; font-family: inherit; cursor: pointer; }
  .seg button.on { background: var(--accent); color: var(--accent-text); }
  .reset-line { font-size: 11px; color: var(--text-2); }

  .lb { display: flex; flex-direction: column; gap: 3px; }
  .lb-head, .lb-row { display: grid; align-items: center; }
  .lb-head { padding: 6px 12px; font-size: 9.5px; font-weight: 900; color: var(--text-3); letter-spacing: 0.12em; }
  .lb-row { padding: 9px 12px; background: rgba(255,255,255,0.025); border-radius: 12px; border: 1px solid transparent; }
  .lb-row.first { border-color: var(--accent-border); background: var(--accent-soft); }
  .rank { width: 22px; height: 22px; border-radius: 7px; display: inline-flex; align-items: center; justify-content: center; background: rgba(255,255,255,0.06); font-size: 10.5px; font-weight: 900; color: var(--text-2); }
  .rank.r1 { background: #eab308; color: #0a0b0d; } .rank.r2 { background: #9ca3af; color: #0a0b0d; } .rank.r3 { background: #b45309; color: #0a0b0d; }
  .who { display: flex; align-items: center; gap: 9px; font-size: 13px; font-weight: 700; color: #fff; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .av { width: 26px; height: 26px; border-radius: 9px; background: rgba(255,255,255,0.07); display: inline-flex; align-items: center; justify-content: center; font-size: 10.5px; font-weight: 900; color: var(--text-2); flex-shrink: 0; }
  .c { text-align: center; font-size: 12.5px; color: var(--text-2); font-variant-numeric: tabular-nums; }
  .c.bold { font-weight: 900; color: #fff; }

  .cpick { display: flex; flex-direction: column; gap: 13px; max-width: 420px; }
  .cprev { height: 56px; border-radius: 14px; border: 1px solid rgba(255,255,255,0.12); }
  .cs { display: flex; flex-direction: column; gap: 6px; }
  .cs > span { font-size: 11px; font-weight: 700; color: var(--text-2); display: flex; justify-content: space-between; }
  .cs em { font-style: normal; color: var(--accent); }
  .track { -webkit-appearance: none; height: 12px; border-radius: 99px; background: rgba(255,255,255,0.08); outline: none; width: 100%; }
  .track.hue { background: linear-gradient(90deg,#f00,#ff0,#0f0,#0ff,#00f,#f0f,#f00); }
  .track::-webkit-slider-thumb { -webkit-appearance: none; width: 18px; height: 18px; border-radius: 50%; background: #fff; cursor: pointer; border: 3px solid #0a0b0d; box-shadow: 0 0 0 1px rgba(255,255,255,0.3); }
  .hexrow { display: flex; gap: 8px; align-items: center; }
  .hexfield { width: 100px; background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.1); border-radius: 10px; padding: 9px 12px; color: #fff; font-size: 13px; font-weight: 800; font-family: inherit; text-transform: uppercase; outline: none; }
  .hexfield:focus { border-color: var(--accent-border); }

  .btn { padding: 9px 18px; background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.08); border-radius: 11px; color: var(--text-2); font-size: 12px; font-weight: 800; font-family: inherit; cursor: pointer; display: inline-flex; align-items: center; gap: 7px; }
  .btn:hover { background: rgba(255,255,255,0.09); color: #fff; }
  .btn.go { background: var(--accent); border-color: transparent; color: var(--accent-text); }
  .btn.go:hover { background: var(--accent-strong); }
  .btn.red { background: var(--danger-soft); border-color: transparent; color: var(--danger); }
  .btn.ghost { background: transparent; border-color: transparent; }
  .btn.dash { background: transparent; border: 1px dashed rgba(255,255,255,0.15); align-self: flex-start; }
  .end { align-self: flex-end; }
  .hud-actions { display: flex; gap: 9px; }

  .ib { width: 27px; height: 27px; background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.07); border-radius: 9px; display: inline-flex; align-items: center; justify-content: center; cursor: pointer; color: var(--text-2); font-size: 11px; }
  .ib:hover { background: rgba(255,255,255,0.1); color: #fff; }
  .ib.red:hover { color: var(--danger); }
  .ib.lime { background: var(--accent-soft); border-color: var(--accent-border); color: var(--accent); }

  .block { background: rgba(255,255,255,0.025); border: 1px solid rgba(255,255,255,0.05); border-radius: 14px; padding: 14px 16px; display: flex; flex-direction: column; gap: 10px; }
  .block.row { flex-direction: row; align-items: center; gap: 10px; }
  .gl { font-size: 13px; color: #fff; }
  .grow { flex: 1; }
  .between { justify-content: space-between; align-items: center; }
  .blk-title { font-size: 11px; font-weight: 900; color: var(--accent); text-transform: uppercase; letter-spacing: 0.1em; }
  .mono { font-family: ui-monospace, 'Cascadia Mono', monospace; font-size: 10.5px; }

  .frow { display: flex; gap: 8px; align-items: flex-end; flex-wrap: wrap; }
  .frow.inset { background: rgba(255,255,255,0.03); border-radius: 10px; padding: 8px 10px; align-items: center; }
  .f { display: flex; flex-direction: column; gap: 5px; min-width: 0; }
  .f.grow { flex: 1; }
  .w70 { width: 70px; } .w90 { width: 90px; }
  .f > span { font-size: 10px; font-weight: 800; color: rgba(255,255,255,0.55); display: flex; justify-content: space-between; gap: 8px; text-transform: uppercase; letter-spacing: 0.05em; }
  .f em { font-style: normal; color: var(--accent); text-transform: none; }
  input:not(.track), select { background: #1d2026; border: 1px solid rgba(255,255,255,0.13); border-radius: 10px; padding: 8px 11px; color: #ffffff !important; font-size: 12.5px; font-weight: 600; font-family: inherit; width: 100%; min-width: 50px; outline: none; caret-color: var(--accent); }
  option { background: #1d2026; color: #ffffff; }
  input::placeholder { color: rgba(255,255,255,0.35); }
  select option { background: #1d2026; color: #ffffff; }
  input:focus, select:focus { border-color: var(--accent-border); }
  input:disabled { opacity: 0.4; }
  select { appearance: none; }

  .sw { width: 42px; height: 23px; background: rgba(255,255,255,0.08); border: 1px solid rgba(255,255,255,0.12); border-radius: 99px; cursor: pointer; position: relative; padding: 0; flex-shrink: 0; }
  .sw i { position: absolute; top: 2px; left: 2px; width: 17px; height: 17px; border-radius: 50%; background: var(--text-2); transition: left 0.15s, background 0.15s; }
  .sw.on { background: var(--accent); border-color: transparent; }
  .sw.on i { left: 21px; background: var(--accent-text); }
  .sw.sm { width: 34px; height: 19px; }
  .sw.sm i { width: 13px; height: 13px; }
  .sw.sm.on i { left: 17px; }

  .ztable { display: flex; flex-direction: column; gap: 3px; }
  .zt-head, .zt-row { display: grid; grid-template-columns: 1fr 80px 85px 110px; align-items: center; padding: 8px 12px; }
  .zt-head { font-size: 9.5px; font-weight: 900; color: var(--text-3); letter-spacing: 0.12em; }
  .zt-row { background: rgba(255,255,255,0.025); border-radius: 12px; }
  .zname { display: flex; align-items: center; gap: 9px; font-size: 13px; font-weight: 700; color: #fff; }
  .zdot { width: 9px; height: 9px; border-radius: 50%; flex-shrink: 0; }
  .zdot.big { width: 30px; height: 30px; border-radius: 9px; border: 1px solid rgba(255,255,255,0.15); }
  .r { text-align: right; }
  .acts { display: flex; gap: 5px; justify-content: flex-end; }

  .themes { display: flex; flex-wrap: wrap; gap: 7px; }
  .theme-chip { display: flex; align-items: center; gap: 7px; padding: 7px 13px; background: #1d2026; border: 1px solid rgba(255,255,255,0.1); border-radius: 10px; color: rgba(255,255,255,0.7); font-size: 12px; font-weight: 700; font-family: inherit; cursor: pointer; text-transform: capitalize; }
  .theme-chip.on { border-color: var(--accent); color: #fff; background: var(--accent-soft); }
  .theme-dot { width: 14px; height: 14px; border-radius: 50%; }
  .presets { display: grid; grid-template-columns: repeat(3, 1fr); gap: 7px; }
  .preset-chip { padding: 9px; text-transform: capitalize; background: #1d2026; border: 1px solid rgba(255,255,255,0.1); border-radius: 10px; color: rgba(255,255,255,0.7); font-size: 11.5px; font-weight: 700; font-family: inherit; cursor: pointer; }
  .preset-chip.on { border-color: var(--accent); color: var(--accent); background: var(--accent-soft); }

  .rank-card { background: #15171b; border: 1px solid rgba(255,255,255,0.07); border-radius: 11px; padding: 11px 13px; display: flex; flex-direction: column; gap: 9px; }
  .rank-name { font-weight: 800 !important; font-size: 13px !important; max-width: 220px; }
  .perm-grid { display: flex; flex-wrap: wrap; gap: 6px; }
  .perm-chip { padding: 5px 11px; background: #1d2026; border: 1px solid rgba(255,255,255,0.1); border-radius: 8px; color: rgba(255,255,255,0.5); font-size: 11px; font-weight: 700; font-family: inherit; cursor: pointer; }
  .perm-chip.on { background: var(--accent); border-color: transparent; color: var(--accent-text); }
  .rank-tag { font-size: 9.5px; font-weight: 800; color: var(--accent); background: var(--accent-soft); border-radius: 5px; padding: 2px 7px; text-transform: uppercase; letter-spacing: 0.05em; }

  .editor { position: absolute; inset: 34px 0 12px 0; background: #0b0c0e; display: flex; flex-direction: column; z-index: 5; }
  .e-head { display: flex; align-items: center; justify-content: space-between; padding: 14px 22px; border-bottom: 1px solid rgba(255,255,255,0.06); flex-shrink: 0; }
  .e-head b { font-size: 15px; font-weight: 900; color: #fff; }
  .e-body { flex: 1; overflow-y: auto; padding: 16px 22px; display: flex; flex-direction: column; gap: 11px; scroll-behavior: smooth; }
  .e-sec { font-size: 10.5px; font-weight: 900; color: var(--accent); text-transform: uppercase; letter-spacing: 0.12em; margin-top: 6px; }
  .e-foot { display: flex; justify-content: flex-end; gap: 8px; padding: 12px 22px; border-top: 1px solid rgba(255,255,255,0.06); flex-shrink: 0; }

  .hud-stage { position: relative; height: 64px; background: rgba(255,255,255,0.03); border: 1px solid rgba(255,255,255,0.06); border-radius: 10px; overflow: hidden; }
  .hud-mini { position: absolute; top: 14px; left: 50%; display: flex; align-items: stretch; height: 30px; background: linear-gradient(180deg, rgba(22,24,28,0.95), rgba(13,14,17,0.95)); border: 1px solid rgba(255,255,255,0.1); border-radius: 999px; overflow: hidden; transform-origin: center top; }
  .hm-blade { display: flex; align-items: center; padding: 0 16px 0 12px; background: var(--mini-accent, #A3E635); color: #0a0b0d; font-size: 9px; font-weight: 900; letter-spacing: 0.15em; clip-path: polygon(0 0, 100% 0, calc(100% - 10px) 100%, 0 100%); }
  .hm-stats { display: flex; align-items: center; padding: 0 16px; color: #fff; font-size: 13px; font-weight: 900; }

  .seg-refresh { padding: 6px 12px !important; font-size: 14px !important; }
  .logs { display: flex; flex-direction: column; gap: 5px; max-height: 280px; overflow-y: auto; }
  .log-row { background: rgba(255,255,255,0.025); border: 1px solid rgba(255,255,255,0.05); border-radius: 10px; padding: 9px 12px; display: flex; flex-direction: column; gap: 4px; }
  .log-top { display: flex; justify-content: space-between; align-items: baseline; gap: 10px; }
  .log-top b { font-size: 12.5px; color: #fff; font-weight: 800; }
  .log-time { font-size: 10px; color: var(--text-3); white-space: nowrap; font-variant-numeric: tabular-nums; }
  .log-desc { font-size: 12px; color: var(--text-2); }
  .log-fields { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 2px; }
  .log-field { font-size: 10.5px; color: var(--text-3); background: rgba(255,255,255,0.04); border-radius: 6px; padding: 2px 8px; }
  .log-field b { color: var(--accent); }

  .win-board { font-size: 9px; font-weight: 900; letter-spacing: 0.08em; padding: 2px 7px; border-radius: 5px; background: var(--accent-soft); color: var(--accent); }
  .win-board.global { background: rgba(34,211,238,0.14); color: #22D3EE; }
  .win-prize { font-size: 11px; font-weight: 800; color: var(--accent); white-space: nowrap; }

  /* Hub / Dashboard */
  .hub-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; margin-bottom: 6px; }
  .hub-card { background: rgba(255,255,255,0.03); border: 1px solid rgba(255,255,255,0.06); border-radius: 12px; padding: 12px 14px; display: flex; flex-direction: column; gap: 4px; }
  .hub-card.big { grid-column: span 3; background: linear-gradient(135deg, var(--accent-soft), rgba(255,255,255,0.02)); border-color: var(--accent-soft); }
  .hub-label { font-size: 10px; font-weight: 800; letter-spacing: 0.06em; text-transform: uppercase; color: var(--text-3); }
  .hub-num { font-size: 22px; font-weight: 900; color: #fff; }
  .hub-big { font-size: 38px; font-weight: 900; color: var(--accent); line-height: 1; }
  .hub-of { font-size: 18px; color: var(--text-3); font-weight: 700; margin-left: 4px; }
  .hub-sub { font-size: 11px; color: var(--text-2); }
  .hub-actions { display: flex; flex-wrap: wrap; gap: 8px; }
  .dim, .zstat { font-size: 10px; color: var(--text-3); }
  .zstat { font-weight: 800; padding: 2px 8px; border-radius: 5px; background: rgba(255,255,255,0.06); }
  .zstat.on { background: var(--accent-soft); color: var(--accent); }

  /* Leaderboard tools */
  .lb-tools { display: flex; gap: 8px; margin-bottom: 8px; align-items: stretch; }
  .lb-search { flex: 1 1 auto; min-width: 0; display: flex; align-items: center; gap: 7px; background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.08); border-radius: 9px; padding: 0 10px; color: var(--text-3); }
  .lb-search svg { flex-shrink: 0; }
  .lb-search input { flex: 1; background: none; border: none; outline: none; color: #fff; font-family: inherit; font-size: 12px; padding: 8px 0; }
  .lb-clear { background: none; border: none; color: var(--text-3); cursor: pointer; font-size: 12px; }
  .lb-sort { flex: 0 0 auto; width: auto !important; min-width: 130px; background: #1d2026; border: 1px solid rgba(255,255,255,0.13); border-radius: 9px; color: #fff; font-family: inherit; font-size: 11.5px; padding: 0 10px; cursor: pointer; appearance: none; }
  .lb-sort option { background: #1d2026; color: #fff; }
  .lb-row.me { background: var(--accent-soft); border-radius: 8px; box-shadow: inset 0 0 0 1px var(--accent); }
  .you-tag { font-size: 8.5px; font-weight: 900; letter-spacing: 0.06em; background: var(--accent); color: var(--accent-text); padding: 1px 5px; border-radius: 4px; margin-left: 7px; }
</style>
