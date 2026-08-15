-- ui/bubble/BubbleState.lua
-- ------------------------------
-- Módulo de estado de burbujas del Core TRPC.
-- Centraliza todas las burbujas vivas en una sola estructura: 4 tablas para
-- burbujas keyeadas (player, radio, playerRadio, vehicleRadio).
--
-- Uso:
--   local BubbleState = require("trpc/client/ui/bubble/BubbleState")
--   BubbleState.add("player", author, bubble)
--   BubbleState.renderAll()

local BubbleState = {}

local bubbles = {
    player = {}, -- author -> PlayerBubble
    radio = {}, -- "xXyYzZ" -> RadioBubble(square)
    playerRadio = {}, -- author -> RadioBubble(player)
    vehicleRadio = {}, -- keyId -> RadioBubble(vehicle)
}

local dead = {}

--- Add a bubble to the state. If a bubble already exists at (kind, key), marks
--- it as dead first.
-- @param kind string - one of "player", "radio", "playerRadio", "vehicleRadio"
-- @param key string - lookup key for table kinds
-- @param bubble table - the bubble instance
function BubbleState.add(kind, key, bubble)
    if bubbles[kind][key] ~= nil then
        bubbles[kind][key].dead = true
        dead[#dead + 1] = bubbles[kind][key]
    end
    bubbles[kind][key] = bubble
end

--- Convenience: add a player bubble by author key.
function BubbleState.addPlayer(author, bubble)
    BubbleState.add("player", author, bubble)
end

--- Convenience: add a square radio bubble by position key.
function BubbleState.addRadio(key, bubble)
    BubbleState.add("radio", key, bubble)
end

--- Convenience: add a player radio bubble by author key.
function BubbleState.addPlayerRadio(author, bubble)
    BubbleState.add("playerRadio", author, bubble)
end

--- Convenience: add a vehicle radio bubble by keyId.
function BubbleState.addVehicleRadio(keyId, bubble)
    BubbleState.add("vehicleRadio", keyId, bubble)
end

--- Get the internal bubbles table (full state snapshot).
-- @return table with keys {player, radio, playerRadio, vehicleRadio}
function BubbleState.getBubbles()
    return bubbles
end

--- Get and clear the dead bubbles array.
-- @return array of dead bubble instances collected since last call
function BubbleState.getDead()
    local result = dead
    dead = {}
    return result
end

--- Remove a bubble from the state by kind and key. Marks it dead for cleanup.
function BubbleState.remove(kind, key)
    if bubbles[kind][key] ~= nil then
        bubbles[kind][key].dead = true
    end
    bubbles[kind][key] = nil
end

--- Convenience: remove a player bubble by author.
function BubbleState.removePlayer(author)
    BubbleState.remove("player", author)
end

--- Convenience: remove a square radio bubble by position key.
function BubbleState.removeRadio(key)
    BubbleState.remove("radio", key)
end

--- Convenience: remove a player radio bubble by author.
function BubbleState.removePlayerRadio(author)
    BubbleState.remove("playerRadio", author)
end

--- Convenience: remove a vehicle radio bubble by keyId.
function BubbleState.removeVehicleRadio(keyId)
    BubbleState.remove("vehicleRadio", keyId)
end

--- Render all living bubbles and collect dead ones.
-- Iterates the 4 table kinds (player, radio, playerRadio, vehicleRadio) via
-- pairs(). Dead bubbles are removed from the state and collected in the dead
-- array.
function BubbleState.renderAll()
    -- Iterate table kinds: player, radio, playerRadio, vehicleRadio
    for kindKey, kindTable in pairs(bubbles) do
        if type(kindTable) == "table" then
            local indexToDelete = {}
            for key, bubble in pairs(kindTable) do
                if bubble.dead then
                    indexToDelete[#indexToDelete + 1] = key
                    dead[#dead + 1] = bubble
                else
                    bubble:render()
                end
            end
            for _, key in ipairs(indexToDelete) do
                bubbles[kindKey][key] = nil
            end
        end
    end
end

return BubbleState
