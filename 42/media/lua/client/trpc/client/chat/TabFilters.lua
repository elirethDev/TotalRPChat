-- chat/TabFilters.lua
-- Pure filter evaluation for message projections.

local TabFilters = {}

local DIMENSIONS = {
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

local FIELD_BY_DIMENSION = {
    channels = "channel",
    excludedChannels = "channel",
    authors = "author",
    targets = "target",
    sources = "source",
    directions = "direction",
    kinds = "kind",
    frequencies = "radioFrequency",
    isFromDiscord = "isFromDiscord",
    isPrivate = "isPrivate",
}

local ALIAS_BY_DIMENSION = {
    channels = "channel",
    authors = "author",
    targets = "target",
    sources = "source",
    directions = "direction",
    kinds = "kind",
    frequencies = "frequency",
    isPrivate = "private",
}

local function CopyValue(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, item in pairs(value) do
        copy[key] = item
    end
    return copy
end

local function GetExpectedValue(filter, dimension)
    local expected = filter[dimension]
    local alias = ALIAS_BY_DIMENSION[dimension]
    if expected == nil and alias ~= nil then
        expected = filter[alias]
    end
    return expected
end

local function Contains(values, value)
    if type(values) ~= "table" then
        return values == value
    end
    if values[value] == true then
        return true
    end
    for _, candidate in ipairs(values) do
        if candidate == value then
            return true
        end
    end
    return false
end

local function MatchesValue(recordValue, expected)
    if expected == nil then
        return true
    end
    if recordValue == nil then
        return false
    end
    if type(recordValue) == "table" then
        for _, value in ipairs(recordValue) do
            if Contains(expected, value) then
                return true
            end
        end
        return false
    end
    return Contains(expected, recordValue)
end

local function MatchesChannel(record, expected)
    if MatchesValue(record.channel, expected) then
        return true
    end

    -- "radio" is a display category. Radio packets retain their transport
    -- channel (for example "say" or "scriptedRadio") and identify the radio
    -- route through their normalized kind/source metadata.
    if not Contains(expected, "radio") then
        return false
    end
    return record.kind == "radio"
        or record.source == "radio"
        or MatchesValue(record.channel, "scriptedRadio")
end

local function Normalize(filter)
    if filter == nil then
        return nil
    end

    local normalized = {}
    for _, dimension in ipairs(DIMENSIONS) do
        local expected = GetExpectedValue(filter, dimension)
        if expected ~= nil then
            normalized[dimension] = CopyValue(expected)
        end
    end
    if filter.includeSystem ~= nil then
        normalized.includeSystem = filter.includeSystem
    end
    return normalized
end

local function Matches(record, filter)
    if filter == nil then
        return true
    end

    record = record or {}
    if filter.includeSystem == false and record.isSystem == true then
        return false
    end
    for _, dimension in ipairs(DIMENSIONS) do
        local expected = GetExpectedValue(filter, dimension)
        if expected ~= nil then
            if dimension == "excludedChannels" then
                if MatchesValue(record.channel, expected) then
                    return false
                end
            else
                local matches
                if dimension == "channels" then
                    matches = MatchesChannel(record, expected)
                else
                    matches = MatchesValue(record[FIELD_BY_DIMENSION[dimension]], expected)
                end
                if dimension == "authors" then
                    matches = matches or MatchesValue(record.characterName, expected)
                end
                if not matches then
                    return false
                end
            end
        end
    end
    return true
end

TabFilters.normalize = Normalize
TabFilters.matches = Matches
TabFilters.match = Matches

return TabFilters
