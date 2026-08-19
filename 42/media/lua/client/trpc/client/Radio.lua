local Character = require("trpc/shared/utils/Character")
local World = require("trpc/shared/utils/World")
local TrpcClientSendCommands = require("trpc/client/network/ClientSend")
local Logger = require("trpc/core/Logger")

local Radio = {}

local statusHandler
local lastObservedDeviceKey

local function GetActiveDevice()
    local player = getPlayer and getPlayer() or nil
    if player == nil then
        return nil, nil
    end
    local radio = Character.getFirstHandOrBeltItemByGroup(player, "Radio")
    return radio, radio and radio:getDeviceData() or nil
end

local function IsBeltRadio(radio)
    return radio ~= nil
        and type(instanceof) == "function"
        and instanceof(radio, "Radio")
        and Character.isItemOnBeltAndNotInHand(getPlayer(), radio)
end

local function GetDeviceKey(radio)
    if radio == nil then
        return "none"
    end
    if type(radio.getID) == "function" then
        return tostring(radio:getID())
    end
    if type(radio.getType) == "function" then
        return tostring(radio:getType())
    end
    return tostring(radio)
end

local function GetConfiguredMaxRange()
    if TrpcServerSettings and TrpcServerSettings.options and TrpcServerSettings.options.radio then
        return TrpcServerSettings.options.radio.soundMaxRange
    end
    return nil
end

local function GetDeviceName(radio)
    if radio == nil then
        return "No radio"
    end
    if type(radio.getDisplayName) == "function" then
        local displayName = radio:getDisplayName()
        if displayName ~= nil and displayName ~= "" then
            return displayName
        end
    end
    if type(radio.getType) == "function" then
        return radio:getType()
    end
    return "Radio"
end

local function GetStatus(radio, radioData, radioMaxRange)
    radioData = radioData or (radio and radio:getDeviceData())
    if radioData == nil then
        return nil
    end
    local volume = radioData:getDeviceVolume()
    local status = {
        device = radio,
        name = GetDeviceName(radio),
        frequency = radioData:getChannel(),
        turnedOn = radioData:getIsTurnedOn(),
        volume = volume,
        volumePercent = math.floor(volume * 100 + 0.5),
        hasHeadphones = radioData:getHeadphoneType() >= 0,
    }
    if radioMaxRange ~= nil then
        status.range = Character.getRadioRange(radioData, radioMaxRange)
    end
    return status
end

local function FormatStatus(status)
    if status == nil then
        return "No active radio detected."
    end
    local power = status.turnedOn and "on" or "off"
    local range = status.range ~= nil and (", range " .. tostring(status.range)) or ""
    local headphones = status.hasHeadphones and ", headphones" or ""
    return status.name
        .. " ["
        .. power
        .. "] frequency "
        .. tostring(status.frequency)
        .. ", volume "
        .. tostring(status.volumePercent)
        .. "%"
        .. range
        .. headphones
end

function Radio.setStatusHandler(handler)
    statusHandler = type(handler) == "function" and handler or nil
end

function Radio.reportStatus(message, details)
    if statusHandler ~= nil then
        statusHandler(message, details)
    end
end

function Radio.getActiveDevice()
    return GetActiveDevice()
end

function Radio.getConfiguredMaxRange()
    return GetConfiguredMaxRange()
end

function Radio.getStatus(radio, radioData, radioMaxRange)
    return GetStatus(radio, radioData, radioMaxRange)
end

function Radio.formatStatus(status)
    return FormatStatus(status)
end

function Radio.reportDeviceStatus(radio, reason)
    local status = GetStatus(radio, nil, GetConfiguredMaxRange())
    if status == nil then
        return false
    end
    Radio.reportStatus(reason .. ": " .. FormatStatus(status), status)
    return true
end

function Radio.observeActiveDevice()
    local radio = GetActiveDevice()
    local key = GetDeviceKey(radio)
    if lastObservedDeviceKey == nil then
        lastObservedDeviceKey = key
        return false
    end
    if key == lastObservedDeviceKey then
        return false
    end
    lastObservedDeviceKey = key
    if radio ~= nil then
        Radio.reportDeviceStatus(radio, "Active radio")
    else
        Radio.reportStatus("Active radio removed.")
    end
    return true
end

function Radio.setFrequency(radio, frequency)
    if radio == nil then
        return false, "missing-device"
    end
    local radioData = radio:getDeviceData()
    if radioData == nil or type(radioData.setChannel) ~= "function" then
        return false, "missing-device-data"
    end
    local numericFrequency = tonumber(frequency) or frequency
    radioData:setChannel(numericFrequency)
    if IsBeltRadio(radio) then
        TrpcClientSendCommands.sendGiveRadioState(radio)
    end
    return true, GetStatus(radio, radioData, GetConfiguredMaxRange())
end

function Radio.SyncSquare(turnedOn, mute, power, volume, frequency, x, y, z)
    if turnedOn == nil then
        Logger.error("Radio", "TRPC error: Radio.SyncSquare: nil turnedOn parameter")
        return
    end
    if mute == nil then
        Logger.error("Radio", "TRPC error: Radio.SyncSquare: nil mute parameter")
        return
    end
    if power == nil then
        Logger.error("Radio", "TRPC error: Radio.SyncSquare: nil power parameter")
        return
    end
    if volume == nil then
        Logger.error("Radio", "TRPC error: Radio.SyncSquare: nil volume parameter")
        return
    end
    if frequency == nil then
        Logger.error("Radio", "TRPC error: Radio.SyncSquare: nil frequency parameter")
        return
    end
    if x == nil then
        Logger.error("Radio", "TRPC error: Radio.SyncSquare: nil x parameter")
        return
    end
    if y == nil then
        Logger.error("Radio", "TRPC error: Radio.SyncSquare: nil y parameter")
        return
    end
    if z == nil then
        Logger.error("Radio", "TRPC error: Radio.SyncSquare: nil z parameter")
        return
    end
    local square = getSquare(x, y, z)
    if square == nil then -- legitimate error, when a client is too far away
        return
    end
    local radios = World.getSquareItemsByGroup(square, "IsoRadio")
    if radios == nil or #radios <= 0 then
        Logger.error("Radio", "TRPC error: Radio.SyncSquare: no radio found at " .. x .. ", " .. y .. ", " .. z)
        return
    end
    local radio = radios[1]
    local radioData = radio:getDeviceData()
    if radioData == nil then
        Logger.error("Radio", "TRPC error: Radio.SyncSquare: radio has not device data")
        return
    end
    if radioData.setIsTurnedOn ~= nil then
        radioData:setIsTurnedOn(turnedOn)
    end
    radioData:setMicIsMuted(mute)
end

function Radio.SyncInHand(id, turnedOn, mute, power, volume, frequency)
    if id == nil then
        Logger.error("Radio", "TRPC error: Radio.SyncInHand: nil id parameter")
        return
    end
    if turnedOn == nil then
        Logger.error("Radio", "TRPC error: Radio.SyncInHand: nil turnedOn parameter")
        return
    end
    if mute == nil then
        Logger.error("Radio", "TRPC error: Radio.SyncInHand: nil mute parameter")
        return
    end
    if power == nil then
        Logger.error("Radio", "TRPC error: Radio.SyncInHand: nil power parameter")
        return
    end
    if volume == nil then
        Logger.error("Radio", "TRPC error: Radio.SyncInHand: nil volume parameter")
        return
    end
    if frequency == nil then
        Logger.error("Radio", "TRPC error: Radio.SyncInHand: nil frequency parameter")
        return
    end
    local radio = Character.getItemById(getPlayer(), id)
    if radio == nil then
        Logger.error("Radio", "TRPC error: Radio.SyncInHand: no radio found on player")
        return
    end
    local radioData = radio:getDeviceData()
    if radioData == nil then
        Logger.error("Radio", "TRPC error: Radio.SyncInHand: radio has not device data")
        return
    end
    if radioData.setIsTurnedOn ~= nil then
        radioData:setIsTurnedOn(turnedOn)
    end
    radioData:setMicIsMuted(mute)
end

local function Update()
    Radio.observeActiveDevice()
    local player = getPlayer()
    local inventoryRadios = player:getAttachedItems()
    local inventoryRadiosSize = inventoryRadios:size()
    for i = 0, inventoryRadiosSize - 1 do
        local item = inventoryRadios:getItemByIndex(i)
        local id = item:getID()
        if instanceof(item, "Radio") then
            -- is on belt
            local primary = player:getPrimaryHandItem()
            local secondary = player:getSecondaryHandItem()
            -- radios in hand already decrease the battery level
            if not ((primary and primary:getID() == id) or (secondary and secondary:getID() == id)) then
                local radioData = item:getDeviceData()
                if radioData then
                    if radioData:getIsTurnedOn() then
                        local useDelta = radioData:getUseDelta()
                        local power = radioData:getPower()
                        local newPower = math.max(0, power - useDelta)
                        radioData:setPower(newPower)
                        if newPower <= 0 and power > 0 and radioData:getIsTurnedOn() then
                            radioData:setIsTurnedOn(false)
                        end
                    end
                    -- we could only send it when the battery reach 0 but every 1 game-time minute
                    -- is really not that much and it will protect us from any sync error
                    TrpcClientSendCommands.sendGiveRadioState(item)
                end
            end
        end
    end
end

Events.EveryOneMinute.Add(Update)

return Radio
