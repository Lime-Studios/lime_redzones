-- Community Bridge adapter (client). Mirrors community_sv.lua so client-side
-- code can ask CB.active before routing through it, with our own bridges as
-- the fallback when it isn't installed.

CB = { active = false }

CreateThread(function()
    for _ = 1, 40 do
        if GetResourceState('community_bridge') == 'started' then break end
        Wait(250)
    end
    CB.active = GetResourceState('community_bridge') == 'started'
end)

function CB.Revive()
    if not CB.active then return nil end
    local ok = pcall(function() return exports.community_bridge:RevivePlayer() end)
    return ok or nil
end
