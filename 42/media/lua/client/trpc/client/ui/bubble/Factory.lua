-- ui/bubble/Factory.lua
-- ------------------------------
-- Módulo BubbleFactory del Core TRPC.
-- Creación de burbujas visuales: de jugador, radio de cuadrado, radio de
-- jugador y radio de vehículo. Gestiona las tablas de burbujas vivas en
-- ISChat.instance.
--
-- Globals de PZ en runtime: ISChat, TrpcServerSettings, getSquare
-- Requires propios: ContextBubble, PlayerBubble, RadioBubble, World.

local ContextBubble = require("trpc/client/ui/bubble/ContextBubble")
local PlayerBubble = require("trpc/client/ui/bubble/PlayerBubble")
local RadioBubble = require("trpc/client/ui/bubble/RadioBubble")
local World = require("trpc/shared/utils/World")
local Logger = require("trpc/core/Logger")
local ChatState = require("trpc/client/ui/ChatState")

local BubbleFactory = {}

local function CreatePlayerBubble(
    author,
    type,
    message,
    color,
    voiceEnabled,
    voicePitch,
    showPlayerName,
    authorName,
    authorColor
)
    ISChat.instance.bubble = ISChat.instance.bubble or {}
    ChatState.setTypingDots(ChatState.getTypingDots() or {})
    if author == nil then
        Logger.error("BubbleFactory", "TRPC error: CreatePlayerBubble: author is null")
        return
    end
    local authorObj = World.getPlayerByUsername(author)
    if authorObj == nil then
        Logger.error("BubbleFactory", "TRPC error: CreatePlayerBubble: author not found " .. author)
        return
    end
    local timer = 10
    local opacity = 70
    if TrpcServerSettings then
        timer = TrpcServerSettings["options"]["bubble"]["timer"]
        opacity = TrpcServerSettings["options"]["bubble"]["opacity"]
    end
    local portrait = (
        TrpcServerSettings
        and ISChat.instance.isPortraitEnabled
        and TrpcServerSettings["options"]["portrait"]
    ) or 1
    local isAction = type == "me"
    if type ~= "do" then
        if ISChat.instance.bubble[author] then
            ISChat.instance.bubble[author].dead = true
        end
        ISChat.instance.bubble[author] = PlayerBubble:new(
            authorObj,
            isAction,
            message,
            color,
            timer,
            opacity,
            voiceEnabled,
            voicePitch,
            portrait,
            showPlayerName,
            authorName,
            authorColor
        )
    else
        if ISChat.instance.contextBubble then
            ISChat.instance.contextBubble.dead = true
        end
        ISChat.instance.contextBubble = ContextBubble:new(message, color, timer, opacity, voiceEnabled, voicePitch)
    end
    -- the player is not typing anymore if his bubble appears
    if ChatState.getTypingDots()[author] ~= nil then
        ChatState.getTypingDots()[author] = nil
    end
end

local function CreateSquareRadioBubble(position, message, messageColor, voicePitch)
    ISChat.instance.radioBubble = ISChat.instance.radioBubble or {}
    if position ~= nil then
        local x, y, z = position["x"], position["y"], position["z"]
        if x == nil or y == nil or z == nil then
            Logger.error("BubbleFactory", "TRPC error: CreateSquareRadioBubble: nil position for a square radio")
            return
        end
        x, y, z = math.abs(x), math.abs(y), math.abs(z)
        if ISChat.instance.radioBubble["x" .. x .. "y" .. y .. "z" .. z] ~= nil then
            ISChat.instance.radioBubble["x" .. x .. "y" .. y .. "z" .. z].dead = true
        end
        local timer = 10
        local opacity = 70
        local square = getSquare(x, y, z)
        local radios = World.getSquareItemsByGroup(square, "IsoRadio")
        local offsetY = 0
        if radios ~= nil and #radios > 0 then
            local radio = radios[1]
            offsetY = radio:getRenderYOffset()
        end
        local bubble = RadioBubble:new(
            square,
            message,
            messageColor,
            timer,
            opacity,
            RadioBubble.types.square,
            ISChat.instance.isVoiceEnabled,
            voicePitch,
            offsetY
        )
        ISChat.instance.radioBubble["x" .. x .. "y" .. y .. "z" .. z] = bubble
    end
end

local function CreatePlayerRadioBubble(author, message, messageColor, voicePitch)
    ISChat.instance.playerRadioBubble = ISChat.instance.playerRadioBubble or {}
    if author == nil then
        Logger.error("BubbleFactory", "TRPC error: CreatePlayerRadioBubble: author is null")
        return
    end
    local authorObj = World.getPlayerByUsername(author)
    if authorObj == nil then
        Logger.error("BubbleFactory", "TRPC error: CreatePlayerRadioBubble: author not found " .. author)
        return
    end
    local timer = 10
    local opacity = 70
    if TrpcServerSettings then
        timer = TrpcServerSettings["options"]["bubble"]["timer"]
        opacity = TrpcServerSettings["options"]["bubble"]["opacity"]
    end
    local bubble = RadioBubble:new(
        authorObj,
        message,
        messageColor,
        timer,
        opacity,
        RadioBubble.types.player,
        ISChat.instance.isVoiceEnabled,
        voicePitch
    )
    ISChat.instance.playerRadioBubble[author] = bubble
end

local function CreateVehicleRadioBubble(vehicle, message, messageColor, voicePitch)
    ISChat.instance.vehicleRadioBubble = ISChat.instance.vehicleRadioBubble or {}
    local timer = 10
    local opacity = 70
    if TrpcServerSettings then
        timer = TrpcServerSettings["options"]["bubble"]["timer"]
        opacity = TrpcServerSettings["options"]["bubble"]["opacity"]
    end
    local keyId = vehicle:getKeyId()
    if keyId == nil then
        Logger.error("BubbleFactory", "TRPC error: CreateVehicleBubble: key id is null")
        return
    end
    local bubble = RadioBubble:new(
        vehicle,
        message,
        messageColor,
        timer,
        opacity,
        RadioBubble.types.vehicle,
        ISChat.instance.isVoiceEnabled,
        voicePitch
    )
    ISChat.instance.vehicleRadioBubble[keyId] = bubble
end

-- API pública
BubbleFactory.createPlayerBubble = CreatePlayerBubble
BubbleFactory.createSquareRadioBubble = CreateSquareRadioBubble
BubbleFactory.createPlayerRadioBubble = CreatePlayerRadioBubble
BubbleFactory.createVehicleRadioBubble = CreateVehicleRadioBubble

return BubbleFactory
