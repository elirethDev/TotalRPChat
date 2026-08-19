local BubbleSkin = {}

local BubbleColors = {
    outline = { r = 0.025, g = 0.03, b = 0.035 },
    fill = { r = 0.115, g = 0.12, b = 0.13 },
    highlight = { r = 0.22, g = 0.24, b = 0.26 },
    shadow = { r = 0.055, g = 0.065, b = 0.075 },
    arrow = { r = 0.16, g = 0.17, b = 0.18 },
}

local function DrawBubbleRect(self, x, y, width, height, color)
    if width > 0 and height > 0 then
        self:drawRect(x, y, width, height, self.alpha, color.r, color.g, color.b)
    end
end

function BubbleSkin.drawFrame(self, leftX, leftW, centerW, centerX, rightX, rightW, topH, centerY, botH, centerH, botY, isAction)
    if isAction then
        local width = math.max(math.floor(leftW + centerW + rightW), 1)
        local height = math.max(math.floor(topH + centerH + botH), 1)
        local colors = BubbleColors

        DrawBubbleRect(self, leftX, 0, width, height, colors.outline)
        DrawBubbleRect(self, leftX + 1, 1, width - 2, height - 2, colors.fill)
        DrawBubbleRect(self, leftX + 1, 1, width - 2, 1, colors.highlight)
        DrawBubbleRect(self, leftX + 1, 2, 1, height - 4, colors.highlight)
        DrawBubbleRect(self, leftX + 1, height - 2, width - 2, 1, colors.shadow)
        DrawBubbleRect(self, leftX + width - 2, 2, 1, height - 4, colors.shadow)
        return
    end

    local width = math.max(math.floor(rightX + rightW), 1)
    local height = math.max(math.floor(botY + botH), 1)
    local colors = BubbleColors

    if width >= 5 and height >= 7 then
        DrawBubbleRect(self, 2, 0, width - 4, 1, colors.outline)
        DrawBubbleRect(self, 1, 1, width - 2, 1, colors.outline)
        DrawBubbleRect(self, 0, 2, width, height - 4, colors.outline)
        DrawBubbleRect(self, 1, height - 2, width - 2, 1, colors.outline)
        DrawBubbleRect(self, 2, height - 1, width - 4, 1, colors.outline)

        DrawBubbleRect(self, 1, 2, width - 2, height - 4, colors.fill)
        DrawBubbleRect(self, 1, 2, width - 2, 1, colors.highlight)
        DrawBubbleRect(self, 1, 3, 1, height - 6, colors.highlight)
        DrawBubbleRect(self, 1, height - 3, width - 2, 1, colors.shadow)
        DrawBubbleRect(self, width - 2, 3, 1, height - 6, colors.shadow)
    else
        DrawBubbleRect(self, 0, 0, width, height, colors.outline)
        DrawBubbleRect(self, 1, 1, width - 2, height - 2, colors.fill)
    end
end

function BubbleSkin.drawArrow(self, x, y, width, height)
    local arrowWidth = math.max(math.floor(width), 1)
    local arrowHeight = math.max(math.floor(height), 1)
    local outline = BubbleColors.outline
    local fill = BubbleColors.arrow

    if arrowWidth >= 7 and arrowHeight >= 9 then
        DrawBubbleRect(self, x, y, 7, 1, outline)
        DrawBubbleRect(self, x, y + 1, 7, 1, outline)
        DrawBubbleRect(self, x + 1, y + 2, 5, 1, outline)
        DrawBubbleRect(self, x + 1, y + 3, 5, 1, outline)
        DrawBubbleRect(self, x + 2, y + 4, 3, 1, outline)
        DrawBubbleRect(self, x + 2, y + 5, 3, 1, outline)
        DrawBubbleRect(self, x + 3, y + 6, 1, arrowHeight - 6, outline)

        DrawBubbleRect(self, x + 1, y + 1, 5, 1, fill)
        DrawBubbleRect(self, x + 2, y + 2, 3, 2, fill)
        DrawBubbleRect(self, x + 3, y + 4, 1, 2, fill)
    else
        DrawBubbleRect(self, x, y, arrowWidth, arrowHeight, outline)
        DrawBubbleRect(self, x + 1, y + 1, arrowWidth - 2, arrowHeight - 2, fill)
    end
end

return BubbleSkin
