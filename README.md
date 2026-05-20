# CDECAD-Sync for vRP

A FiveM resource that syncs vRP character and vehicle data to your CDECAD system, plus a full 911 / NPC-report integration.

## Features

- **Automatic Character Sync**: Characters are synced to CDECAD on `vRP:playerSpawn`
- **Discord Account Linking**: Links FiveM characters to CAD accounts via Discord ID
- **Discord Role Integration**: Filter syncing based on Discord roles (LEO / EMS exclusion)
- **vRP Group Filtering**: Skip syncing for users in configured vRP groups (police, ems, …)
- **Vehicle Sync**: Bulk-pull from `vrp_user_vehicles` and push to CAD
- **911 Call System**: `/911`, `/call911`, `/911anon` with coords + postal
- **NPC Witness Reports**: Automated reports for shots fired, fights, speed cameras
- **Admin Commands**: Manual sync, bulk DB sync, lookups, cache clear

## Requirements

- [vRP](https://github.com/vRP-framework/vRP) (the actively-maintained fork at https://vrp-framework.github.io/vRP/)
- [ox_lib](https://github.com/overextended/ox_lib)
- [oxmysql](https://github.com/overextended/oxmysql)
- [Badger_Discord_API](https://github.com/JaredScar/Badger_Discord_API) (Optional, recommended)
- [nearest-postal](https://forum.cfx.re/t/release-nearest-postal-script/293511) (Optional, recommended)
- [MugShotBase64](https://github.com/MaDHouSe79/mh-mugshot) (Optional)

## Installation

1. Copy this folder into your `resources/` directory as `cdecad-sync-vrp`
2. Edit `shared/config.lua` with your API settings
3. Add `ensure cdecad-sync-vrp` to your `server.cfg` (after `vrp` and `ox_lib`)
4. Restart the server

## Configuration

Edit `shared/config.lua`:

lua
###
API Settings

For security reasons, CDE CAD credentials are now stored in server.cfg as convars rather than in resource files. Add the following block to your server.cfg:
```
##CDECAD
set CDE_CAD_API_URL "https://your-cdecad-instance.com/api"
set CDE_CAD_API_KEY "your-fivem-api-key"
set CDE_CAD_COMMUNITY_ID "your-discord-guild-id"
set CDE_CAD_SERVER_NAME "Your Server Name"
```

### vRP-specific settings

```lua
Config.vRP = {
    DeriveDateOfBirth    = true,                  -- vRP only stores `age`; derive YYYY-01-01 DoB
    UseRegistrationAsSSN = true,                  -- use vRP registration as the CAD SSN
    IdentityTable        = 'vrp_user_identities', -- override if you renamed the table
    VehiclesTable        = 'vrp_user_vehicles',
    SpawnSyncDelay       = 2                      -- seconds after spawn before reading identity
}

Config.ExcludedGroups = { 'police', 'sheriff', 'ems', 'fire', 'dispatch' }
```

## Commands

### Player

| Command | Description |
|---|---|
| `/911 [message]` | Send emergency call |
| `/call911 [message]` | Same as `/911` (alias) |
| `/911anon [message]` | Anonymous emergency call |
| `/reportstolen [desc]` | Report current vehicle stolen |
| `/panic` | Send panic alert |

### Admin

| Command | Description |
|---|---|
| `/cadsync [playerid]` | Force-sync a player (omit ID for self) |
| `/cadsyncall` | Bulk-sync every character from `vrp_user_identities` |
| `/cadforcesyncvehicles` | Bulk-sync every vehicle from `vrp_user_vehicles` |
| `/cadstatus` | CAD API health check |
| `/cadlookup [id/plate]` | Lookup civilian or vehicle |
| `/cadclearcache` | Clear Discord role cache |

## vRP Data Mapping

vRP exposes characters through the Proxy interface:

```lua
local Proxy = module('vrp', 'lib/Proxy')
local vRP   = Proxy.getInterface('vRP')

local user_id  = vRP.getUserId({ source })            -- numeric user_id
local identity = vRP.getUserIdentity({ user_id })     -- { registration, phone, firstname, name, age, ... }
```

### Mapped fields

| vRP `user_identities` column | CDECAD Civilian | Notes |
|---|---|---|
| `firstname` | `firstName` | |
| `name` | `lastName` | vRP stores last name as `name` |
| `age` | `dateOfBirth` | Derived as `(currentYear − age)-01-01` if `Config.vRP.DeriveDateOfBirth` |
| `phone` | `phone` | Formatted to `XXX-XXX-XXXX` when 10 digits |
| `registration` | `ssn` | Used as the unique civilian SSN when `UseRegistrationAsSSN = true` |
| _Discord identifier_ | `discordId` | Pulled from `GetPlayerIdentifiers(source)` |

### Database tables used

| Table | Purpose |
|---|---|
| `vrp_user_identities` | Character data (firstname, name, age, registration, phone) |
| `vrp_user_vehicles` | Vehicle ownership (user_id, vehicle spawn name) |

> **Note on plates**: stock vRP doesn't store a per-vehicle plate in `vrp_user_vehicles` — every owned vehicle uses the user's `registration` as its plate. The bulk-sync therefore uses the registration as the plate; if your server stores plates elsewhere (custom column or a separate table) you'll want to extend `SyncPlayerVehicles` in `server/main.lua`.

## vRP Events Hooked

| Event | Action |
|---|---|
| `vRP:playerJoin` | Cache source → user_id mapping |
| `vRP:playerSpawn` | Sync character (after `SpawnSyncDelay`) |
| `vRP:playerLeave` | Clear Discord role cache for that source |

## Exports

```lua
exports['cdecad-sync-vrp']:SyncCharacter(source)          -- sync a player
exports['cdecad-sync-vrp']:Send911Call(callData)          -- send 911 call payload
exports['cdecad-sync-vrp']:GetSyncedCivilianId(user_id)   -- CAD civilian _id (or nil)
exports['cdecad-sync-vrp']:ForceSync(source)              -- treat as new and re-create
```

## Key Differences from QBCore / ESX Versions

| Feature | QBCore | ESX | vRP |
|---|---|---|---|
| Player ID | `citizenid` (string) | `identifier` (license:xxx) | `user_id` (integer) |
| Character store | `players.charinfo` JSON | `users` columns | `vrp_user_identities` columns |
| Last name field | `charinfo.lastname` | `users.lastname` | `vrp_user_identities.name` |
| Date of birth | `charinfo.birthdate` | `users.dateofbirth` | _Derived from `age`_ |
| Vehicle table | `player_vehicles` | `owned_vehicles` | `vrp_user_vehicles` |
| Per-vehicle plate? | Yes (`plate` col) | Yes (`plate` col) | No (uses `registration`) |
| Player API | `QBCore.Functions.GetPlayer(src)` | `ESX.GetPlayerFromId(src)` | `vRP.getUserId({src})` + `vRP.getUserIdentity({uid})` |
| Spawn event | `QBCore:Server:OnPlayerLoaded` | `esx:playerLoaded` | `vRP:playerSpawn` |

## Troubleshooting

### Characters not syncing
1. Check `Config.API_URL` (no trailing slash) and `Config.API_KEY`.
2. `Config.COMMUNITY_ID` must match your community's Discord guild ID.
3. Verify `vrp_user_identities` actually has rows. vRP creates the row on first login — brand-new users won't have data until they finish character creation.
4. Inspect server console for `[CDECAD-SYNC]` lines and any `Failed to create character` messages.

### Vehicles all have the same plate
This is expected on stock vRP — see the plates note above. Either change your server to write a per-vehicle plate column, or accept that the registration acts as the plate.

### 401 Unauthorized
API key mismatch. Re-check `Config.API_KEY` against the value shown in the CDE CAD community admin panel.

### Player has excluded vRP group
By default users in `police`, `sheriff`, `ems`, `fire`, `dispatch` are not synced as civilians. Add/remove groups via `Config.ExcludedGroups`.
