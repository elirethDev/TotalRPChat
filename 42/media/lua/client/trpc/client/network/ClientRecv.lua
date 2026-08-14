local Logger = require("trpc/core/Logger")
local AvatarManager = require("trpc/client/AvatarManager")
local Radio = require("trpc/client/Radio")
local EventBus = require("trpc/core/EventBus")

local ClientRecv = {}

ClientRecv["ChatMessage"] = function(args)
    EventBus:emit("chat:message", args)
end

ClientRecv["RadioMessage"] = function(args)
    EventBus:emit("chat:radio", args)
end

ClientRecv["RadioEmittingMessage"] = function(args)
    EventBus:emit("chat:radio_emitting", args)
end

ClientRecv["DiscordMessage"] = function(args)
    EventBus:emit("chat:discord", args)
end

ClientRecv["Typing"] = function(args)
    EventBus:emit("chat:typing", args)
end

ClientRecv["ChatError"] = function(args)
    EventBus:emit("chat:error", args)
end

ClientRecv["ServerPrint"] = function(args)
    Logger.info("ServerPrint", "Server: " .. args.message)
end

ClientRecv["SendSandboxVars"] = function(args)
    EventBus:emit("chat:sandbox_vars", args)
end

ClientRecv["RadioSquareState"] = function(args)
    Radio.SyncSquare(args.turnedOn, args.mute, args.power, args.volume, args.frequency, args.x, args.y, args.z)
end

ClientRecv["RadioInHandState"] = function(args)
    Radio.SyncInHand(args.id, args.turnedOn, args.mute, args.power, args.volume, args.frequency)
end

ClientRecv["ApprovedAvatar"] = function(args)
    local username = args["username"]
    local firstName = args["firstName"]
    local lastName = args["lastName"]
    local extension = args["extension"]
    local checksum = args["checksum"]
    local data = args["data"]

    if type(username) ~= "string" then
        Logger.error("ClientRecv", 'TRPC error: ApprovedAvatar packet does not contain a valid "username"')
        return
    end
    if type(firstName) ~= "string" then
        Logger.error("ClientRecv", 'TRPC error: ApprovedAvatar packet does not contain a valid "firstName"')
        return
    end
    if type(lastName) ~= "string" then
        Logger.error("ClientRecv", 'TRPC error: ApprovedAvatar packet does not contain a valid "lastName"')
        return
    end
    if type(extension) ~= "string" then
        Logger.error("ClientRecv", 'TRPC error: ApprovedAvatar packet does not contain a valid "extension"')
        return
    end
    if type(checksum) ~= "number" then
        Logger.error("ClientRecv", 'TRPC error: ApprovedAvatar packet does not contain a valid "checksum"')
        return
    end
    if type(data) ~= "table" then
        Logger.error("ClientRecv", 'TRPC error: ApprovedAvatar packet does not contain a valid "data"')
        return
    end

    AvatarManager:saveApprovedAvatar(username, firstName, lastName, extension, checksum, data)
end

ClientRecv["PendingAvatar"] = function(args)
    local username = args["username"]
    local firstName = args["firstName"]
    local lastName = args["lastName"]
    local extension = args["extension"]
    local checksum = args["checksum"]
    local data = args["data"]

    if type(username) ~= "string" then
        Logger.error("ClientRecv", 'TRPC error: PendingAvatar packet does not contain a valid "username"')
        return
    end
    if type(firstName) ~= "string" then
        Logger.error("ClientRecv", 'TRPC error: PendingAvatar packet does not contain a valid "firstName"')
        return
    end
    if type(lastName) ~= "string" then
        Logger.error("ClientRecv", 'TRPC error: PendingAvatar packet does not contain a valid "lastName"')
        return
    end
    if type(extension) ~= "string" then
        Logger.error("ClientRecv", 'TRPC error: PendingAvatar packet does not contain a valid "extension"')
        return
    end
    if type(checksum) ~= "number" then
        Logger.error("ClientRecv", 'TRPC error: PendingAvatar packet does not contain a valid "checksum"')
        return
    end
    if type(data) ~= "table" then
        Logger.error("ClientRecv", 'TRPC error: PendingAvatar packet does not contain a valid "data"')
        return
    end

    AvatarManager:savePendingAvatar(username, firstName, lastName, extension, checksum, data)
end

ClientRecv["AvatarProcessed"] = function(args)
    local username = args["username"]
    local firstName = args["firstName"]
    local lastName = args["lastName"]
    local checksum = args["checksum"]

    if type(username) ~= "string" then
        Logger.error("ClientRecv", 'TRPC error: PendingAvatar packet does not contain a valid "username"')
        return
    end
    if type(firstName) ~= "string" then
        Logger.error("ClientRecv", 'TRPC error: PendingAvatar packet does not contain a valid "firstName"')
        return
    end
    if type(lastName) ~= "string" then
        Logger.error("ClientRecv", 'TRPC error: PendingAvatar packet does not contain a valid "lastName"')
        return
    end
    if type(checksum) ~= "number" then
        Logger.error("ClientRecv", 'TRPC error: PendingAvatar packet does not contain a valid "checksum"')
        return
    end
    AvatarManager:removeAvatarPending(username, firstName, lastName, checksum)
end

ClientRecv["RollResult"] = function(args)
    Logger.debug("Network", "RollResult received")
    local username = args["username"]
    local characterName = args["characterName"]
    local diceCount = args["diceCount"]
    local diceType = args["diceType"]
    local addCount = args["addCount"]
    local diceResults = args["diceResults"]
    local finalResult = args["finalResult"]

    if type(username) ~= "string" then
        Logger.error("ClientRecv", 'TRPC error: RollResult packet does not contain a valid "username"')
        return
    end
    if type(characterName) ~= "string" then
        Logger.error("ClientRecv", 'TRPC error: RollResult packet does not contain a valid "characterName"')
        return
    end
    if type(diceCount) ~= "number" then
        Logger.error("ClientRecv", 'TRPC error: RollResult packet does not contain a valid "diceCount"')
        return
    end
    if type(diceType) ~= "number" then
        Logger.error("ClientRecv", 'TRPC error: RollResult packet does not contain a valid "diceType"')
        return
    end
    if addCount ~= nil and type(addCount) ~= "number" then
        Logger.error("ClientRecv", 'TRPC error: RollResult packet does not contain a valid "addCount"')
        return
    end
    if type(diceResults) ~= "table" then
        Logger.error("ClientRecv", 'TRPC error: RollResult packet does not contain a valid "diceResults"')
        return
    end
    if type(finalResult) ~= "number" then
        Logger.error("ClientRecv", 'TRPC error: RollResult packet does not contain a valid "finalResult"')
        return
    end
    EventBus:emit("chat:dice_result", {
        username = username,
        characterName = characterName,
        diceCount = diceCount,
        diceType = diceType,
        addCount = addCount,
        diceResults = diceResults,
        finalResult = finalResult,
    })
end

function OnServerCommand(module, command, args)
    if module == "TRPC" and ClientRecv[command] then
        ClientRecv[command](args)
    end
end

Events.OnServerCommand.Add(OnServerCommand)

return ClientRecv
