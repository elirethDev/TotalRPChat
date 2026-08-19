local ABubble = require("trpc/client/ui/bubble/ABubble")
local Coordinates = require("trpc/client/utils/Coordinates")
local Parser = require("trpc/client/parser/Parser")
local BubbleSkin = require("trpc/client/ui/bubble/BubbleSkin")

local RadioBubble = ABubble:derive("RadioBubble")

function RadioBubble:loadTextures()
    -- Radio bubbles keep the base lifecycle hook without loading legacy PNGs.
end

function RadioBubble:drawBubbleFrame(leftX, leftW, centerW, centerX, rightX, rightW, topH, centerY, botH, centerH, botY)
    BubbleSkin.drawFrame(
        self,
        leftX,
        leftW,
        centerW,
        centerX,
        rightX,
        rightW,
        topH,
        centerY,
        botH,
        centerH,
        botY,
        false
    )
end

function RadioBubble:drawBubbleArrow(x, y, width, height)
    BubbleSkin.drawArrow(self, x, y, width, height)
end

function RadioBubble:render()
    if self.dead then
        return
    end
    if not self.texturesLoaded then
        self:loadTextures()
        self.texturesLoaded = true
    end
    local x, y = RadioBubble.CenterTop(self.type, self.object, self:getWidth(), self:getHeight())
    y = y - self.offsetY * Core.getTileScale() / (Coordinates.GetZoom())
    if x == nil then
        return
    end
    self:updateText(x, y)
    self:drawBubble()
end

function RadioBubble.CenterTop(type, object, width, height)
    if type == RadioBubble.types.square then
        return Coordinates.CenterTopOfObject(object, width, height)
    elseif type == RadioBubble.types.player then
        local x, y = Coordinates.CenterTopOfPlayer(object, width, height)
        x = x + 30
        y = y - 30
        return x, y
    elseif type == RadioBubble.types.vehicle then
        return Coordinates.CenterTopOfPlayer(object, width, height)
    else
        error("tried to initialize RadioBubble without a type")
    end
end

RadioBubble.types = {
    square = 1,
    player = 2,
    vehicle = 3,
}

function RadioBubble:new(object, message, messageColor, timer, opacity, type, offsetY)
    local parsedMessages = Parser.ParseTrpcMessage(message, messageColor, ABubble.BUBBLE_WRAP_WORDS, 200)
    local textLength = getTextManager():MeasureStringX(UIFont.medium, parsedMessages["rawMessage"])
    local width = math.min(textLength * 1.25, 162) + 40
    local height = 0
    local x, y = RadioBubble.CenterTop(type, object, width, height)
    if x == nil then
        x, y = 0, 0
    end
    local o = ABubble:new(
        x,
        y,
        parsedMessages["bubble"],
        parsedMessages["rawMessage"],
        message,
        messageColor,
        timer,
        opacity,
        20,
        true,
        false,
        nil,
        nil
    )
    if x == nil then
        self.dead = true
    end
    setmetatable(o, RadioBubble)
    o.type = type
    o.object = object
    o.message = message
    o.color = messageColor
    o.offsetY = offsetY or 0
    return o
end

return RadioBubble
