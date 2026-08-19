package.path = "42/media/lua/client/?.lua;42/media/lua/shared/?.lua;" .. package.path

local function AssertEqual(actual, expected, message)
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local LocalPreferences = require("trpc/client/LocalPreferences")

local state = {
    playerColor = { 1, 2, 3 },
    trpcChatTabs = { sentinel = true },
    localChatPreferences = {
        ignoredPlayers = { Alice = "Alice" },
        mutedChannels = { ooc = true },
        mutedRadioFrequencies = { [101] = true },
        radioPresets = { [101] = "Main" },
    },
}
local addedKey
local addedValue
_G.ModData = {
    get = function(key)
        AssertEqual(key, "trpc", "local preferences load key")
        return state
    end,
    getOrCreate = function(key)
        AssertEqual(key, "trpc", "local preferences save key")
        return state
    end,
    add = function(key, value)
        addedKey = key
        addedValue = value
        state = value
    end,
}

local loaded = LocalPreferences.load()
assert(LocalPreferences.isIgnoredPlayer("alice"), "ignored player lookup is case insensitive")
assert(LocalPreferences.shouldSuppress({ author = "ALICE", channel = "say" }), "ignored author suppresses before rendering")
assert(LocalPreferences.shouldSuppress({ channel = "OOC" }), "muted channel suppresses before rendering")
assert(LocalPreferences.shouldSuppress({ channel = "say", radioFrequency = 101 }), "muted frequency suppresses radio traffic")
assert(not LocalPreferences.shouldSuppress({ author = "Bob", channel = "say", radioFrequency = 102 }), "unmuted traffic remains visible")
AssertEqual(LocalPreferences.getRadioPresets()["101"], "Main", "radio preset labels normalize numeric keys")

local saved, savedState = LocalPreferences.setChannelMuted("ooc", false)
assert(saved, "local preference changes persist")
AssertEqual(addedKey, "trpc", "local preference save does not use the tab key")
assert(addedValue.trpcChatTabs.sentinel, "local preference save preserves trpcChatTabs")
assert(savedState.mutedChannels.ooc == nil, "channel mute can be removed")
assert(state.playerColor[1] == 1, "existing player preferences remain intact")
assert(state.trpcChatTabs.sentinel, "tab preferences remain isolated")

local presetSaved, presetState = LocalPreferences.setRadioPreset(" 103 ", " Backup ", true)
assert(presetSaved, "radio preset changes persist")
AssertEqual(presetState.radioPresets["103"], "Backup", "radio preset frequency and label normalize")
local presetRemoved = LocalPreferences.setRadioPreset(103, nil, false)
assert(presetRemoved, "radio preset can be removed")
assert(LocalPreferences.getRadioPresets()["103"] == nil, "removed radio preset is absent")
assert(state.trpcChatTabs.sentinel, "radio preset save keeps tab preferences isolated")

print("local preference tests passed")
