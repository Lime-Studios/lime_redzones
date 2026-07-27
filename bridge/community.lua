CB = { active = false }

CreateThread(function()
    for _ = 1, 40 do
        if GetResourceState('community_bridge') == 'started' then break end
        Wait(250)
    end
    CB.active = GetResourceState('community_bridge') == 'started'
end)
