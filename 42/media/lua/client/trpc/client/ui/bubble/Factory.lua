-- ui/bubble/Factory.lua
-- ------------------------------
-- Módulo BubbleFactory del Core TRPC.
-- Creación de burbujas visuales: de jugador, radio de cuadrado, radio de
-- jugador y radio de vehículo. Centraliza la construcción en registries
-- channel->constructor y delega el almacenamiento en BubbleState.
--
-- Este módulo NO referencia al singleton ISChat directamente: los valores que
-- antes leía (isVoiceEnabled, isPortraitEnabled) se reciben como parámetros, y
-- la configuración global (timer/opacity) se resuelve de forma centralizada en
-- getBubbleConfig().
--
-- Globals de PZ en runtime: TrpcServerSettings, getSquare
-- Requires propios: PlayerBubble, RadioBubble, World, Logger, ChatState,
--                   BubbleState

local PlayerBubble = require("trpc/client/ui/bubble/PlayerBubble")
local RadioBubble = require("trpc/client/ui/bubble/RadioBubble")
local World = require("trpc/shared/utils/World")
local Logger = require("trpc/core/Logger")
local ChatState = require("trpc/client/ui/ChatState")
local BubbleState = require("trpc/client/ui/bubble/BubbleState")
local Settings = require("trpc/shared/Settings")

local BubbleFactory = {}

-- Fuente de opciones del lado cliente: el payload wire TrpcServerSettings
-- (enviado por el servidor vía SendSandboxVars). El closure se evalúa en
-- cada get(): mientras TrpcServerSettings es nil (ventana ≤2s pre-primer
-- payload) devuelve nil y Settings.get cae a los defaults del catálogo.
Settings.setSource(function(name)
    if TrpcServerSettings == nil then
        return nil
    end
    local options = TrpcServerSettings["options"] or {}
    if name == "BubbleTimerInSeconds" then
        local bubble = options["bubble"] or {}
        return bubble["timer"]
    end
    if name == "BubbleOpacity" then
        local bubble = options["bubble"] or {}
        return bubble["opacity"]
    end
    if name == "BubblePortrait" then
        return options["portrait"]
    end
    return nil
end)

--- Read bubble config, overriding catalog defaults with the wire payload
-- (TrpcServerSettings) when present. Los defaults provienen del catálogo
-- compartido: timer=8, opacity=75, portrait=2 (sandbox-options.txt).
-- @return table { timer, opacity, portrait }
local function getBubbleConfig()
    return {
        timer = Settings.get("BubbleTimerInSeconds"),
        opacity = Settings.get("BubbleOpacity"),
        portrait = Settings.get("BubblePortrait"),
    }
end

-- Registry channel->config de burbujas de jugador. Los canales de acción
-- "do"/"me" producen PlayerBubble(isAction=true); cualquier otro canal produce
-- una burbuja normal (isAction=false). El channel es el parámetro recibido,
-- nunca se infiere de globales.
local playerChannelRegistry = {
    ["do"] = { isAction = true },
    ["me"] = { isAction = true },
}

-- Registry channel->config de burbujas de radio. Cada entrada describe el tipo
-- de RadioBubble y el kind del BubbleState donde se almacena.
local radioChannelRegistry = {
    square = {
        type = RadioBubble.types.square,
        stateKind = "radio",
    },
    player = {
        type = RadioBubble.types.player,
        stateKind = "playerRadio",
    },
    vehicle = {
        type = RadioBubble.types.vehicle,
        stateKind = "vehicleRadio",
    },
}

local function CreatePlayerBubble(
    author,
    channel,
    message,
    color,
    voiceEnabled,
    voicePitch,
    showPlayerName,
    authorName,
    authorColor,
    portraitEnabled
)
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
    local config = getBubbleConfig()
    local portrait = (portraitEnabled and config.portrait) or 1
    local channelConfig = playerChannelRegistry[channel] or { isAction = false }
    local bubble = PlayerBubble:new(
        authorObj,
        channelConfig.isAction,
        message,
        color,
        config.timer,
        config.opacity,
        voiceEnabled,
        voicePitch,
        portrait,
        showPlayerName,
        authorName,
        authorColor
    )
    BubbleState.addPlayer(author, bubble)
    -- the player is not typing anymore if his bubble appears
    if ChatState.getTypingDots()[author] ~= nil then
        ChatState.getTypingDots()[author] = nil
    end
end

--- Build and store a radio bubble for a given channel. Marks the previous
-- bubble at (stateKind, key) as dead via BubbleState.add.
local function BuildRadioBubble(channel, object, message, messageColor, voicePitch, voiceEnabled, key, offsetY)
    local entry = radioChannelRegistry[channel]
    if entry == nil then
        return
    end
    local config = getBubbleConfig()
    local bubble = RadioBubble:new(
        object,
        message,
        messageColor,
        config.timer,
        config.opacity,
        entry.type,
        voiceEnabled,
        voicePitch,
        offsetY
    )
    BubbleState.add(entry.stateKind, key, bubble)
end

local function CreateSquareRadioBubble(position, message, messageColor, voicePitch, voiceEnabled)
    if position ~= nil then
        local x, y, z = position["x"], position["y"], position["z"]
        if x == nil or y == nil or z == nil then
            Logger.error("BubbleFactory", "TRPC error: CreateSquareRadioBubble: nil position for a square radio")
            return
        end
        x, y, z = math.abs(x), math.abs(y), math.abs(z)
        local key = "x" .. x .. "y" .. y .. "z" .. z
        local square = getSquare(x, y, z)
        local offsetY = 0
        local radios = World.getSquareItemsByGroup(square, "IsoRadio")
        if radios ~= nil and #radios > 0 then
            offsetY = radios[1]:getRenderYOffset()
        end
        BuildRadioBubble("square", square, message, messageColor, voicePitch, voiceEnabled, key, offsetY)
    end
end

local function CreatePlayerRadioBubble(author, message, messageColor, voicePitch, voiceEnabled)
    if author == nil then
        Logger.error("BubbleFactory", "TRPC error: CreatePlayerRadioBubble: author is null")
        return
    end
    local authorObj = World.getPlayerByUsername(author)
    if authorObj == nil then
        Logger.error("BubbleFactory", "TRPC error: CreatePlayerRadioBubble: author not found " .. author)
        return
    end
    BuildRadioBubble("player", authorObj, message, messageColor, voicePitch, voiceEnabled, author)
end

local function CreateVehicleRadioBubble(vehicle, message, messageColor, voicePitch, voiceEnabled)
    local keyId = vehicle:getKeyId()
    if keyId == nil then
        Logger.error("BubbleFactory", "TRPC error: CreateVehicleBubble: key id is null")
        return
    end
    BuildRadioBubble("vehicle", vehicle, message, messageColor, voicePitch, voiceEnabled, keyId)
end

-- API pública
BubbleFactory.createPlayerBubble = CreatePlayerBubble
BubbleFactory.createSquareRadioBubble = CreateSquareRadioBubble
BubbleFactory.createPlayerRadioBubble = CreatePlayerRadioBubble
BubbleFactory.createVehicleRadioBubble = CreateVehicleRadioBubble
BubbleFactory.getBubbleConfig = getBubbleConfig

return BubbleFactory
