package.path = "42/media/lua/client/?.lua;42/media/lua/shared/?.lua;" .. package.path

local MessageStore = require("trpc/client/chat/MessageStore")
local TabFilters = require("trpc/client/chat/TabFilters")

local function AssertEqual(actual, expected, message)
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local chatMessage = {
    channel = "say",
    author = "alice",
    source = "network",
    direction = "incoming",
    kind = "chat",
}

assert(TabFilters.matches(chatMessage, nil), "an absent filter matches every record")
assert(TabFilters.matches(chatMessage, { channels = { "say", "yell" } }), "values in one dimension use OR")
assert(not TabFilters.matches(chatMessage, { channels = { "pm" } }), "a channel filter excludes other channels")
local excludedChannels = { excludedChannels = { "pm", "ooc" } }
assert(TabFilters.matches(chatMessage, excludedChannels), "excluded channels leave other channels visible")
assert(not TabFilters.matches({ channel = "pm" }, excludedChannels), "excluded channels hide PM")
assert(not TabFilters.matches({ channel = "ooc" }, excludedChannels), "excluded channels hide OOC")
assert(TabFilters.matches({}, excludedChannels), "missing channel metadata is not rejected by exclusions")
assert(
    TabFilters.matches({ channel = "pm" }, { channels = { "pm" } })
        and not TabFilters.matches({ channel = "say" }, { channels = { "pm" } }),
    "built-in channel filters retain include semantics"
)
assert(
    TabFilters.matches(chatMessage, { channels = { "say", "yell" }, authors = { "alice", "bob" } }),
    "dimensions use AND"
)
assert(
    not TabFilters.matches(chatMessage, { channels = { "say" }, authors = { "charlie" } }),
    "a non-matching dimension excludes the record"
)
assert(TabFilters.matches(chatMessage, { channel = "say", author = "alice" }), "singular aliases are supported")
assert(
    TabFilters.matches(
        { channel = "say", author = "alice", characterName = "Alice" },
        { authors = { "Alice" } }
    ),
    "author filters match character names"
)
assert(
    TabFilters.matches(
        { channel = "say", author = "alice", characterName = "Alice" },
        { authors = { "alice", "charlie" } }
    ),
    "author filters preserve OR semantics across author fields"
)
assert(
    not TabFilters.matches(
        { channel = "say", author = "alice", characterName = "Alice" },
        { authors = { "charlie" } }
    ),
    "author filters reject both unmatched author fields"
)
local radioRecord = MessageStore.createRecord({
    channel = "say",
    source = "radio",
    kind = "radio",
})
assert(
    TabFilters.matches(radioRecord, { channels = { "radio" } }),
    "the radio display category matches radio-routed messages"
)
assert(
    TabFilters.matches(
        MessageStore.createRecord({ channel = "scriptedRadio", source = "radio", kind = "radio" }),
        { channels = { "radio" } }
    ),
    "the radio display category includes scripted radio messages"
)
assert(
    not TabFilters.matches(chatMessage, { channels = { "radio" } }),
    "the radio display category excludes ordinary chat messages"
)
local radioStore = MessageStore.new()
radioStore:registerView(1)
radioStore:registerView("trpc-custom-radio", { channels = { "radio" } })
local _, radioViews = radioStore:append(radioRecord)
AssertEqual(radioViews[2], "trpc-custom-radio", "radio filters route radio messages to custom views")
local excludedStore = MessageStore.new()
excludedStore:registerView(1)
excludedStore:registerView("trpc-custom-excluded", { excludedChannels = { "pm", "ooc" } })
local _, visibleViews = excludedStore:append({ channel = "say" })
AssertEqual(visibleViews[2], "trpc-custom-excluded", "excluded-channel views retain visible channels")
local _, hiddenViews = excludedStore:append({ channel = "pm" })
AssertEqual(#hiddenViews, 1, "excluded-channel views hide excluded channels")
local systemMessage = {
    channel = "say",
    isSystem = true,
    kind = "system",
}
assert(not TabFilters.matches(systemMessage, { includeSystem = false }), "includeSystem=false excludes system records")
assert(TabFilters.matches(systemMessage, { includeSystem = true }), "includeSystem=true allows system records")
assert(TabFilters.matches(systemMessage, {}), "an omitted includeSystem allows system records")
assert(TabFilters.matches({}, { includeSystem = false }), "missing system metadata is not rejected")
local systemPMMessage = { channel = "pm", isSystem = true, kind = "system" }
assert(
    not TabFilters.matches(systemPMMessage, { channels = { "pm" }, includeSystem = false })
        and TabFilters.matches(systemPMMessage, nil),
    "the built-in PM filter excludes system PM records while General includes them"
)

local privateMessage = MessageStore.createRecord({ channel = "pm" })
AssertEqual(privateMessage.isPrivate, true, "PM channels normalize to private records")
AssertEqual(privateMessage.kind, "private", "private records receive a private default kind")
assert(TabFilters.matches(privateMessage, { isPrivate = true }), "private filters match normalized private metadata")
assert(TabFilters.matches(privateMessage, { private = true }), "private aliases are supported")
assert(not TabFilters.matches(chatMessage, { isPrivate = true }), "private filters exclude public records")

local kindSystemMessage = MessageStore.createRecord({ kind = "system" })
local sourceSystemMessage = MessageStore.createRecord({ source = "server" })
AssertEqual(kindSystemMessage.isSystem, true, "system kind normalizes to system metadata")
AssertEqual(sourceSystemMessage.isSystem, true, "system sources normalize to system metadata")
assert(
    not TabFilters.matches(sourceSystemMessage, { includeSystem = false }),
    "normalized system sources honor includeSystem"
)

local invalidMaxStore = MessageStore.new(0)
AssertEqual(
    invalidMaxStore.maxMessages,
    MessageStore.DEFAULT_MAX_MESSAGES,
    "invalid maxMessages values use the safe default"
)

local systemStore = MessageStore.new(2)
systemStore:registerView(1)
systemStore:registerView(2, { channels = { "server" }, includeSystem = false })
local systemRecord, systemViews = systemStore:append({ channel = "server", source = "server" })
AssertEqual(systemRecord.isSystem, true, "server records normalize as system records")
AssertEqual(#systemViews, 1, "system records still reach the unfiltered General view")
AssertEqual(systemViews[1], 1, "General is the system record projection")

local store = MessageStore.new(2)
store:registerView(1)
store:registerView(2, { channels = { "ooc" } })
store:registerView(3, { channels = { "pm" } })

local firstRecord, firstViews = store:append(chatMessage)
AssertEqual(firstRecord.id, 1, "records receive stable sequence ids")
AssertEqual(firstRecord.type, "say", "channel and type are normalized together")
AssertEqual(#firstViews, 1, "say is projected only to General")
AssertEqual(firstViews[1], 1, "General is the unfiltered view")

local secondRecord, secondViews = store:append({
    channel = "ooc",
    author = "bob",
    source = "network",
    kind = "chat",
})
AssertEqual(secondRecord.id, 2, "the second record increments the sequence")
AssertEqual(#secondViews, 2, "OOC is projected to General and OOC")
AssertEqual(secondViews[1], 1, "General remains the first projection")
AssertEqual(secondViews[2], 2, "the channel projection is included")

local thirdRecord, thirdViews = store:append({
    channel = "pm",
    author = "alice",
    target = "bob",
    source = "network",
    kind = "private",
})
AssertEqual(thirdRecord.id, 3, "the third record increments the sequence")
AssertEqual(thirdRecord.kind, "private", "message kind is retained")
AssertEqual(#thirdViews, 2, "private messages are projected to General and PM")
AssertEqual(thirdViews[2], 3, "the PM projection is included")
AssertEqual(#store:getMessages(), 2, "history is bounded")
AssertEqual(store:getMessages()[1].id, 2, "the oldest record is evicted first")

local filteredStore = MessageStore.new(2)
filteredStore:registerView(1, { channels = { "ooc" } })
local _, unmatchedViews = filteredStore:append({ channel = "say" })
AssertEqual(#unmatchedViews, 0, "nonmatching records are not routed to a filter view")
AssertEqual(#filteredStore:getViewIDs(), 1, "a registered view remains distinct from a no-match result")
AssertEqual(#filteredStore:getMessagesForView(1), 0, "nonmatching history stays excluded")

local routeStore = MessageStore.new(2)
routeStore:registerView(1)
routeStore:registerView(2)
routeStore:registerView(3)
local _, deduplicatedViews = routeStore:append({ channel = "say" }, { 3, 3, 2 })
AssertEqual(#deduplicatedViews, 2, "explicit routes deduplicate target views")
AssertEqual(deduplicatedViews[1], 3, "explicit route order is preserved")
AssertEqual(deduplicatedViews[2], 2, "explicit route retains later unique targets")

local _, explicitViews = store:append({ channel = "say", kind = "system" }, { 2 })
AssertEqual(#explicitViews, 1, "legacy routes can target an explicit tab")
AssertEqual(explicitViews[1], 2, "explicit routes bypass projection matching")
local oocMessages = store:getMessagesForView(2)
AssertEqual(#oocMessages, 1, "explicit routes remain visible in their target projection")
AssertEqual(oocMessages[1].id, 4, "explicit route target is preserved in canonical history")
local generalMessages = store:getMessagesForView(1)
AssertEqual(#generalMessages, 1, "explicit routes do not leak into other projections")
AssertEqual(generalMessages[1].id, 3, "filter projections retain their own matching history")

local _, emptyViews = store:append({ channel = "say", kind = "system" }, {})
AssertEqual(#emptyViews, 0, "an explicit empty route targets no projections")
AssertEqual(#store:getMessagesForView(1), 0, "an explicit empty route stays excluded from history queries")

local normalizedFilter = store:registerView(4, { channel = "pm" })
AssertEqual(normalizedFilter.channels, "pm", "registered filters use canonical dimension names")
AssertEqual(store:getViewFilter(4).channels, "pm", "stored filters remain canonical")

local orderedIDs = store:setViewOrder({ 3, 3, "unknown", 2 })
AssertEqual(#orderedIDs, 4, "view order retains every registered view once")
AssertEqual(orderedIDs[1], 1, "view order keeps General first")
AssertEqual(orderedIDs[2], 3, "view order preserves requested custom ordering")
AssertEqual(orderedIDs[3], 2, "view order preserves later requested IDs")
AssertEqual(orderedIDs[4], 4, "view order appends omitted registered IDs deterministically")

local projectionOrderStore = MessageStore.new()
projectionOrderStore:registerView(1)
projectionOrderStore:registerView("trpc-custom-1", { channels = { "ooc" } })
projectionOrderStore:setViewOrder({ "trpc-custom-1", 1, "trpc-custom-1" })
local _, projectionIDs = projectionOrderStore:append({ channel = "ooc" })
AssertEqual(projectionIDs[1], 1, "projection matching follows the deterministic General-first order")
AssertEqual(projectionIDs[2], "trpc-custom-1", "projection matching remains filter-based for custom views")
AssertEqual(#projectionOrderStore:getMessagesForView("trpc-custom-1"), 1, "custom projections replay canonical history")

print("custom chat tab foundation tests passed")
