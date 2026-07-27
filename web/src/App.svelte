<script>
  import { resolveTheme, setCustomTheme, accentVars } from './theme.js'
  import RedzoneHUD from './RedzoneHUD.svelte'
  import TabletApp from './TabletApp.svelte'
  import KillFeed from './KillFeed.svelte'
  import KillCam from './KillCam.svelte'
  import SafeZoneHUD from './SafeZoneHUD.svelte'
  import PlacementBar from './PlacementBar.svelte'
  import KillMessage from './KillMessage.svelte'

  let hud = $state({ display: false, zoneName: 'Redzone', kills: 0, deaths: 0, streak: 0, nextReward: null, moveMode: false, pos: null, theme: 'lime', preset: 'top', scale: 1 })
  let tablet = $state({
    display: false, mode: 'player', tab: 'rzleaderboard',
    zones: {}, gangs: {}, settings: {}, personalColor: null,
    lbData: { players: [], gangs: [], globalPlayers: [], totals: {} },
    placementDraft: null, myIds: null, perms: null, options: {}, elo: { rating: null, rank: null, color: null }, eloRanks: [], eloEnabled: true, podiums: [], logs: [], logCategory: 'admin', logTotal: 0, logConfig: null, prizeHistory: [], firstTime: false, stats: {}, hudTheme: 'lime', hudPreset: 'top', hudScale: 1, tabletScale: 1, killfeedScale: 1, killfeedTheme: 'inherit', killmsgScale: 1, killmsgTheme: 'inherit', customTheme: null, hudLocked: false, lbEditor: { redzone: [], global: [] }, playerGangs: [], gang: null,
  })
  let killcam = $state({ display: false, killer: '', id: 0, theme: 'lime' })
  let elo = $state({ rating: null, rank: null, color: null })
  let szPos = $state(null)
  let szMove = $state(false)
  let safezone = $state({ display: false, name: '', speedLimit: 0, invincible: true, weapons: 'holster', phase: true })
  let placementBar = $state({ display: false, mode: 'poly', count: 0, max: 24, minZ: 0, maxZ: 0, speed: 1 })
  let kmRef
  let kfPos = $state(null)
  let kfMove = $state(false)
  let kfScale = $state(1)
  let kfTheme = $state('lime')
  let kmScale = $state(1)
  let kmTheme = $state('lime')
  let kmPos = $state(null)
  let kmMove = $state(false)
  let kfRef
  let options = $state({})

  const DEFAULT_ROOT = {
    '--accent': '#a3e635', '--accent-strong': '#bef264',
    '--accent-soft': 'rgba(163,230,53,0.12)', '--accent-border': 'rgba(163,230,53,0.25)',
    '--accent-text': '#0f0f11',
  }
  function customIsActive() {
    const c = tablet.customTheme
    return !!(c && c.accent && c.accent.toLowerCase() !== '#a3e635')
  }
  function applyRootTheme() {
    const root = document.documentElement
    const vars = customIsActive()
      ? accentVars(tablet.customTheme.accent, tablet.customTheme.text)
      : DEFAULT_ROOT
    for (const k in vars) root.style.setProperty(k, vars[k])
  }

  function handleMessage(event) {
    const d = event.data
    if (!d?.type) return

    if (d.type === 'updateRedzoneUI') {
      hud.display  = !!d.display
      hud.zoneName = d.zoneName ?? hud.zoneName
      hud.kills    = d.kills    ?? hud.kills
      hud.deaths   = d.deaths   ?? hud.deaths
      hud.streak   = d.streak   ?? hud.streak
      hud.nextReward = d.nextReward ?? null
    }
    if (d.type === 'hudPos')  hud.pos = d.pos ?? null
    if (d.type === 'hudMove') hud.moveMode = !!d.enabled
    if (d.type === 'hudStyle') {
      if (d.theme)  { hud.theme = d.theme; killcam.theme = d.theme }
      if (d.preset) hud.preset = d.preset
      if (d.scale)  hud.scale = +d.scale
    }
    if (d.type === 'kfStyle') {
      if (d.scale) kfScale = +d.scale
      if (d.theme) kfTheme = resolveTheme(d.theme, hud.theme)
    }
    if (d.type === 'kmStyle') {
      if (d.scale) kmScale = +d.scale
      if (d.theme) kmTheme = resolveTheme(d.theme, hud.theme)
    }
    if (d.type === 'kmMove') kmMove = !!d.enabled
    if (d.type === 'kmReset') kmPos = null
    if (d.type === 'kfPos') kfPos = d.pos ?? null
    if (d.type === 'kmPos') kmPos = d.pos ?? null
    if (d.type === 'killFeed') kfRef?.push(d.entry ?? {})
    if (d.type === 'killMessage') kmRef?.show(d.victim, d.weapon, d.streak)
    if (d.type === 'killCam') { killcam.display = !!d.display; killcam.killer = d.killer ?? ''; killcam.id = d.id ?? 0 }
    if (d.type === 'kfMove') kfMove = !!d.enabled
    if (d.type === 'kfReset') kfPos = null
    if (d.type === 'syncOptions') options = d.options ?? options

    if (d.type === 'tablet') {
      if (d.display !== undefined) tablet.display = !!d.display
      if (d.mode) tablet.mode = d.mode
      if (d.tab)  tablet.tab  = d.tab
      if (d.zones)    tablet.zones    = d.zones
      if (d.gangs)    tablet.gangs    = d.gangs
      if (d.settings) tablet.settings = d.settings
      if (d.perms !== undefined) tablet.perms = d.perms
      if (d.playerGangs !== undefined) tablet.playerGangs = d.playerGangs ?? []
      if (d.options)  { tablet.options = d.options; options = d.options }
      if (d.personalColor !== undefined) tablet.personalColor = d.personalColor
      if (d.customTheme) {
        tablet.customTheme = d.customTheme
        setCustomTheme(d.customTheme.accent, d.customTheme.text)
        applyRootTheme()
      }
      if (d.hudTheme)  { hud.theme = d.hudTheme; killcam.theme = d.hudTheme; tablet.hudTheme = d.hudTheme; applyRootTheme() }
      if (d.hudPreset) { hud.preset = d.hudPreset; tablet.hudPreset = d.hudPreset }
      if (d.hudScale)  { hud.scale = +d.hudScale; tablet.hudScale = +d.hudScale }
      if (d.hudLocked !== undefined) tablet.hudLocked = !!d.hudLocked
      if (d.hudPos !== undefined) hud.pos = d.hudPos ?? null
      if (d.szPos !== undefined) szPos = d.szPos ?? null
      if (d.tabletScale) tablet.tabletScale = +d.tabletScale
      if (d.killfeedPos) kfPos = d.killfeedPos
      if (d.killfeedScale) { kfScale = +d.killfeedScale; tablet.killfeedScale = +d.killfeedScale }
      if (d.killfeedTheme) { tablet.killfeedTheme = d.killfeedTheme; kfTheme = resolveTheme(d.killfeedTheme, d.hudTheme || hud.theme) }
      if (d.killmsgPos) kmPos = d.killmsgPos
      if (d.killmsgScale) { kmScale = +d.killmsgScale; tablet.killmsgScale = +d.killmsgScale }
      if (d.killmsgTheme) { tablet.killmsgTheme = d.killmsgTheme; kmTheme = resolveTheme(d.killmsgTheme, d.hudTheme || hud.theme) }
      tablet.firstTime = (d.firstTime === true)
    }
    if (d.type === 'adminData') {
      if (d.zones)    tablet.zones    = d.zones
      if (d.gangs)    tablet.gangs    = d.gangs
      if (d.settings) tablet.settings = d.settings
      if (d.perms !== undefined) tablet.perms = d.perms
      if (d.playerGangs !== undefined) tablet.playerGangs = d.playerGangs ?? []
    }
    if (d.type === 'placementDone') {
      tablet.placementDraft = d.draft
      setTimeout(() => { tablet.placementDraft = null }, 500)
    }
    if (d.type === 'myIdentifier') tablet.myIds = { license: d.license, identifier: d.identifier }
    if (d.type === 'lbEditor') tablet.lbEditor = { redzone: d.redzone ?? [], global: d.global ?? [] }
    if (d.type === 'gangState') tablet.gang = d.state ?? null
    if (d.type === 'logs') { tablet.logCategory = d.category ?? 'admin'; tablet.logs = d.entries ?? []; tablet.logTotal = Number(d.total) || 0 }
    if (d.type === 'logConfig') tablet.logConfig = d.config ?? null
    if (d.type === 'prizeHistory') tablet.prizeHistory = d.history ?? []
    if (d.type === 'stats') tablet.stats = d.stats ?? {}
    if (d.type === 'eloRanks') { tablet.eloRanks = d.ranks ?? []; tablet.eloEnabled = d.enabled !== false }
    if (d.type === 'szMove') szMove = !!d.enabled
    if (d.type === 'szPos') szPos = d.pos ?? null
    if (d.type === 'podiumAdmin') tablet.podiums = d.podiums ?? []
    if (d.type === 'elo') {
      elo = { rating: Number(d.rating) || 0, rank: d.rank ?? null, color: d.color ?? null }
      tablet.elo = elo
    }
    if (d.type === 'safezone') {
      safezone.display = !!d.display
      if (d.name !== undefined) safezone.name = d.name
      safezone.speedLimit = Number(d.speedLimit) || 0
      if (d.invincible !== undefined) safezone.invincible = !!d.invincible
      if (d.weapons !== undefined) safezone.weapons = d.weapons
      if (d.phase !== undefined) safezone.phase = !!d.phase
    }
    if (d.type === 'placementBar') { placementBar = { display: !!d.display, mode: d.mode ?? 'poly', count: Number(d.count) || 0, max: Number(d.max) || 24, minZ: Number(d.minZ) || 0, maxZ: Number(d.maxZ) || 0, speed: Number(d.speed) || 1 } }
    if (d.type === 'lbData') {
      tablet.lbData = {
        players:       d.players       ?? [],
        gangs:         d.gangs         ?? [],
        globalPlayers: d.globalPlayers ?? [],
        totals:        d.totals        ?? {},
      }
    }
  }

  const closeTablet = () => {
    tablet.display = false
    fetch('https://lime_redzones/closeTablet', { method: 'POST', body: '{}' })
  }

  window.addEventListener('message', handleMessage)

  window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && tablet.display) {
      tablet.display = false
      fetch('https://lime_redzones/forceClose', { method: 'POST', body: '{}' })
    }
  })
</script>

<RedzoneHUD {...hud} />
<SafeZoneHUD display={safezone.display} name={safezone.name} speedLimit={safezone.speedLimit}
             invincible={safezone.invincible} weapons={safezone.weapons} phase={safezone.phase}
             scale={hud.scale} pos={szPos} moveMode={szMove} />
<PlacementBar {...placementBar} />
{#if options.killFeedEnabled !== false}
  <KillFeed bind:this={kfRef} pos={kfPos} moveMode={kfMove} scale={kfScale} theme={kfTheme} />
{/if}
{#if options.killCamEnabled !== false}
  <KillCam {...killcam} />
{/if}
<KillMessage bind:this={kmRef} theme={kmTheme} scale={kmScale} pos={kmPos} moveMode={kmMove} />
<TabletApp {...tablet} onclose={closeTablet} />
