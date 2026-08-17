local AvatarIO = require("trpc/shared/utils/AvatarIO")
local AvatarStore = require("trpc/shared/utils/AvatarStore")
local Character = require("trpc/shared/utils/Character")
local File = require("trpc/shared/utils/File")
local Logger = require("trpc/core/Logger")

local AvatarManager = {}

function AvatarManager:getKnownAvatars()
    local toSend = {}
    local survivors, removed = AvatarStore.pruneInvalid(
        AvatarStore.getTable(AvatarStore.KEY_APPROVED),
        function(key, avatar)
            local path = avatar["path"]
            local checksum = avatar["checksum"]
            return path ~= nil and checksum ~= nil and serverFileExists("../Lua/" .. avatar["path"])
        end
    )
    for _, survivor in ipairs(survivors) do
        toSend[survivor.key] = survivor.avatar["checksum"]
    end
    if #removed > 0 then
        AvatarStore.removeMany(AvatarStore.KEY_APPROVED, removed)
    end
    return toSend
end

function AvatarManager:createRequestDirectory()
    local player = getPlayer()
    local username = player:getUsername()
    local path = username .. "/request/"
    local directoryPath = AvatarIO.getBasePath() .. path
    File.createDirectory(directoryPath, "move_your_avatar_here")
end

function AvatarManager:loadAvatarRequest()
    local player = getPlayer()
    local username = player:getUsername()
    local path = username .. "/request/"
    local directoryPath = AvatarIO.getBasePath() .. path
    File.createDirectory(directoryPath, "move_your_avatar_here")
    local avatar = AvatarIO.loadPlayerAvatar(path, player)
    if avatar == nil then
        return nil
    end
    local firstName, lastName = Character.getFirstAndLastName(player)
    local knownAvatar = AvatarManager:getAvatarData(username, firstName, lastName)
    if knownAvatar and knownAvatar.checksum == avatar.checksum then
        return nil -- avatar already approved
    end
    return avatar
end

local function SaveAvatar(modDataKey, username, firstName, lastName, extension, checksum, data, directory)
    local path = getPlayer():getUsername() .. "/" .. directory
    local fullPath = AvatarIO.savePlayerAvatar(username, firstName, lastName, extension, data, path)
    AvatarStore.upsert(modDataKey, username, firstName, lastName, {
        path = fullPath,
        checksum = checksum,
        username = username,
        firstName = firstName,
        lastName = lastName,
    })
    local texture = getTextureFromSaveDir(fullPath, "../Lua")
    if texture then
        Texture.reload(texture:getName())
    end
end

function AvatarManager:saveApprovedAvatar(username, firstName, lastName, extension, checksum, data)
    SaveAvatar(AvatarStore.KEY_APPROVED, username, firstName, lastName, extension, checksum, data, "")
end

function AvatarManager:savePendingAvatar(username, firstName, lastName, extension, checksum, data)
    SaveAvatar(AvatarStore.KEY_PENDING, username, firstName, lastName, extension, checksum, data, "pending")
end

function AvatarManager:getPendingAvatarData(username, firstName, lastName)
    return AvatarStore.get(AvatarStore.KEY_PENDING, username, firstName, lastName)
end

function AvatarManager:getAvatarData(username, firstName, lastName)
    local avatar = AvatarStore.get(AvatarStore.KEY_APPROVED, username, firstName, lastName)
    if avatar ~= nil and not File.exists(avatar["path"]) then
        AvatarStore.remove(AvatarStore.KEY_APPROVED, username, firstName, lastName)
        return nil
    end
    return avatar
end

function AvatarManager:removeAvatarData(username, firstName, lastName)
    AvatarStore.remove(AvatarStore.KEY_APPROVED, username, firstName, lastName)
end

function AvatarManager:getRequestAvatar()
    local player = getPlayer()
    local username = player:getUsername()
    local firstName, lastName = Character.getFirstAndLastName(player)
    local fileName = AvatarIO.createFileName(username, firstName, lastName)
    local path = AvatarIO.getAvatarPath(username .. "/request/" .. fileName)
    if path == nil then
        return nil
    end
    local texture = getTextureFromSaveDir(path, "../Lua")
    if texture == nil then
        Logger.error(
            "AvatarManager",
            'TRPC error: failed to load the request avatar for username "'
                .. username
                .. '" with character named "'
                .. firstName
                .. " "
                .. lastName
                .. '"'
        )
    end
    return texture
end

function AvatarManager:getAvatar(username, firstName, lastName)
    local avatar = self:getAvatarData(username, firstName, lastName)
    if avatar == nil then
        return nil
    end
    local path = avatar["path"]
    if path == nil then
        Logger.error("AvatarManager", "TRPC error: AvatarManager:getAvatar: avatar path is null")
        return nil
    end
    local texture = getTextureFromSaveDir(path, "../Lua")
    if texture == nil then
        Logger.error(
            "AvatarManager",
            'TRPC error: failed to load the avatar for username "'
                .. username
                .. '" with character named "'
                .. firstName
                .. " "
                .. lastName
                .. '", removing texture from cache'
        )
        self:removeAvatarData(username, firstName, lastName)
    end
    return texture
end

function AvatarManager:removeAvatarPending(username, firstName, lastName, checksum)
    assert(type(username) == "string", "TRPC error: rejectAvatar: missing username")
    assert(type(firstName) == "string", "TRPC error: rejectAvatar: missing firstName")
    assert(type(lastName) == "string", "TRPC error: rejectAvatar: missing lastName")
    assert(type(checksum) == "number", "TRPC error: rejectAvatar: missing checksum")
    local avatar = AvatarStore.get(AvatarStore.KEY_PENDING, username, firstName, lastName)
    if avatar ~= nil and avatar["checksum"] == checksum then
        local path = avatar["path"]
        assert(
            type(path) == "string",
            'TRPC error: removeAvatarPending: avatar path not found for username "'
                .. username
                .. '" with character named "'
                .. firstName
                .. " "
                .. lastName
                .. '"'
        )
        AvatarStore.remove(AvatarStore.KEY_PENDING, username, firstName, lastName)
        File.remove(path)
    end
end

function AvatarManager:isPendingAvatarAlive(username, firstName, lastName, checksum)
    assert(type(username) == "string", "TRPC error: rejectAvatar: missing username")
    assert(type(firstName) == "string", "TRPC error: rejectAvatar: missing firstName")
    assert(type(lastName) == "string", "TRPC error: rejectAvatar: missing lastName")
    assert(type(checksum) == "number", "TRPC error: rejectAvatar: missing checksum")
    local avatar = self:getPendingAvatarData(username, firstName, lastName)
    return avatar ~= nil and avatar["checksum"] == checksum
end

--- Shared pending-avatar validity predicate used by both getFirstAvatarPending
--- and getAvatarsPending. Emits the same per-field errors the two original
--- duplicated loops emitted.
local function isPendingAvatarUsable(key, avatar)
    local path = avatar["path"]
    local texture = getTextureFromSaveDir(path, "../Lua")
    local checksum = avatar["checksum"]
    local username = avatar["username"]
    local firstName = avatar["firstName"]
    local lastName = avatar["lastName"]
    if path == nil then
        Logger.error(
            "AvatarManager",
            'TRPC error: no path set for unapproved avatar "' .. key .. '", removing avatar from cache'
        )
        return false
    elseif texture == nil then
        Logger.error(
            "AvatarManager",
            'TRPC error: failed to load the unapproved avatar texture for "'
                .. key
                .. '" at "'
                .. path
                .. '", removing texture from cache'
        )
        return false
    elseif texture:getWidth() ~= AvatarIO.AVATAR_WIDTH or texture:getHeight() ~= AvatarIO.AVATAR_HEIGHT then
        Logger.error("AvatarManager", 'TRPC error: invalid pending avatar dimensions for "' .. key .. '"')
        return false
    elseif checksum == nil then
        Logger.error(
            "AvatarManager",
            'TRPC error: failed to load the unapproved avatar checksum for "' .. key .. '", removing texture from cache'
        )
        return false
    elseif username == nil then
        Logger.error(
            "AvatarManager",
            'TRPC error: failed to load the unapproved avatar username for "' .. key .. '", removing texture from cache'
        )
        return false
    elseif firstName == nil then
        Logger.error(
            "AvatarManager",
            'TRPC error: failed to load the unapproved avatar first name for "'
                .. key
                .. '", removing texture from cache'
        )
        return false
    elseif lastName == nil then
        Logger.error(
            "AvatarManager",
            'TRPC error: failed to load the unapproved avatar last name for "'
                .. key
                .. '", removing texture from cache'
        )
        return false
    end
    return true
end

function AvatarManager:getFirstAvatarPending()
    local survivors, removed =
        AvatarStore.pruneInvalid(AvatarStore.getTable(AvatarStore.KEY_PENDING), isPendingAvatarUsable)
    if #removed > 0 then
        AvatarStore.removeMany(AvatarStore.KEY_PENDING, removed)
    end
    local avatarResult = nil
    local survivor = survivors[1]
    if survivor ~= nil then
        local avatar = survivor.avatar
        avatarResult = {
            username = avatar["username"],
            texture = getTextureFromSaveDir(avatar["path"], "../Lua"),
            checksum = avatar["checksum"],
            firstName = avatar["firstName"],
            lastName = avatar["lastName"],
        }
    end
    return avatarResult
end

function AvatarManager:getAvatarsPending()
    local survivors, removed =
        AvatarStore.pruneInvalid(AvatarStore.getTable(AvatarStore.KEY_PENDING), isPendingAvatarUsable)
    if #removed > 0 then
        AvatarStore.removeMany(AvatarStore.KEY_PENDING, removed)
    end
    local avatarsToApprove = {}
    local count = 0
    for _, survivor in ipairs(survivors) do
        local avatar = survivor.avatar
        table.insert(avatarsToApprove, {
            username = avatar["username"],
            texture = getTextureFromSaveDir(avatar["path"], "../Lua"),
            checksum = avatar["checksum"],
            firstName = avatar["firstName"],
            lastName = avatar["lastName"],
        })
        count = count + 1
    end
    return avatarsToApprove, count
end

local function CreateAvatarManager()
    local o = {}
    setmetatable(o, AvatarManager)
    AvatarManager.__index = AvatarManager
    return o
end

local instance = CreateAvatarManager()

-- Since a lua file is only read once, this file will always return the same
-- value. Making this a singleton that cannot be missused.
return instance
