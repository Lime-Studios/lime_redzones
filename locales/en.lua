-- English locale. Copy this file, translate the values, and set
-- Config.Locale in config.lua to your file's name (e.g. 'de').
Locales = Locales or {}

Locales['en'] = {
    -- Notifications
    ['no_permission']        = 'You do not have permission to do that.',
    ['zone_saved']           = 'Zone "%s" saved.',
    ['zone_deleted']         = 'Zone "%s" deleted.',
    ['zone_enabled']         = 'Zone "%s" enabled.',
    ['zone_disabled']        = 'Zone "%s" disabled.',
    ['gang_saved']           = 'Gang "%s" saved.',
    ['gang_removed']         = 'Gang "%s" removed.',
    ['admin_added']          = 'Admin added: %s',
    ['admin_removed']        = 'Admin removed: %s',
    ['already_admin']        = 'That identifier is already an admin.',
    ['settings_saved']       = 'Settings saved.',
    ['reset_saved']          = 'Reset schedule saved.',
    ['logs_wiped']           = 'Wiped %d log entries.',
    ['logs_cleared_one']     = 'Wiped %d log entry.',

    -- Rewards / economy
    ['reward_received']      = 'Reward: %s',
    ['revived_cost']         = 'Revived — $%s deducted.',
    ['revived_cost_bank']    = 'Revived — $%s deducted from bank.',
    ['revive_need_cash']     = 'You need $%s cash to be revived here.',
    ['revive_need_bank']     = 'You need $%s in your bank to be revived here.',
    ['revive_failed']        = 'Automatic respawn failed — use the normal respawn option.',

    -- Zones
    ['no_vehicles']          = 'Vehicles are not allowed in this redzone.',
    ['weapon_locked']        = 'That weapon is not allowed in this redzone.',
    ['entered_safezone']     = 'Entered safe zone: %s',
    ['left_safezone']        = 'Left safe zone: %s',
    ['placement_mode']       = 'Placement mode — press E to place a point, G to finish.',

    -- Teleport
    ['teleporting']          = 'Teleporting to %s.',
    ['teleporting_cost']     = 'Teleporting to %s — $%s deducted.',
    ['teleport_disabled']    = 'Teleporting to this redzone is disabled.',
    ['teleport_dead']        = 'You cannot teleport while down.',
    ['teleport_cooldown']    = 'Slow down a moment before teleporting again.',
    ['teleport_need_cash']   = 'You need $%s in cash to teleport here.',
    ['teleport_need_bank']   = 'You need $%s in your bank to teleport here.',
    ['teleport_arrived']     = 'Arrived at %s.',

    -- Errors
    ['no_notify_resource']   = 'No supported notification resource detected. Notifications will not be shown.',
}
