fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'lime'
description 'lime_redzones — in-game redzone & safe zone creator'
version '2.0.1'

-- Set to 'true' to silence the startup update check.
suppress_updates 'false'

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/bundle.js',
    'web/bundle.css',
    'web/fonts/PlusJakartaSans-Variable.woff2',
    "stream/limeredzones_prop.ytyp",
    "stream/limeredzones_prop.ydr",
}

shared_scripts {
    'config.lua',
    'locales/*.lua',
    'bridge/locale.lua',
}

client_scripts {
    'bridge/community.lua',
    'bridge/notify.lua',
    'bridge/ambulance.lua',
    'client/client.lua',
}

dependencies {
    'oxmysql',
}

server_scripts {
    '_versioncheck.lua',
    'bridge/community_sv.lua',
    'bridge/notify_sv.lua',
    'bridge/ambulance_sv.lua',
    'bridge/inventory.lua',
    'bridge/logs.lua',
    'bridge/banking.lua',
    'server/server.lua',
}

escrow_ignore {
    '_versioncheck.lua',
    'config.lua',
    'bridge/*.lua',
    'client/*.lua',
    'server/*.lua',
}


data_file "DLC_ITYP_REQUEST" "limeredzones_prop.ytyp"
this_is_a_map "yes"
dependency '/assetpacks'