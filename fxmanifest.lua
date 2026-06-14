fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'lime'
description 'lime_redzones — in-game redzone creator'
version '1.0.0'

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/bundle.js',
    'web/bundle.css',
}

shared_script 'config.lua'

client_scripts {
    'bridge/notify.lua',
    'bridge/ambulance.lua',
    'client/client.lua',
}

dependencies {
    'oxmysql',
}

server_scripts {
    'bridge/notify_sv.lua',
    'bridge/ambulance_sv.lua',
    'bridge/inventory.lua',
    'server/server.lua',
    '_versioncheck.lua',
}

escrow_ignore {
    'config.lua',
    'bridge/*.lua',
    'client/*.lua',
    'server/*.lua',
}
