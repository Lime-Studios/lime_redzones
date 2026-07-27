# lime_redzones

In-game redzone (PvP) **and** safe zone (greenzone) creator. Both zone types
live in one resource, one database, one admin panel.

An in-game redzone creator for FiveM with a tablet-style admin panel, live leaderboards, kill feed, kill cam, streak rewards, and full per-feature toggles. No config editing required — everything is managed in-game and stored in MySQL.

## Features

- **In-game zone creator** — create, edit, enable/disable and delete redzones from a tablet UI. Place respawn points by running around and pressing E.
- **Multi-framework** — auto-detects QBX, QB-Core and ESX.
- **Gangs** — read membership from your framework, or let players start their own crews in-game (create, invite, ranks, kick, disband) that feed the gang leaderboard. Either mode, or off entirely.
- **Multi-inventory** — ox_inventory, one_inventory, qs-inventory, qb-inventory, ps-inventory, core_inventory, codem-inventory, origen_inventory, tgiann-inventory, plus framework-native fallback.
- **Multi-ambulance revive** — built-in adapters for wasabi_ambulance (v1 & v2), qbx_medical, qb-ambulancejob, ps-medic, esx_ambulancejob, ars_ambulancejob and p_ambulancejob, plus a native fallback when no death system is installed. Anything else plugs in through `Config.ReviveExport`. Run `rz_medical` in the server console to see what was detected and what to configure.
- **Teleport-then-revive** — a player killed in a zone is moved out to the exit **while still down**, and only then revived, so nobody comes back up in front of whoever just killed them.
- **Leaderboards** — separate Redzone and Global leaderboards, player and gang rankings, Kills/Deaths/K-D columns (each toggleable), weekly auto-resets with prizes for #1, and an admin score editor for correcting kills, deaths and Elo.
- **Kill feed & kill cam** — toggleable, repositionable.
- **HUD** — six themes plus any custom hex, six position presets, free drag. Player-customisable, with server-wide admin defaults for colour, position, scale and the kill feed / kill message — and an optional lock that forces them on everyone.
- **Rewards** — per-kill items, streak rewards, optional random amounts. Use the item name `money` for cash.
- **Heal on kill** — optionally restore health to the killer, either a set amount or a full heal. Per zone, and bulk-editable.
- **Permissions** — ACE (`lime_redzones.admin` / `lime_redzones.god` / `god`), framework admin groups, plus identifier-based admins with custom ranks that limit panel access.
- **Personal zone colours** — players can override the dome colour for themselves (toggleable, with optional hue and opacity controls).
- **Optimised** — single render thread, idle sleeps to 0.00ms when no players are near a zone.

## Requirements

- **oxmysql** (required — all data persists here)
- A framework: QBX, QB-Core or ESX (optional; runs standalone with reduced features)
- A notification resource (optional): lime_notify, ox_lib, qb, esx, etc. Falls back to native GTA notifications.

## Installation

1. Drop the `lime_redzones` folder into your `resources` directory.
2. Ensure **oxmysql** starts before this resource.
3. The SQL table auto-creates on first start. If you prefer to run it manually, import `lime_redzones.sql`.
4. Add to your `server.cfg`:
   ```
   ensure oxmysql
   ensure lime_redzones
   ```
5. Start the server. **Fresh installs have zero redzones** — open the admin tablet with `/rz_admin` and create your first zone in-game.

## Commands

| Command | Who | Description |
| --- | --- | --- |
| `/rz` | Everyone | Opens the player tablet (leaderboards, zone colour, HUD). |
| `/leaderboard` (F1) | Everyone | Opens the tablet on the leaderboard. |
| `/rz_admin` | Admins | Opens the admin tablet directly. |
| `/rz_color` | Everyone | Opens the personal zone colour picker. |
| `/rz_hud` | Everyone | Enter HUD drag mode. |
| `/rz_hud_reset` | Everyone | Reset HUD to its preset position. |

## Getting to the admin panel

Open the player tablet with **`/rz`**. If you have admin permission, an **"Admin Panel"** button appears at the bottom of the left navigation — click it to switch into the admin tablet. While in the admin tablet, a **"‹ Back"** button in the top status bar returns you to the player view. You can also jump straight in with **`/rz_admin`**.

## Permissions

A player is an admin if any of these are true:

1. They have ACE permission `lime_redzones.admin`, `lime_redzones.god`, `god`, or `command`.
2. Their framework rank is an admin group (QBX/QB `admin`/`god`, ESX `admin`/`superadmin`).
3. Their license or citizenid is listed as an admin — either in `Config.Admins` or added in-game via the **Permissions** tab.

### Ranks

In the admin tablet's **Permissions** tab you can define ranks (e.g. Moderator, Admin) and set which panel sections each can access (Zones, Gangs, Leaderboards, Feed & Cam, Options). Assign a rank when adding an admin identifier to limit what they can do. Ace `god` perms always have full access regardless of rank.

### Config admins

```lua
Config.Admins = {
    { id = 'license:abc123…', rank = 'Admin' },
    'license:def456…',  -- no rank = full access
}
```

## Kill cam & kill feed

Both are toggled in the admin tablet under **Feed & Cam**.

- **Kill feed** — shows a feed of redzone kills to all players. Each player repositions it from their own tablet under **HUD → Kill Feed Position** (Move / Reset).
- **Kill cam** — when a player dies inside a zone, they spectate their killer for 5 seconds with cinematic letterbox bars. Enable/disable it under Feed & Cam.

## HUD customisation

In the player tablet's **HUD** tab:

- **Theme** — pick from lime, crimson, cyan, amber, violet, mono, or any hex via the hue slider / colour picker.
- **Position preset** — top, top-left, top-right, bottom, left, right.
- **Custom position** — drag the HUD anywhere; reset returns it to the preset.
- **Size** — HUD, kill feed and "Eliminated" message each scale independently.

### Admin defaults

The admin tablet's **Options → HUD Defaults (server-wide)** block sets what every player sees before they customise anything:

- Accent colour (preset chip, hue slider, hex field or colour picker) and position preset, scale and free position for the redzone HUD.
- Position for the safe zone badge.
- Theme, scale and position for the kill feed and the "Eliminated" message.

Each **Place default …** button closes the tablet and drops you into the same drag mode players use — position the element, click **Done**, and that becomes the server default. **Reset HUD defaults** puts everything back to factory values.

Changes save the moment you make them and push to connected players live; there is no separate Save step.

**Lock HUD styling** forces the defaults on everyone and replaces the player HUD tab with a notice. Personal settings are kept, just not applied, so lifting the lock restores them.

## Heal on kill

Each redzone has a **Kill Heal** section in the zone editor:

- **Full heal on kill** — every kill puts the killer back to full health.
- **Health restored per kill** — a set amount instead (0-200 on GTA's health scale, where 200 is a full bar). `0` turns it off.

Either way the heal is clamped to the player's maximum, so it never overheals, and it is skipped if the killer is down. Both fields are available in the bulk zone editor, so you can apply one setting across every redzone at once.

## Gangs

The admin tablet's **Gangs** tab picks where gang membership comes from:

| Mode | Behaviour |
| --- | --- |
| **Framework** (default) | Membership is read from QBX / QB-Core / ESX. Nothing for players to do. |
| **Player-made** | Players get a **Gang** tab in their own tablet. Framework gangs are ignored. |
| **Off** | Nothing is credited to gangs and the gang leaderboard stays empty. |

### Player-made gangs

A player with no gang can start one (name, 2-4 character tag, colour) or accept a pending invite. Owners and officers can invite from a list of gang-free online players or by server ID; invites expire on a configurable timer.

Three ranks: **Owner** (everything, including renaming, handing over ownership and disbanding), **Officer** (invite and remove members), **Member**. Every redzone kill a member gets counts towards the gang on the gang leaderboard.

Configurable in the Gangs tab: max members, invite expiry, and an optional cost to start a gang (cash or bank). Admins can disband any gang from the same tab.

## Leaderboard resets

A weekly reset zeroes kills and deaths and pays the #1 player. **Elo ratings and stored podium appearances survive it** — a reset is a fresh scoreboard, not a rank wipe. Records that hold neither a rating nor an appearance are dropped so the table does not grow forever.

If you do want a full seasonal wipe, turn on **Also clear Elo** for that board in the Leaderboards tab, or use **Reset all Elo** in the Ranked tab for a one-off.

## Leaderboard score editor

The admin tablet's **Leaderboards** tab has a **Score Editor** below the reset schedules. Switch between the Redzone and Global boards, search by name or identifier, then edit a player's kills, deaths or Elo in place and click ✓ to save. ↺ discards an unsaved edit; ✕ removes the player from that board entirely (twice to confirm). Leaving Elo blank clears the rating, so that player starts again from the configured starting rating.

Every edit is written to the database, pushed to all clients immediately, and recorded in the admin log with the before/after values.

## Podiums

Place a podium with `/rz_addpodium [redzone|global] [label]` (or from the admin tablet's Ranked tab) and the top three of that board are shown as statues of the actual players, with their name, tier and Elo above them.

Standings are re-checked a couple of seconds after any leaderboard change and the statues update themselves — no reconnect, no resource restart. Players standing on a podium also watch their own appearance, so changing clothes updates the statue within a few seconds.

## Revive integration (config.lua)

Almost everything is managed in the admin tablet. `config.lua` only holds what cannot live there — keybind defaults registered at resource start, bootstrap admins, the weapon-name lookup, and the revive hooks below (kept in a file so they can be fixed while the panel is unreachable *because* revives are broken).

Run **`rz_medical`** in the server console at any time to see what was detected, which revive path is in use, and what (if anything) to configure.

| Setting | Purpose |
| --- | --- |
| `Config.Ambulance` | `'auto'` picks the first running resource with a verified adapter. Set a specific key to pin one, or `'none'` to disable the integration entirely. |
| `Config.MedicalResources` | Resource names that mean "a death/downed system is running here". Used **only** to decide whether it is safe to force a native resurrect — a native resurrect while a death system is active starts a revive → re-down fight. **If your death system isn't listed, add its resource name here.** |
| `Config.ReviveExport` | `{ resource = 'my_bridge', export = 'Revive' }` — called as `exports[resource][export](serverId)`. The surest option. `resource = ''` disables it. |
| `Config.ReviveCommand` | A server console command that revives by server id: run as `<command> <serverId>`. `''` disables. |
| `Config.ReviveServerEvent` | A **server** event your framework listens to, fired with the player's server id. |
| `Config.ReviveClientEvent` | A **client** event fired on the dying player's own machine. |

The hooks override auto-detection and are checked in the order listed.

## Storage

All data (zones, leaderboards, settings, ranks, admins, pending prizes) lives in a single MySQL row in the `lime_redzones` table, written through oxmysql with a 2-second debounce. There is no `data.json` file. Personal preferences (HUD position, theme, personal zone colour, kill feed position) are stored client-side via FiveM KVP.

## Notes

- Server-side validation guards every reward, revive and leaderboard event against spoofing; revive exit coordinates are validated against the zone and clamped if out of range.
- Requires OneSync (standard on modern servers) for position validation.
