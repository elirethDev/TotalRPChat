-- core/Logger.lua
-- ------------------------------
-- Librería reutilizable de logging del Core TRPC.
--
-- AGNÓSTICA del mod: no referencia ISChat ni ninguna feature. Solo usa la
-- API base de PZ (print) que redirige al DebugLog del cliente/server.
--
-- Diseño:
--   - Niveles: ERROR(1) < WARN(2) < INFO(3) < DEBUG(4)
--   - Filtro por nivel mínimo (`minLevel`): DEBUG muestra todo, ERROR solo errores.
--   - Tag por contexto (ej. 'ChatCommands', 'Red', 'Scroll').
--   - Toggle global (`enabled`) para apagarlo en producción sin tocar callers.
--   - Formato estable: [prefijo][nivel][tag] mensaje  ->  grep filtrable.
--
-- Uso:
--   local Logger = require('trpc/core/Logger')
--   Logger.info('ChatCommands', 'commando ejecutado')
--   Logger.debug('Red', 'Enviando paquete %s', tipo)
--
-- La sandbox de Lua de PZ no expone io.*, así que el archivo destino es el
-- DebugLog nativo (console.txt / DebugLog-*.txt vía print). El formato
-- estructurado es lo que permite filtrar con grep sin un archivo aparte.

local Logger = {}

local DateTime = require("trpc/shared/utils/DateTime")
local File = require("trpc/shared/utils/File")

local LEVELS = {
    ERROR = 1,
    WARN = 2,
    INFO = 3,
    DEBUG = 4,
}

Logger.prefix = "TRPC" -- prefijo estable del namespace
Logger.minLevel = "INFO" -- nivel mínimo que se muestra (DEBUG para todo)
Logger.enabled = true -- toggle global en producción

local function levelIndex(level)
    return LEVELS[level] or LEVELS.ERROR
end

local function shouldLog(level)
    if not Logger.enabled then
        return false
    end
    return levelIndex(level) <= levelIndex(Logger.minLevel)
end

local function formatArgs(...)
    local n = select("#", ...)
    if n == 1 then
        return tostring(...)
    end
    local parts = { tostring((...)) }
    for i = 2, n do
        parts[i] = tostring((select(i, ...)))
    end
    return table.concat(parts, " ")
end

local function write(level, tag, message)
    print("[" .. Logger.prefix .. "][" .. level .. "][" .. tostring(tag) .. "] " .. tostring(message))
end

function Logger.log(level, tag, ...)
    if not shouldLog(level) then
        return
    end
    write(level, tag, formatArgs(...))
end

function Logger.error(tag, ...)
    Logger.log("ERROR", tag, ...)
end
function Logger.warn(tag, ...)
    Logger.log("WARN", tag, ...)
end
function Logger.info(tag, ...)
    Logger.log("INFO", tag, ...)
end
function Logger.debug(tag, ...)
    Logger.log("DEBUG", tag, ...)
end

-- ---------------------------------------------------------------------------
-- Chat log persistente (migrado del Logger legacy del autor).
-- Registra cada mensaje del chat a un archivo por fecha y servidor:
--   TRPC/logs/<serverName>/trpc-chat-log-<date>.txt
-- Es auditoría/moderación del server, no logging de consola.
-- ---------------------------------------------------------------------------
local function ChatLogPath()
    local date = DateTime.GetISODate()
    local serverName = getServerName()
    if serverName == nil then
        serverName = "unknown"
        print("[" .. Logger.prefix .. '][WARN][Logger] unknown server name, using "unknown" directory for logs')
    end
    return "TRPC/logs/" .. serverName .. "/trpc-chat-log-" .. date .. ".txt"
end

function Logger.logChat(type, author, characterName, message, radiosFrequenciesList, target)
    if type == nil or author == nil or characterName == nil or message == nil then
        return
    end
    local time = DateTime.GetISOTime()
    local text = time .. " [" .. type .. "] " .. author .. " (" .. characterName .. ")"
    if target ~= nil then
        text = text .. " to " .. target
    end
    local first = true
    for _, radioFrequency in pairs(radiosFrequenciesList) do
        if first then
            text = text .. "["
        else
            text = text .. ", "
        end
        text = text .. string.format("%.2f", radioFrequency / 1000) .. "Hz"
        first = false
    end
    if not first then
        text = text .. "]"
    end
    text = text .. ": " .. message
    File.writeStringWithNewLine(text, ChatLogPath())
end

return Logger
