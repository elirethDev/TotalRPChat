-- server/domain/ChatDomain.lua
-- ------------------------------
-- Módulo ChatDomain del Core TRPC (servidor).
-- Lógica de dominio del chat extraída de ChatMessage.lua: configuración de
-- tipos de mensaje (MessageTypeSettings), control de acceso por autor y por
-- oyente, y cálculo de rango por tipo de mensaje.
--
-- Mantiene firmas exactas de las funciones originales de ChatMessage.

local StringParser = require("trpc/shared/utils/StringParser")
local Logger = require("trpc/core/Logger")
local ServerSend = require("trpc/server/network/ServerSend")
local World = require("trpc/shared/utils/World")

local ChatDomain = {}

local function GetColorFromString(colorString)
    local defaultColor = { 255, 0, 255 }
    local rgb = StringParser.hexaStringToRGB(colorString)
    if rgb == nil then
        Logger.error("ChatDomain", 'TRPC error: invalid color string: "' .. colorString .. '"')
        return defaultColor
    end
    return rgb
end

local function GetColorSandbox(name)
    local colorString = SandboxVars.TRPC[name .. "Color"]
    return GetColorFromString(colorString)
end

ChatDomain.MessageTypeSettings = nil

local function SetMessageTypeSettings()
    ChatDomain.MessageTypeSettings = {
        ["markdown"] = {
            ["italic"] = {
                ["color"] = GetColorSandbox("MarkdownOneAsterisk"),
            },
            ["bold"] = {
                ["color"] = GetColorSandbox("MarkdownTwoAsterisks"),
            },
        },
        ["whisper"] = {
            ["range"] = SandboxVars.TRPC.WhisperRange,
            ["zombieRange"] = SandboxVars.TRPC.WhisperZombieRange,
            ["enabled"] = SandboxVars.TRPC.WhisperEnabled,
            ["color"] = GetColorSandbox("Whisper"),
            ["radio"] = true,
            ["aliveOnly"] = true,
            ["bubble"] = true,
        },
        ["low"] = {
            ["range"] = SandboxVars.TRPC.LowRange,
            ["zombieRange"] = SandboxVars.TRPC.LowZombieRange,
            ["enabled"] = SandboxVars.TRPC.LowEnabled,
            ["color"] = GetColorSandbox("Low"),
            ["radio"] = true,
            ["aliveOnly"] = true,
            ["bubble"] = true,
        },
        ["say"] = {
            ["range"] = SandboxVars.TRPC.SayRange,
            ["zombieRange"] = SandboxVars.TRPC.SayZombieRange,
            ["enabled"] = SandboxVars.TRPC.SayEnabled,
            ["color"] = GetColorSandbox("Say"),
            ["radio"] = true,
            ["aliveOnly"] = true,
            ["bubble"] = true,
        },
        ["yell"] = {
            ["range"] = SandboxVars.TRPC.YellRange,
            ["zombieRange"] = SandboxVars.TRPC.YellZombieRange,
            ["enabled"] = SandboxVars.TRPC.YellEnabled,
            ["color"] = GetColorSandbox("Yell"),
            ["radio"] = true,
            ["aliveOnly"] = true,
            ["bubble"] = true,
        },
        ["pm"] = {
            ["range"] = -1,
            ["zombieRange"] = -1,
            ["enabled"] = SandboxVars.TRPC.PrivateMessageEnabled,
            ["color"] = GetColorSandbox("PrivateMessage"),
            ["radio"] = false,
            ["aliveOnly"] = true,
            ["bubble"] = false,
        },
        ["me"] = {
            ["range"] = SandboxVars.TRPC.MeRange,
            ["zombieRange"] = 0,
            ["enabled"] = SandboxVars.TRPC.MeEnabled,
            ["color"] = GetColorSandbox("Me"),
            ["radio"] = false,
            ["aliveOnly"] = true,
            ["bubble"] = true,
        },
        ["do"] = {
            ["range"] = SandboxVars.TRPC.DoRange,
            ["zombieRange"] = 0,
            ["enabled"] = SandboxVars.TRPC.DoEnabled,
            ["color"] = GetColorSandbox("Do"),
            ["radio"] = false,
            ["aliveOnly"] = true,
            ["bubble"] = true,
            ["adminOnly"] = SandboxVars.TRPC.DoAdminOnly,
        },
        ["faction"] = {
            ["range"] = -1,
            ["zombieRange"] = -1,
            ["enabled"] = SandboxVars.TRPC.FactionMessageEnabled,
            ["color"] = GetColorSandbox("FactionMessage"),
            ["radio"] = false,
            ["aliveOnly"] = true,
            ["bubble"] = false,
        },
        ["safehouse"] = {
            ["range"] = -1,
            ["zombieRange"] = -1,
            ["enabled"] = SandboxVars.TRPC.SafeHouseMessageEnabled,
            ["color"] = GetColorSandbox("SafeHouseMessage"),
            ["radio"] = false,
            ["aliveOnly"] = true,
            ["bubble"] = false,
        },
        ["general"] = {
            ["range"] = -1,
            ["zombieRange"] = -1,
            ["enabled"] = SandboxVars.TRPC.GeneralMessageEnabled,
            ["color"] = GetColorSandbox("GeneralMessage"),
            ["radio"] = false,
            ["aliveOnly"] = true,
            ["discord"] = SandboxVars.TRPC.GeneralDiscordEnabled,
            ["bubble"] = false,
        },
        ["admin"] = {
            ["range"] = -1,
            ["zombieRange"] = -1,
            ["enabled"] = SandboxVars.TRPC.AdminMessageEnabled,
            ["color"] = GetColorSandbox("AdminMessage"),
            ["radio"] = false,
            ["aliveOnly"] = false,
            ["bubble"] = false,
        },
        ["ooc"] = {
            ["range"] = SandboxVars.TRPC.OutOfCharacterMessageRange,
            ["zombieRange"] = -1,
            ["enabled"] = SandboxVars.TRPC.OutOfCharacterMessageEnabled,
            ["color"] = GetColorSandbox("OutOfCharacterMessage"),
            ["radio"] = false,
            ["bubble"] = true,
        },
        ["server"] = {
            ["color"] = { 255, 86, 64 },
        },
        ["scriptedRadio"] = {
            ["enabled"] = true,
            ["color"] = GetColorFromString(SandboxVars.TRPC.RadioColor),
        },
        ["options"] = {
            ["showCharacterName"] = SandboxVars.TRPC.ShowCharacterName,
            ["boredomReduction"] = SandboxVars.TRPC.BoredomReduction,
            ["languages"] = SandboxVars.TRPC.Languages,
            ["verb"] = SandboxVars.TRPC.VerbEnabled,
            ["capitalize"] = SandboxVars.TRPC.Capitalize,
            ["bubble"] = {
                ["timer"] = SandboxVars.TRPC.BubbleTimerInSeconds,
                ["opacity"] = SandboxVars.TRPC.BubbleOpacity,
            },
            ["radio"] = {
                ["discord"] = SandboxVars.TRPC.RadioDiscordEnabled,
                ["frequency"] = SandboxVars.TRPC.RadioDiscordFrequency,
                ["soundMaxRange"] = SandboxVars.TRPC.RadioSoundMaxRange,
            },
            ["hideCallout"] = SandboxVars.TRPC.HideCallout,
            ["isVoiceEnabled"] = SandboxVars.TRPC.VoiceEnabled,
            ["portrait"] = SandboxVars.TRPC.BubblePortrait,
        },
    }
end

local AuthorHasAccessByType = {
    ["whisper"] = function(author, args, sendError)
        return true
    end,
    ["low"] = function(author, args, sendError)
        return true
    end,
    ["say"] = function(author, args, sendError)
        return true
    end,
    ["yell"] = function(author, args, sendError)
        return true
    end,
    ["pm"] = function(author, args, sendError)
        if args.target == nil or World.getPlayerByUsername(args.target) == nil then
            if args.target ~= nil then
                if sendError then
                    ServerSend.ChatErrorMessage(author, args.type, 'unknown player "' .. args.target .. '".')
                end
            else
                Logger.error(
                    "ChatDomain",
                    'TRPC error: Received a private message from "'
                        .. author:getUsername()
                        .. '" without a contact name'
                )
            end
            return false
        end
        return true
    end,
    ["faction"] = function(author, args, sendError)
        local hasFaction = Faction.getPlayerFaction(author) ~= nil
        if not hasFaction and sendError then
            ServerSend.ChatErrorMessage(author, args.type, "you are not part of a faction.")
        end
        return hasFaction
    end,
    ["safehouse"] = function(author, args, sendError)
        local hasSafeHouse = SafeHouse.hasSafehouse(author) ~= nil
        if not hasSafeHouse and sendError then
            ServerSend.ChatErrorMessage(author, args.type, "you are not part of a safe house.")
        end
        return hasSafeHouse
    end,
    ["general"] = function(author, args, sendError)
        return true
    end,
    ["admin"] = function(author, args, sendError)
        return author:getAccessLevel() == "Admin"
    end,
    ["ooc"] = function(author, args, sendError)
        return true
    end,
    ["me"] = function(author, args, sendError)
        return true
    end,
    ["do"] = function(author, args, sendError)
        if
            ChatDomain.MessageTypeSettings
            and (
                not ChatDomain.MessageTypeSettings["do"]["adminOnly"]
                or author:getAccessLevel() == "Admin"
                or author:getAccessLevel() == "Moderator"
            )
        then
            return true
        else
            if sendError then
                ServerSend.ChatErrorMessage(author, args.type, "requires admin privileges.")
            end
            return false
        end
    end,
}

local ListenerHasAccessByType = {
    ["whisper"] = function(author, player, args)
        return true
    end,
    ["low"] = function(author, player, args)
        return true
    end,
    ["say"] = function(author, player, args)
        return true
    end,
    ["yell"] = function(author, player, args)
        return true
    end,
    ["pm"] = function(author, player, args)
        return args.target ~= nil
            and args.author ~= nil
            and (
                player:getUsername():lower() == args.target:lower()
                or player:getUsername():lower() == args.author:lower()
            )
    end,
    ["faction"] = function(author, player, args)
        local authorFaction = Faction.getPlayerFaction(author)
        local playerFaction = Faction.getPlayerFaction(player)
        return playerFaction ~= nil and authorFaction ~= nil and playerFaction:getName() == authorFaction:getName()
    end,
    ["safehouse"] = function(author, player, args)
        local playerSafeHouse = SafeHouse.hasSafehouse(player)
        local authorSafeHouse = SafeHouse.hasSafehouse(author)
        return playerSafeHouse ~= nil
            and authorSafeHouse ~= nil
            and playerSafeHouse:getTitle() == authorSafeHouse:getTitle()
    end,
    ["general"] = function(author, player, args)
        return true
    end,
    ["admin"] = function(author, player, args)
        return player:getAccessLevel() == "Admin"
    end,
    ["ooc"] = function(author, player, args)
        return true
    end,
    ["me"] = function(author, args, sendError)
        return true
    end,
    ["do"] = function(author, args, sendError)
        return true
    end,
}

function ChatDomain.GetRangeForMessageType(type)
    local messageSettings = ChatDomain.MessageTypeSettings[type]
    if messageSettings ~= nil then
        return messageSettings["range"]
    end
    error('unknown message type "' .. type .. '"')
    return nil
end

function ChatDomain.IsAllowedToTalk(author, args, sendError)
    if args.type == nil then
        Logger.error("ChatDomain", "TRPC error: args.type is null")
        return false
    end
    if AuthorHasAccessByType[args.type] == nil then
        Logger.error("ChatDomain", "TRPC error: AuthorHasAccessByType has no method for type " .. args.type)
        return false
    end
    if ChatDomain.MessageTypeSettings[args.type] == nil then
        Logger.error("ChatDomain", "TRPC error: ChatDomain.MessageTypeSettings of " .. args.type .. " is null")
        return false
    end
    return ChatDomain.MessageTypeSettings[args.type]["enabled"] == true
        and (not ChatDomain.MessageTypeSettings[args.type]["aliveOnly"] or author:getBodyDamage():getHealth() > 0)
        and AuthorHasAccessByType[args.type](author, args, sendError)
end

function ChatDomain.IsAllowedToListen(author, player, args)
    if ListenerHasAccessByType[args.type] == nil then
        Logger.error(
            "ChatDomain",
            "TRPC error: IsAllowedToListen: MessageHasAccessByType has no method for " .. args.type
        )
        return false
    end
    return ListenerHasAccessByType[args.type](author, player, args)
end

-- API pública
ChatDomain.SetMessageTypeSettings = SetMessageTypeSettings
ChatDomain.GetRangeForMessageType = ChatDomain.GetRangeForMessageType
ChatDomain.IsAllowedToTalk = ChatDomain.IsAllowedToTalk
ChatDomain.IsAllowedToListen = ChatDomain.IsAllowedToListen

Events.OnServerStarted.Add(SetMessageTypeSettings)

return ChatDomain
