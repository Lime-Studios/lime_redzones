fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'lime'
description 'lime_redzones — in-game redzone & safe zone creator'
version '2.0.0'

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/bundle.js',
    'web/bundle.css',
    'web/fonts/PlusJakartaSans-Variable.woff2',
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
    'bridge/community_sv.lua',
    'bridge/notify_sv.lua',
    'bridge/ambulance_sv.lua',
    'bridge/inventory.lua',
    'bridge/logs.lua',
    'bridge/banking.lua',
    'server/server.lua',
}

escrow_ignore {
    'config.lua',
    'bridge/*.lua',
    'client/*.lua',
    'server/*.lua',
}
