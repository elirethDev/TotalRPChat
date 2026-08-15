local Character = require("trpc/shared/utils/Character")
local Logger = require("trpc/core/Logger")
local RadioManager = require("trpc/server/radio/RadioManager")
local ServerSend = require("trpc/server/network/ServerSend")
local World = require("trpc/shared/utils/World")
local ChatDomain = require("trpc/server/domain/ChatDomain")

local ChatMessage = {}

local function PlayersDistance(source, target)
    local stupidDistance = source:DistTo(target:getX(), target:getY())
    local accurateDistance = math.max(stupidDistance - 1, 0)
    return math.floor(accurateDistance + 0.5)
end

local SandboxVarsCopy = nil
local function CopyTrpcSandboxVars()
    SandboxVarsCopy = {}
    for key, var in pairs(SandboxVars.TRPC) do
        SandboxVarsCopy[key] = var
    end
end

local function HasTrpcSandboxVarsChanged()
    if SandboxVarsCopy == nil then
        return false
    end
    for key, var in pairs(SandboxVars.TRPC) do
        if SandboxVarsCopy[key] ~= var then
            return true
        end
    end
    return false
end

local function DetectMessageTypeSettingsUpdate()
    if ChatDomain.MessageTypeSettings == nil then
        return
    end
    if SandboxVarsCopy == nil then
        CopyTrpcSandboxVars()
        return
    end
    if HasTrpcSandboxVarsChanged() then
        CopyTrpcSandboxVars()
        ChatDomain.SetMessageTypeSettings()
        World.forAllPlayers(function(player)
            ServerSend.Command(player, "SendSandboxVars", ChatDomain.MessageTypeSettings)
        end)
    end
end

local function GetPlayerRadio(player)
    local radio = Character.getFirstHandItemByGroup(player, "Radio")
    if radio == nil then
        local attachedRadio = Character.getFirstAttachedItemByGroup(player, "Radio")
        if attachedRadio then
            radio = RadioManager:getFakeBeltRadio(player)
        end
    end
    return radio
end

local function IsInRadioEmittingRange(radioEmitters, receiver)
    if radioEmitters == nil then
        return false, -1
    end
    for _, radioEmitter in pairs(radioEmitters) do
        local radioData = radioEmitter:getDeviceData()
        if radioData ~= nil then
            local transmitRange = radioData:getTransmitRange()
            local distance = World.distanceManhatten(radioEmitter, receiver)
            if distance <= transmitRange then
                return true, distance
            end
        end
    end
    return false, -1
end

local function GetSquaresRadios(player, args, radioFrequencies, range)
    if ChatDomain.MessageTypeSettings == nil then
        Logger.error(
            "ChatMessage",
            "TRPC error: GetSquaresRadios: tried to get radios before server settings were initialized"
        )
        return {}, false
    end
    local maxSoundRange = ChatDomain.MessageTypeSettings["options"]["radio"]["soundMaxRange"]
    local radiosByFrequency = {}
    local radios = World.getItemsInRangeByGroup(player, range, "IsoRadio")
    local found = false
    for _, radio in pairs(radios) do
        local pos = {
            x = radio:getX(),
            y = radio:getY(),
            z = radio:getZ(),
        }
        -- radio:getSquare() is unreliable
        local radioSquare = getSquare(radio:getX(), radio:getY(), radio:getZ())
        RadioManager:subscribeSquare(radioSquare)
        local radioData = radio:getDeviceData()
        if radioData ~= nil then
            local frequency = radioData:getChannel()
            local turnedOn = radioData:getIsTurnedOn()
            local volume = radioData:getDeviceVolume()
            if volume == nil then
                volume = 0
            end
            volume = math.abs(volume)
            local isInRange, distance = IsInRadioEmittingRange(radioFrequencies[frequency], radio)
            if
                turnedOn
                and frequency ~= nil
                and radioFrequencies[frequency] ~= nil
                and isInRange
                and Character.canHearRadioSound(player, radio, radioData, maxSoundRange)
            then
                if radiosByFrequency[frequency] == nil then
                    radiosByFrequency[frequency] = {}
                end
                table.insert(radiosByFrequency[frequency], {
                    position = pos,
                    distance = distance,
                })
                found = true
            end
        end
    end
    return radiosByFrequency, found
end

local function GetPlayerRadios(player, args, radioFrequencies, range)
    local radiosByFrequency = {}
    local radio = GetPlayerRadio(player)
    local found = false
    if radio == nil then
        return radiosByFrequency
    end
    local radioData = radio and radio:getDeviceData() or nil
    if radioData then
        local frequency = radioData:getChannel()
        local isInRange, distance = IsInRadioEmittingRange(radioFrequencies[frequency], player)
        if radioData:getIsTurnedOn() and frequency ~= nil and radioFrequencies[frequency] ~= nil and isInRange then
            if radiosByFrequency[frequency] == nil then
                radiosByFrequency[frequency] = {}
            end
            table.insert(radiosByFrequency[frequency], {
                username = player:getUsername(),
                distance = distance,
            })
            found = true
        end
    end
    return radiosByFrequency, found
end

local function GetVehiclesRadios(player, args, radioFrequencies, range)
    if ChatDomain.MessageTypeSettings == nil then
        Logger.error(
            "ChatMessage",
            "TRPC error: GetVehiclesRadios: tried to get radios before server settings were initialized"
        )
        return {}, false
    end
    local maxSoundRange = ChatDomain.MessageTypeSettings["options"]["radio"]["soundMaxRange"]
    local vehiclesByFrequency = {}
    local vehicles = World.getVehiclesInRange(player, range)
    local found = false
    for _, vehicle in pairs(vehicles) do
        local radio = vehicle:getPartById("Radio")
        if radio ~= nil then
            RadioManager:subscribeVehicle(vehicle)
            local radioData = radio:getDeviceData()
            if radioData ~= nil then
                local frequency = radioData:getChannel()
                local isInRange, distance = IsInRadioEmittingRange(radioFrequencies[frequency], vehicle)
                if
                    radioData:getIsTurnedOn()
                    and frequency ~= nil
                    and radioFrequencies[frequency] ~= nil
                    and isInRange
                    and Character.canHearRadioSound(player, vehicle, radioData, maxSoundRange)
                then
                    if vehiclesByFrequency[frequency] == nil then
                        vehiclesByFrequency[frequency] = {}
                    end
                    table.insert(vehiclesByFrequency[frequency], {
                        key = vehicle:getKeyId(),
                        distance = distance,
                    })
                    found = true
                end
            end
        end
    end
    return vehiclesByFrequency, found
end

local function SendRadioPackets(author, player, args, sourceRadioByFrequencies)
    local range = ChatDomain.MessageTypeSettings["options"]["radio"]["soundMaxRange"]
    local squaresRadios, squaresRadiosFound = GetSquaresRadios(player, args, sourceRadioByFrequencies, range)
    local playersRadios, playersRadiosFound = GetPlayerRadios(player, args, sourceRadioByFrequencies, range)
    local vehiclesRadios, vehiclesRadiosFound = GetVehiclesRadios(player, args, sourceRadioByFrequencies, range)

    if not squaresRadiosFound and not playersRadiosFound and not vehiclesRadiosFound then
        return
    end

    local targetRadiosByFrequencies = {}
    for frequency, _ in pairs(sourceRadioByFrequencies) do
        targetRadiosByFrequencies[frequency] = {
            squares = squaresRadios[frequency] or {},
            players = playersRadios[frequency] or {},
            vehicles = vehiclesRadios[frequency] or {},
        }
        RadioManager:makeNoise(frequency, range)
    end

    ServerSend.Command(player, "RadioMessage", {
        author = args.author,
        characterName = args.characterName,
        message = args.message,
        color = args.color,
        type = args.type,
        radios = targetRadiosByFrequencies,
        pitch = args.pitch,
        disableVerb = args.disableVerb,
        language = args.language,
    })
end

local function GetEmittingRadios(player, packetType, messageType, range)
    local radioEmission = false
    local radioFrequencies = {}
    if
        ChatDomain.MessageTypeSettings[messageType]
        and ChatDomain.MessageTypeSettings[messageType]["radio"] == true
        and packetType == "ChatMessage"
        and range > 0
    then
        local radios = World.getItemsInRangeByGroup(player, range, "IsoRadio")
        for _, radio in pairs(radios) do
            local radioData = radio:getDeviceData()
            if radioData ~= nil then
                local frequency = radioData:getChannel()
                if
                    radioData:getIsTwoWay()
                    and radioData:getIsTurnedOn()
                    and not radioData:getMicIsMuted()
                    and frequency ~= nil
                then
                    if radioFrequencies[frequency] == nil then
                        radioFrequencies[frequency] = {}
                    end
                    table.insert(radioFrequencies[frequency], radio)
                    radioEmission = true
                end
            end
        end
        local radio = GetPlayerRadio(player)
        local radioData = radio and radio:getDeviceData() or nil
        if radioData then
            local frequency = radioData:getChannel()
            if
                radioData
                and radioData:getIsTwoWay()
                and radioData:getIsTurnedOn()
                and not radioData:getMicIsMuted()
                and frequency ~= nil
            then
                if radioFrequencies[frequency] == nil then
                    radioFrequencies[frequency] = {}
                end
                table.insert(radioFrequencies[frequency], radio)
                radioEmission = true
            end
        end
    end
    return radioEmission, radioFrequencies
end

local function SendRadioEmittingPackets(player, args, radioFrequencies)
    for frequency, _ in pairs(radioFrequencies) do
        if
            ChatDomain.MessageTypeSettings
            and ChatDomain.MessageTypeSettings["options"]["radio"]["discord"]
            and frequency == ChatDomain.MessageTypeSettings["options"]["radio"]["frequency"]
        then
            ServerSend.Command(player, "DiscordMessage", {
                message = args.message,
            })
        end
        ServerSend.Command(player, "RadioEmittingMessage", {
            type = args.type,
            author = args.author,
            characterName = args.characterName,
            message = args.message,
            color = args.color,
            frequency = frequency,
            disableVerb = args.disableVerb,
            language = args.language,
        })
    end
end

local PermissionErrorMessages = {
    ["UNKNOWN_PLAYER"] = function(args)
        return 'unknown player "' .. args.target .. '".'
    end,
    ["NO_FACTION"] = function()
        return "you are not part of a faction."
    end,
    ["NO_SAFEHOUSE"] = function()
        return "you are not part of a safe house."
    end,
    ["ADMIN_ONLY"] = function()
        return "requires admin privileges."
    end,
}

function ChatMessage.ProcessMessage(player, args, packetType, sendError)
    if args.type == nil then
        Logger.error("ChatMessage", 'TRPC error: Received a message from "' .. player:getUsername() .. '" with no type')
        return
    end

    local ok, errorCode = ChatDomain.IsAllowedToTalk(player, args)
    if not ok then
        if sendError and errorCode ~= nil then
            ServerSend.ChatErrorMessage(player, args.type, PermissionErrorMessages[errorCode](args))
        end
        return
    end

    if
        args.type == "general"
        and ChatDomain.MessageTypeSettings
        and ChatDomain.MessageTypeSettings["general"]["discord"]
        and packetType ~= "Typing"
    then
        ServerSend.Command(player, "DiscordMessage", {
            message = args.message,
        })
    end

    local range = ChatDomain.GetRangeForMessageType(args.type)
    if range == nil then
        error('TRPC error: No range for message type "' .. args.type .. '".')
        return
    end
    local radioEmission = false
    local radioFrequencies = {}
    if packetType ~= "Typing" then
        radioEmission, radioFrequencies = GetEmittingRadios(player, packetType, args["type"], range)
        SendRadioEmittingPackets(player, args, radioFrequencies)
        local radiosFrequenciesList = {}
        for frequency, _ in pairs(radioFrequencies) do
            table.insert(radiosFrequenciesList, frequency)
        end
        Logger.logChat(args.type, args.author, args.characterName, args.message, radiosFrequenciesList, args.target)
    end
    local connectedPlayers = getOnlinePlayers()
    for i = 0, connectedPlayers:size() - 1 do
        local connectedPlayer = connectedPlayers:get(i)
        if ChatDomain.IsAllowedToListen(player, connectedPlayer, args) then
            if
                connectedPlayer:getOnlineID() == player:getOnlineID()
                or range == -1
                or PlayersDistance(player, connectedPlayer) < range + 0.001
                or Character.areInSameVehicle(player, connectedPlayer)
            then
                ServerSend.Command(connectedPlayer, packetType, args)
            end
            if radioEmission then
                SendRadioPackets(player, connectedPlayer, args, radioFrequencies)
            end
        end
    end
end

function ChatMessage.RollDice(player, diceCount, diceType, addCount)
    if diceCount < 1 or diceCount > 20 or diceType < 1 then
        return
    end
    local results = {}
    local result = 0
    for _ = 1, diceCount do
        local diceResult = ZombRand(diceType) + 1
        table.insert(results, diceResult)
        result = result + diceResult
    end
    if addCount ~= nil then
        result = result + addCount
    end
    local firstName, lastName = Character.getFirstAndLastName(player)
    local username = player:getUsername()
    local characterName = firstName .. " " .. lastName
    local messageRange = 20
    if
        ChatDomain.MessageTypeSettings
        and ChatDomain.MessageTypeSettings["say"]
        and ChatDomain.MessageTypeSettings["say"]["range"]
    then
        messageRange = ChatDomain.MessageTypeSettings["say"]["range"]
    end
    World.forAllPlayers(function(targetPlayer)
        if PlayersDistance(player, targetPlayer) < messageRange then
            ServerSend.RollResult(targetPlayer, username, characterName, diceCount, diceType, addCount, results, result)
        end
    end)
end

Events.EveryOneMinute.Add(DetectMessageTypeSettingsUpdate)

return ChatMessage
