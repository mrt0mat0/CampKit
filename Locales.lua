-- Translations. Each file in Locales/ fills in ns.L for its own client language.
-- A string with no translation falls back to English, so a missing line never breaks anything.
-- Slash command words (/campkit add, grow up, ...) stay English in every language.

local _, ns = ...
ns = ns or {}
ns.L = setmetatable({}, { __index = function(_, key) return key end })
ns.locale = GetLocale and GetLocale() or "enUS"
