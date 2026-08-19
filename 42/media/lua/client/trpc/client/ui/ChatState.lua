-- ui/ChatState.lua
-- ------------------------------
-- Módulo ChatState del Core TRPC.
-- Estado mutable del chat de cliente, extraído de ISChat.instance.
-- Centraliza el estado de pestañas, burbujas, puntos de "escribiendo...",
-- pestaña activa y foco, con getters/setters para permitir la inyección de
-- dependencias vía require() en lugar de acoplarse al singleton ISChat.
--
-- Uso:
--   local ChatState = require("trpc/client/ui/ChatState")
--   ChatState.setCurrentTabID(1)
--   local id = ChatState.getCurrentTabID()
--
--   -- Bubble access:
--   ChatState.getBubbles():renderAll()
--   ChatState.addBubble("player", author, myBubble)

local BubbleState = require("trpc/client/ui/bubble/BubbleState")
local MessageStore = require("trpc/client/chat/MessageStore")
local ChatState = {}

local state = {
    tabs = {},
    bubbles = BubbleState,
    messageStore = MessageStore.new(),
    typingDots = {},
    currentTabID = 0,
    focused = false,
}

function ChatState.getTabs()
    return state.tabs
end

function ChatState.setTabs(value)
    state.tabs = value
end

function ChatState.getMessageStore()
    return state.messageStore
end

function ChatState.setMessageStore(value)
    state.messageStore = value
end

function ChatState.resetMessageStore()
    state.messageStore:reset()
end

function ChatState.getBubbles()
    return state.bubbles
end

-- Delegation: convenience to add a bubble directly via ChatState
function ChatState.addBubble(kind, key, bubble)
    BubbleState.add(kind, key, bubble)
end

-- setBubbles retained for backward compatibility but reads BubbleState
function ChatState.setBubbles(value)
    state.bubbles = value
end

function ChatState.getTypingDots()
    return state.typingDots
end

function ChatState.setTypingDots(value)
    state.typingDots = value
end

function ChatState.getCurrentTabID()
    return state.currentTabID
end

function ChatState.setCurrentTabID(value)
    state.currentTabID = value
end

function ChatState.isFocused()
    return state.focused
end

function ChatState.setFocused(value)
    state.focused = value
end

return ChatState
