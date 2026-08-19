package.path = "42/media/lua/client/?.lua;42/media/lua/shared/?.lua;" .. package.path

local function AssertEqual(actual, expected, message)
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function NewTab()
    local tab = {
        chatTextLines = {},
        chatTextRawLines = {},
        maxLines = 100,
    }
    function tab:setUIName(value)
        self.uiName = value
    end
    function tab:setY(value)
        self.y = value
    end
    function tab:setHeight(value)
        self.height = value
    end
    function tab:setWidth(value)
        self.width = value
    end
    function tab:setVisible(value)
        self.visible = value
    end
    return tab
end

_G.UIFont = { Small = "small" }
local textManager = {}
function textManager:MeasureStringX(_, title)
    return #title * 10
end
_G.getTextManager = function()
    return textManager
end

local panel = {
    viewList = {},
    blinkTabs = {},
    tabPadX = 4,
    activateByIdCalls = 0,
    activateByNameCalls = 0,
}
function panel:setVisible(value)
    self.visible = value
end
function panel:addView(name, view)
    table.insert(self.viewList, {
        name = name,
        view = view,
        id = #self.viewList + 1,
        tabWidth = #name * 10 + self.tabPadX,
    })
    self.activeView = self.activeView or self.viewList[#self.viewList]
end
function panel:removeView(view)
    for index, entry in ipairs(self.viewList) do
        if entry.view == view then
            table.remove(self.viewList, index)
            if self.activeView == entry then
                self.activeView = self.viewList[1]
            end
            return
        end
    end
end
function panel:activateViewById(id)
    for _, entry in ipairs(self.viewList) do
        if entry.id == id then
            if self.activeView and self.activeView.view ~= entry.view then
                self.activeView.view:setVisible(false)
            end
            entry.view:setVisible(true)
            self.activeView = entry
            self.activateByIdCalls = self.activateByIdCalls + 1
            if self.target and self.target.onActivateView then
                self.target:onActivateView()
            end
            return true
        end
    end
    return false
end
function panel:getWidthOfAllTabs()
    local width = 0
    for _, entry in ipairs(self.viewList) do
        width = width + (entry.tabWidth or 0)
    end
    return width
end
function panel:activateView(name)
    self.activateByNameCalls = self.activateByNameCalls + 1
    for _, entry in ipairs(self.viewList) do
        if entry.name == name then
            self.activeView = entry
            if self.target and self.target.onActivateView then
                self.target:onActivateView()
            end
            return true
        end
    end
    return false
end

local chat = {
    tabCnt = 0,
    panel = panel,
    inset = 2,
    minimumWidth = 200,
}
panel.target = chat
function chat:createTab()
    return NewTab()
end
function chat:addChild(child)
    self.child = child
end
function chat:removeChild(child)
    if self.child == child then
        self.child = nil
    end
end
function chat:calcTabPos()
    return { y = 0 }
end
function chat:calcTabSize()
    return { width = 400, height = 150 }
end
function chat:onActivateView()
    if self.tabCnt > 1 and self.panel.activeView then
        self.chatText = self.panel.activeView.view
    end
end

_G.ISChat = { instance = chat }
local Streams = require("trpc/client/chat/Streams")
ISChat.allChatStreams = Streams.allChatStreams
ISChat.defaultTabStream = Streams.defaultTabStream
ISChat.lastTabStream = Streams.lastTabStream

_G.TrpcServerSettings = {}
for _, stream in ipairs(Streams.allChatStreams) do
    TrpcServerSettings[stream.name] = { enabled = true }
end

local MessageStore = require("trpc/client/chat/MessageStore")
local ChatState = require("trpc/client/ui/ChatState")
local Tabs = require("trpc/client/ui/Tabs")
local TabDefinitions = require("trpc/client/ui/TabDefinitions")

local storedState = {
    schemaVersion = 1,
    nextCustomID = 3,
    order = { "trpc-custom-1", "trpc-custom-2" },
    tabs = {
        ["trpc-custom-1"] = {
            title = "Private",
            inputChannel = "pm",
            filters = { excludedChannels = { "say", "ooc" } },
        },
        ["trpc-custom-2"] = {
            title = "Radio",
            inputChannel = "say",
            filters = { kinds = { "radio" } },
        },
    },
    activeTabID = "trpc-custom-1",
}
local savedState
local saveCalls = 0
_G.ModData = {
    get = function(key)
        AssertEqual(key, TabDefinitions.KEY, "runtime load key")
        return storedState
    end,
    add = function(key, value)
        AssertEqual(key, TabDefinitions.KEY, "runtime save key")
        saveCalls = saveCalls + 1
        savedState = value
    end,
}

ChatState.setTabs({})
ChatState.resetMessageStore()
Streams.resetTabStreams()
Tabs.resetPersistedDefinitions()
local rebuildCounts = {}
Tabs.setHistoryRebuilder(function(tabID)
    rebuildCounts[tabID] = (rebuildCounts[tabID] or 0) + 1
end)

local definitions, status = Tabs.loadPersistedDefinitions()
AssertEqual(status, TabDefinitions.STATUS_OK, "runtime definition status")
AssertEqual(definitions.order[1], "trpc-custom-1", "persisted custom order")
Tabs.addTab("General", 1)
assert(Tabs.registerPersistedDefinitions(), "persisted definitions register")

local privateTab = ChatState.getTabs()["trpc-custom-1"]
AssertEqual(privateTab.tabTitle, "Private", "persisted title reaches runtime")
AssertEqual(privateTab.inputChannel, "pm", "persisted input channel reaches runtime")
AssertEqual(privateTab.chatStreams[1].name, "pm", "custom input stream is mapped")
assert(Streams.isStreamForTab("trpc-custom-1", privateTab.chatStreams[1]), "custom stream belongs to custom tab")
AssertEqual(
    ChatState.getMessageStore():getViewFilter("trpc-custom-1").excludedChannels[1],
    "say",
    "persisted excluded-channel filter is registered"
)

local serverDrivenID, serverDrivenDefinition = Tabs.createCustomTab({
    title = "Server driven input",
    inputChannel = "scriptedRadio",
})
AssertEqual(serverDrivenID, "trpc-custom-3", "server-driven input allocation remains ordered")
AssertEqual(
    serverDrivenDefinition.inputChannel,
    TabDefinitions.DEFAULT_INPUT_CHANNEL,
    "server-driven input uses the safe runtime fallback"
)
AssertEqual(
    ChatState.getTabs()[serverDrivenID].chatStreams[1].name,
    TabDefinitions.DEFAULT_INPUT_CHANNEL,
    "server-driven input maps to a command stream"
)

Tabs.addTab("Private", 3)
assert(Tabs.activateTab(3), "built-in tab with duplicate title activates")
AssertEqual(ChatState.getCurrentTabID(), 3, "duplicate title keeps built-in identity")
AssertEqual(chat.panel.activeView.view.tabID, 3, "duplicate title activates the built-in view")
assert(Tabs.activateTab("trpc-custom-1"), "custom tab with duplicate title activates")
AssertEqual(ChatState.getCurrentTabID(), "trpc-custom-1", "duplicate title keeps custom identity")
AssertEqual(chat.panel.activeView.view.tabID, "trpc-custom-1", "duplicate title activates the custom view")
AssertEqual(chat.panel.activateByNameCalls, 0, "runtime activation does not use title lookup")

local record, viewIDs = ChatState.getMessageStore():append({
    channel = "pm",
    author = "alice",
    source = "network",
    kind = "private",
})
AssertEqual(record.id, 1, "runtime message store assigns a sequence")
AssertEqual(viewIDs[1], 1, "General receives the projected message")
AssertEqual(viewIDs[2], "trpc-custom-1", "custom view receives the projected message")
AssertEqual(#ChatState.getMessageStore():getMessagesForView("trpc-custom-1"), 1, "custom history is queryable")
assert(Tabs.clearTabHistory("trpc-custom-1"), "clear custom tab history succeeds")
AssertEqual(#ChatState.getMessageStore():getMessagesForView("trpc-custom-1"), 0, "clear removes only the selected view history")
AssertEqual(#ChatState.getMessageStore():getMessagesForView(1), 1, "clear preserves General history")

assert(Tabs.activatePersistedTab(), "persisted active tab is restored")
AssertEqual(ChatState.getCurrentTabID(), "trpc-custom-1", "persisted active ID maps to runtime")

local newID, newDefinition = Tabs.createCustomTab({
    title = "Recent Private",
    inputChannel = "say",
    filters = { excludedChannels = { "say", "ooc" } },
})
AssertEqual(newID, "trpc-custom-4", "runtime allocation advances persisted ID")
AssertEqual(newDefinition.title, "Recent Private", "runtime create returns normalized definition")
AssertEqual(
    ChatState.getMessageStore():getViewFilter(newID).excludedChannels[1],
    "say",
    "runtime create registers excluded-channel filters"
)
AssertEqual(#ChatState.getMessageStore():getMessagesForView(newID), 1, "new custom view can query existing history")
assert(rebuildCounts[newID] ~= nil, "new custom view rebuilds from canonical history")

Tabs.addTab("Admin", 4)
Tabs.addTab("Out Of Character", 2)
for _, builtinID in ipairs({ 1, 2, 3, 4 }) do
    assert(not Tabs.setTabFilter(builtinID, { channels = { "say" } }), "built-in filter changes are rejected")
end
assert(Tabs.removeTab("Out Of Character", 2), "temporary built-in tab removal succeeds")
local orderedIDs = Tabs.reconcileDisplayOrder()
AssertEqual(orderedIDs[1], 1, "General remains first after late built-in add")
AssertEqual(orderedIDs[2], 3, "enabled built-in remains before custom tabs")
AssertEqual(orderedIDs[3], 4, "late built-in is placed before custom tabs")
AssertEqual(orderedIDs[4], "trpc-custom-1", "custom tabs remain after built-ins")

local updated, updatedDefinition = Tabs.updateCustomTab("trpc-custom-1", {
    title = "Private Updated",
    inputChannel = "ooc",
    filters = { excludedChannels = { "say" } },
})
assert(updated, "runtime update succeeds")
AssertEqual(updatedDefinition.title, "Private Updated", "runtime update persists title")
AssertEqual(ChatState.getTabs()["trpc-custom-1"].chatStreams[1].name, "ooc", "runtime update refreshes input stream")
AssertEqual(
    ChatState.getMessageStore():getViewFilter("trpc-custom-1").excludedChannels[1],
    "say",
    "runtime update refreshes excluded-channel filter"
)
AssertEqual(ChatState.getTabs()["trpc-custom-1"].tabTitle, "Private Updated", "runtime update refreshes runtime title")
for _, panelView in ipairs(chat.panel.viewList) do
    if panelView.tabID == "trpc-custom-1" then
        AssertEqual(panelView.tabWidth, #"Private Updated" * 10 + chat.panel.tabPadX, "runtime rename refreshes native tab width")
    end
end

local fallbackID, _, fallbackStatus = Tabs.createCustomTab({
    title = "Fallback",
    activeTabID = 2,
})
AssertEqual(fallbackStatus, "active-fallback", "create reports unavailable active target fallback")
AssertEqual(Tabs.getPersistedDefinitions().activeTabID, TabDefinitions.BUILTIN_IDS.general, "create persists General fallback")
AssertEqual(ChatState.getCurrentTabID(), 1, "create activates General fallback")

local fallbackUpdated, _, fallbackUpdateStatus = Tabs.updateCustomTab("trpc-custom-1", {
    activeTabID = 2,
})
assert(fallbackUpdated, "update with unavailable active target succeeds")
AssertEqual(fallbackUpdateStatus, "active-fallback", "update reports unavailable active target fallback")
AssertEqual(Tabs.getPersistedDefinitions().activeTabID, TabDefinitions.BUILTIN_IDS.general, "update persists General fallback")
AssertEqual(fallbackID, "trpc-custom-5", "fallback custom tab allocation remains stable")

local removed = Tabs.removeCustomTab("trpc-custom-2")
assert(removed, "runtime delete succeeds")
assert(ChatState.getTabs()["trpc-custom-2"] == nil, "runtime delete removes the tab")
assert(ChatState.getMessageStore():getViewFilter("trpc-custom-2") == nil, "runtime delete unregisters the view")

ChatState.setCurrentTabID(serverDrivenID)
ChatState.getTabs()[serverDrivenID] = nil
local removedWithoutRuntimeTab = Tabs.removeCustomTab(serverDrivenID)
assert(removedWithoutRuntimeTab, "delete succeeds when the runtime tab is already absent")
AssertEqual(ChatState.getCurrentTabID(), 1, "missing active runtime tab falls back to General")
assert(ChatState.getMessageStore():getViewFilter(serverDrivenID) == nil, "missing runtime tab unregisters its view")
assert(savedState ~= nil, "runtime changes are persisted")

local applyDraft = TabDefinitions.normalize(Tabs.getPersistedDefinitions())
local applyID, allocatedApplyState = TabDefinitions.allocateCustomID(applyDraft)
applyDraft = allocatedApplyState
applyDraft.tabs["trpc-custom-1"] = {
    title = "Applied Private",
    inputChannel = "ooc",
    filters = { excludedChannels = { "say" } },
}
applyDraft.tabs["trpc-custom-4"] = nil
local applyOrder = {}
for _, tabID in ipairs(applyDraft.order) do
    if tabID ~= "trpc-custom-4" then
        table.insert(applyOrder, tabID)
    end
end
table.insert(applyOrder, 1, applyID)
applyDraft.order = applyOrder
applyDraft.tabs[applyID] = {
    title = "Applied New",
    inputChannel = "pm",
    filters = { excludedChannels = { "ooc" } },
}
applyDraft.activeTabID = applyID

local applySaveStart = saveCalls
local applied, appliedState, applyStatus = Tabs.applyCustomTabState(applyDraft)
assert(applied, "complete draft state applies")
AssertEqual(saveCalls, applySaveStart + 1, "complete draft state saves once")
AssertEqual(applyStatus, "ok", "complete draft state reports save status")
AssertEqual(appliedState.order[1], applyID, "complete draft state preserves custom order")
AssertEqual(appliedState.activeTabID, applyID, "complete draft state preserves active custom ID")
AssertEqual(ChatState.getTabs()[applyID].chatStreams[1].name, "pm", "complete draft state refreshes input streams")
AssertEqual(
    ChatState.getMessageStore():getViewFilter(applyID).excludedChannels[1],
    "ooc",
    "complete draft state refreshes excluded-channel filters"
)
assert(ChatState.getTabs()["trpc-custom-4"] == nil, "complete draft state removes deleted runtime tabs")
assert(ChatState.getMessageStore():getViewFilter("trpc-custom-4") == nil, "complete draft state unregisters deleted views")
assert(rebuildCounts[applyID] ~= nil, "complete draft state rebuilds new views from history")
AssertEqual(ChatState.getCurrentTabID(), applyID, "complete draft state activates the stable custom ID")

local fallbackDraft = TabDefinitions.normalize(appliedState)
fallbackDraft.activeTabID = TabDefinitions.BUILTIN_IDS.ooc
local fallbackSaveStart = saveCalls
local fallbackApplied, fallbackState = Tabs.applyCustomTabState(fallbackDraft)
assert(fallbackApplied, "unavailable active built-in falls back successfully")
AssertEqual(saveCalls, fallbackSaveStart + 1, "active fallback still saves once")
AssertEqual(fallbackState.activeTabID, TabDefinitions.BUILTIN_GENERAL_ID, "unavailable active built-in persists General")
AssertEqual(ChatState.getCurrentTabID(), 1, "unavailable active built-in activates General")

local invalidSaveStart = saveCalls
local invalidApplied = Tabs.applyCustomTabState({ schemaVersion = 99 })
assert(not invalidApplied, "unsupported draft state is rejected")
AssertEqual(saveCalls, invalidSaveStart, "rejected draft state does not persist")

local availableModData = ModData
ModData = nil
local unavailableSaveStart = saveCalls
local unavailableApplied, unavailableStatus = Tabs.applyCustomTabState(fallbackState)
assert(not unavailableApplied, "unavailable persistence is rejected")
AssertEqual(unavailableStatus, TabDefinitions.STATUS_UNAVAILABLE, "unavailable persistence reports its status")
AssertEqual(saveCalls, unavailableSaveStart, "unavailable persistence does not partially persist")
ModData = availableModData

local duplicateID, duplicateDefinition = Tabs.duplicateCustomTab(applyID)
assert(duplicateID ~= nil, "runtime duplicate allocates a new custom ID")
AssertEqual(duplicateDefinition.inputChannel, "pm", "runtime duplicate preserves input channel")
AssertEqual(duplicateDefinition.title, "Applied New Copy", "runtime duplicate gets a safe title")
local duplicateIndex
for index, tabID in ipairs(Tabs.getPersistedDefinitions().order) do
    if tabID == duplicateID then
        duplicateIndex = index
    end
end
assert(duplicateIndex ~= nil, "runtime duplicate is inserted into custom order")

local reorderIDs = { duplicateID, applyID }
local reordered = Tabs.reorderCustomTabs(reorderIDs)
assert(reordered, "runtime custom reorder persists")
AssertEqual(Tabs.getPersistedDefinitions().order[1], duplicateID, "runtime custom reorder keeps requested first ID")

local restoredDefaults = Tabs.restoreDefaultTabs()
assert(restoredDefaults, "runtime default restoration succeeds")
AssertEqual(#Tabs.getPersistedDefinitions().order, 0, "default restoration removes custom definitions")
AssertEqual(ChatState.getCurrentTabID(), 1, "default restoration activates General")

print("custom tab runtime tests passed")
