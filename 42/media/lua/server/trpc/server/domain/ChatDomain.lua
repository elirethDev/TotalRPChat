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
local World = require("trpc/shared/utils/World")
local Settings = require("trpc/shared/Settings")

local ChatDomain = {}

-- Fuente de opciones del servidor: SandboxVars.TRPC es el lector canónico.
-- Los defaults del catálogo (sandbox-options.txt) cubren opciones ausentes.
Settings.setSource(function(name)
    return SandboxVars.TRPC[name]
end)

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
    local colorString = Settings.get(name .. "Color")
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
            ["range"] = Settings.get("WhisperRange"),
            ["zombieRange"] = Settings.get("WhisperZombieRange"),
            ["enabled"] = Settings.get("WhisperEnabled"),
            ["color"] = GetColorSandbox("Whisper"),
            ["radio"] = true,
            ["aliveOnly"] = true,
            ["bubble"] = true,
        },
        ["low"] = {
            ["range"] = Settings.get("LowRange"),
            ["zombieRange"] = Settings.get("LowZombieRange"),
            ["enabled"] = Settings.get("LowEnabled"),
            ["color"] = GetColorSandbox("Low"),
            ["radio"] = true,
            ["aliveOnly"] = true,
            ["bubble"] = true,
        },
        ["say"] = {
            ["range"] = Settings.get("SayRange"),
            ["zombieRange"] = Settings.get("SayZombieRange"),
            ["enabled"] = Settings.get("SayEnabled"),
            ["color"] = GetColorSandbox("Say"),
            ["radio"] = true,
            ["aliveOnly"] = true,
            ["bubble"] = true,
        },
        ["yell"] = {
            ["range"] = Settings.get("YellRange"),
            ["zombieRange"] = Settings.get("YellZombieRange"),
            ["enabled"] = Settings.get("YellEnabled"),
            ["color"] = GetColorSandbox("Yell"),
            ["radio"] = true,
            ["aliveOnly"] = true,
            ["bubble"] = true,
        },
        ["pm"] = {
            ["range"] = -1,
            ["zombieRange"] = -1,
            ["enabled"] = Settings.get("PrivateMessageEnabled"),
            ["color"] = GetColorSandbox("PrivateMessage"),
            ["radio"] = false,
            ["aliveOnly"] = true,
            ["bubble"] = false,
        },
        ["me"] = {
            ["range"] = Settings.get("MeRange"),
            ["zombieRange"] = 0,
            ["enabled"] = Settings.get("MeEnabled"),
            ["color"] = GetColorSandbox("Me"),
            ["radio"] = false,
            ["aliveOnly"] = true,
            ["bubble"] = true,
        },
        ["do"] = {
            ["range"] = Settings.get("DoRange"),
            ["zombieRange"] = 0,
            ["enabled"] = Settings.get("DoEnabled"),
            ["color"] = GetColorSandbox("Do"),
            ["radio"] = false,
            ["aliveOnly"] = true,
            ["bubble"] = true,
            ["adminOnly"] = Settings.get("DoAdminOnly"),
        },
        ["faction"] = {
            ["range"] = -1,
            ["zombieRange"] = -1,
            ["enabled"] = Settings.get("FactionMessageEnabled"),
            ["color"] = GetColorSandbox("FactionMessage"),
            ["radio"] = false,
            ["aliveOnly"] = true,
            ["bubble"] = false,
        },
        ["safehouse"] = {
            ["range"] = -1,
            ["zombieRange"] = -1,
            ["enabled"] = Settings.get("SafeHouseMessageEnabled"),
            ["color"] = GetColorSandbox("SafeHouseMessage"),
            ["radio"] = false,
            ["aliveOnly"] = true,
            ["bubble"] = false,
        },
        ["general"] = {
            ["range"] = -1,
            ["zombieRange"] = -1,
            ["enabled"] = Settings.get("GeneralMessageEnabled"),
            ["color"] = GetColorSandbox("GeneralMessage"),
            ["radio"] = false,
            ["aliveOnly"] = true,
            ["discord"] = Settings.get("GeneralDiscordEnabled"),
            ["bubble"] = false,
        },
        ["admin"] = {
            ["range"] = -1,
            ["zombieRange"] = -1,
            ["enabled"] = Settings.get("AdminMessageEnabled"),
            ["color"] = GetColorSandbox("AdminMessage"),
            ["radio"] = false,
            ["aliveOnly"] = false,
            ["bubble"] = false,
        },
        ["ooc"] = {
            ["range"] = Settings.get("OutOfCharacterMessageRange"),
            ["zombieRange"] = -1,
            ["enabled"] = Settings.get("OutOfCharacterMessageEnabled"),
            ["color"] = GetColorSandbox("OutOfCharacterMessage"),
            ["radio"] = false,
            ["bubble"] = true,
        },
        ["server"] = {
            ["color"] = { 255, 86, 64 },
        },
        ["scriptedRadio"] = {
            ["enabled"] = true,
            ["color"] = GetColorFromString(Settings.get("RadioColor")),
        },
        ["options"] = {
            ["showCharacterName"] = Settings.get("ShowCharacterName"),
            ["boredomReduction"] = Settings.get("BoredomReduction"),
            ["languages"] = Settings.get("Languages"),
            ["verb"] = Settings.get("VerbEnabled"),
            ["capitalize"] = Settings.get("Capitalize"),
            ["bubble"] = {
                ["timer"] = Settings.get("BubbleTimerInSeconds"),
                ["opacity"] = Settings.get("BubbleOpacity"),
            },
            ["radio"] = {
                ["discord"] = Settings.get("RadioDiscordEnabled"),
                ["frequency"] = Settings.get("RadioDiscordFrequency"),
                ["soundMaxRange"] = Settings.get("RadioSoundMaxRange"),
            },
            ["hideCallout"] = Settings.get("HideCallout"),
            ["isVoiceEnabled"] = Settings.get("VoiceEnabled"),
            ["portrait"] = Settings.get("BubblePortrait"),
        },
    }
end

-- PermissionRegistry: registro data-driven de permisos por canal (patrón ChannelRegistry).
-- Cada canal define closures puras, sin side-effects de red (los side-effects los resuelve
-- el caller — ChatMessage.ProcessMessage — vía errorCode):
--   authorAccess(author, args)            -> (ok: bool, errorCode: string?)   — sin side-effects
--   listenerAccess(author, player, args)  -> bool                            — sin side-effects
local PermissionRegistry = {
    ["whisper"] = {
        authorAccess = function(author, args)
            return true
        end,
        listenerAccess = function(author, player, args)
            return true
        end,
    },
    ["low"] = {
        authorAccess = function(author, args)
            return true
        end,
        listenerAccess = function(author, player, args)
            return true
        end,
    },
    ["say"] = {
        authorAccess = function(author, args)
            return true
        end,
        listenerAccess = function(author, player, args)
            return true
        end,
    },
    ["yell"] = {
        authorAccess = function(author, args)
            return true
        end,
        listenerAccess = function(author, player, args)
            return true
        end,
    },
    ["pm"] = {
        authorAccess = function(author, args)
            if args.target == nil or World.getPlayerByUsername(args.target) == nil then
                if args.target ~= nil then
                    return false, "UNKNOWN_PLAYER"
                end
                Logger.error(
                    "ChatDomain",
                    'TRPC error: Received a private message from "'
                        .. author:getUsername()
                        .. '" without a contact name'
                )
                return false
            end
            return true
        end,
        listenerAccess = function(author, player, args)
            return args.target ~= nil
                and args.author ~= nil
                and (
                    player:getUsername():lower() == args.target:lower()
                    or player:getUsername():lower() == args.author:lower()
                )
        end,
    },
    ["faction"] = {
        authorAccess = function(author, args)
            if Faction.getPlayerFaction(author) == nil then
                return false, "NO_FACTION"
            end
            return true
        end,
        listenerAccess = function(author, player, args)
            local authorFaction = Faction.getPlayerFaction(author)
            local playerFaction = Faction.getPlayerFaction(player)
            return playerFaction ~= nil and authorFaction ~= nil and playerFaction:getName() == authorFaction:getName()
        end,
    },
    ["safehouse"] = {
        authorAccess = function(author, args)
            if SafeHouse.hasSafehouse(author) == nil then
                return false, "NO_SAFEHOUSE"
            end
            return true
        end,
        listenerAccess = function(author, player, args)
            local playerSafeHouse = SafeHouse.hasSafehouse(player)
            local authorSafeHouse = SafeHouse.hasSafehouse(author)
            return playerSafeHouse ~= nil
                and authorSafeHouse ~= nil
                and playerSafeHouse:getTitle() == authorSafeHouse:getTitle()
        end,
    },
    ["general"] = {
        authorAccess = function(author, args)
            return true
        end,
        listenerAccess = function(author, player, args)
            return true
        end,
    },
    ["admin"] = {
        authorAccess = function(author, args)
            return author:getAccessLevel() == "Admin"
        end,
        listenerAccess = function(author, player, args)
            return player:getAccessLevel() == "Admin"
        end,
    },
    ["ooc"] = {
        authorAccess = function(author, args)
            return true
        end,
        listenerAccess = function(author, player, args)
            return true
        end,
    },
    ["me"] = {
        authorAccess = function(author, args)
            return true
        end,
        listenerAccess = function(author, player, args)
            return true
        end,
    },
    ["do"] = {
        authorAccess = function(author, args)
            if
                ChatDomain.MessageTypeSettings
                and (
                    not ChatDomain.MessageTypeSettings["do"]["adminOnly"]
                    or author:getAccessLevel() == "Admin"
                    or author:getAccessLevel() == "Moderator"
                )
            then
                return true
            end
            return false, "ADMIN_ONLY"
        end,
        listenerAccess = function(author, player, args)
            return true
        end,
    },
}

function ChatDomain.GetRangeForMessageType(type)
    local messageSettings = ChatDomain.MessageTypeSettings[type]
    if messageSettings ~= nil then
        return messageSettings["range"]
    end
    error('unknown message type "' .. type .. '"')
    return nil
end

function ChatDomain.IsAllowedToTalk(author, args)
    if args.type == nil then
        Logger.error("ChatDomain", "TRPC error: args.type is null")
        return false
    end
    local permission = PermissionRegistry[args.type]
    if permission == nil then
        Logger.error("ChatDomain", "TRPC error: PermissionRegistry has no method for type " .. args.type)
        return false
    end
    if ChatDomain.MessageTypeSettings[args.type] == nil then
        Logger.error("ChatDomain", "TRPC error: ChatDomain.MessageTypeSettings of " .. args.type .. " is null")
        return false
    end
    local settings = ChatDomain.MessageTypeSettings[args.type]
    if settings["enabled"] ~= true then
        return false
    end
    if settings["aliveOnly"] and author:getBodyDamage():getHealth() <= 0 then
        return false
    end
    return permission.authorAccess(author, args)
end

function ChatDomain.IsAllowedToListen(author, player, args)
    local permission = PermissionRegistry[args.type]
    if permission == nil then
        Logger.error(
            "ChatDomain",
            "TRPC error: IsAllowedToListen: PermissionRegistry has no method for " .. args.type
        )
        return false
    end
    return permission.listenerAccess(author, player, args)
end

-- API pública
ChatDomain.SetMessageTypeSettings = SetMessageTypeSettings
ChatDomain.GetRangeForMessageType = ChatDomain.GetRangeForMessageType
ChatDomain.IsAllowedToTalk = ChatDomain.IsAllowedToTalk
ChatDomain.IsAllowedToListen = ChatDomain.IsAllowedToListen

Events.OnServerStarted.Add(SetMessageTypeSettings)

return ChatDomain
