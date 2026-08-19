-- chat/MessageStore.lua
-- Canonical client message history and filter-driven tab projections.

local TabFilters = require("trpc/client/chat/TabFilters")

local MessageStore = {}
MessageStore.__index = MessageStore
MessageStore.DEFAULT_MAX_MESSAGES = 100

local SYSTEM_SOURCES = {
    system = true,
    server = true,
    ["local"] = true,
}

local function IsSystemSource(source)
    return SYSTEM_SOURCES[source] == true
end

local function NormalizeMaxMessages(value)
    if type(value) ~= "number" or value ~= value or value == math.huge or value <= 0 or value ~= math.floor(value) then
        return MessageStore.DEFAULT_MAX_MESSAGES
    end
    return value
end

local function CopyRecord(input)
    local record = {}
    for key, value in pairs(input or {}) do
        record[key] = value
    end

    if record.channel == nil then
        record.channel = record.type
    end
    if record.type == nil then
        record.type = record.channel
    end
    if record.source == nil then
        record.source = record.sourceRoute
    end
    if record.sourceRoute == nil then
        record.sourceRoute = record.source
    end
    if record.radioFrequency == nil then
        record.radioFrequency = record.frequency
    end
    if record.frequency == nil then
        record.frequency = record.radioFrequency
    end
    if record.renderedLine == nil then
        record.renderedLine = record.line
    end
    if record.line == nil then
        record.line = record.renderedLine
    end
    if record.isFromDiscord == nil then
        record.isFromDiscord = false
    end

    local explicitIsSystem = record.isSystem
    if explicitIsSystem == nil then
        record.isSystem = record.kind == "system" or IsSystemSource(record.source)
    else
        record.isSystem = explicitIsSystem == true
    end

    local explicitIsPrivate = record.isPrivate
    if explicitIsPrivate == nil then
        record.isPrivate = record.kind == "private" or record.channel == "pm"
    else
        record.isPrivate = explicitIsPrivate == true
    end

    if record.kind == nil then
        if record.isSystem then
            record.kind = "system"
        elseif record.isPrivate then
            record.kind = "private"
        else
            record.kind = "chat"
        end
    end
    return record
end

local function AppendUnique(values, value)
    if value == nil then
        return
    end
    for _, existing in ipairs(values) do
        if existing == value then
            return
        end
    end
    table.insert(values, value)
end

local function CollectRouteIDs(route)
    if type(route) ~= "table" then
        return { route }
    end

    local ids = {}
    if #route > 0 then
        for _, tabID in ipairs(route) do
            AppendUnique(ids, tabID)
        end
    else
        for tabID, enabled in pairs(route) do
            if enabled then
                AppendUnique(ids, tabID)
            end
        end
    end
    return ids
end

local function CopyRouteIDs(routeIDs)
    local copy = {}
    for _, tabID in ipairs(routeIDs) do
        table.insert(copy, tabID)
    end
    return copy
end

local function IncludesRouteID(routeIDs, tabID)
    for _, routedTabID in ipairs(routeIDs) do
        if routedTabID == tabID then
            return true
        end
    end
    return false
end

local function MatchesView(record, tabID, filter)
    if record and record.routeIDs ~= nil then
        return IncludesRouteID(record.routeIDs, tabID)
    end
    return TabFilters.matches(record, filter)
end

function MessageStore.new(maxMessages)
    local store = {
        maxMessages = NormalizeMaxMessages(maxMessages),
        messages = {},
        views = {},
        viewOrder = {},
        nextID = 0,
    }
    setmetatable(store, MessageStore)
    return store
end

function MessageStore.createRecord(input)
    return CopyRecord(input)
end

function MessageStore:reset()
    self.messages = {}
    self.views = {}
    self.viewOrder = {}
    self.nextID = 0
end

function MessageStore:clearMessages()
    self.messages = {}
end

function MessageStore:registerView(tabID, filter)
    local existing = self.views[tabID]
    if self.views[tabID] == nil then
        table.insert(self.viewOrder, tabID)
    end
    local normalizedFilter = TabFilters.normalize(filter)
    self.views[tabID] = {
        filter = normalizedFilter,
        clearedAt = existing and existing.clearedAt or 0,
    }
    return normalizedFilter
end

function MessageStore:unregisterView(tabID)
    if self.views[tabID] == nil then
        return
    end
    self.views[tabID] = nil
    for index, existingID in ipairs(self.viewOrder) do
        if existingID == tabID then
            table.remove(self.viewOrder, index)
            return
        end
    end
end

function MessageStore:setViewFilter(tabID, filter)
    local view = self.views[tabID]
    if view == nil then
        return false
    end
    view.filter = TabFilters.normalize(filter)
    return true
end

function MessageStore:getViewFilter(tabID)
    local view = self.views[tabID]
    return view and view.filter or nil
end

function MessageStore:clearView(tabID)
    local view = self.views[tabID]
    if view == nil then
        return false
    end
    view.clearedAt = self.nextID
    return true
end

function MessageStore:getViewIDs()
    local ids = {}
    for _, tabID in ipairs(self.viewOrder) do
        table.insert(ids, tabID)
    end
    return ids
end

function MessageStore:setViewOrder(orderedIDs)
    local nextOrder = {}
    local seen = {}

    local function appendRegistered(tabID)
        if self.views[tabID] ~= nil and not seen[tabID] then
            seen[tabID] = true
            table.insert(nextOrder, tabID)
        end
    end

    -- General is always the first registered projection, regardless of the
    -- order supplied by a caller or persisted custom-tab definitions.
    appendRegistered(1)

    if type(orderedIDs) == "table" then
        for _, tabID in ipairs(orderedIDs) do
            appendRegistered(tabID)
        end
    end

    -- Registration order is already deterministic and supplies a stable
    -- fallback for registered views omitted by the requested order.
    for _, tabID in ipairs(self.viewOrder) do
        appendRegistered(tabID)
    end

    self.viewOrder = nextOrder
    return self:getViewIDs()
end

function MessageStore:getMatchingViewIDs(record)
    local matching = {}
    for _, tabID in ipairs(self.viewOrder) do
        local view = self.views[tabID]
        if MatchesView(record, tabID, view.filter) then
            table.insert(matching, tabID)
        end
    end
    return matching
end

function MessageStore:append(input, route)
    local record = CopyRecord(input)
    self.maxMessages = NormalizeMaxMessages(self.maxMessages)
    self.nextID = self.nextID + 1
    record.id = self.nextID
    record.sequence = record.id
    table.insert(self.messages, record)

    while #self.messages > self.maxMessages do
        table.remove(self.messages, 1)
    end

    local matching
    if route ~= nil then
        matching = CollectRouteIDs(route)
        record.routeIDs = CopyRouteIDs(matching)
    else
        matching = self:getMatchingViewIDs(record)
    end
    return record, matching
end

MessageStore.add = MessageStore.append

function MessageStore:getMessages()
    return self.messages
end

function MessageStore:getMessagesForView(tabID)
    local view = self.views[tabID]
    if view == nil then
        return {}
    end

    local messages = {}
    for _, record in ipairs(self.messages) do
        if record.id > (view.clearedAt or 0) and MatchesView(record, tabID, view.filter) then
            table.insert(messages, record)
        end
    end
    return messages
end

return MessageStore
