local ABubble = require("trpc/client/ui/bubble/ABubble")
local AvatarManager = require("trpc/client/AvatarManager")
local Character = require("trpc/shared/utils/Character")
local Coordinates = require("trpc/client/utils/Coordinates")
local Parser = require("trpc/client/parser/Parser")
local StringBuilder = require("trpc/client/parser/StringBuilder")

local PlayerBubble = ABubble:derive("PlayerBubble")

local function GetBadgeKind(channel, isAction)
    if isAction or channel == "me" or channel == "do" then
        return "action"
    elseif channel == "whisper" or channel == "low" then
        return "quiet"
    elseif channel == "yell" then
        return "yell"
    elseif channel == "say" then
        return "speech"
    end
    return "neutral"
end

function PlayerBubble:drawChannelBadge()
    local badgeKind = GetBadgeKind(self.channel, self.isAction)
    local badgeX = self.marginLeft - 13
    if self.playerModel then
        badgeX = self.marginLeft + 2
    end
    local badgeY = 2
    local alpha = self.alpha
    local dark = { r = 0.08, g = 0.09, b = 0.08 }
    local colors = {
        speech = { r = 0.72, g = 0.68, b = 0.47 },
        quiet = { r = 0.43, g = 0.55, b = 0.60 },
        yell = { r = 0.72, g = 0.45, b = 0.30 },
        action = { r = 0.65, g = 0.48, b = 0.66 },
        neutral = { r = 0.52, g = 0.52, b = 0.49 },
    }
    local color = colors[badgeKind]

    -- Keep the badge in the header strip, outside the text and portrait margins.
    self:drawRect(badgeX + 1, badgeY, 7, 1, alpha, dark.r, dark.g, dark.b)
    self:drawRect(badgeX, badgeY + 1, 9, 5, alpha, dark.r, dark.g, dark.b)
    self:drawRect(badgeX + 1, badgeY + 6, 5, 1, alpha, dark.r, dark.g, dark.b)

    if badgeKind == "speech" then
        self:drawRect(badgeX + 2, badgeY + 2, 5, 3, alpha, color.r, color.g, color.b)
        self:drawRect(badgeX + 3, badgeY + 5, 2, 1, alpha, color.r, color.g, color.b)
    elseif badgeKind == "quiet" then
        self:drawRect(badgeX + 2, badgeY + 2, 4, 1, alpha, color.r, color.g, color.b)
        self:drawRect(badgeX + 3, badgeY + 4, 3, 1, alpha, color.r, color.g, color.b)
    elseif badgeKind == "yell" then
        self:drawRect(badgeX + 4, badgeY + 1, 1, 4, alpha, color.r, color.g, color.b)
        self:drawRect(badgeX + 4, badgeY + 6, 1, 1, alpha, color.r, color.g, color.b)
        self:drawRect(badgeX + 2, badgeY + 2, 1, 1, alpha, color.r, color.g, color.b)
        self:drawRect(badgeX + 6, badgeY + 2, 1, 1, alpha, color.r, color.g, color.b)
    elseif badgeKind == "action" then
        self:drawRect(badgeX + 4, badgeY + 1, 1, 5, alpha, color.r, color.g, color.b)
        self:drawRect(badgeX + 2, badgeY + 3, 5, 1, alpha, color.r, color.g, color.b)
        self:drawRect(badgeX + 3, badgeY + 2, 3, 3, alpha, color.r, color.g, color.b)
    else
        self:drawRect(badgeX + 3, badgeY + 2, 3, 3, alpha, color.r, color.g, color.b)
        self:drawRect(badgeX + 2, badgeY + 5, 5, 1, alpha, color.r, color.g, color.b)
    end
end

function PlayerBubble:loadTextures()
    if self.isAction then
        self.bubbleTopLeft = getTexture("media/ui/trpc/bubble/simple/bubble-top-left-square.png")
        self.bubbleTopRight = getTexture("media/ui/trpc/bubble/simple/bubble-top-right-square.png")
        self.bubbleBotLeft = getTexture("media/ui/trpc/bubble/simple/bubble-bot-left-square.png")
        self.bubbleBotRight = getTexture("media/ui/trpc/bubble/simple/bubble-bot-right-square.png")
    else
        self.bubbleTopLeft = getTexture("media/ui/trpc/bubble/simple/bubble-top-left.png")
        self.bubbleTopRight = getTexture("media/ui/trpc/bubble/simple/bubble-top-right.png")
        self.bubbleBotLeft = getTexture("media/ui/trpc/bubble/simple/bubble-bot-left.png")
        self.bubbleBotRight = getTexture("media/ui/trpc/bubble/simple/bubble-bot-right.png")
    end
    self.bubbleTop = getTexture("media/ui/trpc/bubble/simple/bubble-top.png")
    self.bubbleCenter = getTexture("media/ui/trpc/bubble/simple/bubble-center.png")
    self.bubbleCenterLeft = getTexture("media/ui/trpc/bubble/simple/bubble-left.png")
    self.bubbleCenterRight = getTexture("media/ui/trpc/bubble/simple/bubble-right.png")
    self.bubbleBot = getTexture("media/ui/trpc/bubble/simple/bubble-bot.png")
    self.bubbleArrow = getTexture("media/ui/trpc/bubble/simple/bubble-arrow.png")

    self.bubbleBotLeftSquare = getTexture("media/ui/trpc/bubble/simple/bubble-bot-left-square.png")

    if self.portrait == 3 then
        self.avatarWidth = 33
        self.avatarHeight = 32
        local steamId = getSteamIDFromUsername(self.player:getUsername())
        if steamId ~= nil then
            self.playerAvatar = getSteamAvatarFromSteamID(steamId)
        end
    elseif self.portrait == 2 then
        self.avatarWidth = 60
        self.avatarHeight = 80
        local firstName, lastName = Character.getFirstAndLastName(self.player)
        self.playerAvatar = AvatarManager:getAvatar(self.player:getUsername(), firstName, lastName)
    end

    if self.portrait == 2 and self.playerAvatar == nil then
        self.avatarWidth = 25
        self.avatarHeight = 80
        self.playerModel = UI3DModel:new()
        -- there is a lot of free space left on the right so the avatarWidth is lower
        self.playerModel:setWidth(40)
        self.playerModel:setHeight(self.avatarHeight)
        self.playerModel:setCharacter(self.player)
        self.playerModel:setState("idle")
        self.playerModel:setDirection(IsoDirections.SE)
        self.playerModel:setIsometric(false)
        self.playerModel:setAnimate(false)
        self.playerModel:setZoom(17)
        self.playerModel:setYOffset(-0.92)
    end
end

function PlayerBubble:render()
    if self.dead then
        return
    end
    if not self.texturesLoaded then
        self:loadTextures()
        self.texturesLoaded = true
    end
    if self.playerAvatar then
        self.topSpace = math.max(self.avatarHeight - (self:getHeight() + 2), 0)
        self.marginLeft = self.avatarWidth + self.defaultLeftMargin
        self:setWidth(self.defaultWidth + self.avatarWidth)
    elseif self.playerModel then
        self.topSpace = math.max(self.avatarHeight - 20 - (self:getHeight() + 2), 0)
        self.marginLeft = self.avatarWidth + self.defaultLeftMargin
        self:setWidth(self.defaultWidth + self.avatarWidth)
    else
        self.topSpace = 0
        self.marginLeft = self.defaultLeftMargin
        self:setWidth(self.defaultWidth)
    end
    local x, y = Coordinates.CenterTopOfPlayer(self.player, self:getWidth(), self:getHeight())
    if x == nil then
        return
    end
    self:updateText(x, y)
    self:drawBubble()
    if self.dead then
        return
    end
    self:drawChannelBadge()
    if self.playerAvatar and (self.portrait == 3 or self.portrait == 2) then
        self:drawTextureScaled(
            self.playerAvatar,
            2,
            self:getHeight() - self.avatarHeight - 2,
            self.avatarWidth,
            self.avatarHeight,
            self.alpha
        )
    elseif self.playerModel then
        local width = self:getWidth()
        local height = self:getHeight()
        local screenWidth = getCore():getScreenWidth()
        local screenHeight = getCore():getScreenHeight()
        local modelX = self.currentX + 2
        if self.currentX < 0 then
            modelX = 2
        elseif self.currentX > screenWidth - width - 2 then
            modelX = 2 + screenWidth - width
        end
        local modelY = self.currentY + height - self.avatarHeight - 2
        if self.currentY < 0 then
            modelY = 0
        elseif self.currentY > screenHeight - height - 2 then
            modelY = screenHeight - self.avatarHeight - 2
        end
        self.playerModel:setX(modelX)
        self.playerModel:setY(modelY)
        self.playerModel:render()
    end
end

local function BuildPlayerNameString(playerName, playerColor)
    return StringBuilder.BuildBracketColorString(playerColor) .. playerName
end

function PlayerBubble:new(
    player,
    channel,
    isAction,
    message,
    messageColor,
    timer,
    opacity,
    portrait,
    showPlayerName,
    playerName,
    playerColor
)
    local parsedMessages = Parser.ParseTrpcMessage(message, messageColor, 20, 200)
    local rawMessage = parsedMessages["rawMessage"]
    local bubbleMessage = parsedMessages["bubble"]
    if showPlayerName then
        rawMessage = playerName .. " " .. rawMessage
        bubbleMessage = BuildPlayerNameString(playerName, playerColor) .. " " .. bubbleMessage
    end
    local textLength = getTextManager():MeasureStringX(UIFont.medium, rawMessage)
    local width = math.min(textLength * 1.25, 162) + 40
    local height = 0
    local x, y = Coordinates.CenterTopOfPlayer(player, width, height)
    if x == nil then
        x, y = 0, 0
    end
    local showArrow = not isAction
    local o = ABubble:new(
        x,
        y,
        bubbleMessage,
        rawMessage,
        message,
        messageColor,
        timer,
        opacity,
        20,
        showArrow,
        showPlayerName,
        playerName,
        playerColor
    )
    if x == nil then
        self.dead = true
    end
    setmetatable(o, PlayerBubble)
    o.channel = channel
    o.isAction = isAction
    o.player = player
    o.portrait = portrait
    return o
end

return PlayerBubble
