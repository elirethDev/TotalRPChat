-- AvatarStore.lua
-- TRPC shared avatar persistence: single source of truth for the two ModData
-- keys and the record CRUD both AvatarManager layers delegate to.
--
-- The store is stateless and table-only: it never touches File.*, Textures,
-- serverFileExists or filesystem paths. Paths arrive as record fields /
-- arguments and are stored verbatim, preserving the client
-- "{username}/{dir}" vs server "/pending" asymmetry (including the deferred
-- server "/pending" bug, which is a separate change).
--
-- Kahlua-safe (Lua 5.1 syntax only), no pcall.
--
-- require path: require("trpc/shared/utils/AvatarStore")

local AvatarIO = require("trpc/shared/utils/AvatarIO")

local AvatarStore = {}

AvatarStore.KEY_APPROVED = "trpcApprovedAvatars"
AvatarStore.KEY_PENDING = "trpcPendingAvatars"

--- getOrCreate -> mutate -> add dance, encapsulated.
--- @param key string one of AvatarStore.KEY_APPROVED / KEY_PENDING
function AvatarStore.getTable(key)
    return ModData.getOrCreate(key)
end

function AvatarStore.get(key, username, firstName, lastName)
    local avatars = AvatarStore.getTable(key)
    local recordKey = AvatarIO.createFileName(username, firstName, lastName)
    return avatars[recordKey]
end

function AvatarStore.upsert(key, username, firstName, lastName, record)
    local avatars = AvatarStore.getTable(key)
    local recordKey = AvatarIO.createFileName(username, firstName, lastName)
    avatars[recordKey] = record
    ModData.add(key, avatars)
end

function AvatarStore.remove(key, username, firstName, lastName)
    local avatars = AvatarStore.getTable(key)
    local recordKey = AvatarIO.createFileName(username, firstName, lastName)
    avatars[recordKey] = nil
    ModData.add(key, avatars)
end

function AvatarStore.removeMany(key, recordKeys)
    local avatars = AvatarStore.getTable(key)
    for _, recordKey in ipairs(recordKeys) do
        avatars[recordKey] = nil
    end
    ModData.add(key, avatars)
end

--- Pure partition: does NOT write ModData. survivors keeps one entry per
--- avatar whose predicate(key, avatar) is truthy; removed holds its keys.
--- Callers own the predicate and decide what to mutate/remove afterwards.
function AvatarStore.pruneInvalid(avatars, predicate)
    local survivors = {}
    local removed = {}
    for key, avatar in pairs(avatars) do
        if predicate(key, avatar) then
            survivors[#survivors + 1] = {
                key = key,
                avatar = avatar,
            }
        else
            removed[#removed + 1] = key
        end
    end
    return survivors, removed
end

return AvatarStore
