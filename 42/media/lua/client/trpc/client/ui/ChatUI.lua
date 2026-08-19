local ChatUI = {}
local ChatState = require("trpc/client/ui/ChatState")

local Palette = {
    frame = { r = 0.10, g = 0.105, b = 0.11 },
    header = { r = 0.115, g = 0.12, b = 0.125 },
    headerInset = { r = 0.15, g = 0.155, b = 0.165 },
    body = { r = 0.07, g = 0.075, b = 0.08 },
    panel = { r = 0.115, g = 0.12, b = 0.125 },
    panelInset = { r = 0.065, g = 0.07, b = 0.075 },
    tab = { r = 0.15, g = 0.16, b = 0.17 },
    tabActive = { r = 0.25, g = 0.27, b = 0.29 },
    tabHover = { r = 0.21, g = 0.225, b = 0.24 },
    tabAlert = { r = 0.32, g = 0.12, b = 0.095 },
    accent = { r = 0.58, g = 0.61, b = 0.64 },
    text = { r = 0.88, g = 0.89, b = 0.90 },
    mutedText = { r = 0.68, g = 0.70, b = 0.72 },
    footer = { r = 0.06, g = 0.065, b = 0.07 },
    input = { r = 0.05, g = 0.055, b = 0.06 },
    inputEdge = { r = 0.28, g = 0.31, b = 0.34 },
    textSurface = { r = 0.055, g = 0.06, b = 0.065 },
    textInset = { r = 0.08, g = 0.085, b = 0.09 },
    textEdge = { r = 0.26, g = 0.29, b = 0.32 },
}

ChatUI.palette = Palette
ChatUI.tabPanel = {}
ChatUI.textEntry = {}

function ChatUI:prerender()
    ISChat.instance = self
    self.gearButton.onclick = self.onGearButtonClick

    self:setDrawFrame(true)

    if not ChatState.isFocused() then
        self.fade:update()
    end
    self:makeFade(self.fade:fraction())

    local width = self:getWidth()
    local height = self:getHeight()
    local th = self:titleBarHeight()
    local titlebarAlpha = self:calcAlpha(ISChat.minControlOpaque, ISChat.maxGeneralOpaque, self.fade:fraction())
    local headerAlpha = math.max(titlebarAlpha + 0.3, 1)
    local header = Palette.header
    local headerInset = Palette.headerInset
    local body = Palette.body

    self:drawRect(
        0,
        0,
        width,
        th,
        headerAlpha,
        header.r,
        header.g,
        header.b
    )

    if width > 2 and th > 2 then
        self:drawRect(1, 1, width - 2, th - 2, headerAlpha, headerInset.r, headerInset.g, headerInset.b)
    end

    local bodyHeight = height - th
    if bodyHeight > 0 then
        self:drawRect(0, th, width, bodyHeight, titlebarAlpha, body.r, body.g, body.b)
        if width > 2 and bodyHeight > 2 then
            self:drawRect(
                1,
                th + 1,
                width - 2,
                bodyHeight - 2,
                titlebarAlpha,
                Palette.panelInset.r,
                Palette.panelInset.g,
                Palette.panelInset.b
            )
        end
        if width > 2 then
            self:drawRect(1, th - 1, width - 2, 1, titlebarAlpha, Palette.accent.r, Palette.accent.g, Palette.accent.b)
        end
    end

    if self.servermsg then
        local x = getCore():getScreenWidth() / 2 - self:getX()
        local y = getCore():getScreenHeight() / 4 - self:getY()
        self:drawTextCentre(self.servermsg, x, y, 1, 0.1, 0.1, 1, UIFont.Title)
        self.servermsgTimer = self.servermsgTimer - UIManager.getMillisSinceLastRender()
        if self.servermsgTimer < 0 then
            self.servermsg = nil
            self.servermsgTimer = 0
        end
    end
end

function ChatUI:render()
    local width = self:getWidth()
    local height = self:getHeight()
    local th = self:titleBarHeight()
    if self.isCollapsed then
        height = th
    end
    if not self.isCollapsed and self.resizable and self.drawFrame and self.resizeWidget:getIsVisible() then
        local rh = self:resizeWidgetHeight()
        local footer = Palette.footer
        local a = 0.9
        self:drawRect(2, height - rh, width - 4, rh - 1, a, footer.r, footer.g, footer.b)
        self:drawRect(2, height - rh, width - 4, 1, a, Palette.accent.r, Palette.accent.g, Palette.accent.b)
        -- Scale the resize arrow to the corner widget (like vanilla) and brighten it
        -- so it is clearly visible against the dark resize bar.
        self:drawTextureScaled(
            self.resizeimage,
            width - rh + 1,
            height - rh + 1,
            rh - 2,
            rh - 2,
            0.95,
            1,
            1,
            1
        )
    end

    if self.clearStentil then
        self:clearStencilRect()
    end
    if self.drawFrame then
        self:drawRectBorder(
            0,
            0,
            width,
            height,
            self.borderColor.a,
            self.borderColor.r,
            self.borderColor.g,
            self.borderColor.b
        )
        if width > 2 and height > 2 then
            self:drawRectBorder(1, 1, width - 2, height - 2, 0.85, Palette.frame.r, Palette.frame.g, Palette.frame.b)
        end
    end

    if self.drawJoypadFocus then
        self:drawRectBorder(0, 0, self:getWidth(), self:getHeight(), 0.4, 0.2, 1.0, 1.0)
        self:drawRectBorder(1, 1, self:getWidth() - 2, self:getHeight() - 2, 0.4, 0.2, 1.0, 1.0)
    end
end

function ChatUI.tabPanel:prerender()
    -- if the mouse is over the tab panel and we got a tab to drag, we gonna display it outside
    if ISTabPanel.mouseOut and ISTabPanel.viewDragging and not ISMouseDrag.dragView then
        self:clearStencilRect()
        self:setStencilRect(
            0 - self:getAbsoluteX(),
            0 - self:getAbsoluteY(),
            getCore():getScreenWidth(),
            getCore():getScreenHeight()
        )
        -- self:drawRectBorder(self:getMouseX(), self:getMouseY(), ISTabPanel.viewDragging.view:getWidth(),
        --     ISTabPanel.viewDragging.view:getHeight(), 1, 1, 1, 1)
        self:clearStencilRect()
    end
    self:updateSmoothScrolling()
end

--************************************************************************--
--** ISTabPanel:render
--**
--************************************************************************--
function ChatUI.tabPanel:render()
    local newViewList = {}
    local tabDragSelected = -1
    if
        self.draggingTab
        and not self.isDragging
        and ISTabPanel.xMouse > -1
        and ISTabPanel.xMouse ~= self:getMouseX()
    then -- do we move the mouse since we have let the left button down ?
        self.isDragging = self.allowDraggingTabs
    end
    local tabWidth = self.maxLength
    local inset = 1 -- assumes a 1-pixel window border on the left to avoid
    local gap = 1 -- gap between tabs
    if self.isDragging and not ISTabPanel.mouseOut then
        -- we fetch all our view to remove the tab of the view we're dragging
        for i, viewObject in ipairs(self.viewList) do
            if i ~= (self.draggingTab + 1) then
                table.insert(newViewList, viewObject)
            else
                ISTabPanel.viewDragging = viewObject
            end
        end
        -- in wich tab slot are we dragging our tab
        tabDragSelected = self:getTabIndexAtX(self:getMouseX()) - 1
        tabDragSelected = math.min(#self.viewList - 1, math.max(tabDragSelected, 0))
        -- we draw a warm outline to show where our tab is going to be
        self:drawRectBorder(
            inset + (tabDragSelected * (tabWidth + gap)),
            0,
            tabWidth,
            self.tabHeight - 1,
            1,
            Palette.accent.r,
            Palette.accent.g,
            Palette.accent.b
        )
    else -- no dragging, we display all our tabs
        newViewList = self.viewList
    end
    -- our principal rect, wich display our different view
    local contentHeight = self.height - self.tabHeight
    local panel = Palette.panel
    local panelAlpha = self.backgroundColor.a
    self:drawRect(
        0,
        self.tabHeight,
        self.width,
        contentHeight,
        panelAlpha,
        panel.r,
        panel.g,
        panel.b
    )
    if self.width > 2 and contentHeight > 2 then
        self:drawRect(
            1,
            self.tabHeight + 1,
            self.width - 2,
            contentHeight - 2,
            panelAlpha,
            Palette.panelInset.r,
            Palette.panelInset.g,
            Palette.panelInset.b
        )
    end
    self:drawRectBorder(
        0,
        self.tabHeight,
        self.width,
        contentHeight,
        panelAlpha * 0.85,
        Palette.textEdge.r,
        Palette.textEdge.g,
        Palette.textEdge.b
    )
    local x = inset
    if self.centerTabs and (self:getWidth() >= self:getWidthOfAllTabs()) then
        x = (self:getWidth() - self:getWidthOfAllTabs()) / 2
    else
        x = x + self.scrollX
    end
    local widthOfAllTabs = self:getWidthOfAllTabs()
    local overflowLeft = self.scrollX < 0
    local overflowRight = x + widthOfAllTabs > self.width
    local blinkTabsAlphaNotUpdated = true
    if widthOfAllTabs > self.width then
        self:setStencilRect(0, 0, self.width, self.tabHeight)
    end
    for i, viewObject in ipairs(newViewList) do
        tabWidth = self.equalTabWidth and self.maxLength or viewObject.tabWidth
        -- if we drag a tab over an existing one, we move the other
        if tabDragSelected ~= -1 and i == (tabDragSelected + 1) then
            x = x + tabWidth + gap
        end
        local tabText = Palette.mutedText
        -- if this tab is the active one, we make the tab btn lighter
        if viewObject.name == self.activeView.name and not self.isDragging and not ISTabPanel.mouseOut then
            -- self:drawTextureScaled(ISTabPanel.tabSelected, x, 0, tabWidth, self.tabHeight - 1, self.tabTransparency, 1, 1,
            --     1)
            local active = Palette.tabActive
            tabText = Palette.text
            self:drawRect(x, 0, tabWidth, self.tabHeight - 1, self.tabTransparency, active.r, active.g, active.b)
            self:drawRect(x, self.tabHeight - 2, tabWidth, 2, self.tabTransparency, Palette.accent.r, Palette.accent.g, Palette.accent.b)
        else
            local alpha = self.tabTransparency
            local shouldBlink = false
            if self.blinkTabs then
                for j, tab in ipairs(self.blinkTabs) do
                    if tab and tab == viewObject.name then
                        shouldBlink = true
                    end
                end
            end
            if (self.blinkTab and self.blinkTab == viewObject.name) or (shouldBlink and blinkTabsAlphaNotUpdated) then
                blinkTabsAlphaNotUpdated = false
                if not self.blinkTabAlpha then
                    self.blinkTabAlpha = self.tabTransparency
                    self.blinkTabAlphaIncrease = false
                end

                if not self.blinkTabAlphaIncrease then
                    self.blinkTabAlpha = self.blinkTabAlpha
                        - 0.1 * self.tabTransparency * (UIManager.getMillisSinceLastRender() / 33.3)
                    if self.blinkTabAlpha < 0 then
                        self.blinkTabAlpha = 0
                        self.blinkTabAlphaIncrease = true
                    end
                else
                    self.blinkTabAlpha = self.blinkTabAlpha
                        + 0.1 * self.tabTransparency * (UIManager.getMillisSinceLastRender() / 33.3)
                    if self.blinkTabAlpha > self.tabTransparency then
                        self.blinkTabAlpha = self.tabTransparency
                        self.blinkTabAlphaIncrease = false
                    end
                end
                alpha = self.blinkTabAlpha
                local alert = Palette.tabAlert
                self:drawRect(x, 0, tabWidth, self.tabHeight - 1, alpha, alert.r, alert.g, alert.b)
                -- self:drawTextureScaled(ISTabPanel.tabUnSelected, x, 0, tabWidth, self.tabHeight - 1, self
                --     .tabTransparency, 1, 1, 1)
                -- self:drawRect(x, 0, tabWidth, self.tabHeight - 1, alpha, 1, 1, 1)
            elseif shouldBlink then
                alpha = self.blinkTabAlpha
                -- self:drawTextureScaled(ISTabPanel.tabUnSelected, x, 0, tabWidth, self.tabHeight - 1, self
                --     .tabTransparency, 1, 1, 1)
                -- self:drawRect(x, 0, tabWidth, self.tabHeight - 1, alpha, 1, 1, 1)
                local alert = Palette.tabAlert
                self:drawRect(x, 0, tabWidth, self.tabHeight - 1, alpha, alert.r, alert.g, alert.b)
            else
                -- self:drawTextureScaled(ISTabPanel.tabUnSelected, x, 0, tabWidth, self.tabHeight - 1, self
                --     .tabTransparency, 1, 1, 1)
                local tab = Palette.tab
                if
                    self:getMouseY() >= 0
                    and self:getMouseY() < self.tabHeight
                    and self:isMouseOver()
                    and self:getTabIndexAtX(self:getMouseX()) == i
                then
                    viewObject.fade:setFadeIn(true)
                    tab = Palette.tabHover
                else
                    viewObject.fade:setFadeIn(false)
                end
                viewObject.fade:update()
                -- self:drawTextureScaled(ISTabPanel.tabSelected, x, 0, tabWidth, self.tabHeight - 1,
                --     0.2 * viewObject.fade:fraction(), 1, 1, 1)
                local a = 0.72 -- 0.2 * viewObject.fade:fraction()
                self:drawRect(x, 0, tabWidth, self.tabHeight - 1, a, tab.r, tab.g, tab.b)
            end
        end
        self:drawTextCentre(
            viewObject.name,
            x + (tabWidth / 2),
            3,
            tabText.r,
            tabText.g,
            tabText.b,
            1,
            UIFont.Small
        )
        x = x + tabWidth + gap
    end
    local butPadX = 3
    if overflowLeft then
        local tex = getTexture("media/ui/arrow_left.png")
        local butWid = tex:getWidthOrig() + butPadX * 2
        self:drawRect(inset, 0, butWid, self.tabHeight, 1, Palette.footer.r, Palette.footer.g, Palette.footer.b)
        self:drawRectBorder(inset, 0, butWid, self.tabHeight, 1, Palette.accent.r, Palette.accent.g, Palette.accent.b)
        self:drawTexture(tex, inset + butPadX, (self.tabHeight - tex:getHeight()) / 2, 1, 1, 1, 1)
    end
    if overflowRight then
        local tex = getTexture("media/ui/arrow_right.png")
        local butWid = tex:getWidthOrig() + butPadX * 2
        self:drawRect(
            self.width - inset - butWid,
            0,
            butWid,
            self.tabHeight,
            1,
            Palette.footer.r,
            Palette.footer.g,
            Palette.footer.b
        )
        self:drawRectBorder(
            self.width - inset - butWid,
            0,
            butWid,
            self.tabHeight,
            1,
            Palette.accent.r,
            Palette.accent.g,
            Palette.accent.b
        )
        self:drawTexture(tex, self.width - butWid + butPadX, (self.tabHeight - tex:getHeight()) / 2, 1, 1, 1, 1)
    end
    if widthOfAllTabs > self.width then
        self:clearStencilRect()
    end
    -- we draw a ghost of our tab we currently dragging
    if self.draggingTab and self.isDragging and not ISTabPanel.mouseOut then
        if self.draggingTab > 0 then
            self:drawTextureScaled(
                ISTabPanel.tabSelected,
                inset + (self.draggingTab * (tabWidth + gap)) + (self:getMouseX() - ISTabPanel.xMouse),
                0,
                tabWidth,
                self.tabHeight - 1,
                0.8,
                1,
                1,
                1
            )
            self:drawTextCentre(
                ISTabPanel.viewDragging.name,
                inset + (self.draggingTab * (tabWidth + gap)) + (self:getMouseX() - ISTabPanel.xMouse) + (tabWidth / 2),
                3,
                1,
                1,
                1,
                1,
                UIFont.Normal
            )
        else
            self:drawTextureScaled(
                ISTabPanel.tabSelected,
                inset + (self:getMouseX() - ISTabPanel.xMouse),
                0,
                tabWidth,
                self.tabHeight - 1,
                0.8,
                1,
                1,
                1
            )
            self:drawTextCentre(
                ISTabPanel.viewDragging.name,
                inset + (self:getMouseX() - ISTabPanel.xMouse) + (tabWidth / 2),
                3,
                1,
                1,
                1,
                1,
                UIFont.Normal
            )
        end
    end
end

function ChatUI.textEntry:prerender()
    local width = self:getWidth()
    local height = self:getHeight()
    local input = Palette.input
    local backgroundAlpha = self.backgroundColor and self.backgroundColor.a or 0.5

    self:drawRect(0, 0, width, height, backgroundAlpha, input.r, input.g, input.b)
    if width > 2 and height > 2 then
        self:drawRectBorder(0, 0, width, height, 0.8, Palette.inputEdge.r, Palette.inputEdge.g, Palette.inputEdge.b)
        self:drawRect(1, 1, width - 2, 1, 0.55, Palette.textEdge.r, Palette.textEdge.g, Palette.textEdge.b)
        if ChatState.isFocused() then
            self:drawRectBorder(1, 1, width - 2, height - 2, 0.8, Palette.accent.r, Palette.accent.g, Palette.accent.b)
        end
    end
end

function ChatUI.textEntry:instantiate()
    --self:initialise()
    self.javaObject = UITextBox2.new(self.font, self.x, self.y, self.width, self.height, self.title, false)
    self.javaObject:setTable(self)
    self.javaObject:setX(self.x)
    self.javaObject:setY(self.y)
    self.javaObject:setHeight(self.height)
    self.javaObject:setWidth(self.width)
    self.javaObject:setAnchorLeft(self.anchorLeft)
    self.javaObject:setAnchorRight(self.anchorRight)
    self.javaObject:setAnchorTop(self.anchorTop)
    self.javaObject:setAnchorBottom(self.anchorBottom)
    self.javaObject:setEditable(true)
    -- This forces the cursor to the end of the line
    self.javaObject:SetText(self.title)
end

return ChatUI
