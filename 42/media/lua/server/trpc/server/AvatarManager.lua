local AvatarIO = require("trpc/shared/utils/AvatarIO")
local AvatarStore = require("trpc/shared/utils/AvatarStore")
local Character = require("trpc/shared/utils/Character")
local File = require("trpc/shared/utils/File")
local ServerSend = require("trpc/server/network/ServerSend")
local World = require("trpc/shared/utils/World")
local Logger = require("trpc/core/Logger")

local AvatarManager = {}

function AvatarManager:loadPlayerAvatar(player)
    local avatar = AvatarIO.loadPlayerAvatar("approved", player)
    if avatar == nil then -- just to make it clear
        return nil
    end
    local key = AvatarIO.createFileNameFromPlayer(player)
    self.avatars[key] = avatar
end

function AvatarManager:freePlayerAvatar(player)
    local key = AvatarIO.createFileNameFromPlayer(player)
    self.avatars[key] = nil
end

function AvatarManager:registerPlayerAvatars(player, avatars)
    if self.players[player:getUsername()] == nil then
        self.players[player:getUsername()] = {}
    end
    self.players[player:getUsername()]["approved"] = avatars
    if self.players[player:getUsername()]["pending"] == nil then
        self.players[player:getUsername()]["pending"] = {}
    end
end

function AvatarManager:loadPendingAvatarsData()
    if self.pendingAvatarsStored == nil then
        self.pendingAvatarsStored = AvatarStore.getTable(AvatarStore.KEY_PENDING)
    end
end

function AvatarManager:loadPendingAvatar(key, avatar)
    local username = avatar["username"]
    local firstName = avatar["firstName"]
    local lastName = avatar["lastName"]
    local checksum = avatar["checksum"]
    local playerAvatar = AvatarIO.loadPlayerAvatarFromNames("pending", username, firstName, lastName)
    if playerAvatar ~= nil then
        if checksum ~= playerAvatar["checksum"] then
            Logger.error(
                "AvatarManager",
                'TRPC error: pending avatar for user "'
                    .. username
                    .. '" and character "'
                    .. firstName
                    .. " "
                    .. lastName
                    .. '" does not match the one sent by the player, if you tried to '
                    .. "upload an avatar on the server through FTP you should move it "
                    .. 'directly in the "approved" directory'
            )
            self:removePendingAvatar(playerAvatar["username"], playerAvatar["firstName"], playerAvatar["lastName"])
            return
        end
        self.pendingAvatarsShared[key] = {
            data = playerAvatar["data"],
            checksum = playerAvatar["checksum"],
            username = username,
            firstName = firstName,
            lastName = lastName,
            extension = playerAvatar["extension"],
        }
    end
end

function AvatarManager:loadPendingAvatars()
    if self.pendingAvatarsStored == nil then
        self:loadPendingAvatarsData()
        self.pendingAvatarsShared = {}
        for key, avatar in pairs(self.pendingAvatarsStored) do
            self:loadPendingAvatar(key, avatar)
        end
    end
end

function AvatarManager:trackPlayersOnline()
    local newConnectedPlayers = {}
    World.forAllPlayers(function(player)
        local username = player:getUsername()
        local firstName, lastName = Character.getFirstAndLastName(player)
        if not self.connectedPlayers[username] then
            self:loadPlayerAvatar(player)
        elseif
            self.charactersNames[username]
            and (
                self.charactersNames[username]["firstName"] ~= firstName
                or self.charactersNames[username]["lastName"] ~= lastName
            )
        then
            self:loadPlayerAvatar(player)
        end
        self.charactersNames[username] = {
            firstName = firstName,
            lastName = lastName,
        }
        newConnectedPlayers[username] = player
    end)
    for username, player in pairs(self.connectedPlayers) do
        if newConnectedPlayers[username] == nil then
            self.players[username] = nil
            self:freePlayerAvatar(player)
        end
    end
    self.connectedPlayers = newConnectedPlayers
end

function AvatarManager:sendApprovedAvatars(playerUsername, playerAvatars)
    for key, avatar in pairs(self.avatars) do
        local storedAvatarChecksum = avatar["checksum"]
        local playerAvatarChecksum = playerAvatars[key]
        if playerAvatarChecksum ~= storedAvatarChecksum then
            local player = self.connectedPlayers[playerUsername]
            if player ~= nil then
                ServerSend.ApprovedAvatar(
                    player,
                    storedAvatarChecksum,
                    avatar["username"],
                    avatar["firstName"],
                    avatar["lastName"],
                    avatar["data"],
                    avatar["extension"]
                )
                playerAvatars[key] = storedAvatarChecksum
            else
                Logger.error("AvatarManager", "TRPC error: sendApprovedAvatars: player not found: " .. playerUsername)
                break
            end
        end
    end
end

function AvatarManager:sendPendingAvatars(playerUsername, playerAvatars)
    local player = self.connectedPlayers[playerUsername]
    if player == nil then
        Logger.error("AvatarManager", "TRPC error: sendPendingAvatars: player not found: " .. playerUsername)
        return
    end
    local accessLevel = player:getAccessLevel()
    if accessLevel ~= "Admin" and accessLevel ~= "Moderator" then
        return
    end
    for key, avatar in pairs(self.pendingAvatarsShared) do
        local storedAvatarChecksum = avatar["checksum"]
        local playerAvatarChecksum = playerAvatars[key]
        if playerAvatarChecksum ~= storedAvatarChecksum then
            ServerSend.PendingAvatar(
                player,
                storedAvatarChecksum,
                avatar["username"],
                avatar["firstName"],
                avatar["lastName"],
                avatar["data"],
                avatar["extension"]
            )
            playerAvatars[key] = storedAvatarChecksum
        end
    end
end

function AvatarManager:sendAvatars()
    for playerUsername, playerAvatarCategories in pairs(self.players) do
        local approvedAvatars = playerAvatarCategories["approved"]
        local pendingAvatars = playerAvatarCategories["pending"]
        self:sendApprovedAvatars(playerUsername, approvedAvatars)
        self:sendPendingAvatars(playerUsername, pendingAvatars)
    end
end

function AvatarManager:removePendingAvatar(username, firstName, lastName)
    if self.pendingAvatarsStored == nil then
        AvatarManager:loadPendingAvatarsData()
    end
    AvatarStore.remove(AvatarStore.KEY_PENDING, username, firstName, lastName)
    local key = AvatarIO.createFileName(username, firstName, lastName)
    local path = nil
    if self.pendingAvatarsStored[key] then
        path = self.pendingAvatarsStored[key]["path"]
    end
    self.pendingAvatarsStored[key] = nil
    self.pendingAvatarsShared[key] = nil
    return path
end

function AvatarManager:removePendingAvatarAndDeleteFile(username, firstName, lastName)
    local path = self:removePendingAvatar(username, firstName, lastName)
    File.remove(path)
end

function AvatarManager:updatePendingAvatarStored(username, firstName, lastName, extension, checksum, data)
    if self.pendingAvatarsStored == nil then
        AvatarManager:loadPendingAvatarsData()
    end
    local path = "/pending"
    -- NOTE: path="/pending" preserves the existing server bug: File.remove on
    -- it zeroes bytes but never unlinks the avatar file. Fixing this is a
    -- separate deferred change (documented in the avatar-store spec).
    AvatarIO.savePlayerAvatar(username, firstName, lastName, extension, data, path)
    local key = AvatarIO.createFileName(username, firstName, lastName)
    local pendingAvatarInfo = {
        path = path,
        checksum = checksum,
        username = username,
        firstName = firstName,
        lastName = lastName,
        extension = extension,
    }
    AvatarStore.upsert(AvatarStore.KEY_PENDING, username, firstName, lastName, pendingAvatarInfo)
    self.pendingAvatarsStored[key] = pendingAvatarInfo
    return key, pendingAvatarInfo
end

-- we could additionally store the data in a table directly, but we could not
-- guarantee the image was successfully saved
function AvatarManager:registerAvatarRequest(username, firstName, lastName, extension, checksum, data)
    local key, pendingAvatarInfo =
        self:updatePendingAvatarStored(username, firstName, lastName, extension, checksum, data)
    self:loadPendingAvatar(key, pendingAvatarInfo)
end

function AvatarManager:update()
    local currentTime = Calendar.getInstance():getTimeInMillis()
    local elapsed = currentTime - self.previousTime
    if elapsed < 500 then
        return
    end
    self:loadPendingAvatars()
    self:trackPlayersOnline()
    self:sendAvatars()
    self.previousTime = currentTime
end

function AvatarManager:notifyAvatarProcessed(username, firstName, lastName, checksum)
    for _, player in pairs(self.connectedPlayers) do
        local accessLevel = player:getAccessLevel()
        if accessLevel == "Admin" or accessLevel == "Moderator" then
            ServerSend.AvatarProcessed(player, username, firstName, lastName, checksum)
        end
        local key = AvatarIO.createFileName(username, firstName, lastName)
        if self.players and self.players[player:getUsername()] and self.players[player:getUsername()]["pending"] then
            self.players[player:getUsername()]["pending"][key] = nil
        end
    end
end

function AvatarManager:approveAvatar(admin, username, firstName, lastName, checksum)
    local key = AvatarIO.createFileName(username, firstName, lastName)
    local avatar = self.pendingAvatarsShared[key]
    local adminName = admin:getUsername()
    if avatar == nil then
        Logger.error(
            "AvatarManager",
            "TRPC error: avatar approved by "
                .. adminName
                .. " not found for "
                .. username
                .. ' "'
                .. firstName
                .. " "
                .. lastName
                .. '" ('
                .. checksum
                .. ")"
        )
        return
    end
    if checksum ~= avatar["checksum"] then
        Logger.error(
            "AvatarManager",
            "TRPC error: avatar approved by "
                .. adminName
                .. " outdated for "
                .. username
                .. ' "'
                .. firstName
                .. " "
                .. lastName
                .. '" ('
                .. checksum
                .. ")"
        )
        return
    end
    local extension = avatar["extension"]
    local data = avatar["data"]
    assert(
        extension ~= nil,
        "TRPC error: not extension found for pending avatar "
            .. username
            .. ' "'
            .. firstName
            .. " "
            .. lastName
            .. '" ('
            .. checksum
            .. ")"
    )
    assert(
        data ~= nil,
        "TRPC error: not data found for pending avatar "
            .. username
            .. ' "'
            .. firstName
            .. " "
            .. lastName
            .. '" ('
            .. checksum
            .. ")"
    )
    AvatarIO.savePlayerAvatar(username, firstName, lastName, extension, data, "approved")
    if self.connectedPlayers[username] then -- players is online so we load the avatar
        local player = self.connectedPlayers[username]
        self:loadPlayerAvatar(player)
    end
    self:removePendingAvatarAndDeleteFile(username, firstName, lastName)
    self:notifyAvatarProcessed(username, firstName, lastName, checksum)
end

function AvatarManager:rejectAvatar(admin, username, firstName, lastName, checksum)
    local key = AvatarIO.createFileName(username, firstName, lastName)
    local avatar = self.pendingAvatarsShared[key]
    local adminName = admin:getUsername()
    if avatar == nil then
        Logger.error(
            "AvatarManager",
            "TRPC error: avatar rejected by "
                .. adminName
                .. " not found for "
                .. username
                .. ' "'
                .. firstName
                .. " "
                .. lastName
                .. '" ('
                .. checksum
                .. ")"
        )
        return
    end
    if checksum ~= avatar["checksum"] then
        Logger.error(
            "AvatarManager",
            "TRPC error: avatar rejected by "
                .. adminName
                .. " outdated for "
                .. username
                .. ' "'
                .. firstName
                .. " "
                .. lastName
                .. '" ('
                .. checksum
                .. ")"
        )
        return
    end
    self:removePendingAvatarAndDeleteFile(username, firstName, lastName)
    self:notifyAvatarProcessed(username, firstName, lastName, checksum)
end

local function CreateAvatarManager()
    local o = {}
    setmetatable(o, AvatarManager)
    AvatarManager.__index = AvatarManager
    o.players = {}
    o.avatars = {}
    o.pendingAvatarsStored = nil
    o.pendingAvatarsShared = nil
    o.connectedPlayers = {}
    o.charactersNames = {}
    o.previousTime = 0
    return o
end

local instance = CreateAvatarManager()

if not isClient() then
    Events.OnTick.Add(function()
        instance:update()
    end)
end

-- Since a lua file is only read once, this file will always return the same
-- value. Making this a singleton that cannot be missused.
return instance
