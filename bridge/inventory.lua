local Inv = 'framework'

if GetResourceState('ox_inventory') == 'started' then Inv = 'ox'
elseif GetResourceState('one_inventory') == 'started' then Inv = 'one'
elseif GetResourceState('qs-inventory') == 'started' then Inv = 'qs'
elseif GetResourceState('qb-inventory') == 'started' then Inv = 'qb'
elseif GetResourceState('ps-inventory') == 'started' then Inv = 'ps'
elseif GetResourceState('core_inventory') == 'started' then Inv = 'core'
elseif GetResourceState('codem-inventory') == 'started' then Inv = 'codem'
elseif GetResourceState('origen_inventory') == 'started' then Inv = 'origen'
elseif GetResourceState('tgiann-inventory') == 'started' then Inv = 'tgiann'
end

function GetInventoryName() return Inv end

function InvAddItem(src, item, amount)
    local ok, res = pcall(function()
        if Inv == 'ox' then
            return exports.ox_inventory:AddItem(src, item, amount)
        elseif Inv == 'one' then
            -- one_inventory:AddItem(inv, item, count) -> boolean, reason?
            local success = exports.one_inventory:AddItem(src, item, amount)
            return success == true
        elseif Inv == 'qs' then
            return exports['qs-inventory']:AddItem(src, item, amount)
        elseif Inv == 'qb' then
            return exports['qb-inventory']:AddItem(src, item, amount, false, false, 'redzone-reward')
        elseif Inv == 'ps' then
            return exports['ps-inventory']:AddItem(src, item, amount)
        elseif Inv == 'core' then
            return exports.core_inventory:addItem(src, item, amount)
        elseif Inv == 'codem' then
            return exports['codem-inventory']:AddItem(src, item, amount)
        elseif Inv == 'origen' then
            return exports.origen_inventory:addItem(src, item, amount)
        elseif Inv == 'tgiann' then
            return exports['tgiann-inventory']:AddItem(src, item, amount)
        end
        return nil
    end)
    if not ok then return false end
    if res == nil and Inv ~= 'framework' then return false end
    if res == nil then return false end
    return res ~= false
end

function InvIsFramework() return Inv == 'framework' end
