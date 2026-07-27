Locales = Locales or {}

local function load(lang)
    if type(lang) ~= 'string' or lang == '' then return nil end
    if Locales[lang] then return Locales[lang] end

    local raw = LoadResourceFile(GetCurrentResourceName(), ('locales/%s.json'):format(lang))
    if not raw then return nil end

    local ok, parsed = pcall(json.decode, raw)
    if not ok or type(parsed) ~= 'table' then
        print(('^1[lime_redzones] locales/%s.json is not valid JSON — falling back to English.^0'):format(lang))
        return nil
    end

    Locales[lang] = parsed
    return parsed
end

CreateThread(function()
    local lang = (Config and Config.Locale) or 'en'
    if not load(lang) and lang ~= 'en' then
        print(('^3[lime_redzones] Locale "%s" not found — using English.^0'):format(lang))
    end
    load('en')
end)

function _U(key, ...)
    local lang = (Config and Config.Locale) or 'en'
    local str = (load(lang) or {})[key] or (load('en') or {})[key]
    if not str then return key end
    if select('#', ...) > 0 then
        local ok, formatted = pcall(string.format, str, ...)
        if ok then return formatted end
    end
    return str
end
