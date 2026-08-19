-- LocalPreferences.lua
-- Local-only chat filters and radio preferences stored alongside player preferences.

local LocalPreferences = {}

LocalPreferences.MOD_DATA_KEY = "trpc"
LocalPreferences.FIELD = "localChatPreferences"
LocalPreferences.SCHEMA_VERSION = 2

local function CopyMap(value)
    local copy = {}
    if type(value) ~= "table" then
        return copy
    end
    for key, item in pairs(value) do
        copy[key] = item
    end
    return copy
end

local function NormalizeName(value)
    if type(value) ~= "string" then
        return nil
    end
    local name = value:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then
        return nil
    end
    return name
end

local function NormalizeKey(value)
    local normalized = NormalizeName(value)
    return normalized and string.lower(normalized) or nil
end

local function NormalizeSet(value, lowerKeys)
    local normalized = {}
    if type(value) ~= "table" then
        return normalized
    end

    if #value > 0 then
        for _, item in ipairs(value) do
            local key = lowerKeys and NormalizeKey(item) or NormalizeName(item)
            if key ~= nil then
                normalized[key] = lowerKeys and NormalizeName(item) or true
            end
        end
    else
        for item, enabled in pairs(value) do
            if enabled == true or (lowerKeys and type(enabled) == "string") then
                local key = lowerKeys and NormalizeKey(item) or NormalizeName(item)
                if key ~= nil then
                    normalized[key] = lowerKeys and (type(enabled) == "string" and enabled or NormalizeName(item)) or true
                end
            end
        end
    end
    return normalized
end

local function NormalizeFrequencySet(value)
    local normalized = {}
    if type(value) ~= "table" then
        return normalized
    end
    if #value > 0 then
        for _, frequency in ipairs(value) do
            if type(frequency) == "number" or type(frequency) == "string" then
                normalized[tostring(frequency)] = true
            end
        end
    else
        for frequency, enabled in pairs(value) do
            if enabled == true and (type(frequency) == "number" or type(frequency) == "string") then
                normalized[tostring(frequency)] = true
            end
        end
    end
    return normalized
end

local function NormalizeFrequency(value)
    if type(value) == "number" then
        return tostring(value)
    end
    if type(value) ~= "string" then
        return nil
    end
    local frequency = value:gsub("^%s+", ""):gsub("%s+$", "")
    return frequency ~= "" and frequency or nil
end

local function NormalizePresetLabel(value, frequency)
    if type(value) == "string" then
        local label = value:gsub("^%s+", ""):gsub("%s+$", "")
        if label ~= "" then
            return label
        end
    end
    return frequency
end

local function NormalizeRadioPresets(value)
    local normalized = {}
    if type(value) ~= "table" then
        return normalized
    end

    local function AddPreset(frequency, label)
        local key = NormalizeFrequency(frequency)
        if key ~= nil then
            normalized[key] = NormalizePresetLabel(label, key)
        end
    end

    if #value > 0 then
        for _, preset in ipairs(value) do
            if type(preset) == "table" then
                AddPreset(preset.frequency or preset.channel, preset.label or preset.name)
            else
                AddPreset(preset, nil)
            end
        end
    else
        for frequency, preset in pairs(value) do
            if type(preset) == "table" then
                AddPreset(preset.frequency or frequency, preset.label or preset.name)
            elseif preset == true or type(preset) == "string" then
                AddPreset(frequency, type(preset) == "string" and preset or nil)
            end
        end
    end
    return normalized
end

local function NewState()
    return {
        schemaVersion = LocalPreferences.SCHEMA_VERSION,
        ignoredPlayers = {},
        mutedChannels = {},
        mutedRadioFrequencies = {},
        radioPresets = {},
    }
end

local function Normalize(value)
    if type(value) ~= "table" then
        return NewState()
    end
    return {
        schemaVersion = LocalPreferences.SCHEMA_VERSION,
        ignoredPlayers = NormalizeSet(value.ignoredPlayers, true),
        mutedChannels = NormalizeSet(value.mutedChannels, true),
        mutedRadioFrequencies = NormalizeFrequencySet(value.mutedRadioFrequencies),
        radioPresets = NormalizeRadioPresets(value.radioPresets),
    }
end

local state = NewState()

local function Load()
    if ModData == nil or type(ModData.get) ~= "function" then
        state = NewState()
        return state, "unavailable"
    end
    local playerData = ModData.get(LocalPreferences.MOD_DATA_KEY)
    state = Normalize(playerData and playerData[LocalPreferences.FIELD])
    return state, "ok"
end

local function Save(nextState)
    local normalized = Normalize(nextState)
    if ModData == nil or type(ModData.getOrCreate) ~= "function" or type(ModData.add) ~= "function" then
        return false, normalized, "unavailable"
    end

    local playerData = ModData.getOrCreate(LocalPreferences.MOD_DATA_KEY)
    if type(playerData) ~= "table" then
        return false, normalized, "unavailable"
    end
    playerData[LocalPreferences.FIELD] = normalized
    ModData.add(LocalPreferences.MOD_DATA_KEY, playerData)
    state = normalized
    return true, state, "ok"
end

local function EnsureLoaded()
    if state == nil then
        Load()
    end
    return state
end

local function SetEntry(collection, key, value)
    local nextState = Normalize(EnsureLoaded())
    if value then
        nextState[collection][key] = value
    else
        nextState[collection][key] = nil
    end
    return Save(nextState)
end

local function IsIgnoredPlayer(username)
    local key = NormalizeKey(username)
    return key ~= nil and EnsureLoaded().ignoredPlayers[key] ~= nil
end

local function IsChannelMuted(channel)
    local key = NormalizeKey(channel)
    return key ~= nil and EnsureLoaded().mutedChannels[key] ~= nil
end

local function IsRadioFrequencyMuted(frequency)
    if frequency == nil then
        return false
    end
    return EnsureLoaded().mutedRadioFrequencies[tostring(frequency)] == true
end

local function GetRadioPresets()
    return CopyMap(EnsureLoaded().radioPresets)
end

local function ShouldSuppress(record)
    if type(record) ~= "table" then
        return false
    end
    return IsIgnoredPlayer(record.author)
        or IsChannelMuted(record.channel or record.type)
        or IsRadioFrequencyMuted(record.radioFrequency or record.frequency)
end

function LocalPreferences.setState(value)
    state = Normalize(value)
    return state
end

function LocalPreferences.getState()
    return EnsureLoaded()
end

LocalPreferences.load = Load
LocalPreferences.save = Save
LocalPreferences.normalize = Normalize
LocalPreferences.isIgnoredPlayer = IsIgnoredPlayer
LocalPreferences.isChannelMuted = IsChannelMuted
LocalPreferences.isRadioFrequencyMuted = IsRadioFrequencyMuted
LocalPreferences.getRadioPresets = GetRadioPresets
LocalPreferences.shouldSuppress = ShouldSuppress

function LocalPreferences.setIgnoredPlayer(username, ignored)
    local name = NormalizeName(username)
    local key = NormalizeKey(name)
    if key == nil then
        return false, "invalid"
    end
    return SetEntry("ignoredPlayers", key, ignored and name or nil)
end

function LocalPreferences.setChannelMuted(channel, muted)
    local key = NormalizeKey(channel)
    if key == nil then
        return false, "invalid"
    end
    return SetEntry("mutedChannels", key, muted == true)
end

function LocalPreferences.setRadioFrequencyMuted(frequency, muted)
    if type(frequency) ~= "number" and type(frequency) ~= "string" then
        return false, "invalid"
    end
    return SetEntry("mutedRadioFrequencies", tostring(frequency), muted == true)
end

function LocalPreferences.setRadioPreset(frequency, label, enabled)
    local key = NormalizeFrequency(frequency)
    if key == nil then
        return false, "invalid"
    end
    if enabled == false then
        return SetEntry("radioPresets", key, nil)
    end
    return SetEntry("radioPresets", key, NormalizePresetLabel(label, key))
end

function LocalPreferences.getIgnoredPlayers()
    return CopyMap(EnsureLoaded().ignoredPlayers)
end

return LocalPreferences
