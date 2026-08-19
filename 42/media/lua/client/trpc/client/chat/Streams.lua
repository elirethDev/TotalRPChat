-- Streams.lua
-- TRPC chat stream/channel definitions and command lookup helpers.
--
-- Extracted from ISChat.lua (incremental refactor, first module).
-- The singleton ISChat.instance is preserved: these tables/functions are
-- assigned onto the ISChat global by the entry point (ISChat.lua) and operate
-- on ISChat.* at runtime. This module body itself makes no reference to
-- ISChat at load time, so it is safe to require before ISChat is initialized.

local Streams = {}
local ChatState = require("trpc/client/ui/ChatState")
local ChannelRegistry = require("trpc/shared/ChannelRegistry")

-- ---------------------------------------------------------------------------
-- Chat stream (channel) definitions
-- ---------------------------------------------------------------------------
-- Per-channel client metadata, keyed by the registry channel name. allChatStreams
-- is derived below from ChannelRegistry.getAll() + STREAM_META so the registry
-- stays the single source of the 13 wire names. Values copied verbatim from the
-- previous literal table (byte-equivalent).
local STREAM_META = {
    say = { command = "/say ", shortCommand = "/s ", tabID = 1 },
    whisper = { command = "/whisper ", shortCommand = "/w ", tabID = 1 },
    low = { command = "/low ", shortCommand = "/l ", tabID = 1 },
    yell = { command = "/yell ", shortCommand = "/y ", tabID = 1 },
    faction = { command = "/faction ", shortCommand = "/f ", tabID = 1 },
    safehouse = { command = "/safehouse ", shortCommand = "/sh ", tabID = 1 },
    general = { command = "/all ", shortCommand = "/g ", tabID = 1 },
    scriptedRadio = { tabID = 1 },
    ooc = { command = "/ooc ", shortCommand = "/o ", tabID = 2 },
    pm = { command = "/pm ", shortCommand = "/p ", tabID = 3 },
    admin = { command = "/admin ", shortCommand = "/a ", tabID = 4 },
    me = { command = "/me ", shortCommand = nil, tabID = 1, forget = true },
    ["do"] = { command = "/do ", shortCommand = nil, tabID = 1, forget = true },
}

Streams.allChatStreams = {}
Streams.chatStreamsByName = {}
local registryEntries = ChannelRegistry.getAll()
for i, entry in ipairs(registryEntries) do
    local meta = STREAM_META[entry.name]
    local stream = { name = entry.name }
    if meta then
        stream.command = meta.command
        stream.shortCommand = meta.shortCommand
        stream.tabID = meta.tabID
        if meta.forget then
            stream.forget = true
        end
    end
    Streams.allChatStreams[i] = stream
    Streams.chatStreamsByName[entry.name] = stream
end

-- ---------------------------------------------------------------------------
-- Trpc (slash) command definitions
-- ---------------------------------------------------------------------------
Streams.trpcCommand = {}
Streams.trpcCommand[1] = { name = "color", command = "/color", shortCommand = nil }
Streams.trpcCommand[2] = { name = "roll", command = "/roll", shortCommand = nil }
Streams.trpcCommand[3] = { name = "language", command = "/language", shortCommand = "/la" }

-- ---------------------------------------------------------------------------
-- Default/last stream per tab. These reference the same stream objects as
-- allChatStreams (not copies), matching the original reference semantics.
-- ---------------------------------------------------------------------------
Streams.defaultTabStream = {}
Streams.defaultTabStream[1] = Streams.allChatStreams[1]
Streams.defaultTabStream[2] = Streams.allChatStreams[9]
Streams.defaultTabStream[3] = Streams.allChatStreams[10]
Streams.defaultTabStream[4] = Streams.allChatStreams[11]

Streams.lastTabStream = {}
Streams.lastTabStream[1] = Streams.defaultTabStream[1]
Streams.lastTabStream[2] = Streams.defaultTabStream[2]
Streams.lastTabStream[3] = Streams.defaultTabStream[3]
Streams.lastTabStream[4] = Streams.defaultTabStream[4]

local function IsStreamEnabled(streamName, allowBeforeSettings)
    if TrpcServerSettings == nil then
        return allowBeforeSettings == true
    end
    return TrpcServerSettings[streamName] ~= nil and TrpcServerSettings[streamName].enabled == true
end

local function GetFallbackInputStream()
    return Streams.defaultTabStream[1] or Streams.allChatStreams[1]
end

local function ResolveInputChannel(inputChannel, allowBeforeSettings)
    local stream = Streams.chatStreamsByName[inputChannel]
    if stream ~= nil and stream.command ~= nil and IsStreamEnabled(stream.name, allowBeforeSettings == true) then
        return stream
    end
    return GetFallbackInputStream()
end

local function IsOnlySpacesOrEmpty(command)
    local commandWithoutSpaces = command:gsub("%s+", "")
    return #commandWithoutSpaces == 0
end

local function GetCommandFromMessage(command)
    if not luautils.stringStarts(command, "/") then
        local defaultStream = ISChat.defaultTabStream[ChatState.getCurrentTabID()]
            or ISChat.defaultTabStream[1]
        return defaultStream, "", false
    end
    if IsOnlySpacesOrEmpty(command) then
        return nil
    end
    for _, stream in ipairs(ISChat.allChatStreams) do
        if stream.command and luautils.stringStarts(command, stream.command) then
            return stream, stream.command, false
        elseif stream.shortCommand and luautils.stringStarts(command, stream.shortCommand) then
            return stream, stream.shortCommand, false
        end
    end
    return nil
end

local function GetTrpcCommandFromMessage(command)
    if not luautils.stringStarts(command, "/") then
        return nil
    end
    if IsOnlySpacesOrEmpty(command) then
        return nil
    end
    for _, stream in ipairs(ISChat.trpcCommand) do
        if luautils.stringStarts(command, stream.command) then
            return stream, stream.command
        elseif stream.shortCommand and luautils.stringStarts(command, stream.shortCommand) then
            return stream, stream.shortCommand
        end
    end
    return nil
end

local function UpdateTabStreams(newTab, tabID, inputChannel)
    newTab.chatStreams = {}
    Streams.defaultTabStream[tabID] = nil
    Streams.lastTabStream[tabID] = nil

    if inputChannel ~= nil then
        local stream = ResolveInputChannel(inputChannel, true)
        if stream ~= nil then
            table.insert(newTab.chatStreams, stream)
            Streams.defaultTabStream[tabID] = stream
            Streams.lastTabStream[tabID] = stream
        end
    else
        for _, stream in ipairs(Streams.allChatStreams) do
            local name = stream["name"]
            if stream["tabID"] == tabID and IsStreamEnabled(name, false) then
                table.insert(newTab.chatStreams, stream)
            end
        end
        if tabID == 1 and #newTab.chatStreams == 0 then
            local stream = GetFallbackInputStream()
            if stream ~= nil then
                table.insert(newTab.chatStreams, stream)
                Streams.defaultTabStream[tabID] = stream
                Streams.lastTabStream[tabID] = stream
            end
        end
        if #newTab.chatStreams >= 1 then
            Streams.defaultTabStream[tabID] = newTab.chatStreams[1]
            Streams.lastTabStream[tabID] = Streams.lastTabStream[tabID] or newTab.chatStreams[1]
        end
    end

    if #newTab.chatStreams >= 1 then
        newTab.lastChatCommand = newTab.chatStreams[1].command
    else
        newTab.lastChatCommand = nil
    end
end

local function RemoveTabStreams(tabID)
    Streams.defaultTabStream[tabID] = nil
    Streams.lastTabStream[tabID] = nil
end

local function ResetTabStreams()
    for tabID in pairs(Streams.defaultTabStream) do
        Streams.defaultTabStream[tabID] = nil
    end
    for tabID in pairs(Streams.lastTabStream) do
        Streams.lastTabStream[tabID] = nil
    end

    Streams.defaultTabStream[1] = Streams.allChatStreams[1]
    Streams.defaultTabStream[2] = Streams.allChatStreams[9]
    Streams.defaultTabStream[3] = Streams.allChatStreams[10]
    Streams.defaultTabStream[4] = Streams.allChatStreams[11]
    Streams.lastTabStream[1] = Streams.defaultTabStream[1]
    Streams.lastTabStream[2] = Streams.defaultTabStream[2]
    Streams.lastTabStream[3] = Streams.defaultTabStream[3]
    Streams.lastTabStream[4] = Streams.defaultTabStream[4]
end

local function IsStreamForTab(tabID, stream)
    if stream == nil then
        return false
    end
    local tabStream = Streams.lastTabStream[tabID] or Streams.defaultTabStream[tabID]
    return tabStream == stream
end

Streams.IsOnlySpacesOrEmpty = IsOnlySpacesOrEmpty
Streams.GetCommandFromMessage = GetCommandFromMessage
Streams.GetTrpcCommandFromMessage = GetTrpcCommandFromMessage
Streams.resolveInputChannel = ResolveInputChannel
Streams.getFallbackInputStream = GetFallbackInputStream
Streams.UpdateTabStreams = UpdateTabStreams
Streams.removeTabStreams = RemoveTabStreams
Streams.resetTabStreams = ResetTabStreams
Streams.isStreamForTab = IsStreamForTab

return Streams
