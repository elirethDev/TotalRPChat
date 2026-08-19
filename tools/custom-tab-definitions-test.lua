package.path = "42/media/lua/client/?.lua;42/media/lua/shared/?.lua;" .. package.path

local TabDefinitions = require("trpc/client/ui/TabDefinitions")

local function AssertEqual(actual, expected, message)
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function AssertArray(actual, expected, message)
    AssertEqual(#actual, #expected, message .. " length")
    for index, value in ipairs(expected) do
        AssertEqual(actual[index], value, message .. " item " .. tostring(index))
    end
end

local function AssertAbsent(tableValue, key, message)
    assert(tableValue[key] == nil, message .. ": unexpected value " .. tostring(tableValue[key]))
end

local missing, missingStatus, missingChanged = TabDefinitions.normalize(nil)
AssertEqual(missingStatus, TabDefinitions.STATUS_MISSING, "missing state status")
assert(missingChanged, "missing state is reported as changed")
AssertEqual(missing.schemaVersion, 1, "missing state schema")
AssertEqual(missing.nextCustomID, 1, "empty state starts at custom ID one")
AssertEqual(missing.activeTabID, "builtin.general", "empty state active tab")

local malformed, malformedStatus = TabDefinitions.normalize("not a state")
AssertEqual(malformedStatus, TabDefinitions.STATUS_MALFORMED, "malformed top-level status")
AssertEqual(malformed.schemaVersion, 1, "malformed state schema")
AssertEqual(#malformed.order, 0, "malformed state order")
AssertEqual(next(malformed.tabs), nil, "malformed state tabs")

local raw = {
    schemaVersion = 1,
    nextCustomID = 2,
    order = { "trpc-custom-2", "trpc-custom-1", "unknown", "trpc-custom-2" },
    tabs = {
        [1] = { title = "numeric built-in" },
        ["builtin.general"] = { title = "string built-in" },
        ["trpc-custom-1"] = {
            title = "  private\r\n",
            inputChannel = "pm",
            filters = {
                channels = { "pm", "unknown", "" },
                excludedChannels = { "pm", "ooc", "unknown", "" },
                sources = { "network", "invalid" },
                directions = { "incoming", "sideways", "outgoing" },
                authors = { "alice", "" },
                targets = {},
                kinds = { "private", "unknown" },
                frequencies = { 101, "bad" },
                isPrivate = true,
                includeSystem = false,
                isFromDiscord = "not a boolean",
                empty = { "discarded" },
            },
        },
        ["trpc-custom-2"] = {
            title = "PRIVATE",
            inputChannel = "not-a-channel",
            filters = { channels = { "bogus" } },
        },
        ["trpc-custom-3"] = {
            title = string.rep("x", TabDefinitions.MAX_TITLE_LENGTH + 8),
            inputChannel = "say",
            filters = { channels = {} },
        },
        ["trpc-custom-4"] = {
            title = "   \t\r\n",
        },
    },
    activeTabID = "missing-custom-tab",
}

local normalized, normalizedStatus, normalizedChanged = TabDefinitions.normalize(raw)
AssertEqual(normalizedStatus, TabDefinitions.STATUS_NORMALIZED, "normalized state status")
assert(normalizedChanged, "invalid data is reported as changed")
assert(normalized ~= raw and normalized.tabs ~= raw.tabs, "normalization returns fresh tables")
AssertEqual(raw.tabs["trpc-custom-1"].title, "  private\r\n", "raw title is not mutated")
AssertArray(normalized.order, { "trpc-custom-2", "trpc-custom-1", "trpc-custom-3" }, "repaired order")
AssertEqual(normalized.tabs["trpc-custom-2"].title, "PRIVATE", "first duplicate title is retained")
AssertEqual(normalized.tabs["trpc-custom-1"].title, "private (2)", "duplicate title repair is case insensitive")
AssertEqual(#normalized.tabs["trpc-custom-3"].title, TabDefinitions.MAX_TITLE_LENGTH, "title length is bounded")
AssertAbsent(normalized.tabs, "trpc-custom-4", "empty titles are rejected")
AssertAbsent(normalized.tabs, 1, "numeric built-in definitions are rejected")
AssertAbsent(normalized.tabs, "builtin.general", "string built-in definitions are rejected")
AssertEqual(normalized.tabs["trpc-custom-2"].inputChannel, "say", "invalid input channels use the safe fallback")
AssertEqual(normalized.tabs["trpc-custom-1"].inputChannel, "pm", "known input channels are retained")
local scriptedRadioFilter = TabDefinitions.normalizeFilters({ channels = { "scriptedRadio" } })
AssertArray(
    scriptedRadioFilter.channels,
    { "scriptedRadio" },
    "server-driven channels remain valid display filter values"
)
local radioCategoryFilter = TabDefinitions.normalizeFilters({ channels = { "radio" } })
AssertArray(radioCategoryFilter.channels, { "radio" }, "radio remains a valid display filter category")

local serverDrivenInput = TabDefinitions.normalize({
    schemaVersion = 1,
    nextCustomID = 1,
    order = { "trpc-custom-1" },
    tabs = {
        ["trpc-custom-1"] = { title = "Server driven", inputChannel = "scriptedRadio" },
    },
    activeTabID = "builtin.general",
})
AssertEqual(
    serverDrivenInput.tabs["trpc-custom-1"].inputChannel,
    TabDefinitions.DEFAULT_INPUT_CHANNEL,
    "server-driven channels use the safe input fallback"
)
AssertEqual(normalized.activeTabID, "builtin.general", "invalid active IDs use General")

local privateFilter = normalized.tabs["trpc-custom-1"].filters
AssertArray(privateFilter.channels, { "pm" }, "unknown channel filter values are removed")
AssertArray(privateFilter.excludedChannels, { "pm", "ooc" }, "excluded channel values are normalized")
AssertArray(privateFilter.sources, { "network" }, "unknown source filter values are removed")
AssertArray(privateFilter.directions, { "incoming", "outgoing" }, "unknown direction values are removed")
AssertArray(privateFilter.authors, { "alice" }, "empty author values are removed")
AssertAbsent(privateFilter, "targets", "empty filter dimensions are removed")
AssertArray(privateFilter.kinds, { "private" }, "unknown kind values are removed")
AssertArray(privateFilter.frequencies, { 101 }, "invalid frequency values are removed")
AssertEqual(privateFilter.isPrivate, true, "isPrivate boolean is preserved")
AssertEqual(privateFilter.includeSystem, false, "includeSystem boolean is preserved")
AssertAbsent(privateFilter, "isFromDiscord", "invalid boolean values are removed")
AssertAbsent(privateFilter, "empty", "unknown filter dimensions are removed")
AssertEqual(normalized.tabs["trpc-custom-3"].filters.channels, nil, "empty dimensions are omitted")

local counterRepair = TabDefinitions.normalize({
    schemaVersion = 1,
    nextCustomID = 1,
    order = { "trpc-custom-7" },
    tabs = {
        ["trpc-custom-7"] = { title = "Seven" },
    },
    activeTabID = "trpc-custom-7",
})
AssertEqual(counterRepair.nextCustomID, 8, "counter advances beyond observed IDs")
local allocatedID, allocatedState = TabDefinitions.allocateCustomID(counterRepair)
AssertEqual(allocatedID, "trpc-custom-8", "allocation uses the persisted counter")
AssertEqual(counterRepair.nextCustomID, 8, "allocation does not mutate the input state")
AssertEqual(allocatedState.nextCustomID, 9, "allocation advances the returned state")
local allocatedAgain = TabDefinitions.allocateCustomID(allocatedState)
AssertEqual(allocatedAgain, "trpc-custom-9", "deleted IDs are not reused")

local futureRaw = {
    schemaVersion = 99,
    nextCustomID = 100,
    order = { "trpc-custom-99" },
    tabs = { ["trpc-custom-99"] = { title = "Future" } },
    futureOnly = { callback = function() end },
}
local future, futureStatus, futureChanged = TabDefinitions.normalize(futureRaw)
AssertEqual(futureStatus, TabDefinitions.STATUS_UNSUPPORTED, "future schema status")
assert(not futureChanged, "future schema is not marked for destructive repair")
assert(future ~= futureRaw and future.futureOnly ~= futureRaw.futureOnly, "future state is copied before return")
AssertEqual(future.schemaVersion, 99, "future schema version is preserved")
AssertEqual(future.tabs["trpc-custom-99"].title, "Future", "future definitions are preserved")

local stored = {
    schemaVersion = 1,
    nextCustomID = 2,
    order = { "trpc-custom-1" },
    tabs = {
        ["trpc-custom-1"] = {
            title = "Stored",
            inputChannel = "say",
            filters = {},
        },
    },
    activeTabID = "trpc-custom-1",
}
local getCalls = 0
local addCalls = 0
local addedKey
local addedState
_G.ModData = {
    get = function(key)
        getCalls = getCalls + 1
        AssertEqual(key, TabDefinitions.KEY, "ModData load key")
        return stored
    end,
    add = function(key, value)
        addCalls = addCalls + 1
        addedKey = key
        addedState = value
    end,
}

local loaded, loadedStatus = TabDefinitions.load()
AssertEqual(getCalls, 1, "ModData get is called once")
AssertEqual(loadedStatus, TabDefinitions.STATUS_OK, "ModData load status")
assert(loaded ~= stored and loaded.tabs ~= stored.tabs, "ModData load returns normalized fresh data")

local saved, savedState, savedStatus = TabDefinitions.save(stored)
assert(saved, "ModData save succeeds")
AssertEqual(savedStatus, TabDefinitions.STATUS_OK, "ModData save status")
AssertEqual(addCalls, 1, "ModData add is called once")
AssertEqual(addedKey, TabDefinitions.KEY, "ModData save key")
assert(savedState == addedState, "ModData receives the normalized state")

stored.schemaVersion = 99
local futureLoaded, futureLoadedStatus = TabDefinitions.load()
AssertEqual(futureLoadedStatus, TabDefinitions.STATUS_UNSUPPORTED, "future ModData load status")
AssertEqual(futureLoaded.schemaVersion, 99, "future ModData state is not overwritten")
local futureSaved = TabDefinitions.save(stored)
assert(not futureSaved, "future schema is not saved destructively")
AssertEqual(addCalls, 1, "future schema does not call ModData add")

_G.ModData = nil
local unavailableState, unavailableStatus = TabDefinitions.load()
AssertEqual(unavailableStatus, TabDefinitions.STATUS_UNAVAILABLE, "missing ModData runtime status")
AssertEqual(unavailableState.schemaVersion, 1, "missing ModData uses an empty state")

print("custom tab definition tests passed")
