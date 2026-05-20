fx_version 'cerulean'
game 'gta5'

name 'cdecad-sync-vrp'
description 'Sync vRP characters to CDECAD - Character, Vehicle, and 911 integration'
author 'CDECAD'
version '1.0.0'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
    'shared/utils.lua',
    'shared/vehicles.lua'
}

server_scripts {
    '@vrp/lib/utils.lua',
    'server/secrets.lua',
    'server/api.lua',
    'server/discord.lua',
    'server/main.lua',
    'server/commands.lua'
}

client_scripts {
    '@vrp/lib/utils.lua',
    'client/main.lua',
    'client/911.lua'
}

dependencies {
    'vrp',
    'ox_lib'
}

-- Optional dependencies (will use if available)
-- 'Badger_Discord_API' - For Discord role checking
-- 'nearest-postal' - For postal code in 911 calls
-- 'MugShotBase64' - For automatic mugshot capture
