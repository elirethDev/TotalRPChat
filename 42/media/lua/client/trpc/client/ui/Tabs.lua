-- ui/Tabs.lua
-- ------------------------------
-- Módulo Tabs del Core TRPC.
-- Gestión de pestañas del chat: crear/eliminar pestañas, navegación por
-- tecla (siguiente pestaña) y por clic (mapeo posición->tabID).
--
-- Globals de PZ en runtime: ISChat
-- Requires propios: Streams (UpdateTabStreams)

local Streams = require("trpc/client/chat/Streams")

local Tabs = {}

local function GetFirstTab()
    if ISChat.instance.tabs == nil then
        return nil
    end
    for tabId, tab in pairs(ISChat.instance.tabs) do
        return tabId, tab
    end
end

local function AddTab(tabTitle, tabID)
    local chat = ISChat.instance
    if chat.tabs[tabID] ~= nil then
        return
    end
    local newTab = chat:createTab()
    newTab.parent = chat
    newTab.tabTitle = tabTitle
    newTab.tabID = tabID
    newTab.streamID = 1
    Streams.UpdateTabStreams(newTab, tabID)
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
        chat.currentTabID = tabID
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
    chat.tabs[tabID] = newTab
    chat.tabCnt = chat.tabCnt + 1
end

local function RemoveTab(tabTitle, tabID)
    local foundTab
    if ISChat.instance.tabs[tabID] ~= nil then
        foundTab = ISChat.instance.tabs[tabID]
        ISChat.instance.tabs[tabID] = nil
    else
        return
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
        return
    end
    if ISChat.instance.currentTabID == tabID then
        ISChat.instance.currentTabID = firstTabId
        local chat = ISChat.instance
        chat.panel:activateView(chat.tabs[chat.currentTabID].tabTitle)
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
end

local function GetTabIdFromView(view)
    if view and view.name then
        for tabId, tab in pairs(ISChat.instance.tabs) do
            if tab.tabTitle == view.name then
                return tabId
            end
        end
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

-- API pública
Tabs.addTab = AddTab
Tabs.removeTab = RemoveTab
Tabs.getTabIdFromView = GetTabIdFromView
Tabs.getNextTabId = GetNextTabId
Tabs.getTabFromOrder = GetTabFromOrder

return Tabs