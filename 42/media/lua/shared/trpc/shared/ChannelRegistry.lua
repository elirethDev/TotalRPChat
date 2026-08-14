-- ChannelRegistry.lua
-- TRPC shared channel identity registry: single authoritative list of the 13
-- wire channel names with their wire-level flags (hasSlashCommand,
-- isServerDriven). Layers (Streams, Formatting, ChatDomain) extend by name.
--
-- require path: require("trpc/shared/ChannelRegistry")

local ChannelRegistry = {}

local channels = {
    { name = "say",           hasSlashCommand = true,  isServerDriven = false },
    { name = "whisper",       hasSlashCommand = true,  isServerDriven = false },
    { name = "low",           hasSlashCommand = true,  isServerDriven = false },
    { name = "yell",          hasSlashCommand = true,  isServerDriven = false },
    { name = "faction",       hasSlashCommand = true,  isServerDriven = false },
    { name = "safehouse",     hasSlashCommand = true,  isServerDriven = false },
    { name = "general",       hasSlashCommand = true,  isServerDriven = false },
    { name = "scriptedRadio", hasSlashCommand = false, isServerDriven = true },
    { name = "ooc",           hasSlashCommand = true,  isServerDriven = false },
    { name = "pm",            hasSlashCommand = true,  isServerDriven = false },
    { name = "admin",         hasSlashCommand = true,  isServerDriven = false },
    { name = "me",            hasSlashCommand = true,  isServerDriven = false },
    { name = "do",            hasSlashCommand = true,  isServerDriven = false },
}

-- Build name index for O(1) lookup
local nameIndex = {}
for _, entry in ipairs(channels) do
    nameIndex[entry.name] = entry
end

function ChannelRegistry.getChannel(name)
    return nameIndex[name]
end

function ChannelRegistry.getAll()
    return channels
end

return ChannelRegistry