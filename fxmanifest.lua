fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'lime'
description 'lime_redzones — in-game redzone & safe zone creator'
version '2.1.0'

suppress_updates 'false'

ui_page 'web/index.html'

files {
    'locales/*.json',
    'web/index.html',
    'web/bundle.js',
    'web/bundle.css',
    'web/fonts/PlusJakartaSans-Variable.woff2',
}

shared_scripts {
    'config.lua',
    'bridge/locale.lua',
}

client_scripts {
    'bridge/community.lua',
    'bridge/notify.lua',
    'bridge/ambulance.lua',
    'client/client.lua',
    'client/podium.lua',
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
