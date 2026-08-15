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
