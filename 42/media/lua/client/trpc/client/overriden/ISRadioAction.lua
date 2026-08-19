local Character = require("trpc/shared/utils/Character")
local TrpcClientSendCommands = require("trpc/client/network/ClientSend")
local Radio = require("trpc/client/Radio")

local function ReportDevice(action, device)
    Radio.reportDeviceStatus(device, action)
end

-- mute was not sync at all with the server so we do it there
function ISRadioAction:performMuteMicrophone()
    if self:isValidMuteMicrophone() then
        -- a belt item is not sync with the server, so we need to tell it everything
        if Character.isItemOnBeltAndNotInHand(getPlayer(), self.device) then
            self.deviceData:setMicIsMuted(self.secondaryItem)
            TrpcClientSendCommands.sendGiveRadioState(self.device)
        else
            TrpcClientSendCommands.sendMuteRadio(self.device, self.secondaryItem)
        end
        ReportDevice("Microphone state changed", self.device)
    end
end

-- a belt item is not sync with the server, so we need to tell it everything
local defaultPerformToggleOnOff = ISRadioAction.performToggleOnOff
function ISRadioAction:performToggleOnOff()
    defaultPerformToggleOnOff(self)
    if Character.isItemOnBeltAndNotInHand(getPlayer(), self.device) then
        TrpcClientSendCommands.sendGiveRadioState(self.device)
    end
    ReportDevice("Radio power changed", self.device)
end

local defaultPerformSetVolume = ISRadioAction.performSetVolume
function ISRadioAction:performSetVolume()
    defaultPerformSetVolume(self)
    if Character.isItemOnBeltAndNotInHand(getPlayer(), self.device) then
        TrpcClientSendCommands.sendGiveRadioState(self.device)
    end
    ReportDevice("Radio volume changed", self.device)
end

local defaultPerformRemoveHeadphones = ISRadioAction.performRemoveHeadphones
function ISRadioAction:performRemoveHeadphones()
    defaultPerformRemoveHeadphones(self)
    if Character.isItemOnBeltAndNotInHand(getPlayer(), self.device) then
        TrpcClientSendCommands.sendGiveRadioState(self.device)
    end
    ReportDevice("Radio headphones removed", self.device)
end

local defaultPerformAddHeadphones = ISRadioAction.performAddHeadphones
function ISRadioAction:performAddHeadphones()
    defaultPerformAddHeadphones(self)
    if Character.isItemOnBeltAndNotInHand(getPlayer(), self.device) then
        TrpcClientSendCommands.sendGiveRadioState(self.device)
    end
    ReportDevice("Radio headphones added", self.device)
end

local defaultPerformRemoveBattery = ISRadioAction.performRemoveBattery
function ISRadioAction:performRemoveBattery()
    defaultPerformRemoveBattery(self)
    if Character.isItemOnBeltAndNotInHand(getPlayer(), self.device) then
        -- when removing the battery the device is not turned on if not synced (belt is not synced)
        if self.deviceData:getIsTurnedOn() then
            defaultPerformToggleOnOff(self)
        end
        TrpcClientSendCommands.sendGiveRadioState(self.device)
    end
    ReportDevice("Radio battery removed", self.device)
end

local defaultPerformAddBattery = ISRadioAction.performAddBattery
function ISRadioAction:performAddBattery()
    defaultPerformAddBattery(self)
    if Character.isItemOnBeltAndNotInHand(getPlayer(), self.device) then
        TrpcClientSendCommands.sendGiveRadioState(self.device)
    end
    ReportDevice("Radio battery added", self.device)
end

local defaultPerformSetChannel = ISRadioAction.performSetChannel
function ISRadioAction:performSetChannel()
    defaultPerformSetChannel(self)
    if Character.isItemOnBeltAndNotInHand(getPlayer(), self.device) then
        TrpcClientSendCommands.sendGiveRadioState(self.device)
    end
    ReportDevice("Radio frequency changed", self.device)
end
