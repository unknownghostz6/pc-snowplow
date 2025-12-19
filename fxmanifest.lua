name 'pc-snowplow'
description ''
version '0.0.1'
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'crusopaul (updated by UnknownGhostz for latest qb-core compatibility)'

dependencies {
    'qb-core',
    'qb-target',
    'qb-menu',
    'qb-weathersync'
}

shared_script 'config.lua'

server_scripts {
    'server/functions.lua',
    'server/main.lua',
}

client_scripts {
    'client/functions.lua',
    'client/main.lua',
}
