require("ISUI/ISCollapsableWindow")
require("ISUI/ISButton")
require("ISUI/ISComboBox")
require("ISUI/ISScrollingListBox")
require("ISUI/ISTextEntryBox")

local ChannelRegistry = require("trpc/shared/ChannelRegistry")
local TabDefinitions = require("trpc/client/ui/TabDefinitions")
local Tabs = require("trpc/client/ui/Tabs")

local TabEditorWindow = ISCollapsableWindow:derive("TabEditorWindow")

local WINDOW_WIDTH = 600
local WINDOW_HEIGHT = 500
local PADDING = 12
local CONTROL_HEIGHT = 24
local BUTTON_HEIGHT = 25
local LIST_WIDTH = 180

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

local function Text(key, fallback)
    if type(getText) == "function" then
        local translated = getText(key)
        if translated ~= nil and translated ~= key then
            return translated
        end
    end
    return fallback
end

local function Trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function ToArray(value)
    if value == nil then
        return {}
    end
    if type(value) ~= "table" then
        return { value }
    end

    local values = {}
    for _, item in ipairs(value) do
        table.insert(values, item)
    end
    return values
end

local function Contains(values, value)
    for _, item in ipairs(values) do
        if item == value then
            return true
        end
    end
    return false
end

local function CalculateCoordinatesAndSize()
    local screenWidth = getCore():getScreenWidth()
    local screenHeight = getCore():getScreenHeight()
    local width = math.max(1, math.min(WINDOW_WIDTH, screenWidth - 40))
    local height = math.max(1, math.min(WINDOW_HEIGHT, screenHeight - 40))
    return screenWidth / 2 - width / 2, screenHeight / 2 - height / 2, width, height
end

local function BuildExcludedChannelChoices()
    local choices = {}
    local seen = {}
    for _, entry in ipairs(ChannelRegistry.getAll()) do
        if not seen[entry.name] then
            seen[entry.name] = true
            table.insert(choices, { text = entry.name, value = entry.name })
        end
    end
    for _, name in ipairs({ "server", "radio", "system", "error" }) do
        if not seen[name] then
            seen[name] = true
            table.insert(choices, { text = name, value = name })
        end
    end
    return choices
end

local function BuildInputChannelChoices()
    local choices = {}
    for _, entry in ipairs(ChannelRegistry.getAll()) do
        if entry.hasSlashCommand ~= false then
            table.insert(choices, { text = entry.name, value = entry.name })
        end
    end
    return choices
end

local function CopyExcludedChannelFilter(filters)
    local values = filters and filters.excludedChannels
    local normalized = TabDefinitions.normalizeFilters({ excludedChannels = ToArray(values) })
    if normalized.excludedChannels == nil then
        return {}
    end
    return { excludedChannels = normalized.excludedChannels }
end

local function GetExcludedChannelValueText(value)
    return tostring(value)
end

function TabEditorWindow:initialise()
    ISCollapsableWindow.initialise(self)
end

function TabEditorWindow:createChildren()
    self._parentClass.createChildren(self)

    local titleBarHeight = self:titleBarHeight()
    local contentY = titleBarHeight + PADDING
    local listWidth = math.min(LIST_WIDTH, math.max(120, math.floor(self.width * 0.34)))
    local rightX = PADDING + listWidth + PADDING
    local rightWidth = math.max(1, self.width - rightX - PADDING)
    local fieldWidth = rightWidth
    local actionWidth = math.min(80, math.max(56, math.floor(fieldWidth * 0.3)))
    local excludedChannelValueWidth = math.max(1, fieldWidth - actionWidth - 6)

    self.layout = {
        contentY = contentY,
        listWidth = listWidth,
        rightX = rightX,
        rightWidth = rightWidth,
        fieldX = rightX,
        fieldWidth = fieldWidth,
        excludedChannelValueWidth = excludedChannelValueWidth,
        statusY = self.height - 51,
    }

    self.tabList = ISScrollingListBox:new(
        PADDING,
        contentY + 20,
        listWidth,
        math.max(1, self.height - contentY - 90)
    )
    self.tabList:initialise()
    self.tabList:setOnMouseDownFunction(self, self.onTabSelected)
    self:addChild(self.tabList)

    self.titleEntry = ISTextEntryBox:new("", rightX, contentY + 20, fieldWidth, CONTROL_HEIGHT)
    self.titleEntry:initialise()
    self:addChild(self.titleEntry)
    self.titleEntry:setMaxTextLength(TabDefinitions.MAX_TITLE_LENGTH)
    self.titleEntry:setPlaceholderText(Text("UI_TRPC_chat_tab_title_placeholder", "A name for this tab"))

    self.inputChannelCombo = ISComboBox:new(rightX, contentY + 54, fieldWidth, CONTROL_HEIGHT)
    self.inputChannelCombo:initialise()
    for _, entry in ipairs(BuildInputChannelChoices()) do
        self.inputChannelCombo:addOptionWithData(entry.text, entry.value)
    end
    self.inputChannelCombo:selectData(TabDefinitions.DEFAULT_INPUT_CHANNEL)
    self:addChild(self.inputChannelCombo)

    self.excludedChannelCombo = ISComboBox:new(rightX, contentY + 88, excludedChannelValueWidth, CONTROL_HEIGHT)
    self.excludedChannelCombo:initialise()
    for _, entry in ipairs(BuildExcludedChannelChoices()) do
        self.excludedChannelCombo:addOptionWithData(entry.text, entry.value)
    end
    self.excludedChannelCombo:selectData("say")
    self:addChild(self.excludedChannelCombo)

    self.addExcludedChannelButton = ISButton:new(
        rightX + fieldWidth - actionWidth,
        contentY + 88,
        actionWidth,
        CONTROL_HEIGHT,
        Text("UI_TRPC_chat_tab_add_excluded_channel", "Add"),
        self,
        self.addExcludedChannel
    )
    self.addExcludedChannelButton:initialise()
    self:addChild(self.addExcludedChannelButton)

    self.excludedChannelList = ISScrollingListBox:new(
        rightX,
        contentY + 154,
        rightWidth,
        math.max(1, self.height - contentY - 253)
    )
    self.excludedChannelList:initialise()
    self:addChild(self.excludedChannelList)

    self.removeExcludedChannelButton = ISButton:new(
        rightX,
        self.height - 82,
        actionWidth,
        BUTTON_HEIGHT,
        Text("UI_TRPC_chat_tab_remove_excluded_channel", "Remove"),
        self,
        self.removeSelectedExcludedChannel
    )
    self.removeExcludedChannelButton:initialise()
    self:addChild(self.removeExcludedChannelButton)

    self.clearExcludedChannelButton = ISButton:new(
        rightX + actionWidth + 6,
        self.height - 82,
        actionWidth,
        BUTTON_HEIGHT,
        Text("UI_TRPC_chat_tab_clear_excluded_channels", "Clear"),
        self,
        self.clearExcludedChannels
    )
    self.clearExcludedChannelButton:initialise()
    self:addChild(self.clearExcludedChannelButton)

    self.newButton = ISButton:new(
        PADDING,
        self.height - 62,
        listWidth,
        BUTTON_HEIGHT,
        Text("UI_TRPC_chat_tab_new", "New"),
        self,
        self.beginNewTab
    )
    self.newButton:initialise()
    self:addChild(self.newButton)

    self.deleteButton = ISButton:new(
        PADDING,
        self.height - 34,
        listWidth,
        BUTTON_HEIGHT,
        Text("UI_TRPC_chat_tab_delete", "Delete"),
        self,
        self.deleteSelected
    )
    self.deleteButton:initialise()
    self:addChild(self.deleteButton)

    local actionY = self.height - 34
    local bottomActionWidth = math.min(84, math.max(60, math.floor((rightWidth - 6) / 2)))
    self.cancelButton = ISButton:new(
        self.width - PADDING - bottomActionWidth * 2 - 6,
        actionY,
        bottomActionWidth,
        BUTTON_HEIGHT,
        Text("UI_TRPC_chat_tab_cancel", "Cancel"),
        self,
        self.cancel
    )
    self.cancelButton:initialise()
    self:addChild(self.cancelButton)

    self.saveButton = ISButton:new(
        self.width - PADDING - bottomActionWidth,
        actionY,
        bottomActionWidth,
        BUTTON_HEIGHT,
        Text("UI_TRPC_chat_tab_save", "Save"),
        self,
        self.saveTab
    )
    self.saveButton:initialise()
    self:addChild(self.saveButton)

    self.excludedChannelDraft = {}
    self.draftState = nil
    self.selectedID = nil
    self.statusMessage = nil
    self:refreshTabs()
end

function TabEditorWindow:prerender()
    self._parentClass.prerender(self)

    local layout = self.layout
    if layout == nil then
        return
    end

    local labelColor = { r = 0.85, g = 0.85, b = 0.85, a = 1 }
    local labelFont = UIFont.Small
    local function DrawLabel(text, x, y)
        self:drawText(text, x, y, labelColor.r, labelColor.g, labelColor.b, labelColor.a, labelFont)
    end

    DrawLabel(Text("UI_TRPC_chat_tab_list", "Custom tabs"), PADDING, layout.contentY)
    DrawLabel(Text("UI_TRPC_chat_tab_title", "Tab name"), layout.rightX, layout.contentY + 25)
    DrawLabel(Text("UI_TRPC_chat_tab_input", "Input channel"), layout.rightX, layout.contentY + 59)
    DrawLabel(
        Text("UI_TRPC_chat_tab_excluded_channels", "Excluded channels"),
        layout.rightX,
        layout.contentY + 93
    )
    DrawLabel(
        Text("UI_TRPC_chat_tab_excluded_channels_list", "Channels to hide"),
        layout.rightX,
        layout.contentY + 130
    )

    if self.statusMessage ~= nil then
        local color = self.statusIsError and { r = 1, g = 0.45, b = 0.45, a = 1 }
            or { r = 0.55, g = 1, b = 0.55, a = 1 }
        self:drawText(
            self.statusMessage,
            layout.rightX,
            layout.statusY,
            color.r,
            color.g,
            color.b,
            color.a,
            UIFont.Small
        )
    end
end

function TabEditorWindow:setStatus(message, isError)
    self.statusMessage = message
    self.statusIsError = isError == true
end

function TabEditorWindow:refreshDraftList(preferredID, preserveEditor)
    self.tabList:clear()
    self.tabList.selected = -1

    local draftState = self.draftState
    if draftState == nil or type(draftState.order) ~= "table" or type(draftState.tabs) ~= "table" then
        return
    end

    local selectedIndex
    for _, tabID in ipairs(draftState.order) do
        local definition = draftState.tabs[tabID]
        if TabDefinitions.isCustomID(tabID) and definition ~= nil then
            local item = self.tabList:addItem(definition.title, { id = tabID, definition = definition })
            if preferredID == tabID then
                selectedIndex = item.itemindex
            end
        end
    end

    if selectedIndex == nil and #self.tabList.items > 0 then
        selectedIndex = 1
    end
    if selectedIndex ~= nil then
        self.tabList.selected = selectedIndex
        if not preserveEditor then
            self:loadTab(self.tabList.items[selectedIndex].item)
        end
    end
end

function TabEditorWindow:refreshTabs(preferredID)
    local definitions = Tabs.getPersistedDefinitions()
    self.draftState = definitions and DeepCopy(definitions) or nil
    self.selectedID = nil

    if self.draftState == nil
        or type(self.draftState.order) ~= "table"
        or type(self.draftState.tabs) ~= "table"
    then
        self:refreshDraftList()
        self:beginNewTab()
        self:setStatus(Text("UI_TRPC_chat_tab_unavailable", "Chat tab data is unavailable."), true)
        return
    end

    self:refreshDraftList(preferredID)
    if #self.tabList.items == 0 then
        self:beginNewTab()
    end
end

function TabEditorWindow:onTabSelected(item)
    if item == nil then
        return
    end
    self:loadTab(item)
end

function TabEditorWindow:loadTab(item)
    local definition = item and item.definition
    if definition == nil then
        return
    end

    self.selectedID = item.id
    self.titleEntry:setText(definition.title or "")
    self.inputChannelCombo:selectData(definition.inputChannel or TabDefinitions.DEFAULT_INPUT_CHANNEL)
    self.excludedChannelDraft = CopyExcludedChannelFilter(definition.filters)
    self:refreshExcludedChannelRows()
    self:setStatus(nil)
end

function TabEditorWindow:beginNewTab()
    if self.titleEntry == nil then
        return
    end

    local allocatedID
    if self.draftState ~= nil then
        local allocatedState
        allocatedID, allocatedState = TabDefinitions.allocateCustomID(self.draftState)
        if allocatedID ~= nil then
            self.draftState = allocatedState
        end
    end

    self.selectedID = allocatedID
    self.titleEntry:setText("")
    self.inputChannelCombo:selectData(TabDefinitions.DEFAULT_INPUT_CHANNEL)
    self.excludedChannelDraft = {}
    self:refreshExcludedChannelRows()
    self:setStatus(Text("UI_TRPC_chat_tab_new_hint", "Create a new custom tab."))
end

function TabEditorWindow:addExcludedChannel()
    local channel = self.excludedChannelCombo:getSelectedData()
    if channel == nil then
        self:setStatus(Text("UI_TRPC_chat_tab_excluded_channel_required", "Choose a channel to hide."), true)
        return
    end

    local values = ToArray(self.excludedChannelDraft.excludedChannels)
    if Contains(values, channel) then
        self:setStatus(
            Text("UI_TRPC_chat_tab_excluded_channel_duplicate", "That excluded channel is already present."),
            true
        )
        return
    end
    table.insert(values, channel)
    self.excludedChannelDraft = CopyExcludedChannelFilter({ excludedChannels = values })
    self:refreshExcludedChannelRows()
    self:setStatus(nil)
end

function TabEditorWindow:refreshExcludedChannelRows()
    if self.excludedChannelList == nil then
        return
    end

    self.excludedChannelList:clear()
    self.excludedChannelList.selected = -1
    for _, channel in ipairs(ToArray(self.excludedChannelDraft.excludedChannels)) do
        self.excludedChannelList:addItem(
            Text("UI_TRPC_chat_tab_excluded_channel", "Excluded channel")
                .. " = "
                .. GetExcludedChannelValueText(channel),
            { value = channel }
        )
    end
end

function TabEditorWindow:removeSelectedExcludedChannel()
    local listItem = self.excludedChannelList.items[self.excludedChannelList.selected]
    local row = listItem and listItem.item
    if row == nil then
        return
    end

    local values = {}
    for _, channel in ipairs(ToArray(self.excludedChannelDraft.excludedChannels)) do
        if channel ~= row.value then
            table.insert(values, channel)
        end
    end
    self.excludedChannelDraft = CopyExcludedChannelFilter({ excludedChannels = values })
    self:refreshExcludedChannelRows()
    self:setStatus(nil)
end

function TabEditorWindow:clearExcludedChannels()
    self.excludedChannelDraft = {}
    self:refreshExcludedChannelRows()
    self:setStatus(nil)
end

function TabEditorWindow:saveTab()
    if self.draftState == nil or self.selectedID == nil or not TabDefinitions.isCustomID(self.selectedID) then
        self:setStatus(Text("UI_TRPC_chat_tab_save_failed", "Unable to save chat tabs."), true)
        return
    end

    local title = Trim(self.titleEntry:getText())
    if title == "" then
        self:setStatus(Text("UI_TRPC_chat_tab_title_required", "Enter a tab name."), true)
        return
    end

    local savedID = self.selectedID
    local definition = {
        title = title,
        inputChannel = self.inputChannelCombo:getSelectedData() or TabDefinitions.DEFAULT_INPUT_CHANNEL,
        filters = CopyExcludedChannelFilter(self.excludedChannelDraft),
    }
    if self.draftState.tabs[savedID] == nil then
        table.insert(self.draftState.order, savedID)
    end
    self.draftState.tabs[savedID] = definition

    local applied, savedState, status = Tabs.applyCustomTabState(self.draftState)
    if not applied then
        self:setStatus(Text("UI_TRPC_chat_tab_save_failed", "Unable to save chat tabs.") .. " (" .. tostring(status) .. ")", true)
        return
    end

    self.draftState = DeepCopy(savedState)
    self:refreshDraftList(savedID)
    self:setStatus(Text("UI_TRPC_chat_tab_saved", "Chat tab saved."))
end

function TabEditorWindow:deleteSelected()
    if self.selectedID == nil or self.draftState == nil or not TabDefinitions.isCustomID(self.selectedID) then
        return
    end

    local deletedID = self.selectedID
    self.draftState.tabs[deletedID] = nil
    local nextOrder = {}
    for _, tabID in ipairs(self.draftState.order) do
        if tabID ~= deletedID then
            table.insert(nextOrder, tabID)
        end
    end
    self.draftState.order = nextOrder
    if self.draftState.activeTabID == deletedID then
        self.draftState.activeTabID = TabDefinitions.BUILTIN_GENERAL_ID
    end

    self.selectedID = nil
    self:refreshDraftList()
    if #self.tabList.items == 0 then
        self:beginNewTab()
    end
    self:setStatus("Chat tab removed from draft. Save to apply.")
end

function TabEditorWindow:discardDraft()
    self.draftState = nil
    self.selectedID = nil
    self.excludedChannelDraft = {}
end

function TabEditorWindow:cancel()
    self:discardDraft()
    self:setVisible(false)
end

function TabEditorWindow:open()
    if self.javaObject == nil then
        self:initialise()
        self:addToUIManager()
        ISLayoutManager.RegisterWindow("trpc_chat_tab_editor", ISCollapsableWindow, self)
    end
    self:setVisible(true)
    self:bringToTop()
    self:refreshTabs(self.selectedID)
end

function TabEditorWindow:close()
    self:discardDraft()
    self:setVisible(false)
end

function TabEditorWindow:new()
    local x, y, width, height = CalculateCoordinatesAndSize()
    local o = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o._parentClass = ISCollapsableWindow
    o:setResizable(false)
    o:setTitle(Text("UI_TRPC_chat_tab_editor_title", "Chat tabs"))
    o.excludedChannelDraft = {}
    o.draftState = nil
    o.selectedID = nil
    o.statusMessage = nil
    return o
end

return TabEditorWindow
