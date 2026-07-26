-- Almost everything is managed in-game via the admin tablet and saved to your
-- database. This file only holds startup-time values and lookup data.
-- Fresh installs start with zero redzones — create them in-game.

Config = {}

-- Language file to use from locales/. Ships with 'en'; copy en.lua, translate
-- it, and set this to the new file's name.
Config.Locale = 'en'

-- Keybinds must be registered at startup. Players can rebind in GTA Settings >
-- Key Bindings. These are the DEFAULT keys; the admin panel (Options > Keybinds)
-- can change these defaults and toggle each bind — changes apply on the next
-- resource restart, and any player who has personally rebound keeps their choice.
Config.LeaderboardKeybindEnabled = false
Config.LeaderboardKey            = 'F1'
Config.AdminKeybindEnabled       = false
Config.AdminKey                  = 'F6'
Config.HudMoveKeybindEnabled     = false
Config.HudMoveKey                = 'F7'

-- Optional bootstrap admin(s) for a brand-new install (ACE/framework admins work too).
-- Formats: 'license:xxxx'  or  { id = 'license:xxxx', rank = 'Admin' }
Config.Admins = {
    -- 'license:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
}

-- Logging buffer/appearance (everything else about logging is in the panel & saved to DB).
Config.LogKeepInMemory = 200          -- recent log entries kept per category for the panel
Config.LogColor        = 10672181     -- Discord embed colour (decimal) — #A3E635

-- Ped models used (in placement order) for the up-to-4 physical "teleport to
-- redzone" NPCs placed per zone with /rz_addteleportnpc. Interact with one
-- (ox_target/qb-target/qtarget, or press E natively) to be teleported to that
-- zone through the same paid/validated flow as the tablet's Teleport button.
Config.TeleportNpcModels = {
    'a_m_y_business_01', 'a_m_y_soucent_01', 'a_f_y_business_02', 'a_m_m_business_01',
}

-- Tablet prop shown in-hand while the panel is open. Uses the base-game
-- 'prop_cs_tablet' — a stock model present on every client, so nothing custom
-- is streamed. If you want a custom model, stream it in your own resource and
-- set Config.TabletProp to its ytyp archetype name.
Config.TabletProp         = 'prop_cs_tablet'   -- default GTA tablet (always loaded)
Config.TabletPropFallback = 'prop_cs_tablet'

-- Hold pose played while the panel is open. A stock GTA dictionary — nothing
-- custom is streamed. It's an upper-body idle, so you can still walk around
-- with the tablet out, and it's re-applied automatically if anything cancels
-- it. If this dictionary can't stream, two other stock poses are tried before
-- giving up. Set Config.TabletProp/these to '' only if you want no pose at all;
-- the pose can also be toggled per-server in the admin panel (Options).
Config.TabletAnimDict = 'amb@code_human_in_bus_passenger_idles@female@tablet@base'
Config.TabletAnimName = 'base'

-- ── Revive integration ───────────────────────────────────────────────────
-- Run `rz_medical` in the server console at any time to see exactly what was
-- detected, which revive path is in use, and what (if anything) to configure.
--
-- Which ambulance/death system to drive. 'auto' picks the first running
-- resource this script has a verified adapter for (see the list printed by
-- rz_medical). Set it to a specific key to pin one, or 'none' to disable the
-- integration entirely and let your own death system handle everything.
Config.Ambulance = 'auto'

-- Resources that mean "a death/downed system is running here". This list is
-- used ONLY to decide whether it is safe for this script to force a native
-- resurrect. A native resurrect while a death system is active starts a
-- revive → re-down fight, so when any of these is running the script stays
-- hands-off and routes revives through the adapter or the hooks below.
--
-- If your death system isn't listed, ADD ITS RESOURCE NAME HERE. That alone
-- stops the conflict; pair it with one of the hooks below to get zone revives
-- working through it.
Config.MedicalResources = {
    'wasabi_ambulance', 'wasabi_ambulance_v2', 'wasabi_medical',
    'qbx_medical', 'qbx_ambulancejob', 'qb-ambulancejob', 'ps-medic',
    'esx_ambulancejob', 'esx-ambulancejob', 'esx_basicneeds',
    'ars_ambulancejob', 'brutal_ambulancejob', 'p_ambulancejob',
    'qs-ambulancejob', 'codem-ambulancejob', 'rcore_medic', 'nc_ambulance',
    'origen_hospital', 'k5_hospital', 'redutzu_ambulance', 'lb-medical',
    'msk_ambulancejob', 'okokAmbulanceJob', 'tgiann-hospital',
}

-- ── Revive hooks (all optional, checked in this order) ───────────────────
-- These override auto-detection. Use one if your system isn't auto-detected,
-- or if you'd rather revives went through code you already trust.
--
-- ReviveExport: the surest option. A resource + export that revives a player
-- by server id — e.g. your own bridge that does `exports("Revive", revive)`.
-- Called as: exports[resource][export](serverId).
Config.ReviveExport = { resource = '', export = 'Revive' }   -- resource '' = disabled

-- ReviveCommand: a server console command that revives a player by server id.
Config.ReviveCommand     = ''   -- runs as: <command> <serverId>  ('' = disabled)
-- ReviveServerEvent: a SERVER event your framework listens to, fired with the
-- player's server id as the first argument.
Config.ReviveServerEvent = ''      -- e.g. 'myambulance:server:revive'
-- ReviveClientEvent: a CLIENT event fired on the dying player's own client.
Config.ReviveClientEvent = ''      -- e.g. 'myambulance:client:revive'

-- ── Revive timing ────────────────────────────────────────────────────────
-- How long to wait for a revive to actually land before giving up. The longer
-- value applies when a death system is running (some have a hold/countdown
-- before they let you up); the shorter one when this script's own native
-- resurrect is the only thing involved.
Config.ReviveWaitMedical = 12000   -- ms, with a death system present
Config.ReviveWaitNative  = 4000    -- ms, native resurrect only

-- Last-resort native resurrect when NO death system is detected at all. Leave
-- true so players are never stuck dead on a server with no ambulance job.
-- Setting it true does NOT override the hands-off rule above — a detected
-- death system always wins.
Config.NativeReviveFallback = true

-- Weapon hash -> readable label, used in kill feed / logs.
Config.WeaponNames = {
    [453432689]  = 'Pistol',          [1593441988]  = 'Combat Pistol',
    [-1716589765]= 'Pistol .50',      [-1076751822] = 'SNS Pistol',
    [-771403250] = 'Heavy Pistol',    [137902532]   = 'Vintage Pistol',
    [-1063057011]= 'AP Pistol',       [-1045183535] = 'Assault Rifle',
    [-2084633992]= 'Carbine Rifle',   [-1357824103] = 'Advanced Rifle',
    [2132975508] = 'Bullpup Rifle',   [-494615257]  = 'Micro SMG',
    [324215364]  = 'SMG',             [736523883]   = 'Assault SMG',
    [-619010992] = 'Combat PDW',      [487013001]   = 'Pump Shotgun',
    [2017895192] = 'Sawed-Off',       [-1654528753] = 'Bullpup Shotgun',
    [100416529]  = 'Sniper Rifle',    [205991906]   = 'Heavy Sniper',
    [-1466123335]= 'Knife',           [-122831616]  = 'Pistol Mk2',
    [3220176749] = 'Heavy Revolver',  [-879347409]  = 'Revolver',
    [-853065399] = 'Combat MG',       [-1660422300] = 'MG',
    [911657153]  = 'Stun Gun',        [615608432]   = 'Melee',
    [-1786099057]= 'Nightstick',      [1737195953]  = 'Unarmed',
    [-1569615261]= 'Unarmed',
}
