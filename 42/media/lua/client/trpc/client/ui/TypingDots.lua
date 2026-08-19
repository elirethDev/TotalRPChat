local Coordinates = require("trpc/client/utils/Coordinates")

local TypingDots = ISUIElement:derive("TypingDots")
local DotColors = {
    outline = { r = 0.025, g = 0.03, b = 0.035 },
    idle = { r = 0.16, g = 0.17, b = 0.18 },
    active = { r = 0.38, g = 0.41, b = 0.44 },
}
local DOT_SIZE = 5
local DOT_CORE_SIZE = 3
local DOT_INSET = 1
local DOT_Y = 0

local function drawDot(self, x, color)
    local outline = DotColors.outline
    self:drawRect(x + DOT_INSET, DOT_Y, DOT_CORE_SIZE, 1, 1, outline.r, outline.g, outline.b)
    self:drawRect(x, DOT_Y + DOT_INSET, DOT_SIZE, DOT_CORE_SIZE, 1, outline.r, outline.g, outline.b)
    self:drawRect(x + DOT_INSET, DOT_Y + DOT_SIZE - DOT_INSET, DOT_CORE_SIZE, 1, 1, outline.r, outline.g, outline.b)
    self:drawRect(x + DOT_INSET, DOT_Y + DOT_INSET, DOT_CORE_SIZE, DOT_CORE_SIZE, 1, color.r, color.g, color.b)
end

function TypingDots:render()
    local time = Calendar.getInstance():getTimeInMillis()
    if time - self.startingTime > self.timer then
        self.dead = true
        return
    end
    local elapsedTime = time - self.lastStepTime
    if elapsedTime >= self.stepTime then
        self.lastStepTime = time
        self.step = self.step % 3 + 1
    end

    local firstDot = DotColors.idle
    local secondDot = DotColors.idle
    local thirdDot = DotColors.idle
    if self.step == 1 then
        firstDot = DotColors.active
    elseif self.step == 2 then
        secondDot = DotColors.active
    else
        thirdDot = DotColors.active
    end

    local x, y = Coordinates.CenterTopOfPlayer(self.player, 20, 6)
    if x == nil then
        return
    end
    self:setX(x)
    self:setY(y - 6)
    drawDot(self, 0, firstDot)
    drawDot(self, 7, secondDot)
    drawDot(self, 14, thirdDot)
end

function TypingDots:refresh()
    self.startingTime = Calendar.getInstance():getTimeInMillis()
end

function TypingDots:new(player, timer)
    TypingDots.__index = self
    local x, y = Coordinates.CenterTopOfPlayer(player, 20, 6)
    if x == nil then
        x, y = 0, 0
    end
    setmetatable(TypingDots, { __index = ISUIElement })
    local o = ISUIElement:new(x, y, 20, 6)
    setmetatable(o, TypingDots)
    local time = Calendar.getInstance():getTimeInMillis()
    o.player = player
    o.startingTime = time
    o.lastStepTime = time
    o.stepTime = 250
    o.step = 1
    o.timer = timer * 1000
    o.dead = false
    o:instantiate()
    return o
end

return TypingDots
