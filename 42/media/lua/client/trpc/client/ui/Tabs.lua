-- ui/Tabs.lua
-- ------------------------------
-- Módulo Tabs del Core TRPC.
-- Gestión de pestañas del chat: crear/eliminar pestañas, navegación por
-- tecla (siguiente pestaña) y por clic (mapeo posición->tabID).
--
-- Globals de PZ en runtime: ISChat
-- Requires propios: Streams (UpdateTabStreams)

local Streams = require("trpc/client/chat/Streams")
local ChatState = require("trpc/client/ui/ChatState")
local TabDefinitions = require("trpc/client/ui/TabDefinitions")

local Tabs = {}

local BUILTIN_RUNTIME_IDS = {
    [TabDefinitions.BUILTIN_IDS.general] = 1,
    [TabDefinitions.BUILTIN_IDS.ooc] = 2,
    [TabDefinitions.BUILTIN_IDS.pm] = 3,
    [TabDefinitions.BUILTIN_IDS.admin] = 4,
}

local BUILTIN_RUNTIME_ID_SET = {
    [1] = true,
    [2] = true,
    [3] = true,
    [4] = true,
}

local persistedDefinitions
local persistedStatus
local persistedTabsRegistered = false
local persistedActiveApplied = false
local historyRebuilder
local activePersistenceSuspended = 0
local ReconcileDisplayOrder
local PersistActiveTab
local IsRuntimeReady
local ActivatePersistedTab

local DEFAULT_FILTERS = {
    [2] = { channels = { "ooc" }, includeSystem = false },
    [3] = { channels = { "pm" }, includeSystem = false },
    [4] = { channels = { "admin" }, includeSystem = false },
}

local function ResolveFilter(tabID, filter)
    if tabID == 1 then
        return nil
    end
    if filter ~= nil then
        return filter
    end
    return DEFAULT_FILTERS[tabID]
end

local function GetFirstTab()
    if ChatState.getTabs() == nil then
        return nil
    end
    for _, tabID in ipairs(ChatState.getMessageStore():getViewIDs()) do
        local tab = ChatState.getTabs()[tabID]
        if tab ~= nil then
            return tabID, tab
        end
    end
end

local function FindPanelView(tabID)
    local chat = ISChat and ISChat.instance
    local panel = chat and chat.panel
    if panel == nil or panel.viewList == nil then
        return nil
    end
    local tab = ChatState.getTabs()[tabID]
    for _, view in ipairs(panel.viewList) do
        if view.view == tab then
            return view
        end
        if view.view and view.view.tabID == tabID then
            return view
        end
        if view.tabID == tabID then
            return view
        end
    end
    return nil
end

local function SetPanelViewIdentity(panelView, tabID)
    if panelView == nil then
        return
    end
    panelView.tabID = tabID
    panelView.id = tabID
    if panelView.view ~= nil then
        panelView.view.tabID = tabID
    end
end

local function RefreshPanelTabMetrics(panel)
    if panel == nil or panel.viewList == nil then
        return
    end

    local textManager
    if type(getTextManager) == "function" and UIFont ~= nil and UIFont.Small ~= nil then
        textManager = getTextManager()
    end

    local maxLength = 0
    local measured = false
    for _, panelView in ipairs(panel.viewList) do
        if textManager ~= nil and type(textManager.MeasureStringX) == "function" then
            local width = textManager:MeasureStringX(UIFont.Small, panelView.name)
            if type(width) == "number" then
                panelView.tabWidth = width + (panel.tabPadX or 0)
                measured = true
            end
        end
        if type(panelView.tabWidth) == "number" and panelView.tabWidth > maxLength then
            maxLength = panelView.tabWidth
        end
    end

    if measured then
        panel.maxLength = maxLength
    end
end

local function ValuesEqual(left, right, seen)
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
        if not ValuesEqual(value, right[key], seen) then
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

local function SameArray(left, right)
    if #left ~= #right then
        return false
    end
    for index, value in ipairs(left) do
        if value ~= right[index] then
            return false
        end
    end
    return true
end

local function ToRuntimeTabID(tabID)
    return BUILTIN_RUNTIME_IDS[tabID] or tabID
end

local function ToPersistedTabID(tabID)
    if tabID == 1 then
        return TabDefinitions.BUILTIN_IDS.general
    elseif tabID == 2 then
        return TabDefinitions.BUILTIN_IDS.ooc
    elseif tabID == 3 then
        return TabDefinitions.BUILTIN_IDS.pm
    elseif tabID == 4 then
        return TabDefinitions.BUILTIN_IDS.admin
    end
    return tabID
end

local function UpdatePanelTitle(tab, oldTitle, newTitle)
    local panelView = FindPanelView(tab.tabID)
    if panelView ~= nil then
        panelView.name = newTitle
    end

    local panel = ISChat and ISChat.instance and ISChat.instance.panel
    if panel ~= nil and panel.blinkTabs ~= nil and oldTitle ~= newTitle then
        for index, blinkedTab in ipairs(panel.blinkTabs) do
            if blinkedTab == oldTitle then
                panel.blinkTabs[index] = newTitle
            end
        end
    end
    RefreshPanelTabMetrics(panel)
end

local function ActivatePanelView(tabID)
    local chat = ISChat and ISChat.instance
    local panel = chat and chat.panel
    local panelView = FindPanelView(tabID)
    if chat == nil or panel == nil or panelView == nil then
        return false
    end

    SetPanelViewIdentity(panelView, tabID)
    if type(panel.activateViewById) == "function" then
        return panel:activateViewById(panelView.id) == true
    end

    if panel.activeView ~= panelView then
        if panel.activeView ~= nil and panel.activeView.view ~= nil then
            panel.activeView.view:setVisible(false)
        end
        panelView.view:setVisible(true)
        panel.activeView = panelView
    end
    if chat.onActivateView ~= nil then
        chat:onActivateView()
    end
    return true
end

local function AddTab(tabTitle, tabID, filter, inputChannel)
    local chat = ISChat.instance
    if ChatState.getTabs()[tabID] ~= nil then
        return ChatState.getTabs()[tabID]
    end
    if TabDefinitions.isCustomID(tabID) then
        inputChannel = TabDefinitions.normalizeInputChannel(inputChannel)
    end
    local messageFilter = ResolveFilter(tabID, filter)
    local newTab = chat:createTab()
    newTab.parent = chat
    newTab.tabTitle = tabTitle
    newTab.tabID = tabID
    newTab.messageFilter = messageFilter
    newTab.inputChannel = inputChannel
    newTab.streamID = 1
    Streams.UpdateTabStreams(newTab, tabID, inputChannel)
    newTab:setUIName("chat text panel with title '" .. tabTitle .. "'")
    local pos = chat:calcTabPos()
    local size = chat:calcTabSize()
    newTab:setY(pos.y)
    newTab:setHeight(size.height)
    newTab:setWidth(size.width)
    if chat.tabCnt == 0 then
        chat:addChild(newTab)
        chat.chatText = newTab
        chat.chatText:setVisible(true)
        ChatState.setCurrentTabID(tabID)
    end
    if chat.tabCnt == 1 then
        chat.panel:setVisible(true)
        chat.chatText:setY(pos.y)
        chat.chatText:setHeight(size.height)
        chat.chatText:setWidth(size.width)
        chat:removeChild(chat.chatText)
        chat.panel:addView(chat.chatText.tabTitle, chat.chatText)
    end

    if chat.tabCnt >= 1 then
        chat.panel:addView(tabTitle, newTab)
        chat.minimumWidth = chat.panel:getWidthOfAllTabs() + 2 * chat.inset
    end
    local panelView = FindPanelView(tabID)
    SetPanelViewIdentity(panelView, tabID)
    ChatState.getTabs()[tabID] = newTab
    local normalizedFilter = ChatState.getMessageStore():registerView(tabID, messageFilter)
    newTab.messageFilter = normalizedFilter
    chat.tabCnt = chat.tabCnt + 1
    if historyRebuilder ~= nil then
        historyRebuilder(tabID)
    end
    return newTab
end

local function RemoveTab(tabTitle, tabID)
    if tabID == 1 then
        return false
    end
    local foundTab
    if ChatState.getTabs()[tabID] ~= nil then
        foundTab = ChatState.getTabs()[tabID]
        ChatState.getTabs()[tabID] = nil
        ChatState.getMessageStore():unregisterView(tabID)
        Streams.removeTabStreams(tabID)
    else
        return false
    end
    if ISChat.instance.tabCnt > 1 then
        for i, blinkedTab in ipairs(ISChat.instance.panel.blinkTabs) do
            if tabTitle == blinkedTab then
                table.remove(ISChat.instance.panel.blinkTabs, i)
                break
            end
        end
        ISChat.instance.panel:removeView(foundTab)
        ISChat.instance.minimumWidth = ISChat.instance.panel:getWidthOfAllTabs() + 2 * ISChat.instance.inset
    end
    ISChat.instance.tabCnt = ISChat.instance.tabCnt - 1
    local firstTabId, firstTab = GetFirstTab()
    if firstTabId == nil then
        return true
    end
    if ChatState.getCurrentTabID() == tabID then
        local fallbackTabID = ChatState.getTabs()[1] ~= nil and 1 or firstTabId
        ChatState.setCurrentTabID(fallbackTabID)
        local fallbackTab = ChatState.getTabs()[fallbackTabID]
        if fallbackTab ~= nil then
            ActivatePanelView(fallbackTabID)
        end
    end
    if ISChat.instance.tabCnt == 1 then
        local lastTab = firstTab
        ISChat.instance.panel:setVisible(false)
        ISChat.instance.panel:removeView(lastTab)
        ISChat.instance.chatText = lastTab
        ISChat.instance:addChild(ISChat.instance.chatText)
        ISChat.instance.chatText:setVisible(true)
    end
    ISChat.instance:onActivateView()
    return true
end

local function SetTabFilter(tabID, filter)
    local tab = ChatState.getTabs()[tabID]
    if tab == nil or BUILTIN_RUNTIME_ID_SET[tabID] then
        return false
    end
    local messageStore = ChatState.getMessageStore()
    if not messageStore:setViewFilter(tabID, filter) then
        return false
    end
    tab.messageFilter = messageStore:getViewFilter(tabID)
    if historyRebuilder ~= nil then
        historyRebuilder(tabID)
    end
    return true
end

local function GetTabFilter(tabID)
    local tab = ChatState.getTabs()[tabID]
    if tab == nil then
        return nil
    end
    return ChatState.getMessageStore():getViewFilter(tabID)
end

local function GetTabIdFromView(view)
    local associatedView = view and view.view or view
    local associatedTabID = view and view.tabID
    if associatedTabID == nil and associatedView ~= nil then
        associatedTabID = associatedView.tabID
    end
    if associatedTabID ~= nil and associatedView ~= nil and ChatState.getTabs()[associatedTabID] == associatedView then
        return associatedTabID
    end
    if associatedView ~= nil then
        for _, tabID in ipairs(ChatState.getMessageStore():getViewIDs()) do
            if ChatState.getTabs()[tabID] == associatedView then
                return tabID
            end
        end
    end
    if view and view.id ~= nil and associatedView ~= nil and ChatState.getTabs()[view.id] == associatedView then
        return view.id
    end
    if view and view.name then
        local titleMatch
        for _, tabId in ipairs(ChatState.getMessageStore():getViewIDs()) do
            local tab = ChatState.getTabs()[tabId]
            if tab ~= nil and tab.tabTitle == view.name then
                if titleMatch ~= nil then
                    return nil
                end
                titleMatch = tabId
            end
        end
        return titleMatch
    end
    return nil
end

local function GetNextTabId(currentTabId)
    local views = ISChat.instance.panel.viewList
    local firstId = nil
    local found = false
    for _, view in ipairs(views) do
        local vid = GetTabIdFromView(view)
        if vid then
            if firstId == nil then
                firstId = vid
            end
            if currentTabId == vid then
                found = true
            elseif found then
                return vid
            end
        end
    end
    return firstId
end

local function GetTabFromOrder(tabIndex)
    return GetTabIdFromView(ISChat.instance.panel.viewList[tabIndex])
end

ReconcileDisplayOrder = function()
    local tabs = ChatState.getTabs()
    local messageStore = ChatState.getMessageStore()
    local requested = {}
    local requestedSet = {}

    local function appendTab(tabID)
        if not requestedSet[tabID] and tabs[tabID] ~= nil then
            requestedSet[tabID] = true
            table.insert(requested, tabID)
        end
    end

    appendTab(1)
    for tabID = 2, 4 do
        appendTab(tabID)
    end
    if persistedDefinitions ~= nil then
        for _, tabID in ipairs(persistedDefinitions.order) do
            appendTab(tabID)
        end
    end
    for _, tabID in ipairs(messageStore:getViewIDs()) do
        if TabDefinitions.isCustomID(tabID) then
            appendTab(tabID)
        end
    end

    local orderedIDs = messageStore:setViewOrder(requested)
    local chat = ISChat and ISChat.instance
    local panel = chat and chat.panel
    if panel ~= nil and panel.viewList ~= nil then
        local viewsByID = {}
        for _, view in ipairs(panel.viewList) do
            local tabID = GetTabIdFromView(view)
            if tabID ~= nil then
                SetPanelViewIdentity(view, tabID)
                viewsByID[tabID] = view
            end
        end

        local orderedViews = {}
        for _, tabID in ipairs(orderedIDs) do
            local view = viewsByID[tabID]
            if view ~= nil then
                table.insert(orderedViews, view)
            end
        end
        panel.viewList = orderedViews
        RefreshPanelTabMetrics(panel)
        if panel.getWidthOfAllTabs ~= nil then
            chat.minimumWidth = panel:getWidthOfAllTabs() + 2 * chat.inset
        end
    end
    return orderedIDs
end

local function SetHistoryRebuilder(rebuilder)
    historyRebuilder = rebuilder
end

local function LoadPersistedDefinitions()
    local state, status, changed = TabDefinitions.load()
    persistedStatus = status
    persistedTabsRegistered = false
    persistedActiveApplied = false
    if status == TabDefinitions.STATUS_UNSUPPORTED or status == TabDefinitions.STATUS_UNAVAILABLE then
        persistedDefinitions = nil
        return nil, status, changed
    end

    persistedDefinitions = state
    return persistedDefinitions, persistedStatus, changed
end

local function ResetPersistedDefinitions()
    persistedDefinitions = nil
    persistedStatus = nil
    persistedTabsRegistered = false
    persistedActiveApplied = false
end

local function RefreshTabStreams()
    local tabs = ChatState.getTabs()
    for _, tabID in ipairs(ChatState.getMessageStore():getViewIDs()) do
        local tab = tabs[tabID]
        if tab ~= nil then
            Streams.UpdateTabStreams(tab, tabID, tab.inputChannel)
        end
    end
end

local function ApplyCustomTabRuntime(tabID, definition, forceRebuild)
    local tab = ChatState.getTabs()[tabID]
    if tab == nil then
        return false
    end

    local messageStore = ChatState.getMessageStore()
    local oldTitle = tab.tabTitle
    local oldInputChannel = tab.inputChannel
    local oldFilter = messageStore:getViewFilter(tabID)
    local filterChanged = not ValuesEqual(oldFilter, definition.filters)

    tab.tabTitle = definition.title
    tab.inputChannel = definition.inputChannel
    if messageStore:setViewFilter(tabID, definition.filters) then
        tab.messageFilter = messageStore:getViewFilter(tabID)
    end
    tab:setUIName("chat text panel with title '" .. definition.title .. "'")
    Streams.UpdateTabStreams(tab, tabID, tab.inputChannel)
    UpdatePanelTitle(tab, oldTitle, definition.title)

    if forceRebuild or oldTitle ~= definition.title or oldInputChannel ~= definition.inputChannel or filterChanged then
        if historyRebuilder ~= nil then
            historyRebuilder(tabID)
        end
    end
    return true
end

local function RestoreCustomTabs(definitions)
    if definitions == nil then
        definitions = persistedDefinitions
    end
    if type(definitions) ~= "table" then
        return false, persistedStatus
    end

    local normalized, status = TabDefinitions.normalize(definitions)
    if status == TabDefinitions.STATUS_UNSUPPORTED or status == TabDefinitions.STATUS_UNAVAILABLE then
        return false, status
    end

    persistedDefinitions = normalized
    persistedStatus = status
    persistedActiveApplied = false

    activePersistenceSuspended = activePersistenceSuspended + 1
    local expected = {}
    for _, tabID in ipairs(normalized.order) do
        local definition = normalized.tabs[tabID]
        if definition ~= nil then
            expected[tabID] = true
            if ChatState.getTabs()[tabID] == nil then
                AddTab(definition.title, tabID, definition.filters, definition.inputChannel)
            else
                ApplyCustomTabRuntime(tabID, definition, false)
            end
        end
    end

    local staleIDs = {}
    for _, tabID in ipairs(ChatState.getMessageStore():getViewIDs()) do
        if TabDefinitions.isCustomID(tabID) and not expected[tabID] then
            table.insert(staleIDs, tabID)
        end
    end
    for _, tabID in ipairs(staleIDs) do
        local tab = ChatState.getTabs()[tabID]
        if tab ~= nil then
            RemoveTab(tab.tabTitle, tabID)
        end
    end

    persistedTabsRegistered = true
    ReconcileDisplayOrder()
    activePersistenceSuspended = activePersistenceSuspended - 1
    if IsRuntimeReady() then
        ActivatePersistedTab()
    end
    return true, status
end

local function RegisterPersistedDefinitions()
    return RestoreCustomTabs(persistedDefinitions)
end

local function ResolveRuntimeTabID(definitionID)
    return BUILTIN_RUNTIME_IDS[definitionID] or definitionID
end

local function ActivateTab(tabID)
    local runtimeTabID = ToRuntimeTabID(tabID)
    local tab = ChatState.getTabs()[runtimeTabID]
    if tab == nil or ISChat.instance == nil then
        return false
    end

    local chat = ISChat.instance
    local activated = true
    if chat.tabCnt > 1 then
        activated = ActivatePanelView(runtimeTabID)
    else
        chat.chatText = tab
        tab:setVisible(true)
        if chat.onActivateView ~= nil then
            chat:onActivateView()
        end
    end
    if not activated then
        return false
    end

    ChatState.setCurrentTabID(runtimeTabID)
    if activePersistenceSuspended == 0 and PersistActiveTab ~= nil then
        PersistActiveTab(runtimeTabID)
    end
    return true
end

IsRuntimeReady = function()
    return ISChat ~= nil and ISChat.instance ~= nil and ChatState.getTabs()[1] ~= nil
end

local function ResolveExplicitActiveTabID(requestedTabID, pendingRuntimeTabID)
    local persistedTabID = ToPersistedTabID(requestedTabID)
    if not IsRuntimeReady() then
        return persistedTabID
    end

    local runtimeTabID = ToRuntimeTabID(persistedTabID)
    if runtimeTabID == pendingRuntimeTabID or ChatState.getTabs()[runtimeTabID] ~= nil then
        return persistedTabID
    end
    return TabDefinitions.BUILTIN_IDS.general, "active-fallback"
end

local function ActivateRequestedTab(persistedTabID)
    local runtimeTabID = ToRuntimeTabID(persistedTabID)
    if ActivateTab(runtimeTabID) then
        return true
    end
    if runtimeTabID ~= 1 and ActivateTab(1) then
        return true, "active-fallback"
    end
    return false, "active-unavailable"
end

ActivatePersistedTab = function()
    if persistedDefinitions == nil then
        return false
    end
    if persistedActiveApplied then
        return true
    end
    local tabID = ResolveRuntimeTabID(persistedDefinitions.activeTabID)
    if ChatState.getTabs()[tabID] == nil then
        tabID = 1
    end
    activePersistenceSuspended = activePersistenceSuspended + 1
    local activated = ActivateTab(tabID)
    if not activated and tabID ~= 1 then
        activated = ActivateTab(1)
    end
    activePersistenceSuspended = activePersistenceSuspended - 1
    if activated then
        persistedActiveApplied = true
    end
    return activated
end

local function SavePersistedDefinitions(state)
    local saved, savedState, status = TabDefinitions.save(state)
    if not saved then
        return false, status
    end
    persistedDefinitions = savedState
    persistedStatus = status
    return true, status
end

local function EnsurePersistedDefinitions()
    if persistedDefinitions ~= nil then
        return persistedDefinitions
    end
    LoadPersistedDefinitions()
    return persistedDefinitions
end

local function RemoveRuntimeCustomTab(tabID)
    local runtimeTab = ChatState.getTabs()[tabID]
    if runtimeTab ~= nil and ISChat ~= nil and ISChat.instance ~= nil then
        return RemoveTab(runtimeTab.tabTitle, tabID)
    end

    ChatState.getTabs()[tabID] = nil
    ChatState.getMessageStore():unregisterView(tabID)
    Streams.removeTabStreams(tabID)
    return true
end

local function ApplyCustomTabState(state)
    if type(state) ~= "table" then
        return false, "invalid"
    end

    local normalized, normalizeStatus = TabDefinitions.normalize(state)
    if normalizeStatus == TabDefinitions.STATUS_MALFORMED
        or normalizeStatus == TabDefinitions.STATUS_UNSUPPORTED
        or normalizeStatus == TabDefinitions.STATUS_UNAVAILABLE
    then
        return false, normalizeStatus
    end
    if not IsRuntimeReady()
        or type(ISChat.instance.createTab) ~= "function"
        or ISChat.instance.panel == nil
        or historyRebuilder == nil
    then
        return false, TabDefinitions.STATUS_UNAVAILABLE
    end

    local activeStatus
    if not TabDefinitions.isCustomID(normalized.activeTabID) then
        local runtimeActiveID = ToRuntimeTabID(normalized.activeTabID)
        if ChatState.getTabs()[runtimeActiveID] == nil then
            normalized.activeTabID = TabDefinitions.BUILTIN_GENERAL_ID
            activeStatus = "active-fallback"
        end
    end

    local saved, savedState, saveStatus = TabDefinitions.save(normalized)
    if not saved then
        return false, saveStatus
    end

    persistedDefinitions = savedState
    persistedStatus = saveStatus
    persistedTabsRegistered = false
    persistedActiveApplied = false

    local tabs = ChatState.getTabs()
    local messageStore = ChatState.getMessageStore()
    activePersistenceSuspended = activePersistenceSuspended + 1
    local expected = {}
    for tabID in pairs(savedState.tabs) do
        expected[tabID] = true
    end

    local staleIDs = {}
    local staleSet = {}
    for tabID in pairs(tabs) do
        if TabDefinitions.isCustomID(tabID) and not expected[tabID] and not staleSet[tabID] then
            staleSet[tabID] = true
            table.insert(staleIDs, tabID)
        end
    end
    for _, tabID in ipairs(messageStore:getViewIDs()) do
        if TabDefinitions.isCustomID(tabID) and not expected[tabID] and not staleSet[tabID] then
            staleSet[tabID] = true
            table.insert(staleIDs, tabID)
        end
    end
    for _, tabID in ipairs(staleIDs) do
        RemoveRuntimeCustomTab(tabID)
    end

    for _, tabID in ipairs(savedState.order) do
        local definition = savedState.tabs[tabID]
        if definition ~= nil then
            if tabs[tabID] == nil then
                AddTab(definition.title, tabID, definition.filters, definition.inputChannel)
            else
                if messageStore:getViewFilter(tabID) == nil then
                    messageStore:registerView(tabID, definition.filters)
                end
                ApplyCustomTabRuntime(tabID, definition, false)
            end
        end
    end

    RefreshTabStreams()
    ReconcileDisplayOrder()

    local runtimeActiveID = ToRuntimeTabID(savedState.activeTabID)
    if tabs[runtimeActiveID] == nil then
        runtimeActiveID = 1
        activeStatus = "active-fallback"
    end

    local activated = ActivateTab(runtimeActiveID)
    if not activated and runtimeActiveID ~= 1 then
        activated = ActivateTab(1)
        if activated then
            activeStatus = "active-fallback"
        end
    end
    activePersistenceSuspended = activePersistenceSuspended - 1
    if not activated then
        return false, "active-unavailable"
    end

    persistedTabsRegistered = true
    persistedActiveApplied = true
    if ISChat ~= nil and type(ISChat.refreshActiveInputChannel) == "function" then
        ISChat.refreshActiveInputChannel()
    end
    return true, persistedDefinitions, activeStatus or saveStatus
end

PersistActiveTab = function(runtimeTabID)
    local state = EnsurePersistedDefinitions()
    if state == nil then
        return false, persistedStatus
    end

    local persistedTabID = ToPersistedTabID(runtimeTabID)
    if state.activeTabID == persistedTabID then
        return true
    end

    local nextState = TabDefinitions.normalize(state)
    nextState.activeTabID = persistedTabID
    local saved, saveStatus = SavePersistedDefinitions(nextState)
    if saved then
        persistedActiveApplied = true
    end
    return saved, saveStatus
end

local function CreateCustomTab(definition)
    if type(definition) ~= "table" then
        return nil, "invalid"
    end
    local state = EnsurePersistedDefinitions()
    if state == nil then
        return nil, persistedStatus
    end
    local title = TabDefinitions.normalizeTitle(definition.title)
    if title == nil then
        return nil, "invalid"
    end

    local tabID, nextState, allocationStatus = TabDefinitions.allocateCustomID(state)
    if tabID == nil then
        return nil, allocationStatus
    end
    local activeStatus
    nextState.tabs[tabID] = {
        title = title,
        inputChannel = definition.inputChannel,
        filters = definition.filters or definition.filter,
    }
    table.insert(nextState.order, tabID)
    if definition.activeTabID ~= nil then
        local requestedActiveTabID = ToPersistedTabID(definition.activeTabID)
        if IsRuntimeReady() then
            nextState.activeTabID, activeStatus = ResolveExplicitActiveTabID(requestedActiveTabID, tabID)
        else
            nextState.activeTabID = requestedActiveTabID
        end
    end
    nextState = TabDefinitions.normalize(nextState)

    local saved, saveStatus = SavePersistedDefinitions(nextState)
    if not saved then
        return nil, saveStatus
    end
    if persistedTabsRegistered or (ISChat ~= nil and ISChat.instance ~= nil and ChatState.getTabs()[1] ~= nil) then
        local savedDefinition = persistedDefinitions.tabs[tabID]
        AddTab(savedDefinition.title, tabID, savedDefinition.filters, savedDefinition.inputChannel)
        ReconcileDisplayOrder()
        if definition.activeTabID ~= nil then
            local _, activationStatus = ActivateRequestedTab(persistedDefinitions.activeTabID)
            activeStatus = activationStatus or activeStatus
        end
    end
    return tabID, persistedDefinitions.tabs[tabID], activeStatus or saveStatus
end

local function BuildCustomOrder(state, orderedIDs)
    local nextOrder = {}
    local seen = {}
    for _, tabID in ipairs(orderedIDs) do
        if TabDefinitions.isCustomID(tabID) and state.tabs[tabID] ~= nil and not seen[tabID] then
            seen[tabID] = true
            table.insert(nextOrder, tabID)
        end
    end
    for _, tabID in ipairs(state.order) do
        if not seen[tabID] then
            seen[tabID] = true
            table.insert(nextOrder, tabID)
        end
    end
    return nextOrder
end

local function UpdateCustomTab(definitionOrTabID, suppliedDefinition)
    local tabID
    local definition
    if type(definitionOrTabID) == "table" then
        definition = definitionOrTabID
        tabID = definition.tabID or definition.id
    else
        tabID = definitionOrTabID
        definition = suppliedDefinition
    end
    if not TabDefinitions.isCustomID(tabID) or type(definition) ~= "table" then
        return false, "invalid"
    end
    local state = EnsurePersistedDefinitions()
    local current = state and state.tabs[tabID]
    if current == nil then
        return false, "missing"
    end

    local title = definition.title ~= nil and TabDefinitions.normalizeTitle(definition.title) or current.title
    if title == nil then
        return false, "invalid"
    end
    local filters = definition.filters
    if filters == nil then
        filters = definition.filter
    end
    local nextState = TabDefinitions.normalize(state)
    nextState.tabs[tabID] = {
        title = title,
        inputChannel = definition.inputChannel ~= nil and definition.inputChannel or current.inputChannel,
        filters = filters ~= nil and filters or current.filters,
    }
    if definition.order ~= nil then
        if type(definition.order) ~= "table" then
            return false, "invalid"
        end
        nextState.order = BuildCustomOrder(nextState, definition.order)
    end
    local activeStatus
    if definition.activeTabID ~= nil then
        local requestedActiveTabID = ToPersistedTabID(definition.activeTabID)
        if IsRuntimeReady() then
            nextState.activeTabID, activeStatus = ResolveExplicitActiveTabID(requestedActiveTabID)
        else
            nextState.activeTabID = requestedActiveTabID
        end
    end
    nextState = TabDefinitions.normalize(nextState)

    local saved, saveStatus = SavePersistedDefinitions(nextState)
    if not saved then
        return false, saveStatus
    end

    local tab = ChatState.getTabs()[tabID]
    if tab ~= nil then
        local savedDefinition = persistedDefinitions.tabs[tabID]
        ApplyCustomTabRuntime(tabID, savedDefinition, true)
    end
    if definition.activeTabID ~= nil and IsRuntimeReady() then
        local _, activationStatus = ActivateRequestedTab(persistedDefinitions.activeTabID)
        activeStatus = activationStatus or activeStatus
    end
    ReconcileDisplayOrder()
    return true, persistedDefinitions.tabs[tabID], activeStatus or saveStatus
end

local function ReorderCustomTabs(orderedIDs)
    if type(orderedIDs) ~= "table" then
        return false, "invalid"
    end
    local state = EnsurePersistedDefinitions()
    if state == nil then
        return false, persistedStatus
    end

    local nextState = TabDefinitions.normalize(state)
    nextState.order = BuildCustomOrder(nextState, orderedIDs)
    if SameArray(nextState.order, state.order) then
        return true, persistedDefinitions
    end

    local saved, saveStatus = SavePersistedDefinitions(nextState)
    if not saved then
        return false, saveStatus
    end
    ReconcileDisplayOrder()
    return true, persistedDefinitions, saveStatus
end

local function RemoveCustomTab(tabID)
    if not TabDefinitions.isCustomID(tabID) then
        return false, "invalid"
    end
    local state = EnsurePersistedDefinitions()
    if state == nil or state.tabs[tabID] == nil then
        return false, "missing"
    end

    local nextState = TabDefinitions.normalize(state)
    nextState.tabs[tabID] = nil
    for index, existingID in ipairs(nextState.order) do
        if existingID == tabID then
            table.remove(nextState.order, index)
            break
        end
    end
    if nextState.activeTabID == tabID then
        nextState.activeTabID = TabDefinitions.BUILTIN_GENERAL_ID
    end

    local saved, saveStatus = SavePersistedDefinitions(nextState)
    if not saved then
        return false, saveStatus
    end
    local runtimeTab = ChatState.getTabs()[tabID]
    if runtimeTab ~= nil and ISChat ~= nil and ISChat.instance ~= nil then
        RemoveTab(runtimeTab.tabTitle, tabID)
    else
        ChatState.getTabs()[tabID] = nil
        ChatState.getMessageStore():unregisterView(tabID)
        Streams.removeTabStreams(tabID)
    end
    if ChatState.getCurrentTabID() == tabID then
        ChatState.setCurrentTabID(1)
        if ChatState.getTabs()[1] ~= nil then
            ActivateTab(1)
        end
    end
    ReconcileDisplayOrder()
    return true, saveStatus
end

local function RebuildTab(tabID)
    if historyRebuilder == nil then
        return false, "unavailable"
    end
    return historyRebuilder(ToRuntimeTabID(tabID))
end

local function ClearRuntimeTab(tabID)
    local tab = ChatState.getTabs()[tabID]
    if tab == nil then
        return false
    end
    tab.chatTextRawLines = {}
    tab.chatTextLines = {}
    tab.chatMessages = {}
    tab.log = {}
    tab.logIndex = 0
    tab.text = ""
    tab.textDirty = true
    if tab.paginate ~= nil then
        tab:paginate()
    end
    return true
end

local function ClearTabHistory(tabID)
    local runtimeTabID = ToRuntimeTabID(tabID)
    if not ChatState.getMessageStore():clearView(runtimeTabID) then
        return false, "missing"
    end
    ClearRuntimeTab(runtimeTabID)
    return true
end

local function DuplicateCustomTab(tabID)
    if not TabDefinitions.isCustomID(tabID) then
        return nil, "invalid"
    end
    local state = EnsurePersistedDefinitions()
    local source = state and state.tabs[tabID]
    if source == nil then
        return nil, "missing"
    end

    local duplicateID, nextState, allocationStatus = TabDefinitions.allocateCustomID(state)
    if duplicateID == nil then
        return nil, allocationStatus
    end
    nextState.tabs[duplicateID] = {
        title = source.title .. " Copy",
        inputChannel = source.inputChannel,
        filters = source.filters,
    }
    local nextOrder = {}
    for _, existingID in ipairs(nextState.order) do
        table.insert(nextOrder, existingID)
        if existingID == tabID then
            table.insert(nextOrder, duplicateID)
        end
    end
    nextState.order = nextOrder
    nextState = TabDefinitions.normalize(nextState)

    local saved, saveStatus = SavePersistedDefinitions(nextState)
    if not saved then
        return nil, saveStatus
    end
    if persistedTabsRegistered or IsRuntimeReady() then
        local definition = persistedDefinitions.tabs[duplicateID]
        AddTab(definition.title, duplicateID, definition.filters, definition.inputChannel)
        ReconcileDisplayOrder()
    end
    return duplicateID, persistedDefinitions.tabs[duplicateID], saveStatus
end

local function RestoreDefaultTabs()
    local state = TabDefinitions.newState()
    local saved, saveStatus = SavePersistedDefinitions(state)
    if not saved then
        return false, saveStatus
    end

    activePersistenceSuspended = activePersistenceSuspended + 1
    local staleIDs = {}
    for tabID in pairs(ChatState.getTabs()) do
        if TabDefinitions.isCustomID(tabID) then
            table.insert(staleIDs, tabID)
        end
    end
    for _, tabID in ipairs(staleIDs) do
        RemoveRuntimeCustomTab(tabID)
    end
    ReconcileDisplayOrder()
    local activated = not IsRuntimeReady() or ActivateTab(1)
    activePersistenceSuspended = activePersistenceSuspended - 1
    if not activated then
        return false, "active-unavailable"
    end
    persistedDefinitions.activeTabID = TabDefinitions.BUILTIN_GENERAL_ID
    persistedActiveApplied = true
    return true, persistedDefinitions, saveStatus
end

local function PersistRuntimeCustomOrder()
    local panel = ISChat and ISChat.instance and ISChat.instance.panel
    if panel == nil or type(panel.viewList) ~= "table" then
        return false, "unavailable"
    end
    local orderedIDs = {}
    for _, view in ipairs(panel.viewList) do
        local tabID = GetTabIdFromView(view)
        if tabID ~= nil then
            table.insert(orderedIDs, tabID)
        end
    end
    return ReorderCustomTabs(orderedIDs)
end

local function GetInputChannel(tabID)
    local runtimeTabID = ToRuntimeTabID(tabID)
    if persistedDefinitions ~= nil and persistedDefinitions.tabs[runtimeTabID] ~= nil then
        return persistedDefinitions.tabs[runtimeTabID].inputChannel
    end
    local tab = ChatState.getTabs()[runtimeTabID]
    return tab and tab.inputChannel or nil
end

-- API pública
Tabs.addTab = AddTab
Tabs.removeTab = RemoveTab
Tabs.setTabFilter = SetTabFilter
Tabs.getTabFilter = GetTabFilter
Tabs.getTabIdFromView = GetTabIdFromView
Tabs.getNextTabId = GetNextTabId
Tabs.getTabFromOrder = GetTabFromOrder
Tabs.setHistoryRebuilder = SetHistoryRebuilder
Tabs.loadPersistedDefinitions = LoadPersistedDefinitions
Tabs.resetPersistedDefinitions = ResetPersistedDefinitions
Tabs.registerPersistedDefinitions = RegisterPersistedDefinitions
Tabs.refreshTabStreams = RefreshTabStreams
Tabs.activateTab = ActivateTab
Tabs.activatePersistedTab = ActivatePersistedTab
Tabs.addCustomTab = CreateCustomTab
Tabs.createCustomTab = CreateCustomTab
Tabs.updateCustomTab = UpdateCustomTab
Tabs.removeCustomTab = RemoveCustomTab
Tabs.reorderCustomTabs = ReorderCustomTabs
Tabs.restoreCustomTabs = RestoreCustomTabs
Tabs.reconcileDisplayOrder = ReconcileDisplayOrder
Tabs.rebuildTab = RebuildTab
Tabs.clearTabHistory = ClearTabHistory
Tabs.duplicateCustomTab = DuplicateCustomTab
Tabs.restoreDefaultTabs = RestoreDefaultTabs
Tabs.persistRuntimeCustomOrder = PersistRuntimeCustomOrder
Tabs.getInputChannel = GetInputChannel
Tabs.applyCustomTabState = ApplyCustomTabState
Tabs.getPersistedDefinitions = function()
    return persistedDefinitions, persistedStatus
end
Tabs.isCustomTabID = TabDefinitions.isCustomID

return Tabs
