-- ═══════════════════════════════════════════════════════════════
--  lime_redzones — minimal config
--
--  Almost everything is managed IN-GAME via the admin tablet (/rz_admin)
--  and saved to your database. This file only holds a few things that
--  must exist before the script boots (keybinds) or are just lookup data.
--
--  Fresh installs start with ZERO redzones — create them in-game.
-- ═══════════════════════════════════════════════════════════════

Config = {}

-- Keybind to open the leaderboard. Keybinds must be registered at startup,
-- so this one lives here. Players can rebind it in GTA Settings > Key Bindings.
Config.LeaderboardKeybindEnabled = true
Config.LeaderboardKey            = 'F1'

-- OPTIONAL bootstrap admin(s) so you can get into the panel on a brand-new install.
-- After that, manage admins/ranks entirely in-game. ACE perms and framework
-- god/admin groups also grant access, so you can usually leave this empty.
--   Entry formats:  'license:xxxx'   or   { id = 'license:xxxx', rank = 'Admin' }
Config.Admins = {
    -- 'license:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
}

-- Logging buffer/appearance (everything else about logging is in the panel & saved to DB).
Config.LogKeepInMemory = 200          -- recent log entries kept per category for the panel
Config.LogColor        = 10672181     -- Discord embed colour (decimal) — #A3E635

-- Weapon hash → readable label (used in kill feed / logs). Pure lookup data;
-- add entries here if you use custom weapons.
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
