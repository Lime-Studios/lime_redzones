# lime_redzones

In-game redzone (PvP) **and** safe zone (greenzone) creator. Both zone types
live in one resource, one database, one admin panel.

An in-game redzone creator for FiveM with a tablet-style admin panel, live leaderboards, kill feed, kill cam, streak rewards, and full per-feature toggles. No config editing required — everything is managed in-game and stored in MySQL.

## Features

- **In-game zone creator** — create, edit, enable/disable and delete redzones from a tablet UI. Place respawn points by running around and pressing E.
- **Multi-framework** — auto-detects QBX, QB-Core and ESX.
- **Multi-inventory** — ox_inventory, one_inventory, qs-inventory, qb-inventory, ps-inventory, core_inventory, codem-inventory, origen_inventory, tgiann-inventory, plus framework-native fallback.
- **Multi-ambulance revive** — wasabi, core, esx-ambulancejob, qb-ambulancejob, qbx_medical, ars, ps-medic, fd, codem, lc_doj, t-ems, plus native fallback.
- **Leaderboards** — separate Redzone and Global leaderboards, player and gang rankings, Kills/Deaths/K-D columns (each toggleable), weekly auto-resets with prizes for #1.
- **Kill feed & kill cam** — toggleable, repositionable.
- **HUD** — six themes, six position presets, free drag, all player-customisable with admin-set defaults.
- **Rewards** — per-kill items, streak rewards, optional random amounts. Use the item name `money` for cash.
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

- **Theme** — pick from lime, crimson, cyan, amber, violet, mono.
- **Default Position Preset** — top, top-left, top-right, bottom, left, right.
- **Custom Position** — drag the HUD anywhere; reset returns it to the preset.

Admins set the server-wide default theme and preset in the **Options** tab. Players who haven't customised use those defaults.

## Storage

All data (zones, leaderboards, settings, ranks, admins, pending prizes) lives in a single MySQL row in the `lime_redzones` table, written through oxmysql with a 2-second debounce. There is no `data.json` file. Personal preferences (HUD position, theme, personal zone colour, kill feed position) are stored client-side via FiveM KVP.

## Notes

- Server-side validation guards every reward, revive and leaderboard event against spoofing; revive exit coordinates are validated against the zone and clamped if out of range.
- Requires OneSync (standard on modern servers) for position validation.
