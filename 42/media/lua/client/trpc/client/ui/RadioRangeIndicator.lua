local RangeIndicator = require("trpc/client/ui/RangeIndicator")
local Character = require("trpc/shared/utils/Character")
local World = require("trpc/shared/utils/World")
local RadioStatusIcons = require("trpc/client/ui/RadioStatusIcons")

local RadioRangeIndicator = {}

local Colors = {
    { 235, 255, 000 },
    { 000, 235, 255 },
    { 255, 000, 235 },
    { 255, 235, 000 },
    { 000, 255, 235 },
    { 235, 000, 255 },
}

local NextColorIndex = 1

function RadioRangeIndicator:freeIndicators()
    for _, indicator in pairs(self.indicators) do
        if indicator ~= nil then
            indicator:unsubscribe()
        end
    end
    self.indicators = {}
    self.radios = {}
    NextColorIndex = 1
end

function RadioRangeIndicator:registerRadio(object, radio, radios)
    local radioData = radio:getDeviceData()
    if radioData ~= nil then
        if radioData:getIsTurnedOn() then
            local range = Character.getRadioRange(radioData, self.radioMaxRange)
            if radios[object] == nil then
                radios[object] = { object = object, radio = radio, range = range }
            end
        end
    end
end

function RadioRangeIndicator:reconcileRadios(desiredRadios)
    local removedRadios = {}
    for object, info in pairs(self.radios) do
        local desired = desiredRadios[object]
        if desired == nil then
            removedRadios[object] = info
        else
            info.radio = desired.radio
            if info.range ~= desired.range then
                info.range = desired.range
                info.indicator.range = desired.range
            end
            desiredRadios[object] = nil
        end
    end

    for object, info in pairs(removedRadios) do
        info.indicator:unsubscribe()
        self.indicators[object] = nil
        self.radios[object] = nil
        if self.statusHandler ~= nil then
            local status = "unavailable"
            local radioData = info.radio and info.radio:getDeviceData()
            if radioData ~= nil and not radioData:getIsTurnedOn() then
                status = "inactive"
            elseif info.object ~= nil and World.distanceManhatten(info.object, self.player) > self.range then
                status = "out-of-range"
            end
            self.statusHandler(info, status)
        end
    end

    for object, info in pairs(desiredRadios) do
        local indicator = RangeIndicator:new(object, info.range, Colors[NextColorIndex])
        NextColorIndex = NextColorIndex % #Colors + 1
        info.indicator = indicator
        self.indicators[object] = indicator
        self.radios[object] = info
        indicator:subscribe()
    end
end

function RadioRangeIndicator:discoverRadios()
    local radios = Character.getRunningRadiosInRange(self.player, self.range)
    local desiredRadios = {}
    if radios ~= nil then
        for _, radio in pairs(radios.squares) do
            self:registerRadio(radio, radio, desiredRadios)
        end
        for _, info in pairs(radios.players) do
            local player = info["player"]
            local radio = info["radio"]
            self:registerRadio(player, radio, desiredRadios)
        end
        for _, info in pairs(radios.vehicles) do
            local vehicle = info["vehicle"]
            local radio = info["radio"]
            self:registerRadio(vehicle, radio, desiredRadios)
        end
    end
    self:reconcileRadios(desiredRadios)
end

function RadioRangeIndicator:update()
    local currentTime = Calendar.getInstance():getTimeInMillis()
    local elapsed = currentTime - self.previousTime
    if elapsed < 500 then
        return
    end
    self:discoverRadios()
    self.previousTime = currentTime
end

function RadioRangeIndicator:updateIcons()
    local radios = Character.getAllHandAndBeltItemsByGroup(self.player, "Radio")
    for _, radio in pairs(radios) do
        local radioData = radio:getDeviceData()
        if radioData then
            if radioData:getIsTurnedOn() then
                self.radioStatusIcons.enabled = self.showIcon
                return
            end
        end
    end
    for _, info in pairs(self.radios) do
        local object = info["object"]
        local range = info["range"]

        local distance = World.distanceManhatten(object, self.player)
        if distance <= range then
            self.radioStatusIcons.enabled = self.showIcon
            return
        end
    end
    self.radioStatusIcons.enabled = false
end

function RadioRangeIndicator:setStatusHandler(handler)
    self.statusHandler = type(handler) == "function" and handler or nil
end

function RadioRangeIndicator:subscribe()
    self:subscribeIndicators()
    if self.event then
        return
    end
    self.event = function()
        self:update()
    end
    Events.OnTick.Add(self.event)
    self.iconEvent = function()
        self:updateIcons()
    end
    Events.OnPreUIDraw.Add(self.iconEvent)
    self.radioStatusIcons:subscribe()
end

function RadioRangeIndicator:unsubscribe()
    self:unsubscribeIndicators()
    self:freeIndicators()
    if not self.event then
        return
    end
    Events.OnTick.Remove(self.event)
    self.event = nil
    Events.OnPreUIDraw.Remove(self.iconEvent)
    self.iconEvent = nil
    self.radioStatusIcons:unsubscribe()
end

function RadioRangeIndicator:subscribeIndicators()
    for _, indicator in pairs(self.indicators) do
        indicator:subscribe()
    end
end

function RadioRangeIndicator:unsubscribeIndicators()
    for _, indicator in pairs(self.indicators) do
        indicator:unsubscribe()
    end
end

function RadioRangeIndicator:new(discoveringRange, radioMaxRange, showIcon)
    local o = {}
    setmetatable(o, self)
    self.__index = self

    o.player = getPlayer()
    o.range = discoveringRange
    o.radioMaxRange = radioMaxRange
    o.showIcon = showIcon
    o.indicators = {}
    o.radios = {}
    o.previousTime = 0
    o.radioStatusIcons = RadioStatusIcons:new(o.player)
    o.statusHandler = nil
    return o
end

return RadioRangeIndicator
