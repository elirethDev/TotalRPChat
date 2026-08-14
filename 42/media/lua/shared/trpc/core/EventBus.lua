-- core/EventBus.lua
-- ------------------------------
-- Módulo EventBus del Core TRPC.
-- Desacopla la capa de red (ClientRecv) de la capa de UI (ISChat).
-- Implementa un dispatch por tabla (SIN metatables) para evitar el riesgo de
-- rechazo por parte del sandbox Kahlua: subscribe/emit/unsubscribe sobre una
-- tabla de suscriptores por evento.
--
-- Uso:
--   local EventBus = require("trpc/core/EventBus")
--   EventBus:subscribe("chat:message", function(args) ... end)
--   EventBus:emit("chat:message", args)
--
-- Eventos definidos:
--   chat:message, chat:radio, chat:radio_emitting, chat:discord, chat:typing,
--   chat:error, chat:sandbox_vars, chat:dice_result

local EventBus = {}

-- [evento] = lista de funciones suscriptoras
EventBus._subs = {}

function EventBus.emit(self, event, ...)
    local subs = self._subs[event]
    if subs == nil then
        return
    end
    for _, fn in ipairs(subs) do
        fn(...)
    end
end

function EventBus.subscribe(self, event, fn)
    self._subs[event] = self._subs[event] or {}
    table.insert(self._subs[event], fn)
end

function EventBus.unsubscribe(self, event, fn)
    local subs = self._subs[event]
    if subs == nil then
        return
    end
    for i, existing in ipairs(subs) do
        if existing == fn then
            table.remove(subs, i)
            return
        end
    end
end

return EventBus
