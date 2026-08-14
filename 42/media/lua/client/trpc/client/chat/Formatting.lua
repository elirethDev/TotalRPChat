-- chat/Formatting.lua
-- ------------------------------
-- Módulo Formatting del Core TRPC.
-- Construcción de mensajes de chat: prefijos, colores por canal, verbos,
-- comillas, formateo de mensajes y líneas de chat.
--
-- Globals de PZ en runtime: TrpcServerSettings, UIFont, string.format
-- Requires propios: LanguageManager, Parser, StringBuilder.

local LanguageManager = require("trpc/client/languages/LanguageManager")
local Parser = require("trpc/client/parser/Parser")
local StringBuilder = require("trpc/client/parser/StringBuilder")

local Formatting = {}

local function BuildChannelPrefixString(channel)
    if channel == nil then
        return ""
    end
    local color
    if TrpcServerSettings ~= nil then
        color = TrpcServerSettings[channel]["color"]
    else
        color = { 255, 255, 255 }
    end
    return StringBuilder.BuildBracketColorString(color) .. "[" .. channel .. "] "
end

local function BuildLanguagePrefixString(languageCode)
    if languageCode == nil then
        return ""
    end
    local color = { 162, 162, 185 }
    return StringBuilder.BuildBracketColorString(color) .. "(" .. languageCode .. ") "
end

local function FontStringToEnum(fontString)
    if fontString == "small" then
        return UIFont.NewSmall
    elseif fontString == "medium" then
        return UIFont.Medium
    else
        return UIFont.Large
    end
end

local MessageTypeToColor = {
    ["whisper"] = { 130, 200, 200 },
    ["low"] = { 180, 230, 230 },
    ["say"] = { 255, 255, 255 },
    ["yell"] = { 230, 150, 150 },
    ["radio"] = { 144, 122, 176 },
    ["pm"] = { 255, 149, 211 },
    ["faction"] = { 100, 255, 66 },
    ["safehouse"] = { 220, 255, 80 },
    ["general"] = { 109, 111, 170 },
    ["admin"] = { 230, 130, 111 },
    ["ooc"] = { 146, 255, 148 },
}

local function BuildColorFromMessageType(type)
    if TrpcServerSettings ~= nil and TrpcServerSettings[type] and TrpcServerSettings[type]["color"] then
        return TrpcServerSettings[type]["color"]
    elseif MessageTypeToColor[type] == nil then
        error('unknown message type "' .. type .. '"')
    end
    return MessageTypeToColor[type]
end

local MessageTypeToVerb = {
    ["whisper"] = " whispers, ",
    ["low"] = " says quietly, ",
    ["say"] = " says, ",
    ["yell"] = " yells, ",
    ["radio"] = " over the radio, ",
    ["scriptedRadio"] = "over the radio, ",
    ["pm"] = " ",
    ["faction"] = " ",
    ["safehouse"] = " ",
    ["general"] = " ",
    ["admin"] = " ",
    ["ooc"] = " ",
}

local function BuildVerbString(type)
    if MessageTypeToVerb[type] == nil then
        error('unknown message type "' .. type .. '"')
    end
    return MessageTypeToVerb[type]
end

local NoQuoteTypes = {
    ["general"] = true,
    ["safehouse"] = true,
    ["faction"] = true,
    ["admin"] = true,
    ["pm"] = true,
    ["ooc"] = true,
}

local function BuildQuote(type)
    if NoQuoteTypes[type] == true then
        return ""
    end
    return '"'
end

local function BuildPlayerNameString(playerName, playerColor)
    return StringBuilder.BuildBracketColorString(playerColor) .. playerName
end

local function BuildMessageFromPacket(type, message, name, playerColor, frequency, disableVerb)
    local messageColor = BuildColorFromMessageType(type)
    local parsedMessage = Parser.ParseTrpcMessage(message, messageColor, 20, 200)
    local radioPrefix = ""
    if frequency then
        radioPrefix = "(" .. string.format("%.1fMHz", frequency / 1000) .. ") "
    end
    local messageColorString = StringBuilder.BuildBracketColorString(messageColor)
    local quote
    local verbString
    if
        not disableVerb
        and (TrpcServerSettings == nil or TrpcServerSettings["options"]["verb"] == true)
        and type ~= "do"
        and type ~= "me"
    then
        quote = BuildQuote(type)
        verbString = BuildVerbString(type)
    else
        quote = ""
        verbString = " "
    end
    local formatedMessage = ""
    if type == "do" then
        formatedMessage = formatedMessage .. "** "
    elseif type == "me" then
        formatedMessage = formatedMessage .. "* "
    end
    if name ~= nil and type ~= "do" then
        formatedMessage = formatedMessage .. BuildPlayerNameString(name, playerColor)
    end
    formatedMessage = formatedMessage
        .. StringBuilder.BuildBracketColorString({ 150, 150, 150 })
        .. verbString
        .. radioPrefix
        .. messageColorString
        .. quote
        .. parsedMessage.body
        .. messageColorString
        .. quote
    return formatedMessage, parsedMessage
end

local function BuildChatMessage(fontSize, showTimestamp, showTitle, showLanguage, language, rawMessage, time, channel)
    local line = StringBuilder.BuildFontSizeString(fontSize)
    if showTimestamp and time then
        line = line .. StringBuilder.BuildTimePrefixString(time)
    end
    if showTitle and channel ~= nil then
        line = line .. BuildChannelPrefixString(channel)
    end
    if showLanguage and language and language ~= LanguageManager.DefaultLanguage then
        local languageCode = LanguageManager.GetCodeFromLanguage(language)
        line = line .. BuildLanguagePrefixString(languageCode)
    end
    line = line .. rawMessage
    return line
end

-- API pública
Formatting.buildChannelPrefixString = BuildChannelPrefixString
Formatting.buildLanguagePrefixString = BuildLanguagePrefixString
Formatting.fontStringToEnum = FontStringToEnum
Formatting.buildColorFromMessageType = BuildColorFromMessageType
Formatting.buildVerbString = BuildVerbString
Formatting.buildQuote = BuildQuote
Formatting.buildPlayerNameString = BuildPlayerNameString
Formatting.buildMessageFromPacket = BuildMessageFromPacket
Formatting.buildChatMessage = BuildChatMessage

return Formatting