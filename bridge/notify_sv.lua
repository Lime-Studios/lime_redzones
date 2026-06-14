function NotifySv(src, message, ntype, duration)

    TriggerClientEvent('lime_redzones:client:notify', src, message, ntype or 'info', duration or 4000)
end
