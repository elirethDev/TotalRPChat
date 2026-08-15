-- shared/trpc/shared/Settings.lua
-- ------------------------------
-- Catálogo central de opciones de sandbox TRPC (patrón ChannelRegistry).
-- Los nombres y defaults son byte-idénticos a 42/media/sandbox-options.txt
-- (53 opciones: 17 page TRPC + 36 page TRPCChannels). Cada lado registra su
-- lector vía setSource(fn): el servidor lee SandboxVars.TRPC, el cliente lee
-- el payload wire TrpcServerSettings (solo opciones de burbuja).
--
-- Kahlua-safe: solo operaciones de tabla/string/número, sin mecanismos de
-- excepción.
-- require path: require("trpc/shared/Settings")

local Settings = {}

local OPTIONS = {
    -- page TRPC (17)
    ["ShowCharacterName"] = { type = "boolean", default = true },
    ["BoredomReduction"] = { type = "double", default = 1.2 },
    ["Languages"] = { type = "boolean", default = false },
    ["BubblePortrait"] = { type = "enum", default = 2 },
    ["BubbleTimerInSeconds"] = { type = "integer", default = 8 },
    ["BubbleOpacity"] = { type = "integer", default = 75 },
    ["VoiceEnabled"] = { type = "boolean", default = true },
    ["VerbEnabled"] = { type = "boolean", default = false },
    ["Capitalize"] = { type = "boolean", default = false },
    ["HideCallout"] = { type = "boolean", default = true },
    ["MarkdownOneAsteriskColor"] = { type = "string", default = "#F676FF" },
    ["MarkdownTwoAsterisksColor"] = { type = "string", default = "#D2D200" },
    ["GeneralDiscordEnabled"] = { type = "boolean", default = false },
    ["RadioDiscordEnabled"] = { type = "boolean", default = true },
    ["RadioDiscordFrequency"] = { type = "integer", default = 100000 },
    ["RadioColor"] = { type = "string", default = "#ABF08C" },
    ["RadioSoundMaxRange"] = { type = "integer", default = 6 },
    -- page TRPCChannels (36)
    ["WhisperEnabled"] = { type = "boolean", default = true },
    ["WhisperRange"] = { type = "integer", default = 3 },
    ["WhisperZombieRange"] = { type = "integer", default = 3 },
    ["WhisperColor"] = { type = "string", default = "#B4FFC5" },
    ["LowEnabled"] = { type = "boolean", default = true },
    ["LowRange"] = { type = "integer", default = 10 },
    ["LowZombieRange"] = { type = "integer", default = 10 },
    ["LowColor"] = { type = "string", default = "#B4FFFF" },
    ["SayEnabled"] = { type = "boolean", default = true },
    ["SayRange"] = { type = "integer", default = 30 },
    ["SayZombieRange"] = { type = "integer", default = 30 },
    ["SayColor"] = { type = "string", default = "#F5F5F5" },
    ["YellEnabled"] = { type = "boolean", default = true },
    ["YellRange"] = { type = "integer", default = 60 },
    ["YellZombieRange"] = { type = "integer", default = 60 },
    ["YellColor"] = { type = "string", default = "#E69696" },
    ["PrivateMessageEnabled"] = { type = "boolean", default = true },
    ["PrivateMessageColor"] = { type = "string", default = "#FFB8DA" },
    ["MeEnabled"] = { type = "boolean", default = true },
    ["MeRange"] = { type = "integer", default = 30 },
    ["MeColor"] = { type = "string", default = "#B8F0FF" },
    ["DoEnabled"] = { type = "boolean", default = true },
    ["DoRange"] = { type = "integer", default = 30 },
    ["DoColor"] = { type = "string", default = "#B8F0FF" },
    ["DoAdminOnly"] = { type = "boolean", default = true },
    ["FactionMessageEnabled"] = { type = "boolean", default = true },
    ["FactionMessageColor"] = { type = "string", default = "#AAFFAA" },
    ["SafeHouseMessageEnabled"] = { type = "boolean", default = true },
    ["SafeHouseMessageColor"] = { type = "string", default = "#F5F580" },
    ["GeneralMessageEnabled"] = { type = "boolean", default = true },
    ["GeneralMessageColor"] = { type = "string", default = "#BEBEFF" },
    ["AdminMessageEnabled"] = { type = "boolean", default = true },
    ["AdminMessageColor"] = { type = "string", default = "#FFAAAA" },
    ["OutOfCharacterMessageEnabled"] = { type = "boolean", default = true },
    ["OutOfCharacterMessageRange"] = { type = "integer", default = 120 },
    ["OutOfCharacterMessageColor"] = { type = "string", default = "#92FF94" },
}

local source = nil

function Settings.setSource(fn)
    source = fn
end

function Settings.get(name)
    local entry = OPTIONS[name]
    if entry == nil then
        return nil
    end
    if source then
        local value = source(name)
        if value ~= nil then
            return value
        end
    end
    return entry.default
end

return Settings
