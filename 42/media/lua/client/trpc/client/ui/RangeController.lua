-- ui/RangeController.lua
-- ------------------------------
-- Módulo RangeController del Core TRPC.
-- Controla el indicador de rango de voz (subscribe/unsubscribe según el
-- estado del botón de rango y el stream activo).
--
-- Globals de PZ en runtime: ISChat, TrpcServerSettings, getPlayer
-- Requires propios: RangeIndicator

local RangeIndicator = require("trpc/client/ui/RangeIndicator")
local ChatState = require("trpc/client/ui/ChatState")

local RangeController = {}

local function UpdateRangeIndicatorVisibility()
    if ISChat.instance.rangeButtonState == "visible" then
        if ISChat.instance.rangeIndicator and ChatState.isFocused() then
            ISChat.instance.rangeIndicator:subscribe()
        end
    elseif ISChat.instance.rangeButtonState == "hidden" then
        if ISChat.instance.rangeIndicator then
            ISChat.instance.rangeIndicator:unsubscribe()
        end
    else
        if ISChat.instance.rangeIndicator then
            ISChat.instance.rangeIndicator:subscribe()
        end
    end
end

local function UpdateRangeIndicator(stream)
    if
        TrpcServerSettings ~= nil
        and TrpcServerSettings[stream.name]["range"] ~= nil
        and TrpcServerSettings[stream.name]["range"] ~= -1
        and TrpcServerSettings[stream.name]["color"] ~= nil
    then
        if ISChat.instance.rangeIndicator then
            ISChat.instance.rangeIndicator:unsubscribe()
        end
        local range = TrpcServerSettings[stream.name]["range"]
        ISChat.instance.rangeIndicator =
            RangeIndicator:new(getPlayer(), range, TrpcServerSettings[stream.name]["color"])
        UpdateRangeIndicatorVisibility()
    else
        if ISChat.instance.rangeIndicator then
            ISChat.instance.rangeIndicator:unsubscribe()
        end
        ISChat.instance.rangeIndicator = nil
    end
end

-- API pública
RangeController.updateRangeIndicatorVisibility = UpdateRangeIndicatorVisibility
RangeController.updateRangeIndicator = UpdateRangeIndicator

return RangeController
