-- PlayerData.lua
-- ------------------------------
-- Estado persistente del jugador: color de voz, pitch, flags globales
-- guardados en ModData "trpc" y expuestos en ISChat.instance.
--
-- Globals de PZ en runtime: ISChat, ModData, getPlayer, ZombRand,
-- ZombRandFloat.

local PlayerData = {}

local function GetRandomInt(min, max)
    return ZombRand(max - min) + min
end

local function GenerateRandomColor()
    return { GetRandomInt(0, 254), GetRandomInt(0, 254), GetRandomInt(0, 254) }
end

local function SetPlayerColor(color)
    ISChat.instance.trpcModData["playerColor"] = color
    ModData.add("trpc", ISChat.instance.trpcModData)
end

local function SetPlayerPitch(pitch)
    ISChat.instance.trpcModData["voicePitch"] = pitch
    ModData.add("trpc", ISChat.instance.trpcModData)
end

local function RandomVoicePitch(isFemale)
    local randomPitch = ZombRandFloat(0.85, 1.15)
    if isFemale == true then
        randomPitch = randomPitch + 0.30
    end
    return randomPitch
end

local function InitGlobalModData()
    local trpcModData = ModData.getOrCreate("trpc")
    ISChat.instance.trpcModData = trpcModData

    if trpcModData["playerColor"] == nil then
        SetPlayerColor(GenerateRandomColor())
    end
    if trpcModData["isVoiceEnabled"] == nil and ISChat.instance.isVoiceEnabled == nil then
        -- wait for the server settings to override this if voices are enabled by default
        ISChat.instance.isVoiceEnabled = false
    elseif trpcModData["isVoiceEnabled"] ~= nil then
        ISChat.instance.isVoiceEnabled = trpcModData["isVoiceEnabled"]
    end
    if trpcModData["isRadioIconEnabled"] == nil and ISChat.instance.isRadioIconEnabled == nil then
        ISChat.instance.isRadioIconEnabled = true
    elseif trpcModData["isRadioIconEnabled"] ~= nil then
        ISChat.instance.isRadioIconEnabled = trpcModData["isRadioIconEnabled"]
    end
    if trpcModData["isPortraitEnabled"] == nil and ISChat.instance.isPortraitEnabled == nil then
        ISChat.instance.isPortraitEnabled = true
    elseif trpcModData["isPortraitEnabled"] ~= nil then
        ISChat.instance.isPortraitEnabled = trpcModData["isPortraitEnabled"]
    end
    if trpcModData["voicePitch"] == nil then
        local randomPitch = RandomVoicePitch(getPlayer():getVisual():isFemale())
        SetPlayerPitch(randomPitch)
    end
end

-- API pública
PlayerData.GetRandomInt = GetRandomInt
PlayerData.GenerateRandomColor = GenerateRandomColor
PlayerData.SetPlayerColor = SetPlayerColor
PlayerData.SetPlayerPitch = SetPlayerPitch
PlayerData.RandomVoicePitch = RandomVoicePitch
PlayerData.InitGlobalModData = InitGlobalModData

return PlayerData
