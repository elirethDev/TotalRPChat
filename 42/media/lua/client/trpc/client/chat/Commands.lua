-- chat/Commands.lua
-- ------------------------------
-- Módulo ChatCommands del Core TRPC.
-- Parsing y ejecución de comandos de chat: streams (/say, /whisper...) y
-- slash commands (/color, /roll, /language).
--
-- Dependencias:
--   - Globals de PZ en runtime: getPlayer, getText, addSound, ISChat,
--     TrpcServerSettings, ModData
--   - Requires propios: ClientSend, LanguageManager, StringFormat,
--     StringParser, Parser, PlayerData
--
-- Solo expone processChatCommand y processTrpcCommand; el resto son helpers
-- internos del módulo.

local ClientSend = require("trpc/client/network/ClientSend")
local LanguageManager = require("trpc/client/languages/LanguageManager")
local Parser = require("trpc/client/parser/Parser")
local PlayerData = require("trpc/client/PlayerData")
local StringFormat = require("trpc/shared/utils/StringFormat")
local StringParser = require("trpc/shared/utils/StringParser")

local Commands = {}

-- Handler functions (defined before dispatch tables)

local function HandlePM(command, language, playerColor)
    local targetStart, targetEnd = command:find('^%s*"%a+%s?%a+"')
    if targetStart == nil then
        targetStart, targetEnd = command:find("^%s*%a+")
    end
    if targetStart == nil or targetEnd + 1 >= #command or command:sub(targetEnd + 1, targetEnd + 1) ~= " " then
        return false
    end
    local target = command:sub(targetStart, targetEnd)
    local pmBody = command:sub(targetEnd + 2)
    ClientSend.sendPrivateMessage(pmBody, language, playerColor, target)
    ISChat.instance.chatText.lastChatCommand = ISChat.instance.chatText.lastChatCommand .. target .. " "
    return true
end

local function ProcessColorCommand(arguments)
    local currentColor = ISChat.instance.trpcModData["playerColor"]
    if arguments == nil then
        ISChat.sendInfoToCurrentTab("color value is " .. StringFormat.color(currentColor))
        return true
    end
    local newColor = StringParser.rgbStringToRGB(arguments) or StringParser.hexaStringToRGB(arguments)
    if newColor == nil then
        return false
    end
    PlayerData.SetPlayerColor(newColor)
    ISChat.sendInfoToCurrentTab(
        "player color updated to " .. StringFormat.color(newColor) .. " from " .. StringFormat.color(currentColor)
    )
    return true
end

local function ProcessRollCommand(arguments)
    if arguments == nil then
        return false
    end
    local regex = "^(%d*)d(%d+)(%+?)(%d*) *$"
    local m1, m2, m3, m4 = arguments:match(regex)
    local diceCount = tonumber(m1)
    local diceType = tonumber(m2)
    local hasPlus = m3 == "+"
    local addCount = tonumber(m4)
    if diceType == nil or diceType < 1 then
        return false
    end
    if diceCount == nil then
        diceCount = 1
    end
    if diceCount < 1 or diceCount > 20 or (hasPlus and addCount == nil) then
        return false
    end
    ClientSend.sendRoll(diceCount, diceType, addCount)
    return true
end

local function ProcessLanguageCommand(arguments)
    if not TrpcServerSettings or not TrpcServerSettings["options"]["languages"] then
        ISChat.sendErrorToCurrentTab(getText("UI_TRPC_Messages_languages_disabled"))
        return true
    end
    if arguments == nil then
        local knownLanguages = LanguageManager:getKnownLanguages()
        local knownLanguagesFormatted = ""
        local first = true
        for _, languageCode in pairs(knownLanguages) do
            if not first then
                knownLanguagesFormatted = knownLanguagesFormatted .. ", "
            end
            knownLanguagesFormatted = knownLanguagesFormatted .. languageCode
            first = false
        end
        local currentLanguage = LanguageManager:getCurrentLanguage()
        local currentLanguageCode = LanguageManager.GetCodeFromLanguage(currentLanguage)
        local currentLanguageTranslated = LanguageManager.GetLanguageTranslated(currentLanguage)
        ISChat.sendInfoToCurrentTab(
            getText("UI_TRPC_Messages_current_language", currentLanguageTranslated, currentLanguageCode)
        )
        ISChat.sendInfoToCurrentTab(getText("UI_TRPC_Messages_known_languages", knownLanguagesFormatted))
        return true
    end
    local regex = "^(%a%a) *$"
    local languageCode = arguments:match(regex)
    if languageCode == nil then
        return false
    end
    if not LanguageManager:isCodeKnown(languageCode) then
        ISChat.sendErrorToCurrentTab(getText("UI_TRPC_Messages_unknown_language_code", languageCode))
        return true
    end
    LanguageManager:setCurrentLanguageFromCode(languageCode)
    local languageTranslated = LanguageManager.GetLanguageTranslatedFromCode(languageCode)
    ISChat.sendInfoToCurrentTab(getText("UI_TRPC_Messages_language_set_to", languageTranslated))
    return true
end

-- Helpers

local function RemoveLeadingSpaces(text)
    local trailingCount = 0
    for index = 1, #text do
        if text:byte(index) ~= 32 then -- 32 is ASCII code for space ' '
            break
        end
        trailingCount = trailingCount + 1
    end
    return text:sub(trailingCount)
end

local function GetArgumentsFromMessage(trpcCommand, message)
    local command = message:match("^/%a+")
    if #message < #command + 2 then -- command + space + chars
        return nil
    end
    local arguments = message:sub(#command + 2)
    arguments = RemoveLeadingSpaces(arguments)
    if #arguments == 0 then
        return nil
    end
    return arguments
end

-- Dispatch tables

local ChatDispatch = {
    yell = { type = "yell", disableVerb = false },
    say = { type = "say", disableVerb = false },
    low = { type = "low", disableVerb = false },
    whisper = { type = "whisper", disableVerb = false },
    me = { type = "me", disableVerb = true },
    ["do"] = { type = "do", disableVerb = true },
    pm = { handler = HandlePM },
    faction = { type = "faction", disableVerb = false },
    safehouse = { type = "safehouse", disableVerb = false },
    general = { type = "general", disableVerb = false },
    admin = { type = "admin", disableVerb = false },
    ooc = { type = "ooc", disableVerb = false },
}

local TrpcDispatch = {
    color = {
        fn = ProcessColorCommand,
        hint = 'color command expects the format: "/color value" with value as 255, 255, 255 or #FFFFFF',
    },
    roll = {
        fn = ProcessRollCommand,
        hint = 'roll command expects the format: "/roll xdy" with x and y numbers and x from 1 to 20',
    },
    language = {
        fn = ProcessLanguageCommand,
        hint = 'language command expects the format: "/language en" with "en" the language code',
    },
}

-- Processors

local function ProcessChatCommand(stream, command)
    if TrpcServerSettings and TrpcServerSettings[stream.name] == false then
        return false
    end
    local trpcCommand = Parser.ParseTrpcMessage(command)
    local playerColor = ISChat.instance.trpcModData["playerColor"]
    if trpcCommand == nil then
        return false
    end
    local language = LanguageManager:getCurrentLanguage()
    local entry = ChatDispatch[stream.name]
    if entry == nil then
        return false
    end
    if entry.handler then
        if entry.handler(command, language, playerColor) == false then
            return false
        end
    else
        ClientSend.sendChatMessage(command, language, playerColor, entry.type, entry.disableVerb)
    end
    if
        TrpcServerSettings ~= nil
        and TrpcServerSettings[stream.name] ~= nil
        and TrpcServerSettings[stream.name]["zombieRange"] ~= nil
        and TrpcServerSettings[stream.name]["zombieRange"] ~= -1
    then
        local zombieRange = TrpcServerSettings[stream.name]["zombieRange"]
        local square = getPlayer():getSquare()
        addSound(getPlayer(), square:getX(), square:getY(), square:getZ(), zombieRange, zombieRange)
    end
    return true
end

local function ProcessTrpcCommand(trpcCommand, message)
    local arguments = GetArgumentsFromMessage(trpcCommand, message)
    local entry = TrpcDispatch[trpcCommand["name"]]
    if entry then
        if entry.fn(arguments) == false then
            ISChat.sendErrorToCurrentTab(entry.hint)
            return false
        end
    end
end

-- API pública
Commands.processChatCommand = ProcessChatCommand
Commands.processTrpcCommand = ProcessTrpcCommand

return Commands
