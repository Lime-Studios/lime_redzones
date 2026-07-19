-- Locale lookup. Falls back to English, then to the key itself, so a missing
-- translation degrades to readable text instead of a nil error.
Locales = Locales or {}

function _U(key, ...)
    local lang = (Config and Config.Locale) or 'en'
    local str = (Locales[lang] and Locales[lang][key]) or (Locales['en'] and Locales['en'][key])
    if not str then return key end
    if select('#', ...) > 0 then
        local ok, formatted = pcall(string.format, str, ...)
        if ok then return formatted end
    end
    return str
end
