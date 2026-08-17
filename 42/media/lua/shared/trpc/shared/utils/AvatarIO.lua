local Character = require("trpc/shared/utils/Character")
local File = require("trpc/shared/utils/File")
local Logger = require("trpc/core/Logger")

local AvatarIO = {}

AvatarIO.AVATAR_WIDTH = 60
AvatarIO.AVATAR_HEIGHT = 80

local function ReadByte(data, index)
    local byte = data[index]
    if
        type(byte) ~= "number"
        or byte ~= byte
        or byte < 0
        or byte > 255
        or byte ~= math.floor(byte)
    then
        return nil
    end
    return byte
end

local function ReadUInt16(data, index)
    local high = ReadByte(data, index)
    local low = ReadByte(data, index + 1)
    if high == nil or low == nil then
        return nil
    end
    return high * 256 + low
end

local function ReadUInt32(data, index)
    local first = ReadByte(data, index)
    local second = ReadByte(data, index + 1)
    local third = ReadByte(data, index + 2)
    local fourth = ReadByte(data, index + 3)
    if first == nil or second == nil or third == nil or fourth == nil then
        return nil
    end
    return ((first * 256 + second) * 256 + third) * 256 + fourth
end

local function IsJpegStartOfFrame(marker)
    return (marker >= 0xC0 and marker <= 0xC3)
        or (marker >= 0xC5 and marker <= 0xC7)
        or (marker >= 0xC9 and marker <= 0xCB)
        or (marker >= 0xCD and marker <= 0xCF)
end

-- Project Zomboid's server Lua APIs do not provide a safe full image decode.
-- Validate the dimensions declared by PNG/JPEG structure instead, then repeat
-- this check after the pending file is materialized before it can be approved.
function AvatarIO.getImageDimensions(data, extension)
    if type(data) ~= "table" or type(extension) ~= "string" then
        return nil
    end

    if extension == "png" then
        if ReadByte(data, 1) ~= 0x89
            or ReadByte(data, 2) ~= 0x50
            or ReadByte(data, 3) ~= 0x4E
            or ReadByte(data, 4) ~= 0x47
            or ReadByte(data, 5) ~= 0x0D
            or ReadByte(data, 6) ~= 0x0A
            or ReadByte(data, 7) ~= 0x1A
            or ReadByte(data, 8) ~= 0x0A
            or ReadUInt32(data, 9) ~= 13
            or ReadByte(data, 13) ~= 0x49
            or ReadByte(data, 14) ~= 0x48
            or ReadByte(data, 15) ~= 0x44
            or ReadByte(data, 16) ~= 0x52
        then
            return nil
        end
        local width = ReadUInt32(data, 17)
        local height = ReadUInt32(data, 21)
        if width == nil or height == nil or width == 0 or height == 0 then
            return nil
        end
        return width, height
    end

    if extension ~= "jpg" and extension ~= "jpeg" then
        return nil
    end
    if ReadByte(data, 1) ~= 0xFF or ReadByte(data, 2) ~= 0xD8 then
        return nil
    end

    local dataLength = #data
    local index = 3
    while index <= dataLength do
        if ReadByte(data, index) ~= 0xFF then
            return nil
        end
        repeat
            index = index + 1
        until index > dataLength or ReadByte(data, index) ~= 0xFF

        local marker = ReadByte(data, index)
        if marker == nil or marker == 0x00 then
            return nil
        end
        if marker == 0xD9 or marker == 0xDA then
            return nil
        end

        if marker == 0xD8 or marker == 0x01 or (marker >= 0xD0 and marker <= 0xD7) then
            index = index + 1
        else
            local segmentLength = ReadUInt16(data, index + 1)
            if segmentLength == nil or segmentLength < 2 or index + segmentLength > dataLength then
                return nil
            end
            if IsJpegStartOfFrame(marker) then
                local height = ReadUInt16(data, index + 4)
                local width = ReadUInt16(data, index + 6)
                if width == nil or height == nil or width == 0 or height == 0 then
                    return nil
                end
                return width, height
            end
            index = index + 1 + segmentLength
        end
    end
    return nil
end

function AvatarIO.hasExpectedDimensions(data, extension)
    local width, height = AvatarIO.getImageDimensions(data, extension)
    return width == AvatarIO.AVATAR_WIDTH and height == AvatarIO.AVATAR_HEIGHT
end

function AvatarIO.getBasePath()
    if isClient() then
        -- a client does not know the server name...
        return "avatars/client/" .. getServerIP() .. "/"
    else
        local serverName = getServerName()
        if serverName == nil then
            serverName = "unknown"
            Logger.error("AvatarIO", 'TRPC error: AvatarIO: unknown server name, using "unknown" directory for avatars')
        end
        return "avatars/server/" .. serverName .. "/"
    end
end

function AvatarIO.getAvatarPath(partialPath)
    local basePath = AvatarIO.getBasePath()
    local pathPrefix = basePath .. "/" .. partialPath .. "."
    local extension = "png"
    local path = pathPrefix .. extension
    if not serverFileExists("../Lua/" .. path) then
        extension = "jpg"
        path = pathPrefix .. extension
        if not serverFileExists("../Lua/" .. path) then
            extension = "jpeg"
            path = pathPrefix .. extension
            if not serverFileExists("../Lua/" .. path) then
                return nil
            end
        end
    end
    return path, extension
end

function AvatarIO.createFileName(username, firstName, lastName)
    return username .. "_" .. firstName .. "_" .. lastName
end

function AvatarIO.createFileNameFromPlayer(player)
    local username = player:getUsername()
    local firstName, lastName = Character.getFirstAndLastName(player)
    return AvatarIO.createFileName(username, firstName, lastName)
end

function AvatarIO.loadPlayerAvatarFromNames(path, username, firstName, lastName)
    local key = AvatarIO.createFileName(username, firstName, lastName)
    local partialPath = path .. "/" .. key
    local fullPath, extension = AvatarIO.getAvatarPath(partialPath)
    if fullPath == nil then
        return
    end
    local data, checksum = File.readAllBytes(fullPath)
    if data == nil or checksum == nil then
        Logger.error("AvatarIO", 'TRPC error: failed to read file at path: "' .. fullPath .. '"')
        return
    end
    return {
        data = data,
        checksum = checksum:tonumber(),
        extension = extension,
        username = username,
        firstName = firstName,
        lastName = lastName,
    }
end

function AvatarIO.loadPlayerAvatar(path, player)
    local username = player:getUsername()
    local firstName, lastName = Character.getFirstAndLastName(player)
    return AvatarIO.loadPlayerAvatarFromNames(path, username, firstName, lastName)
end

function AvatarIO.savePlayerAvatar(username, firstName, lastName, extension, data, path)
    local basePath = AvatarIO.getBasePath()
    local fileName = AvatarIO.createFileName(username, firstName, lastName)
    local fullPath = basePath .. "/" .. path .. "/" .. fileName .. "." .. extension
    File.writeAllBytes(data, fullPath)
    return fullPath
end

return AvatarIO
