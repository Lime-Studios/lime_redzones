Config = {}

-- ─────────────────────────────────────────────────────────────
--  GENERAL
-- ─────────────────────────────────────────────────────────────
Config.RenderDistance = 120.0            -- default dome render distance past a zone's edge (admins can override in-game)
Config.LeaderboardKey = 'F1'             -- keybind to open the leaderboard
Config.LeaderboardKeybindEnabled = true  -- set false to disable the keybind entirely
Config.SeedDefaultZone = true            -- seed a starter zone on first boot (see Config.DefaultZone)

-- Static admins (ACE perms and framework admin groups also work).
-- Entries can be a plain identifier string, or { id = 'license:..', rank = 'Admin' }.
Config.Admins = {
    -- 'license:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
    -- { id = 'license:xxxx', rank = 'Moderator' },
}

-- ─────────────────────────────────────────────────────────────
--  LOGGING  (Discord webhooks + in-game admin log)
-- ─────────────────────────────────────────────────────────────
Config.Logs = {
    enabled = true,            -- master switch for all logging
    keepInMemory = 200,        -- recent entries kept per category for the admin panel

    -- Paste Discord webhook URLs here. Empty = skip Discord for that category
    -- (it still shows in the in-game admin panel if enabled below).
    webhooks = {
        admin       = '',      -- zone edits, option changes, rank/admin changes, resets
        kills       = '',      -- kills inside redzones
        revives     = '',      -- paid revives
        leaderboard = '',      -- periodic public leaderboard snapshot
    },

    -- Per-category toggles (also configurable live from the admin panel).
    categories = {
        admin   = true,
        kills   = false,       -- high-volume; off by default
        revives = true,
    },

    -- Public leaderboard auto-post.
    leaderboardPost = {
        enabled  = false,
        interval = 30,         -- minutes between posts
        board    = 'redzone',  -- 'redzone' or 'global'
        top      = 10,
    },

    color = 10672181,          -- embed colour (decimal) #A3E635
}

-- ─────────────────────────────────────────────────────────────
--  WEAPON NAMES  (hash → readable label for kill feed/logs)
--  Add or correct entries here without touching server code.
-- ─────────────────────────────────────────────────────────────
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

-- ─────────────────────────────────────────────────────────────
--  DEFAULT ZONE  (first boot only, if Config.SeedDefaultZone = true)
-- ─────────────────────────────────────────────────────────────
Config.DefaultZone = {
    id = '1', name = 'Ambush Zone',
    coords = { x = 1204.55, y = -1288.42, z = 35.23 },
    radius = 60.0, colorHex = '#FF0000', colorA = 80,
    blipSprite = 310, blipColor = 1,
    rewardItems   = { { name = 'money', amount = 5000 } },
    streakRewards = { { streak = 3, name = 'armor', amount = 1 }, { streak = 5, name = 'money', amount = 2500 } },
    reviveCost = 10000, reviveInside = true, reviveDelay = 8000,
    teleportAway = 30.0, exits = {}, enabled = true,
}
