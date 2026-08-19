-- ui/TabDefinitions.lua
-- Validated persistence model for player-created chat tabs.

local TabFilters = require("trpc/client/chat/TabFilters")
local ChannelRegistry = require("trpc/shared/ChannelRegistry")

local TabDefinitions = {}

TabDefinitions.KEY = "trpcChatTabs"
TabDefinitions.SCHEMA_VERSION = 1
TabDefinitions.CUSTOM_ID_PREFIX = "trpc-custom-"
TabDefinitions.DEFAULT_INPUT_CHANNEL = "say"
TabDefinitions.MAX_TITLE_LENGTH = 32

TabDefinitions.STATUS_OK = "ok"
TabDefinitions.STATUS_MISSING = "missing"
TabDefinitions.STATUS_MALFORMED = "malformed"
TabDefinitions.STATUS_NORMALIZED = "normalized"
TabDefinitions.STATUS_UNSUPPORTED = "unsupported"
TabDefinitions.STATUS_UNAVAILABLE = "unavailable"

TabDefinitions.BUILTIN_IDS = {
    general = "builtin.general",
    ooc = "builtin.ooc",
    pm = "builtin.pm",
    admin = "builtin.admin",
}
TabDefinitions.BUILTIN_GENERAL_ID = TabDefinitions.BUILTIN_IDS.general

local BUILTIN_ID_BY_NUMBER = {
    [1] = TabDefinitions.BUILTIN_IDS.general,
    [2] = TabDefinitions.BUILTIN_IDS.ooc,
    [3] = TabDefinitions.BUILTIN_IDS.pm,
    [4] = TabDefinitions.BUILTIN_IDS.admin,
}

-- Both ID namespaces are reserved. The numeric values are still used by the
-- current runtime tabs, while persisted definitions use namespaced strings.
TabDefinitions.RESERVED_BUILTIN_IDS = {
    [1] = true,
    [2] = true,
    [3] = true,
    [4] = true,
    ["builtin.general"] = true,
    ["builtin.ooc"] = true,
    ["builtin.pm"] = true,
    ["builtin.admin"] = true,
}
TabDefinitions.RESERVED_BUILTIN_NUMERIC_IDS = { 1, 2, 3, 4 }

local BUILTIN_ID_SET = {
    ["builtin.general"] = true,
    ["builtin.ooc"] = true,
    ["builtin.pm"] = true,
    ["builtin.admin"] = true,
}

local FILTER_DIMENSIONS = {
    "channels",
    "excludedChannels",
    "authors",
    "targets",
    "sources",
    "directions",
    "kinds",
    "frequencies",
    "isFromDiscord",
    "isPrivate",
}

local VALID_INPUT_CHANNELS = {}
for _, entry in ipairs(ChannelRegistry.getAll()) do
    if entry.hasSlashCommand ~= false then
        VALID_INPUT_CHANNELS[entry.name] = true
    end
end

local VALID_FILTER_CHANNELS = {}
for _, entry in ipairs(ChannelRegistry.getAll()) do
    VALID_FILTER_CHANNELS[entry.name] = true
end
for _, channel in ipairs({ "server", "radio", "system", "error" }) do
    VALID_FILTER_CHANNELS[channel] = true
end

local VALID_FILTER_VALUES = {
    channels = VALID_FILTER_CHANNELS,
    excludedChannels = VALID_FILTER_CHANNELS,
    sources = {
        network = true,
        discord = true,
        server = true,
        radio = true,
        system = true,
        ["local"] = true,
    },
    directions = {
        incoming = true,
        outgoing = true,
    },
    kinds = {
        chat = true,
        private = true,
        system = true,
        radio = true,
    },
}

local function IsFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function IsPositiveInteger(value)
    return IsFiniteNumber(value) and value > 0 and value == math.floor(value)
end

local function DeepCopy(value, seen)
    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] ~= nil then
        return seen[value]
    end

    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do
        copy[DeepCopy(key, seen)] = DeepCopy(item, seen)
    end
    return copy
end

local function DeepEqual(left, right, seen)
    if left == right then
        return true
    end
    if type(left) ~= type(right) or type(left) ~= "table" then
        return false
    end

    seen = seen or {}
    seen[left] = seen[left] or {}
    if seen[left][right] then
        return true
    end
    seen[left][right] = true

    for key, value in pairs(left) do
        if not DeepEqual(value, right[key], seen) then
            return false
        end
    end
    for key in pairs(right) do
        if left[key] == nil then
            return false
        end
    end
    return true
end

local function ExtractCustomNumber(value)
    if type(value) ~= "string" then
        return nil
    end

    local suffix = value:match("^trpc%-custom%-([1-9]%d*)$")
    if suffix == nil then
        return nil
    end

    local number = tonumber(suffix)
    if not IsPositiveInteger(number) then
        return nil
    end
    return number
end

local function IsCustomID(value)
    return ExtractCustomNumber(value) ~= nil
end

local function CompareCustomIDs(left, right)
    local leftNumber = ExtractCustomNumber(left)
    local rightNumber = ExtractCustomNumber(right)
    if leftNumber == rightNumber then
        return left < right
    end
    return leftNumber < rightNumber
end

local function CompareValues(left, right)
    if type(left) == type(right) and left == right then
        return false
    end
    return tostring(left) < tostring(right)
end

local function NormalizeTitle(value)
    if type(value) ~= "string" then
        return nil
    end

    local title = value:gsub("[%c]", "")
    title = title:gsub("^%s+", ""):gsub("%s+$", "")
    if #title == 0 then
        return nil
    end
    return title:sub(1, TabDefinitions.MAX_TITLE_LENGTH)
end

local function MakeUniqueTitle(title, usedTitles)
    local candidate = title
    local suffixNumber = 1
    while usedTitles[string.lower(candidate)] do
        suffixNumber = suffixNumber + 1
        local suffix = " (" .. tostring(suffixNumber) .. ")"
        candidate = title:sub(1, TabDefinitions.MAX_TITLE_LENGTH - #suffix) .. suffix
    end
    usedTitles[string.lower(candidate)] = true
    return candidate
end

local function NormalizeInputChannel(value)
    if VALID_INPUT_CHANNELS[value] then
        return value
    end
    return TabDefinitions.DEFAULT_INPUT_CHANNEL
end

local function IsValidFilterScalar(dimension, value)
    if dimension == "isFromDiscord" or dimension == "isPrivate" then
        return type(value) == "boolean"
    end
    if dimension == "authors" or dimension == "targets" then
        return type(value) == "string" and value:match("%S") ~= nil
    end
    if dimension == "frequencies" then
        return IsFiniteNumber(value)
    end

    local allowed = VALID_FILTER_VALUES[dimension]
    return allowed ~= nil and allowed[value] == true
end

local function NormalizeFilterValue(dimension, value)
    if type(value) ~= "table" then
        if IsValidFilterScalar(dimension, value) then
            return value
        end
        return nil
    end

    local values = {}
    local seen = {}
    local candidates = {}
    if #value > 0 then
        for index = 1, #value do
            table.insert(candidates, value[index])
        end
    else
        for candidate, enabled in pairs(value) do
            if enabled == true then
                table.insert(candidates, candidate)
            end
        end
        table.sort(candidates, CompareValues)
    end

    for _, candidate in ipairs(candidates) do
        if IsValidFilterScalar(dimension, candidate) and not seen[candidate] then
            seen[candidate] = true
            table.insert(values, candidate)
        end
    end
    if #values == 0 then
        return nil
    end
    return values
end

local function NormalizeFilters(filter)
    if type(filter) ~= "table" then
        return {}
    end

    local canonical = TabFilters.normalize(filter) or {}
    local normalized = {}
    for _, dimension in ipairs(FILTER_DIMENSIONS) do
        local value = NormalizeFilterValue(dimension, canonical[dimension])
        if value ~= nil then
            normalized[dimension] = value
        end
    end
    if type(filter.includeSystem) == "boolean" then
        normalized.includeSystem = filter.includeSystem
    end
    return normalized
end

local function NewState()
    return {
        schemaVersion = TabDefinitions.SCHEMA_VERSION,
        nextCustomID = 1,
        order = {},
        tabs = {},
        activeTabID = TabDefinitions.BUILTIN_GENERAL_ID,
    }
end

local function CollectObservedIDs(raw)
    local observed = {}
    local highest = 0

    local function Observe(value)
        local number = ExtractCustomNumber(value)
        if number ~= nil then
            observed[value] = true
            if number > highest then
                highest = number
            end
        end
    end

    if type(raw.tabs) == "table" then
        for id in pairs(raw.tabs) do
            Observe(id)
        end
    end
    if type(raw.order) == "table" then
        for index = 1, #raw.order do
            Observe(raw.order[index])
        end
    end
    return observed, highest
end

local function Normalize(raw)
    if raw == nil then
        return NewState(), TabDefinitions.STATUS_MISSING, true
    end
    if type(raw) ~= "table" then
        return NewState(), TabDefinitions.STATUS_MALFORMED, true
    end
    if type(raw.schemaVersion) ~= "number" or raw.schemaVersion ~= raw.schemaVersion then
        return NewState(), TabDefinitions.STATUS_MALFORMED, true
    end
    if raw.schemaVersion > TabDefinitions.SCHEMA_VERSION then
        return DeepCopy(raw), TabDefinitions.STATUS_UNSUPPORTED, false
    end
    if raw.schemaVersion ~= TabDefinitions.SCHEMA_VERSION or type(raw.tabs) ~= "table" then
        return NewState(), TabDefinitions.STATUS_MALFORMED, true
    end

    local _, highestObservedID = CollectObservedIDs(raw)
    local candidateDefinitions = {}
    for id, definition in pairs(raw.tabs) do
        if IsCustomID(id) and type(definition) == "table" then
            local title = NormalizeTitle(definition.title)
            if title ~= nil then
                candidateDefinitions[id] = {
                    title = title,
                    inputChannel = definition.inputChannel,
                    filters = definition.filters,
                }
            end
        end
    end

    local orderedIDs = {}
    local included = {}
    if type(raw.order) == "table" then
        for index = 1, #raw.order do
            local id = raw.order[index]
            if candidateDefinitions[id] ~= nil and not included[id] then
                included[id] = true
                table.insert(orderedIDs, id)
            end
        end
    end

    local omittedIDs = {}
    for id in pairs(candidateDefinitions) do
        if not included[id] then
            table.insert(omittedIDs, id)
        end
    end
    table.sort(omittedIDs, CompareCustomIDs)
    for _, id in ipairs(omittedIDs) do
        table.insert(orderedIDs, id)
    end

    local normalized = NewState()
    local nextCustomID = raw.nextCustomID
    if not IsPositiveInteger(nextCustomID) then
        nextCustomID = 1
    end
    if nextCustomID <= highestObservedID then
        nextCustomID = highestObservedID + 1
    end
    normalized.nextCustomID = nextCustomID

    local usedTitles = {}
    for _, id in ipairs(orderedIDs) do
        local definition = candidateDefinitions[id]
        normalized.order[#normalized.order + 1] = id
        normalized.tabs[id] = {
            title = MakeUniqueTitle(definition.title, usedTitles),
            inputChannel = NormalizeInputChannel(definition.inputChannel),
            filters = NormalizeFilters(definition.filters),
        }
    end

    if IsCustomID(raw.activeTabID) and normalized.tabs[raw.activeTabID] ~= nil then
        normalized.activeTabID = raw.activeTabID
    elseif BUILTIN_ID_SET[raw.activeTabID] then
        normalized.activeTabID = raw.activeTabID
    elseif BUILTIN_ID_BY_NUMBER[raw.activeTabID] ~= nil then
        normalized.activeTabID = BUILTIN_ID_BY_NUMBER[raw.activeTabID]
    end

    local changed = not DeepEqual(normalized, raw)
    local status = changed and TabDefinitions.STATUS_NORMALIZED or TabDefinitions.STATUS_OK
    return normalized, status, changed
end

local function AllocateCustomID(state)
    local normalized, status, changed = Normalize(state)
    if status == TabDefinitions.STATUS_UNSUPPORTED then
        return nil, normalized, status, changed
    end

    local nextState = DeepCopy(normalized)
    local number = nextState.nextCustomID
    nextState.nextCustomID = number + 1
    return TabDefinitions.CUSTOM_ID_PREFIX .. tostring(number), nextState, TabDefinitions.STATUS_NORMALIZED, true
end

local function Load()
    if ModData == nil or type(ModData.get) ~= "function" then
        return NewState(), TabDefinitions.STATUS_UNAVAILABLE, true
    end
    return Normalize(ModData.get(TabDefinitions.KEY))
end

local function Save(state)
    local normalized, status, changed = Normalize(state)
    if status == TabDefinitions.STATUS_UNSUPPORTED then
        return false, normalized, status, changed
    end
    if ModData == nil or type(ModData.add) ~= "function" then
        return false, normalized, TabDefinitions.STATUS_UNAVAILABLE, changed
    end
    ModData.add(TabDefinitions.KEY, normalized)
    return true, normalized, status, changed
end

TabDefinitions.newState = NewState
TabDefinitions.normalize = Normalize
TabDefinitions.normalizeTitle = NormalizeTitle
TabDefinitions.normalizeInputChannel = NormalizeInputChannel
TabDefinitions.normalizeFilters = NormalizeFilters
TabDefinitions.isCustomID = IsCustomID
TabDefinitions.allocateCustomID = AllocateCustomID
TabDefinitions.allocateID = AllocateCustomID
TabDefinitions.load = Load
TabDefinitions.save = Save

return TabDefinitions
