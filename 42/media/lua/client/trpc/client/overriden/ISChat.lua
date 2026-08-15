local TRPC_VERSION = require("trpc/shared/Version")

local ChatUI = require("trpc/client/ui/ChatUI")
local ChatText = require("trpc/client/ui/Chat/ChatText")

local ContextBubble = require("trpc/client/ui/bubble/ContextBubble")
local PlayerBubble = require("trpc/client/ui/bubble/PlayerBubble")
local RadioBubble = require("trpc/client/ui/bubble/RadioBubble")

local AvatarManager = require("trpc/client/AvatarManager")
local AvatarUploadWindow = require("trpc/client/ui/AvatarUploadWindow")
local AvatarValidationWindow = require("trpc/client/ui/AvatarValidationWindow")
local Character = require("trpc/shared/utils/Character")
local LanguageManager = require("trpc/client/languages/LanguageManager")
local FakeRadioPacket = require("trpc/client/FakeRadioPacket")
local Parser = require("trpc/client/parser/Parser")
local RadioRangeIndicator = require("trpc/client/ui/RadioRangeIndicator")
local RangeIndicator = require("trpc/client/ui/RangeIndicator")
local ClientSend = require("trpc/client/network/ClientSend")
local StringBuilder = require("trpc/client/parser/StringBuilder")
local StringFormat = require("trpc/shared/utils/StringFormat")
local StringParser = require("trpc/shared/utils/StringParser")
local TypingDots = require("trpc/client/ui/TypingDots")
local World = require("trpc/shared/utils/World")
local Streams = require("trpc/client/chat/Streams")
local Commands = require("trpc/client/chat/Commands")
local PlayerData = require("trpc/client/PlayerData")
local Formatting = require("trpc/client/chat/Formatting")
local BubbleFactory = require("trpc/client/ui/bubble/Factory")
local Tabs = require("trpc/client/ui/Tabs")
local RangeController = require("trpc/client/ui/RangeController")
local ChatState = require("trpc/client/ui/ChatState")
local BubbleState = require("trpc/client/ui/bubble/BubbleState")
local EventBus = require("trpc/core/EventBus")
local Logger = require("trpc/core/Logger")

ISChat.allChatStreams = Streams.allChatStreams
ISChat.chatStreamsByName = Streams.chatStreamsByName
ISChat.trpcCommand = Streams.trpcCommand
ISChat.defaultTabStream = Streams.defaultTabStream
ISChat.lastTabStream = Streams.lastTabStream

local IsOnlySpacesOrEmpty = Streams.IsOnlySpacesOrEmpty
local GetCommandFromMessage = Streams.GetCommandFromMessage
local GetTrpcCommandFromMessage = Streams.GetTrpcCommandFromMessage
local UpdateTabStreams = Streams.UpdateTabStreams

ISChat.onSwitchStream = function()
    if ChatState.isFocused() then
        local t = ISChat.instance.textEntry
        local internalText = t:getInternalText()
        local data = luautils.split(internalText, " ")
        local onlineUsers = getOnlinePlayers()
        for i = 0, onlineUsers:size() - 1 do
            local username = onlineUsers:get(i):getUsername()
            if #data > 1 and string.match(string.lower(username), string.lower(data[#data])) then
                local txt = ""
                for i = 1, #data - 1 do
                    txt = txt .. data[i] .. " "
                end
                txt = txt .. username
                ISChat.instance.textEntry:setText(txt)
                return
            end
        end

        local curTxtPanel = ISChat.instance.chatText
        if curTxtPanel == nil then
            return
        end
        local chatStreams = curTxtPanel.chatStreams
        curTxtPanel.streamID = curTxtPanel.streamID % #chatStreams + 1
        local stream = chatStreams[curTxtPanel.streamID]
        ISChat.lastTabStream[ChatState.getCurrentTabID()] = stream
        ISChat.instance.textEntry:setText(stream.command)
        RangeController.updateRangeIndicator(stream)
    end
end

Events.OnChatWindowInit.Remove(ISChat.initChat)

local lastAskedDataTime = Calendar.getInstance():getTimeInMillis() - 2000
local function AskServerData()
    local delta = Calendar.getInstance():getTimeInMillis() - lastAskedDataTime
    if delta < 2000 then
        return
    end
    lastAskedDataTime = Calendar.getInstance():getTimeInMillis()

    ClientSend.sendAskSandboxVars()
end

local eventBusSetupDone = false
local function SetupEventBusSubscriptions()
    if eventBusSetupDone then
        return
    end
    eventBusSetupDone = true

    EventBus:subscribe("chat:message", function(args)
        ISChat.onMessagePacket(
            args["type"],
            args["author"],
            args["characterName"],
            args["message"],
            args["language"],
            args["color"],
            args["hideInChat"],
            args["target"],
            false,
            args["pitch"],
            args["disableVerb"]
        )
    end)

    EventBus:subscribe("chat:radio", function(args)
        ISChat.onRadioPacket(
            args["type"],
            args["author"],
            args["characterName"],
            args["message"],
            args["language"],
            args["color"],
            args["radios"],
            args["pitch"],
            args["disableVerb"]
        )
    end)

    EventBus:subscribe("chat:radio_emitting", function(args)
        ISChat.onRadioEmittingPacket(
            args["type"],
            args["author"],
            args["characterName"],
            args["message"],
            args["language"],
            args["color"],
            args["frequency"],
            args["disableVerb"]
        )
    end)

    EventBus:subscribe("chat:discord", function(args)
        ISChat.onDiscordPacket(args["message"])
    end)

    EventBus:subscribe("chat:typing", function(args)
        ISChat.onTypingPacket(args["author"], args["type"])
    end)

    EventBus:subscribe("chat:error", function(args)
        ISChat.onChatErrorPacket(args["type"], args["message"])
    end)

    EventBus:subscribe("chat:sandbox_vars", function(args)
        ISChat.onRecvSandboxVars(args)
    end)

    EventBus:subscribe("chat:dice_result", function(args)
        ISChat.onDiceResult(
            args["username"],
            args["characterName"],
            args["diceCount"],
            args["diceType"],
            args["addCount"],
            args["diceResults"],
            args["finalResult"]
        )
    end)
end

ISChat.initChat = function()
    TrpcServerSettings = nil
    SetupEventBusSubscriptions()
    local instance = ISChat.instance
    if instance.tabCnt == 1 then
        instance.chatText:setVisible(false)
        instance:removeChild(instance.chatText)
        instance.chatText = nil
    elseif instance.tabCnt > 1 then
        instance.panel:setVisible(false)
        for tabId, tab in pairs(ChatState.getTabs()) do
            instance.panel:removeView(tab)
        end
    end
    instance.tabCnt = 0
    ChatState.setTabs({})
    ChatState.setCurrentTabID(0)
    instance.rangeButtonState = "hidden"
    instance.online = false
    instance.lastDiscordMessages = {}

    PlayerData.InitGlobalModData()
    Tabs.addTab("General", 1)
    AvatarManager:createRequestDirectory()
    Events.OnPostRender.Add(AskServerData)
end

Events.OnGameStart.Remove(ISChat.createChat)

local function CreateChat()
    if not isClient() then
        return
    end
    ISChat.chat = ISChat:new(15, getCore():getScreenHeight() - 400, 500, 200)
    ISChat.chat:initialise()
    ISChat.chat:addToUIManager()
    ISChat.chat:setVisible(true)
    ISChat.chat:bringToTop()
    ISLayoutManager.RegisterWindow("chat", ISChat, ISChat.chat)

    ISChat.instance:setVisible(true)

    Events.OnAddMessage.Add(ISChat.addLineInChat)
    Events.OnMouseDown.Add(ISChat.unfocusEvent)
    Events.OnKeyPressed.Add(ISChat.onToggleChatBox)
    Events.OnKeyKeepPressed.Add(ISChat.onKeyKeepPressed)
    Events.OnTabAdded.Add(ISChat.onTabAdded)
    Events.OnSetDefaultTab.Add(ISChat.onSetDefaultTab)
    Events.OnTabRemoved.Add(ISChat.onTabRemoved)
    Events.SwitchChatStream.Add(ISChat.onSwitchStream)
end

Events.OnGameStart.Add(CreateChat)

function ISChat:onCommandEntered()
    local command = ISChat.instance.textEntry:getText()
    local chat = ISChat.instance

    ISChat.instance:unfocus()
    if not command or command == "" then
        return
    end

    local stream, commandName = GetCommandFromMessage(command)
    local trpcCommand = GetTrpcCommandFromMessage(command)
    Logger.debug(
        "Chat",
        "command entered [" .. tostring(command) .. "] trpc=" .. tostring(trpcCommand and trpcCommand.name or "nil")
    )
    if stream then -- chat message
        if #commandName > 0 and #command >= #commandName then
            -- removing the command and trailing space '/command '
            command = string.sub(command, #commandName + 1)
        end
        if IsOnlySpacesOrEmpty(command) then
            return
        end
        if not Commands.processChatCommand(stream, command) then
            return
        end
        chat.chatText.lastChatCommand = commandName
        chat:logChatCommand(command)
    elseif trpcCommand ~= nil then
        Commands.processTrpcCommand(trpcCommand, command)
    elseif luautils.stringStarts(command, "/") then -- server command
        SendCommandToServer(command)
        chat:logChatCommand(command)
    end

    if ISChat.instance.chatText then
        ISChat.instance.chatText:scrollToBottom()
    end
    doKeyPress(false)
    ISChat.instance.timerTextEntry = 20
end

function ISChat:updateChatPrefixSettings()
    updateChatSettings(self.chatFont, self.showTimestamp, self.showTitle)
    for tabNumber, chatText in pairs(ChatState.getTabs()) do
        chatText.firstPrintableLine = 1
        chatText.text = ""
        local newText = ""
        chatText.chatTextLines = {}
        chatText.chatTextRawLines = chatText.chatTextRawLines or {}
        chatText.defaultFont = Formatting.fontStringToEnum(self.chatFont or "medium")
        for i, msg in ipairs(chatText.chatTextRawLines) do
            self.chatFont = self.chatFont or "medium"
            local showLanguage = TrpcServerSettings and TrpcServerSettings["options"]["languages"]
            local line = Formatting.buildChatMessage(
                self.chatFont,
                self.showTimestamp,
                self.showTitle,
                showLanguage,
                msg.language,
                msg.line,
                msg.time,
                msg.channel
            )
            line = line .. StringBuilder.BuildNewLine()
            table.insert(chatText.chatTextLines, line)
            if i == #chatText.chatTextRawLines then
                line = string.gsub(line, "<LINE>$", "")
            end
            newText = newText .. line
        end
        chatText.text = newText
        chatText:paginate()
        chatText:scrollToBottom()
    end
end

function ISChat.onTypingPacket(author, type)
    ChatState.setTypingDots(ChatState.getTypingDots() or {})
    local onlineUsers = getOnlinePlayers()
    local authorObj = nil
    for i = 0, onlineUsers:size() - 1 do
        local user = onlineUsers:get(i)
        if user:getUsername() == author then
            authorObj = onlineUsers:get(i)
            break
        end
    end
    if authorObj == nil then
        return
    end
    if ChatState.getTypingDots()[author] then
        ChatState.getTypingDots()[author]:refresh()
    else
        ChatState.getTypingDots()[author] = TypingDots:new(authorObj, 1)
    end
end

local function GetStreamFromType(type)
    return ISChat.chatStreamsByName[type]
end

local function AddMessageToTab(tabID, language, time, formattedMessage, line, channel)
    if not ISChat.instance.chatText then
        ISChat.instance.chatText = ISChat.instance.defaultTab
        ISChat.instance:onActivateView()
    end
    local chatText = ChatState.getTabs()[tabID]

    chatText.chatTextRawLines = chatText.chatTextRawLines or {}
    table.insert(chatText.chatTextRawLines, {
        time = time,
        line = formattedMessage,
        channel = channel,
        language = language,
    })
    local chatTextRawLinesSize = #chatText.chatTextRawLines
    local maxRawMessages = chatText.maxLines
    if chatTextRawLinesSize > maxRawMessages then
        local newRawLines = {}
        for i = chatTextRawLinesSize - maxRawMessages, chatTextRawLinesSize do
            table.insert(newRawLines, chatText.chatTextRawLines[i])
        end
        chatText.chatTextRawLines = newRawLines
    end
    if chatText.tabTitle ~= ISChat.instance.chatText.tabTitle then
        local alreadyExist = false
        for _, blinkedTab in pairs(ISChat.instance.panel.blinkTabs) do
            if blinkedTab == chatText.tabTitle then
                alreadyExist = true
                break
            end
        end
        if alreadyExist == false then
            table.insert(ISChat.instance.panel.blinkTabs, chatText.tabTitle)
        end
    end
    local scrollAreaHeight = chatText:getScrollAreaHeight()
    local scrollHeight = chatText:getScrollHeight()
    local scrolledToBottom = scrollHeight <= scrollAreaHeight
        or math.abs(chatText:getYScroll()) >= scrollHeight - scrollAreaHeight - 1
    Logger.debug(
        "Scroll",
        "area="
            .. tostring(scrollAreaHeight)
            .. " h="
            .. tostring(scrollHeight)
            .. " y="
            .. tostring(chatText:getYScroll())
            .. " sB="
            .. tostring(scrolledToBottom)
    )
    if #chatText.chatTextLines > ISChat.maxLine then
        local newLines = {}
        for i, v in ipairs(chatText.chatTextLines) do
            if i ~= 1 then
                table.insert(newLines, v)
            end
        end
        table.insert(newLines, line .. StringBuilder.BuildNewLine())
        chatText.chatTextLines = newLines
    else
        table.insert(chatText.chatTextLines, line .. StringBuilder.BuildNewLine())
    end
    chatText.text = ""
    local newText = ""
    local chatTextLinesCount = #chatText.chatTextLines
    for i, v in ipairs(chatText.chatTextLines) do
        if i == chatTextLinesCount then
            v = string.gsub(v, "<LINE>$", "")
        end
        newText = newText .. v
    end
    chatText.text = newText
    chatText:paginate()
    if scrolledToBottom then
        chatText:scrollToBottom()
    end
end

local function ReduceBoredom()
    local player = getPlayer()
    if player:getStats() == nil then
        return
    end
    local boredom = player:getStats():get(CharacterStat.BOREDOM)
    local boredomReduction = 0
    if TrpcServerSettings then
        boredomReduction = TrpcServerSettings["options"]["boredomReduction"]
    end
    player:getStats():add(CharacterStat.BOREDOM, boredom - boredomReduction)
    if getCore():getDebug() then
        player:setHaloNote("Boredom " .. tostring(player:getStats():get(CharacterStat.BOREDOM)))
    end
end

function ISChat.onDiceResult(author, characterName, diceCount, diceType, addCount, diceResults, finalResult)
    Logger.debug("Roll", "onDiceResult entered")
    local name = characterName
    if TrpcServerSettings and not TrpcServerSettings["options"]["showCharacterName"] then
        name = author
    end
    local message = name .. " rolled " .. diceCount .. "d" .. diceType
    if addCount ~= nil then
        message = message .. "+" .. addCount
    end
    message = message .. " ("
    local first = true
    for _, r in pairs(diceResults) do
        if first then
            first = false
        else
            message = message .. ", "
        end
        message = message .. r
    end
    message = message .. ")"
    if addCount ~= nil then
        message = message .. "+" .. addCount
    end
    message = message .. " = " .. finalResult
    Logger.debug("Roll", "final message=[" .. tostring(message) .. "]")
    Logger.debug("Roll", "calling sendInfo, author=" .. tostring(author) .. " char=" .. tostring(characterName))
    ISChat.sendInfoToCurrentTab(message)
end

local function CapitalizeAndPonctuate(message)
    message = message:gsub("^%l", string.upper)
    local lastChar = string.sub(message, message:len())
    if not (lastChar == "." or lastChar == "!" or lastChar == "?") then
        message = message .. "."
    end
    return message
end

function ISChat.onMessagePacket(
    type,
    author,
    characterName,
    message,
    language,
    color,
    hideInChat,
    target,
    isFromDiscord,
    voicePitch,
    disableVerb
)
    if author ~= getPlayer():getUsername() then
        ReduceBoredom()
    end
    local name = characterName
    if TrpcServerSettings and not TrpcServerSettings["options"]["showCharacterName"] then
        name = author
    end

    local updatedMessage = message
    if TrpcServerSettings ~= nil and TrpcServerSettings["options"]["capitalize"] == true then
        updatedMessage = CapitalizeAndPonctuate(updatedMessage)
    end
    if type == "pm" and target:lower() == getPlayer():getUsername():lower() then
        ISChat.instance.lastPrivateMessageAuthor = author
    end
    ISChat.instance.chatFont = ISChat.instance.chatFont or "medium"
    local showLanguage = TrpcServerSettings and TrpcServerSettings["options"]["languages"]
    local showBubble = TrpcServerSettings and TrpcServerSettings[type] and TrpcServerSettings[type]["bubble"]
    if not isFromDiscord and voicePitch ~= nil and showBubble then
        if showLanguage and not LanguageManager:isKnown(language) and type ~= "me" and type ~= "do" then
            updatedMessage = LanguageManager:getRandomMessage(updatedMessage)
        end
        -- ooc should not distract the RP with voices
        local voiceEnabled = ISChat.instance.isVoiceEnabled and type ~= "ooc"
        BubbleFactory.createPlayerBubble(
            author,
            type,
            updatedMessage,
            Formatting.buildColorFromMessageType(type),
            voiceEnabled,
            voicePitch,
            type == "me",
            name,
            color,
            ISChat.instance.isPortraitEnabled
        )
    end
    local formattedMessage, parsedMessage =
        Formatting.buildMessageFromPacket(type, updatedMessage, name, color, nil, disableVerb)
    local time = Calendar.getInstance():getTimeInMillis()
    local line = Formatting.buildChatMessage(
        ISChat.instance.chatFont,
        ISChat.instance.showTimestamp,
        ISChat.instance.showTitle,
        showLanguage,
        language,
        formattedMessage,
        time,
        type
    )
    local stream = GetStreamFromType(type)
    if stream == nil then
        Logger.error("ISChat", "TRPC error: onMessagePacket: stream not found")
        return
    end
    if not hideInChat then
        AddMessageToTab(stream["tabID"], language, time, formattedMessage, line, stream["name"])
    end
end

function BuildServerMessage(fontSize, showTimestamp, showTitle, rawMessage, time, channel)
    local line = StringBuilder.BuildFontSizeString(fontSize)
    if showTimestamp then
        line = line .. StringBuilder.BuildTimePrefixString(time)
    end
    if showTitle and channel ~= nil then
        line = line .. Formatting.buildChannelPrefixString(channel)
    end
    line = line .. rawMessage
    return line
end

function ISChat.onServerMessage(message)
    local color = (TrpcServerSettings and TrpcServerSettings["server"]["color"]) or { 255, 86, 64 }
    local time = Calendar.getInstance():getTimeInMillis()
    local stream = GetStreamFromType("general")
    if stream == nil then
        Logger.error("ISChat", "TRPC error: onServerMessage: stream not found")
        return
    end
    local parsedMessage = Parser.ParseTrpcMessage(message, color, 20, 200)
    local line = Formatting.buildChatMessage(
        ISChat.instance.chatFont,
        ISChat.instance.showTimestamp,
        ISChat.instance.showTitle,
        false,
        nil,
        parsedMessage.body,
        time,
        "server"
    )
    AddMessageToTab(stream["tabID"], nil, time, parsedMessage.body, line, "server")
end

local function CreateSquaresRadiosBubbles(message, messageColor, squaresInfo, voicePitch)
    if squaresInfo == nil then
        Logger.error("ISChat", "TRPC error: CreateSquaresRadiosBubbles: squaresInfo table is null")
        return
    end
    for _, info in pairs(squaresInfo) do
        local position = info["position"]
        if position ~= nil then
            BubbleFactory.createSquareRadioBubble(
                position,
                message,
                messageColor,
                voicePitch,
                ISChat.instance.isVoiceEnabled
            )
            local square = getSquare(position["x"], position["y"], position["z"])
            if square ~= nil then
                local radio = World.getFirstSquareItem(square, "IsoRadio")
                if radio ~= nil then
                    local radioData = radio:getDeviceData()
                    if radioData ~= nil then
                        local distance = info["distance"]
                        if distance ~= nil then
                            radioData:doReceiveSignal(distance)
                        else
                            Logger.error(
                                "ISChat",
                                "TRPC error: received radio packet for a square radio without distance"
                            )
                        end
                    else
                        Logger.error("ISChat", "TRPC error: received radio packet for a square radio without data")
                    end
                else
                    Logger.error("ISChat", "TRPC error: received radio packet for a square with no radio")
                end
            else
                Logger.error("ISChat", "TRPC error: received radio packet for a null square")
            end
        else
            Logger.error("ISChat", "TRPC error: received radio packet for a square without position")
        end
    end
end

local function CreatePlayersRadiosBubbles(message, messageColor, playersInfo, voicePitch)
    if playersInfo == nil then
        Logger.error("ISChat", "TRPC error: CreatePlayersRadiosBubbles: playersInfo table is null")
        return
    end
    for _, info in pairs(playersInfo) do
        local username = info["username"]
        if username ~= nil then
            BubbleFactory.createPlayerRadioBubble(
                getPlayer():getUsername(),
                message,
                messageColor,
                voicePitch,
                ISChat.instance.isVoiceEnabled
            )
            if username:upper() == getPlayer():getUsername():upper() then
                local radio = Character.getFirstHandOrBeltItemByGroup(getPlayer(), "Radio")
                if radio ~= nil then
                    local radioData = radio:getDeviceData()
                    if radioData ~= nil then
                        local distance = info["distance"]
                        if distance ~= nil then
                            radioData:doReceiveSignal(distance)
                        else
                            Logger.error(
                                "ISChat",
                                "TRPC error: received radio packet for a player radio without distance"
                            )
                        end
                    else
                        Logger.error("ISChat", "TRPC error: received radio packet for a player radio without data")
                    end
                else
                    Logger.error("ISChat", "TRPC error: received radio packet for a player with no radio in hand")
                end
            end
        else
            Logger.error("ISChat", "TRPC error: received radio packet for a player without username")
        end
    end
end

local function CreateVehiclesRadiosBubbles(message, messageColor, vehiclesInfo, voicePitch)
    if vehiclesInfo == nil then
        Logger.error("ISChat", "TRPC error: CreateVehiclesRadiosBubbles: vehiclesKeyIds table is null")
        return
    end
    local range = (TrpcServerSettings and TrpcServerSettings["say"]["range"]) or 15
    local vehicles = World.getVehiclesInRange(getPlayer(), range)
    for _, info in pairs(vehiclesInfo) do
        local vehicleKeyId = info["key"]
        if vehicleKeyId ~= nil then
            local vehicle = vehicles[vehicleKeyId]
            if vehicle ~= nil then
                BubbleFactory.createVehicleRadioBubble(
                    vehicle,
                    message,
                    messageColor,
                    voicePitch,
                    ISChat.instance.isVoiceEnabled
                )
                local radio = vehicle:getPartById("Radio")
                if radio ~= nil then
                    local radioData = radio:getDeviceData()
                    if radioData ~= nil then
                        local distance = info["distance"]
                        if distance ~= nil then
                            radioData:doReceiveSignal(distance)
                        else
                            Logger.error(
                                "ISChat",
                                "TRPC error: received radio packet for a vehicle radio without distance"
                            )
                        end
                    else
                        Logger.error("ISChat", "TRPC error: received radio packet for a vehicle radio without data")
                    end
                else
                    Logger.error("ISChat", "TRPC error: received radio packet for a vehicle with no radio")
                end
            else
                Logger.error(
                    "ISChat",
                    "TRPC error: CreateVehiclesRadiosBubble: vehicle not found for key id " .. vehicleKeyId
                )
            end
        else
            Logger.error("ISChat", "TRPC error: received vehicle packet for a vehicle with no key")
        end
    end
end

function ISChat.onDiscordPacket(message)
    processGeneralMessage(message)
end

function ISChat.onRadioEmittingPacket(type, author, characterName, message, language, color, frequency, disableVerb)
    local time = Calendar.getInstance():getTimeInMillis()
    local stream = GetStreamFromType(type)
    if stream == nil then
        Logger.error("ISChat", "TRPC error: onRadioEmittingPacket: stream not found")
        return
    end
    local name = characterName
    if TrpcServerSettings and not TrpcServerSettings["options"]["showCharacterName"] then
        name = author
    end
    local cleanMessage = message
    if TrpcServerSettings ~= nil and TrpcServerSettings["options"]["capitalize"] == true then
        cleanMessage = CapitalizeAndPonctuate(message)
    end
    local formattedMessage, parsedMessages =
        Formatting.buildMessageFromPacket(type, cleanMessage, name, color, frequency, disableVerb)
    local showLanguage = TrpcServerSettings and TrpcServerSettings["options"]["languages"]
    local line = Formatting.buildChatMessage(
        ISChat.instance.chatFont,
        ISChat.instance.showTimestamp,
        ISChat.instance.showTitle,
        showLanguage,
        language,
        formattedMessage,
        time,
        type
    )
    AddMessageToTab(stream["tabID"], language, time, formattedMessage, line, stream["name"])
end

function ISChat.onRadioPacket(
    type,
    author,
    characterName,
    message,
    language,
    color,
    radiosInfo,
    voicePitch,
    disableVerb
)
    local time = Calendar.getInstance():getTimeInMillis()
    local stream = GetStreamFromType(type)
    if stream == nil then
        Logger.error("ISChat", "TRPC error: onRadioPacket: stream not found")
        return
    end

    local playerName = getPlayer():getUsername()
    if author ~= playerName then
        ReduceBoredom()
    end
    local name = characterName
    if TrpcServerSettings and not TrpcServerSettings["options"]["showCharacterName"] then
        name = author
    end
    local updatedMessage = message
    if TrpcServerSettings ~= nil and TrpcServerSettings["options"]["capitalize"] == true then
        updatedMessage = CapitalizeAndPonctuate(updatedMessage)
    end
    local showLanguage = TrpcServerSettings and TrpcServerSettings["options"]["languages"]
    for frequency, radios in pairs(radiosInfo) do
        if showLanguage and not LanguageManager:isKnown(language) then
            updatedMessage = LanguageManager:getRandomMessage(updatedMessage)
        end
        local messageColor = Formatting.buildColorFromMessageType(type)
        CreateSquaresRadiosBubbles(updatedMessage, messageColor, radios["squares"], voicePitch)
        CreatePlayersRadiosBubbles(updatedMessage, messageColor, radios["players"], voicePitch)
        CreateVehiclesRadiosBubbles(updatedMessage, messageColor, radios["vehicles"], voicePitch)

        local formattedMessage, parsedMessages =
            Formatting.buildMessageFromPacket(type, updatedMessage, name, color, frequency, disableVerb)
        local line = Formatting.buildChatMessage(
            ISChat.instance.chatFont,
            ISChat.instance.showTimestamp,
            ISChat.instance.showTitle,
            showLanguage,
            language,
            formattedMessage,
            time,
            type
        )
        -- a special packet is making sure the author always has a radio feedback in the chat
        -- useful in case the listening range and emitting range of the radio differs
        -- this is to avoid any confusion from players thinking the radios mights not work
        if author ~= playerName then
            AddMessageToTab(stream["tabID"], language, time, formattedMessage, line, stream["name"])
        end
    end
end

function ISChat.sendInfoToCurrentTab(message)
    local time = Calendar.getInstance():getTimeInMillis()
    local formattedMessage = StringBuilder.BuildBracketColorString({ 70, 70, 255 }) .. message
    local line = Formatting.buildChatMessage(
        ISChat.instance.chatFont,
        ISChat.instance.showTimestamp,
        false,
        false,
        nil,
        formattedMessage,
        time,
        nil
    )
    local tabID = ISChat.defaultTabStream[ChatState.getCurrentTabID()]["tabID"]
    Logger.debug(
        "Chat",
        "sendInfo currentTabID=" .. tostring(ChatState.getCurrentTabID()) .. " tabID=" .. tostring(tabID)
    )
    AddMessageToTab(tabID, nil, time, formattedMessage, line, nil)
end

function ISChat.sendErrorToCurrentTab(message)
    local time = Calendar.getInstance():getTimeInMillis()
    local formattedMessage = StringBuilder.BuildBracketColorString({ 255, 40, 40 })
        .. "error: "
        .. StringBuilder.BuildBracketColorString({ 255, 70, 70 })
        .. message
    local line = Formatting.buildChatMessage(
        ISChat.instance.chatFont,
        ISChat.instance.showTimestamp,
        false,
        false,
        nil,
        formattedMessage,
        time,
        nil
    )
    local tabID = ISChat.defaultTabStream[ChatState.getCurrentTabID()]["tabID"]
    AddMessageToTab(tabID, nil, time, formattedMessage, line, nil)
end

function ISChat.onChatErrorPacket(type, message)
    local time = Calendar.getInstance():getTimeInMillis()
    local formattedMessage = StringBuilder.BuildBracketColorString({ 255, 50, 50 })
        .. "error: "
        .. StringBuilder.BuildBracketColorString({ 255, 60, 60 })
        .. message
    local line = Formatting.buildChatMessage(
        ISChat.instance.chatFont,
        ISChat.instance.showTimestamp,
        ISChat.instance.showTitle,
        false,
        nil,
        formattedMessage,
        time,
        type
    )
    local stream
    if type == nil then
        stream = ISChat.defaultTabStream[ChatState.getCurrentTabID()]
    else
        stream = GetStreamFromType(type)
        if stream == nil then
            stream = ISChat.defaultTabStream[ChatState.getCurrentTabID()]
        end
    end
    AddMessageToTab(stream["tabID"], nil, time, formattedMessage, line)
end

local function GetMessageType(message)
    if message.toString == nil then
        return nil
    end
    local stringRep = message:toString()
    return stringRep:match("^ChatMessage{chat=(%a*),")
end

local function GenerateRadiosPacketFromListeningRadiosInRange(frequency)
    if TrpcServerSettings == nil then
        return nil
    end
    local maxSoundRange = TrpcServerSettings["options"]["radio"]["soundMaxRange"]
    local radios = FakeRadioPacket.getListeningRadiosPositions(getPlayer(), maxSoundRange, frequency)
    if radios == nil then
        return nil
    end
    return {
        [frequency] = radios,
    }
end

local function RemoveDiscordMessagePrefix(message)
    local regex = "<@%d+>(.*)"
    return message:match(regex)
end

-- TODO: try to clean this mess copied from the base game
ISChat.addLineInChat = function(message, tabID)
    if
        UdderlyUpToDate
        and message.setOverHeadSpeech == nil
        and message.isFromDiscord == nil
        and message.getDatetimeStr == nil
    then -- probably a fake message from UdderlyUpToDate mod
        ISChat.sendErrorToCurrentTab(message:getText())
        return
    end

    local messageType = GetMessageType(message)
    local line = message:getText()
    if messageType == nil then
        ISChat.sendInfoToCurrentTab(line)
        return
    end

    if message:getAuthor() == "Server" then
        ISChat.sendInfoToCurrentTab(line)
    elseif message:getRadioChannel() ~= -1 then -- scripted radio message
        local messageWithoutColorPrefix = message:getText():gsub("*%d+,%d+,%d+*", "")
        message:setText(messageWithoutColorPrefix)
        local color = (TrpcServerSettings and TrpcServerSettings["scriptedRadio"]["color"])
            or {
                171,
                240,
                140,
            }
        ISChat.onRadioPacket(
            "scriptedRadio",
            nil,
            nil,
            messageWithoutColorPrefix,
            "en",
            color,
            {}, -- todo find a way to locate the radio
            message:getRadioChannel(),
            false
        )
    else
        message:setOverHeadSpeech(false)
    end

    if messageType == "Local" then -- when pressing Q to shout
        local player = World.getPlayerByUsername(message:getAuthor())
        local firstName, lastName = Character.getFirstAndLastName(player)
        local characterName = firstName .. " " .. lastName
        ISChat.onMessagePacket(
            "yell",
            message:getAuthor(),
            characterName,
            line,
            LanguageManager.DefaultLanguage,
            { 255, 255, 255 },
            TrpcServerSettings and TrpcServerSettings["options"] and TrpcServerSettings["options"]["hideCallout"] or nil,
            nil,
            false,
            ISChat.instance.trpcModData["voicePitch"],
            false
        )
    end

    if message:isFromDiscord() then
        local currentDiscordMessage = message:getDatetimeStr() .. message:getText()
        local currentTime = Calendar.getInstance():getTimeInMillis()
        local isDuplicate = false
        local toRemove = {}
        for key, discordMessageInfo in pairs(ISChat.instance.lastDiscordMessages) do
            local discordMessage = discordMessageInfo["message"]
            local discordMessageTime = discordMessageInfo["time"]
            if currentTime - discordMessageTime < 2000 then
                if discordMessage == currentDiscordMessage then
                    isDuplicate = true
                end
            else
                table.insert(toRemove, key)
            end
        end
        for _, key in pairs(toRemove) do
            ISChat.instance.lastDiscordMessages[key] = nil
        end
        if isDuplicate then
            return
        end
        table.insert(ISChat.instance.lastDiscordMessages, {
            message = currentDiscordMessage,
            time = currentTime,
        })
        local discordColor = { 88, 101, 242 } -- discord logo color
        local messageWithoutPrefix = RemoveDiscordMessagePrefix(line)
        if messageWithoutPrefix == nil then
            -- for some reason some servers receive discord messages without the @discord-id-of-bot prefix
            messageWithoutPrefix = line
        end
        if
            TrpcServerSettings
            and TrpcServerSettings["general"]
            and TrpcServerSettings["general"]["discord"]
            and TrpcServerSettings["general"]["enabled"]
        then
            ISChat.onMessagePacket(
                "general",
                message:getAuthor(),
                message:getAuthor(),
                messageWithoutPrefix,
                "en",
                discordColor,
                false,
                nil,
                true,
                1.15, -- voice pitch, should not be used anyway
                false
            )
        end
        if
            TrpcServerSettings
            and TrpcServerSettings["options"]
            and TrpcServerSettings["options"]["radio"]
            and TrpcServerSettings["options"]["radio"]["discord"]
        then
            local frequency = TrpcServerSettings["options"]["radio"]["frequency"]
            if frequency then
                local radiosInfo = GenerateRadiosPacketFromListeningRadiosInRange(frequency)
                if radiosInfo ~= nil then
                    ISChat.onRadioPacket(
                        "say",
                        message:getAuthor(),
                        message:getAuthor(),
                        messageWithoutPrefix,
                        "en",
                        discordColor,
                        radiosInfo,
                        1.15,
                        false
                    )
                end
            end
        end
        return
    elseif message:isServerAlert() then
        ISChat.instance.servermsg = ""
        if message:isShowAuthor() then
            ISChat.instance.servermsg = message:getAuthor() .. ": "
        end
        ISChat.instance.servermsg = ISChat.instance.servermsg .. message:getText()
        ISChat.instance.servermsgTimer = 5000
        ISChat.instance.onServerMessage(line)
        return
    else
        return
    end
end

function ISChat:render()
    ChatUI.render(self)
end

function ISChat:prerender()
    local instance = ISChat.instance

    instance:createValidationWindowButton()

    if instance.rangeIndicator ~= nil then
        if instance.rangeButtonState == "visible" then
            if ChatState.isFocused() then
                instance.rangeIndicator:subscribe()
            else
                instance.rangeIndicator:unsubscribe()
            end
        elseif instance.rangeButtonState == "hidden" then
            instance.rangeIndicator:unsubscribe()
        else
            instance.rangeIndicator:subscribe()
        end
    end

    -- Render all living bubbles (player, radio, playerRadio, vehicleRadio,
    -- context) via the unified BubbleState render loop.
    BubbleState.renderAll()

    -- Typing dots are tracked separately in ChatState and rendered here.
    local typingDots = ChatState.getTypingDots()
    local indexToDelete = {}
    for index, bubble in pairs(typingDots) do
        if bubble.dead then
            table.insert(indexToDelete, index)
        else
            bubble:render()
        end
    end
    for _, index in pairs(indexToDelete) do
        typingDots[index] = nil
    end
    ChatUI.prerender(self)
end

function IsOnlyCommand(text)
    return text:match("/%a* *") == text
end

function ISChat.onTextChange()
    local t = ISChat.instance.textEntry
    local internalText = t:getInternalText()
    if
        #internalText > 1
        and IsOnlyCommand(internalText:sub(1, #internalText - 1))
        and internalText:sub(#internalText) == "/"
    then
        t:setText("/")
        if ISChat.instance.rangeIndicator then
            ISChat.instance.rangeIndicator:unsubscribe()
        end
        ISChat.instance.rangeIndicator = nil
        ISChat.instance.lastStream = nil
        return
    end

    if
        internalText == "/r"
        and ISChat.instance.lastPrivateMessageAuthor ~= nil
        and ChatState.getCurrentTabID() == 3
    then
        t:setText("/pm " .. ISChat.instance.lastPrivateMessageAuthor .. " ")
        return
    end
    local stream = GetCommandFromMessage(internalText)
    if stream ~= nil then
        if ISChat.instance.lastStream ~= stream then
            RangeController.updateRangeIndicator(stream)
        end
        -- you are allowed to use a command from another tab but it wont be remembered for the next message
        -- /me* commands are also not remembered as they should be occasional
        if ChatState.getCurrentTabID() == stream["tabID"] and not stream["forget"] then
            ISChat.lastTabStream[ChatState.getCurrentTabID()] = stream
        end
        local streamName = stream["name"]
        ClientSend.sendTyping(getPlayer():getUsername(), streamName)
    else
        if ISChat.instance.rangeIndicator then
            ISChat.instance.rangeIndicator:unsubscribe()
        end
        ISChat.instance.rangeIndicator = nil
    end
    ISChat.instance.lastStream = stream
end

function ISChat:onActivateView()
    if self.tabCnt > 1 then
        self.chatText = self.panel.activeView.view
    end
    for i, blinkedTab in ipairs(self.panel.blinkTabs) do
        if self.chatText.tabTitle and self.chatText.tabTitle == blinkedTab then
            table.remove(self.panel.blinkTabs, i)
            break
        end
    end
end

local function RenderChatText(chat)
    chat:setStencilRect(0, 0, chat.width, chat.height)
    ChatText.render(chat)
    chat:clearStencilRect()
end

function ISChat:createTab()
    local chatY = self:titleBarHeight() + self.btnHeight + 2 * self.inset
    local chatHeight = self.textEntry:getY() - chatY
    local chatText = ChatText:new(0, chatY, self:getWidth(), chatHeight)
    chatText.maxLines = 100
    chatText:initialise()
    chatText.background = false
    chatText:setAnchorBottom(true)
    chatText:setAnchorRight(true)
    chatText:setAnchorTop(true)
    chatText:setAnchorLeft(true)
    chatText.log = {}
    chatText.logIndex = 0
    chatText.marginTop = 2
    chatText.marginBottom = 0
    chatText.onRightMouseUp = nil
    chatText.render = RenderChatText
    chatText.autosetheight = false
    chatText:addScrollBars()
    chatText.vscroll:setVisible(false)
    chatText.vscroll.background = false
    chatText:ignoreHeightChange()
    chatText:setVisible(false)
    chatText.chatTextLines = {}
    chatText.chatMessages = {}
    chatText.onRightMouseUp = ISChat.onRightMouseUp
    chatText.onRightMouseDown = ISChat.onRightMouseDown
    chatText.onMouseUp = ISChat.onMouseUp
    chatText.onMouseDown = ISChat.onMouseDown
    return chatText
end

ISChat.onTabAdded = function(tabTitle, tabID)
    -- callback from the Java
    -- 0 is General
    -- 1 is Admin
    if tabID == 1 then
        if TrpcServerSettings ~= nil and TrpcServerSettings["admin"]["enabled"] and ChatState.getTabs()[4] == nil then
            Tabs.addTab("Admin", 4)
        end
    end
end

local function UpdateInfoWindow()
    local info = getText("SurvivalGuide_TRPC", TRPC_VERSION)
    info = info .. getText("SurvivalGuide_TRPC_Markdown")
    if TrpcServerSettings["whisper"]["enabled"] then
        info = info .. getText("SurvivalGuide_TRPC_Whisper")
    end
    if TrpcServerSettings["low"]["enabled"] then
        info = info .. getText("SurvivalGuide_TRPC_Low")
    end
    if TrpcServerSettings["say"]["enabled"] then
        info = info .. getText("SurvivalGuide_TRPC_Say")
    end
    if TrpcServerSettings["yell"]["enabled"] then
        info = info .. getText("SurvivalGuide_TRPC_Yell")
    end
    if TrpcServerSettings["me"]["enabled"] then
        info = info .. getText("SurvivalGuide_TRPC_Me")
    end
    if TrpcServerSettings["do"]["enabled"] and not TrpcServerSettings["do"]["adminOnly"] then
        info = info .. getText("SurvivalGuide_TRPC_Do")
    end
    if TrpcServerSettings["pm"]["enabled"] then
        info = info .. getText("SurvivalGuide_TRPC_Pm")
    end
    if TrpcServerSettings["faction"]["enabled"] then
        info = info .. getText("SurvivalGuide_TRPC_Faction")
    end
    if TrpcServerSettings["safehouse"]["enabled"] then
        info = info .. getText("SurvivalGuide_TRPC_SafeHouse")
    end
    if TrpcServerSettings["general"]["enabled"] then
        info = info .. getText("SurvivalGuide_TRPC_General")
    end
    if TrpcServerSettings["admin"]["enabled"] then
        info = info .. getText("SurvivalGuide_TRPC_Admin")
    end
    if TrpcServerSettings["ooc"]["enabled"] then
        info = info .. getText("SurvivalGuide_TRPC_Ooc")
    end
    info = info .. getText("SurvivalGuide_TRPC_Color")
    info = info .. getText("SurvivalGuide_TRPC_Pitch")
    info = info .. getText("SurvivalGuide_TRPC_Roll")
    if TrpcServerSettings["options"]["languages"] then
        info = info .. getText("SurvivalGuide_TRPC_Languages")
    end
    ISChat.instance:setInfo(info)
end

local function HasAtLeastOneChanelEnabled(tabId)
    if TrpcServerSettings == nil then
        return false
    end
    for _, stream in pairs(ISChat.allChatStreams) do
        local name = stream["name"]
        if stream["tabID"] == tabId and TrpcServerSettings[name] and TrpcServerSettings[name]["enabled"] then
            return true
        end
    end
    return false
end

ISChat.onRecvSandboxVars = function(messageTypeSettings)
    if TrpcServerSettings == nil then
        Events.OnPostRender.Remove(AskServerData)
    end

    local knownAvatars = AvatarManager:getKnownAvatars()
    ClientSend.sendKnownAvatars(knownAvatars)

    TrpcServerSettings = messageTypeSettings -- a global

    if HasAtLeastOneChanelEnabled(2) == true then
        Tabs.addTab("Out Of Character", 2)
    elseif ChatState.getTabs()[2] ~= nil then
        Tabs.removeTab("Out Of Character", 2)
    end
    if HasAtLeastOneChanelEnabled(3) == true then
        Tabs.addTab("Private Message", 3)
    elseif ChatState.getTabs()[3] ~= nil then
        Tabs.removeTab("Private Message", 3)
    end
    if getPlayer():getAccessLevel() == "Admin" and messageTypeSettings["admin"]["enabled"] then
        Tabs.addTab("Admin", 4)
    elseif ChatState.getTabs()[4] ~= nil then
        Tabs.removeTab("Admin", 4)
    end
    if ISChat.instance.tabCnt > 1 and not HasAtLeastOneChanelEnabled(1) then
        Tabs.removeTab("General", 1)
    else
        UpdateTabStreams(ChatState.getTabs()[1], 1)
    end

    RangeController.updateRangeIndicator(ISChat.defaultTabStream[ChatState.getCurrentTabID()])
    UpdateInfoWindow()
    if ISChat.instance.trpcModData == nil or ISChat.instance.trpcModData["isVoiceEnabled"] == nil then
        ISChat.instance.isVoiceEnabled = messageTypeSettings["options"]["isVoiceEnabled"]
    end
    local radioMaxRange = TrpcServerSettings["options"]["radio"]["soundMaxRange"]
    if ISChat.instance.radioRangeIndicator then
        ISChat.instance.radioRangeIndicator:unsubscribe()
    end
    ISChat.instance.radioRangeIndicator = RadioRangeIndicator:new(25, radioMaxRange, ISChat.instance.isRadioIconEnabled)
    if ISChat.instance.radioButtonState == true then
        ISChat.instance.radioRangeIndicator:subscribe()
    end
    ISChat.instance.online = true
end

ISChat.onTabRemoved = function(tabTitle, tabID)
    if tabID ~= 1 then -- Admin tab is 1 in the Java code
        return
    end
    Tabs.removeTab("Admin", 4) -- Admin tab is 4 in our table
end

ISChat.onSetDefaultTab = function(defaultTabTitle) end

ISChat.onToggleChatBox = function(key)
    if ISChat.instance == nil then
        return
    end
    if key == getCore():getKey("Toggle chat") or key == getCore():getKey("Alt toggle chat") then
        ISChat.instance:focus()
    end
    local chat = ISChat.instance
    if key == getCore():getKey("Switch chat stream") then
        local nextTabId = Tabs.getNextTabId(ChatState.getCurrentTabID())
        if nextTabId == nil then
            Logger.error("ISChat", "TRPC error: onToggleChatBox: next tab ID not found")
            return
        end
        ChatState.setCurrentTabID(nextTabId)
        chat.panel:activateView(ChatState.getTabs()[ChatState.getCurrentTabID()].tabTitle)
        ISChat.instance:onActivateView()
    end
end

ISChat.ISTabPanelOnMouseDown = function(target, x, y)
    if target:getMouseY() >= 0 and target:getMouseY() < target.tabHeight then
        if target:getScrollButtonAtX(x) == "left" then
            target:onMouseWheel(-1)
            return true
        end
        if target:getScrollButtonAtX(x) == "right" then
            target:onMouseWheel(1)
            return true
        end
        local tabIndex = target:getTabIndexAtX(target:getMouseX())
        local tabId = Tabs.getTabFromOrder(tabIndex)
        if tabId ~= nil then
            ChatState.setCurrentTabID(tabId)
        end
        -- if we clicked on a tab, the first time we set up the x,y of the mouse, so next time we can see if the player moved the mouse (moved the tab)
        if tabIndex >= 1 and tabIndex <= #target.viewList and ISTabPanel.xMouse == -1 and ISTabPanel.yMouse == -1 then
            ISTabPanel.xMouse = target:getMouseX()
            ISTabPanel.yMouse = target:getMouseY()
            target.draggingTab = tabIndex - 1
            local clickedTab = target.viewList[target.draggingTab + 1]
            target:activateView(clickedTab.name)
        end
    end
    return false
end

local function OnRangeButtonClick()
    if TrpcServerSettings == nil then
        return
    end
    if ISChat.instance.rangeButtonState == "visible" then
        ISChat.instance.rangeButtonState = "always-visible"
        ISChat.instance.rangeButton:setImage(getTexture("media/ui/RadioButtonCircle.png"))
    elseif ISChat.instance.rangeButtonState == "always-visible" then
        ISChat.instance.rangeButtonState = "hidden"
        ISChat.instance.rangeButton:setImage(getTexture("media/ui/RadioButtonCircle.png"))
    else
        ISChat.instance.rangeButtonState = "visible"
        ISChat.instance.rangeButton:setImage(getTexture("media/ui/RadioButtonCircle.png"))
    end
    RangeController.updateRangeIndicator(ISChat.lastTabStream[ChatState.getCurrentTabID()])
end

local function OnRadioButtonClick()
    if TrpcServerSettings == nil or ISChat.instance.radioRangeIndicator == nil then
        return
    end
    ISChat.instance.radioButtonState = not ISChat.instance.radioButtonState
    if ISChat.instance.radioButtonState == true then
        ISChat.instance.radioRangeIndicator:subscribe()
        ISChat.instance.radioButton:setImage(getTexture("media/ui/RadioButtonIndicator.png"))
    else
        ISChat.instance.radioRangeIndicator:unsubscribe()
        ISChat.instance.radioButton:setImage(getTexture("media/ui/RadioButtonIndicator.png"))
    end
end

local function OnAvatarUploadButtonClick()
    if ISChat.instance.avatarUploadWindow then
        ISChat.instance.avatarUploadWindow:unsubscribe()
    end
    ISChat.instance.avatarUploadWindow = AvatarUploadWindow:new()
    ISChat.instance.avatarUploadWindow:subscribe()
end

local function OnAvatarValidationWindowButtonClick()
    if ISChat.instance.avatarValidationWindow then
        ISChat.instance.avatarValidationWindow:unsubscribe()
    end
    ISChat.instance.avatarValidationWindow = AvatarValidationWindow:new()
    ISChat.instance.avatarValidationWindow:subscribe()
end

-- redefining ISTabPanel:activateView to remove the update of the info button
local function PanelActivateView(panel, viewName)
    local self = panel
    for ind, value in ipairs(self.viewList) do
        -- we get the view we want to display
        if value.name == viewName then
            self.activeView.view:setVisible(false)
            value.view:setVisible(true)
            self.activeView = value
            self:ensureVisible(ind)

            if self.onActivateView and self.target then
                self.onActivateView(self.target, self)
            end

            return true
        end
    end
    return false
end

function ISChat:createValidationWindowButton()
    if TrpcServerSettings == nil or TrpcServerSettings["options"]["portrait"] ~= 2 then
        if self.avatarUploadButton then
            self:removeChild(self.avatarUploadButton)
            self.avatarUploadButton = nil
        end
        if self.avatarValidationWindowButton then
            self:removeChild(self.avatarValidationWindowButton)
            self.avatarValidationWindowButton = nil
        end
        return
    end

    local th = self:titleBarHeight()
    if self.avatarUploadButton == nil then
        --avatar upload button
        ISChat.avatarUploadButtonName = "avatar upload"
        self.avatarUploadButton =
            ISButton:new(self.radioButton:getX() - th / 2 - th, 1, th, th, "", self, OnAvatarUploadButtonClick)
        self.avatarUploadButton.anchorRight = true
        self.avatarUploadButton.anchorLeft = false
        self.avatarUploadButton:initialise()
        self.avatarUploadButton.borderColor.a = 0.0
        self.avatarUploadButton.backgroundColor.a = 0
        self.avatarUploadButton.backgroundColorMouseOver.a = 0.5
        self.avatarUploadButton:setImage(getTexture("media/ui/inventoryPanes/Button_GuideN.png"))
        self.avatarUploadButton:setUIName(ISChat.avatarUploadButtonName)
        self:addChild(self.avatarUploadButton)
        self.avatarUploadButton:setVisible(true)
    end

    if self.avatarValidationWindowButton == nil then
        local accessLevel = getPlayer():getAccessLevel()
        if accessLevel == "Admin" or accessLevel == "Moderator" then
            ISChat.avatarValidationWindowButtonName = "avatar validation window button"
            self.avatarValidationWindowButton = ISButton:new(
                self.avatarUploadButton:getX() - th / 2 - th,
                1,
                th,
                th,
                "",
                self,
                OnAvatarValidationWindowButtonClick
            )
            self.avatarValidationWindowButton.anchorRight = true
            self.avatarValidationWindowButton.anchorLeft = false
            self.avatarValidationWindowButton:initialise()
            self.avatarValidationWindowButton.borderColor.a = 0.0
            self.avatarValidationWindowButton.backgroundColor.a = 0
            self.avatarValidationWindowButton.backgroundColorMouseOver.a = 0.5
            self.avatarValidationWindowButton:setImage(getTexture("media/ui/inventoryPanes/Button_GuideP.png"))
            self.avatarValidationWindowButton:setUIName(ISChat.avatarValidationWindowButtonName)
            self:addChild(self.avatarValidationWindowButton)
            self.avatarValidationWindowButton:setVisible(true)
        end
    end
end

function ISChat:createChildren()
    --window stuff
    -- Do corner x + y widget
    local rh = self:resizeWidgetHeight()
    local resizeWidget = ISResizeWidget:new(self.width - rh, self.height - rh, rh, rh, self)
    resizeWidget:initialise()
    resizeWidget.onMouseDown = ISChat.onMouseDown
    resizeWidget.onMouseUp = ISChat.onMouseUp
    resizeWidget:setVisible(self.resizable)
    resizeWidget:bringToTop()
    resizeWidget:setUIName(ISChat.xyResizeWidgetName)
    self:addChild(resizeWidget)
    self.resizeWidget = resizeWidget

    -- Do bottom y widget
    local resizeWidget2 = ISResizeWidget:new(0, self.height - rh, self.width - rh, rh, self, true)
    resizeWidget2.anchorLeft = true
    resizeWidget2.anchorRight = true
    resizeWidget2:initialise()
    resizeWidget2.onMouseDown = ISChat.onMouseDown
    resizeWidget2.onMouseUp = ISChat.onMouseUp
    resizeWidget2:setVisible(self.resizable)
    resizeWidget2:setUIName(ISChat.yResizeWidgetName)
    self:addChild(resizeWidget2)
    self.resizeWidget2 = resizeWidget2

    -- close button
    local th = self:titleBarHeight()
    self.closeButton = ISButton:new(3, 0, th, th, "", self, self.close)
    self.closeButton:initialise()
    self.closeButton.borderColor.a = 0.0
    self.closeButton.backgroundColor.a = 0
    self.closeButton.backgroundColorMouseOver.a = 0.5
    self.closeButton:setImage(self.closeButtonTexture)
    self.closeButton:setUIName(ISChat.closeButtonName)
    self:addChild(self.closeButton)

    -- lock button
    self.lockButton = ISButton:new(self.width - 19, 0, th, th, "", self, ISChat.pin)
    self.lockButton.anchorRight = true
    self.lockButton.anchorLeft = false
    self.lockButton:initialise()
    self.lockButton.borderColor.a = 0.0
    self.lockButton.backgroundColor.a = 0
    self.lockButton.backgroundColorMouseOver.a = 0.5
    if self.locked then
        self.lockButton:setImage(self.chatLockedButtonTexture)
    else
        self.lockButton:setImage(self.chatUnLockedButtonTexture)
    end
    self.lockButton:setUIName(ISChat.lockButtonName)
    self:addChild(self.lockButton)
    self.lockButton:setVisible(true)

    --gear button
    self.gearButton = ISButton:new(self.lockButton:getX() - th / 2 - th, 1, th, th, "", self, ISChat.onGearButtonClick)
    self.gearButton.anchorRight = true
    self.gearButton.anchorLeft = false
    self.gearButton:initialise()
    self.gearButton.borderColor.a = 0.0
    self.gearButton.backgroundColor.a = 0
    self.gearButton.backgroundColorMouseOver.a = 0.5
    self.gearButton:setImage(getTexture("media/ui/inventoryPanes/Button_Gear.png"))
    self.gearButton:setUIName(ISChat.gearButtonName)
    self:addChild(self.gearButton)
    self.gearButton:setVisible(true)

    --info button
    ISChat.infoButtonName = "chat info button"
    self.infoButton =
        ISButton:new(self.gearButton:getX() - th / 2 - th, 1, th, th, "", self, ISCollapsableWindow.onInfo)
    self.infoButton.anchorRight = true
    self.infoButton.anchorLeft = false
    self.infoButton:initialise()
    self.infoButton.borderColor.a = 0.0
    self.infoButton.backgroundColor.a = 0
    self.infoButton.backgroundColorMouseOver.a = 0.5
    self.infoButton:setImage(getTexture("media/ui/inventoryPanes/Button_Info.png"))
    self.infoButton:setUIName(ISChat.infoButtonName)
    self:addChild(self.infoButton)
    self.infoButton:setVisible(true)
    local info = getText("SurvivalGuide_TRPC", TRPC_VERSION)
    info = info .. getText("SurvivalGuide_TRPC_Color")
    self:setInfo(info)

    --range button
    ISChat.rangeButtonName = "chat range button"
    self.rangeButton = ISButton:new(self.infoButton:getX() - th / 2 - th, 1, th, th, "", self, OnRangeButtonClick)
    self.rangeButton.anchorRight = true
    self.rangeButton.anchorLeft = false
    self.rangeButton:initialise()
    self.rangeButton.borderColor.a = 0.0
    self.rangeButton.backgroundColor.a = 0
    self.rangeButton.backgroundColorMouseOver.a = 0.5
    self.rangeButton:setImage(getTexture("media/ui/RadioButtonCircle.png"))
    self.rangeButton:setUIName(ISChat.rangeButtonName)
    self:addChild(self.rangeButton)
    self.rangeButton:setVisible(true)

    --radio button
    ISChat.radioButtonName = "radio button"
    self.radioButton = ISButton:new(self.rangeButton:getX() - th / 2 - th, 1, th, th, "", self, OnRadioButtonClick)
    self.radioButton.anchorRight = true
    self.radioButton.anchorLeft = false
    self.radioButton:initialise()
    self.radioButton.borderColor.a = 0.0
    self.radioButton.backgroundColor.a = 0
    self.radioButton.backgroundColorMouseOver.a = 0.5
    self.radioButton:setImage(getTexture("media/ui/RadioButtonIndicator.png"))
    self.radioButton:setUIName(ISChat.radioButtonName)
    self:addChild(self.radioButton)
    self.radioButton:setVisible(true)

    --avatar validation window button
    self:createValidationWindowButton()

    --general stuff
    self.minimumHeight = 90
    self.minimumWidth = 200
    self:setResizable(true)
    self:setDrawFrame(true)
    self:addToUIManager()

    ChatState.setTabs({})
    self.tabCnt = 0
    self.btnHeight = 25
    ChatState.setCurrentTabID(0)
    self.inset = 2
    self.fontHgt = getTextManager():getFontFromEnum(UIFont.Medium):getLineHeight()

    --text entry stuff
    local inset, EdgeSize, fontHgt = self.inset, 5, self.fontHgt

    -- EdgeSize must match UITextBox2.EdgeSize
    local height = EdgeSize * 2 + fontHgt
    self.textEntry =
        ISTextEntryBox:new("", inset, self:getHeight() - 8 - inset - height, self:getWidth() - inset * 2, height)
    self.textEntry.font = UIFont.Medium
    self.textEntry:initialise()
    -- self.textEntry:instantiate()
    ChatUI.textEntry.instantiate(self.textEntry)
    self.textEntry.backgroundColor = { r = 0, g = 0, b = 0, a = 0.5 }
    self.textEntry.borderColor = { r = 1, g = 1, b = 1, a = 0.0 }
    self.textEntry:setHasFrame(true)
    self.textEntry:setAnchorTop(false)
    self.textEntry:setAnchorBottom(true)
    self.textEntry:setAnchorRight(true)
    self.textEntry.onCommandEntered = ISChat.onCommandEntered
    self.textEntry.onTextChange = ISChat.onTextChange
    self.textEntry.onPressDown = ISChat.onPressDown
    self.textEntry.onPressUp = ISChat.onPressUp
    self.textEntry.onOtherKey = ISChat.onOtherKey
    self.textEntry.onClick = ISChat.onMouseDown
    self.textEntry:setUIName(ISChat.textEntryName) -- need to be right this. If it will empty or another then focus will lost on click in chat
    self.textEntry:setHasFrame(true)
    self:addChild(self.textEntry)
    self.textEntry.prerender = ChatUI.textEntry.prerender
    ISChat.maxTextEntryOpaque = self.textEntry:getFrameAlpha()

    --tab panel stuff
    local panelHeight = self.textEntry:getY() - self:titleBarHeight() - self.inset
    self.panel = ISTabPanel:new(0, self:titleBarHeight(), self.width - inset, panelHeight)
    self.panel:initialise()
    self.panel.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    self.panel.onActivateView = ISChat.onActivateView
    self.panel.target = self
    self.panel:setAnchorTop(true)
    self.panel:setAnchorLeft(true)
    self.panel:setAnchorRight(true)
    self.panel:setAnchorBottom(true)
    self.panel:setEqualTabWidth(false)
    self.panel:setVisible(false)
    self.panel.onRightMouseUp = ISChat.onRightMouseUp
    self.panel.onRightMouseDown = ISChat.onRightMouseDown
    self.panel.onMouseUp = ISChat.onMouseUp
    self.panel.onMouseDown = ISChat.ISTabPanelOnMouseDown
    self.panel:setUIName(ISChat.tabPanelName)
    self:addChild(self.panel)
    self.panel.activateView = PanelActivateView
    self.panel.render = ChatUI.tabPanel.render
    self.panel.prerender = ChatUI.tabPanel.prerender

    self:bringToTop()
    self.textEntry:bringToTop()
    self.minimumWidth = self.panel:getWidthOfAllTabs() + 2 * inset
    self.minimumHeight = self.textEntry:getHeight()
        + self:titleBarHeight()
        + 2 * inset
        + self.panel.tabHeight
        + fontHgt * 4
    self:unfocus()

    self.mutedUsers = {}
end

function ISChat:focus()
    self:setVisible(true)
    ChatState.setFocused(true)
    self.textEntry:setEditable(true)
    self.textEntry:focus()
    self.textEntry:ignoreFirstInput()
    local stream = ISChat.lastTabStream[ChatState.getCurrentTabID()]
    self.textEntry:setText(stream["command"])
    RangeController.updateRangeIndicator(stream)
    self.fade:reset()
    self.fade:update() --reset fraction to start value
end

function ISChat:unfocus()
    self.textEntry:unfocus()
    self.textEntry:setText("")
    if ChatState.isFocused() then
        self.fade:reset() -- to begin fade. unfocus called when element was unfocused also.
    end
    ChatState.setFocused(false)
    self.textEntry:setEditable(false)
end

function ISChat:onGearButtonClick()
    local context =
        ISContextMenu.get(0, self:getAbsoluteX() + self:getWidth() / 2, self:getAbsoluteY() + self.gearButton:getY())
    if context == nil then
        Logger.error("ISChat", "TRPC error: ISChat:onGearButtonClick: gear button context is null")
        return
    end

    local timestampOptionName = getText("UI_chat_context_enable_timestamp")
    if self.showTimestamp then
        timestampOptionName = getText("UI_chat_context_disable_timestamp")
    end
    context:addOption(timestampOptionName, ISChat.instance, ISChat.onToggleTimestampPrefix)

    local tagOptionName = getText("UI_chat_context_enable_tags")
    if self.showTitle then
        tagOptionName = getText("UI_chat_context_disable_tags")
    end
    context:addOption(tagOptionName, ISChat.instance, ISChat.onToggleTagPrefix)

    local fontSizeOption = context:addOption(getText("UI_chat_context_font_submenu_name"), ISChat.instance)
    local fontSubMenu = context:getNew(context)
    context:addSubMenu(fontSizeOption, fontSubMenu)
    fontSubMenu:addOption(getText("UI_chat_context_font_small"), ISChat.instance, ISChat.onFontSizeChange, "small")
    fontSubMenu:addOption(getText("UI_chat_context_font_medium"), ISChat.instance, ISChat.onFontSizeChange, "medium")
    fontSubMenu:addOption(getText("UI_chat_context_font_large"), ISChat.instance, ISChat.onFontSizeChange, "large")
    if self.chatFont == "small" then
        fontSubMenu:setOptionChecked(fontSubMenu.options[1], true)
    elseif self.chatFont == "medium" then
        fontSubMenu:setOptionChecked(fontSubMenu.options[2], true)
    elseif self.chatFont == "large" then
        fontSubMenu:setOptionChecked(fontSubMenu.options[3], true)
    end

    local minOpaqueOption = context:addOption(getText("UI_chat_context_opaque_min"), ISChat.instance)
    local minOpaqueSubMenu = context:getNew(context)
    context:addSubMenu(minOpaqueOption, minOpaqueSubMenu)
    local opaques = { 0, 0.25, 0.5, 0.6, 0.75, 1 }
    for i = 1, #opaques do
        if logTo01(opaques[i]) <= self.maxOpaque then
            local option = minOpaqueSubMenu:addOption(
                (opaques[i] * 100) .. "%",
                ISChat.instance,
                ISChat.onMinOpaqueChange,
                opaques[i]
            )
            local current = math.floor(self.minOpaque * 1000)
            local value = math.floor(logTo01(opaques[i]) * 1000)
            if current == value then
                minOpaqueSubMenu:setOptionChecked(option, true)
            end
        end
    end

    local maxOpaqueOption = context:addOption(getText("UI_chat_context_opaque_max"), ISChat.instance)
    local maxOpaqueSubMenu = context:getNew(context)
    context:addSubMenu(maxOpaqueOption, maxOpaqueSubMenu)
    for i = 1, #opaques do
        if logTo01(opaques[i]) >= self.minOpaque then
            local option = maxOpaqueSubMenu:addOption(
                (opaques[i] * 100) .. "%",
                ISChat.instance,
                ISChat.onMaxOpaqueChange,
                opaques[i]
            )
            local current = math.floor(self.maxOpaque * 1000)
            local value = math.floor(logTo01(opaques[i]) * 1000)
            if current == value then
                maxOpaqueSubMenu:setOptionChecked(option, true)
            end
        end
    end

    local fadeTimeOption = context:addOption(getText("UI_chat_context_opaque_fade_time_submenu_name"), ISChat.instance)
    local fadeTimeSubMenu = context:getNew(context)
    context:addSubMenu(fadeTimeOption, fadeTimeSubMenu)
    local availFadeTime = { 0, 1, 2, 3, 5, 10 }
    local option =
        fadeTimeSubMenu:addOption(getText("UI_chat_context_disable"), ISChat.instance, ISChat.onFadeTimeChange, 0)
    if 0 == self.fadeTime then
        fadeTimeSubMenu:setOptionChecked(option, true)
    end
    for i = 2, #availFadeTime do
        local time = availFadeTime[i]
        option = fadeTimeSubMenu:addOption(time .. " s", ISChat.instance, ISChat.onFadeTimeChange, time)
        if time == self.fadeTime then
            fadeTimeSubMenu:setOptionChecked(option, true)
        end
    end

    local opaqueOnFocusOption = context:addOption(getText("UI_chat_context_opaque_on_focus"), ISChat.instance)
    local opaqueOnFocusSubMenu = context:getNew(context)
    context:addSubMenu(opaqueOnFocusOption, opaqueOnFocusSubMenu)
    opaqueOnFocusSubMenu:addOption(
        getText("UI_chat_context_disable"),
        ISChat.instance,
        ISChat.onFocusOpaqueChange,
        false
    )
    opaqueOnFocusSubMenu:addOption(getText("UI_chat_context_enable"), ISChat.instance, ISChat.onFocusOpaqueChange, true)
    opaqueOnFocusSubMenu:setOptionChecked(opaqueOnFocusSubMenu.options[self.opaqueOnFocus and 2 or 1], true)

    local voiceOptionName = getText("UI_TRPC_chat_enable_voices")
    if self.isVoiceEnabled then
        voiceOptionName = getText("UI_TRPC_chat_disable_voices")
    end
    context:addOption(voiceOptionName, ISChat.instance, ISChat.onToggleVoice)

    local radioIconOptionName = getText("UI_TRPC_enable_radio_icon")
    if self.isRadioIconEnabled then
        radioIconOptionName = getText("UI_TRPC_disable_radio_icon")
    end
    context:addOption(radioIconOptionName, ISChat.instance, ISChat.onToggleRadioIcon)

    if TrpcServerSettings and TrpcServerSettings["options"]["portrait"] ~= 1 then
        local portraitOptionName = getText("UI_TRPC_enable_portrait")
        if self.isPortraitEnabled then
            portraitOptionName = getText("UI_TRPC_disable_portrait")
        end
        context:addOption(portraitOptionName, ISChat.instance, ISChat.onTogglePortrait)
    end
end

function ISChat.onToggleVoice()
    ISChat.instance.isVoiceEnabled = not ISChat.instance.isVoiceEnabled

    -- the player has set this option at least once, that means he is aware of its existence
    -- we'll use this settings in the future instead of the server default behavior
    ISChat.instance.trpcModData["isVoiceEnabled"] = ISChat.instance.isVoiceEnabled
    ModData.add("trpc", ISChat.instance.trpcModData)
end

function ISChat.onToggleRadioIcon()
    ISChat.instance.isRadioIconEnabled = not ISChat.instance.isRadioIconEnabled
    ISChat.instance.trpcModData["isRadioIconEnabled"] = ISChat.instance.isRadioIconEnabled
    ModData.add("trpc", ISChat.instance.trpcModData)
    if ISChat.instance.radioRangeIndicator then
        ISChat.instance.radioRangeIndicator.showIcon = ISChat.instance.isRadioIconEnabled
    end
end

function ISChat.onTogglePortrait()
    ISChat.instance.isPortraitEnabled = not ISChat.instance.isPortraitEnabled
    ISChat.instance.trpcModData["isPortraitEnabled"] = ISChat.instance.isPortraitEnabled
    ModData.add("trpc", ISChat.instance.trpcModData)
end

Events.OnChatWindowInit.Add(ISChat.initChat)
