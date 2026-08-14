local ABubble = require("trpc/client/ui/bubble/ABubble")
local Parser = require("trpc/client/parser/Parser")

local KeyboardSound = require("trpc/client/voice/KeyboardSound")
local Logger = require("trpc/core/Logger")

local ContextBubble = ABubble:derive("ContextBubble")

function ContextBubble:loadTextures()
    self.bubbleTopLeft = getTexture("media/ui/trpc/bubble/simple/bubble-top-left-square.png")
    self.bubbleTopRight = getTexture("media/ui/trpc/bubble/simple/bubble-top-right-square.png")
    self.bubbleBotLeft = getTexture("media/ui/trpc/bubble/simple/bubble-bot-left-square.png")
    self.bubbleBotRight = getTexture("media/ui/trpc/bubble/simple/bubble-bot-right-square.png")
    self.bubbleTop = getTexture("media/ui/trpc/bubble/simple/bubble-top.png")
    self.bubbleCenter = getTexture("media/ui/trpc/bubble/simple/bubble-center.png")
    self.bubbleCenterLeft = getTexture("media/ui/trpc/bubble/simple/bubble-left.png")
    self.bubbleCenterRight = getTexture("media/ui/trpc/bubble/simple/bubble-right.png")
    self.bubbleBot = getTexture("media/ui/trpc/bubble/simple/bubble-bot.png")
end

function ContextBubble:render()
    if self.dead then
        return
    end
    if not self.texturesLoaded then
        self:loadTextures()
        self.texturesLoaded = true
    end

    self.marginLeft = self.defaultLeftMargin
    self:setWidth(self.targetWidth)

    local screenWidth = getCore():getScreenWidth()
    local x, y = screenWidth / 2 - self:getWidth() / 2, 150 - self:getHeight() / 2
    Logger.debug("ContextBubble", "x:" .. x .. ", y:" .. y)

    -- Intro animation (was in drawBubble): Lerp width from 0 to targetWidth
    if not self.isBubbleReady then
        local time = Calendar.getInstance():getTimeInMillis()
        local elapsedTime = time - self.startTime
        local delta = time - self.previousTime

        if elapsedTime > self.introAnimationTime then
            self.isBubbleReady = true
            self.currentX = self.targetX
            self.currentWidth = self.targetWidth
        else
            local newProgression = delta / (2 * 100)
            self.currentProgression = self.currentProgression + newProgression
            local progression = self.currentProgression
            if progression < 0.0 then
                progression = 0.0
            elseif progression >= 1.0 then
                progression = 1.0
            end
            self.currentWidth = (self.targetWidth - 0) * progression
            self.currentX = self.startingX - self.currentWidth / 2
        end
        self:setWidth(self.currentWidth)
        self:setX(self.currentX)
    end

    self:updateText(x, y)
    self:drawBubble()
end

function ContextBubble:new(message, messageColor, timer, opacity, isVoiceEnabled, voicePitch)
    local parsedMessages = Parser.ParseTrpcMessage(message, messageColor, 40, 200)
    local rawMessage = parsedMessages["rawMessage"]
    local bubbleMessage = parsedMessages["bubble"]

    local textLength = getTextManager():MeasureStringX(UIFont.medium, rawMessage)
    local width = math.min(textLength * 1.25, 364) + 40
    local height = 40
    local screenWidth = getCore():getScreenWidth()
    local x, y = screenWidth / 2 - width / 2, 150 - height / 2

    local o = ISTrpcRichTextPanel:new(x, y, width, height)
    setmetatable(o, self)

    if isVoiceEnabled then
        o.voice = KeyboardSound:new(rawMessage, getPlayer(), voicePitch)
    end
    o.text = ""
    o.timer = timer * 1000
    o.opacity = opacity / 100
    o.message = message
    o.color = messageColor
    o.rawText = rawMessage
    o.fullMessageLength = #rawMessage
    o.messageFinishedScrolling = false
    o.background = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.5 }
    o.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }

    o.anchorLeft = true
    o.anchorRight = false
    o.anchorTop = true
    o.anchorBottom = false

    o.moveWithMouse = false

    o.startTime = Calendar.getInstance():getTimeInMillis()
    o.previousTime = o.startTime
    o.dead = false

    ISUIElement.initialise(o)
    o:paginate()
    o:setHeight(height)

    o.introAnimationTime = 300
    o.texturesLoaded = false
    o.alpha = o.opacity
    o.fadingProgression = 1
    o.defaultLeftMargin = 20
    o.defaultTopMargin = 10
    o.topSpace = 0

    o.isBubbleReady = false
    o.startingX = screenWidth / 2
    o.currentX = o.startingX
    o.targetX = x
    o.currentWidth = 0
    o.targetWidth = width
    o.currentHeight = height
    o.currentProgression = 0
    return o
end

return ContextBubble
