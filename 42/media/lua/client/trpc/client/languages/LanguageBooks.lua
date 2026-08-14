local ISReadLanguageBook = require('trpc/client/languages/ISReadLanguageBook')
local LanguageManager    = require('trpc/client/languages/LanguageManager')


ISInventoryMenuElements = ISInventoryMenuElements or {}

function ISInventoryMenuElements.ContextLanguageBooks()
    local self = ISMenuElement.new()
    self.inventoryMenu = ISContextManager.getInstance().getInventoryMenu()

    function self.init()
    end

    function self.createMenu(item)
        local itemFullType = item:getFullType()
        local languageName = itemFullType:match('(%a+)LanguageBook')
        if languageName == nil then
            return
        end

        self.inventoryMenu.context:removeOptionByName(getText('ContextMenu_Read'))
        if languageName == 'Forget' then
            self.inventoryMenu.context:addOption(
                getText("ContextMenu_TRPC_forget_languages"),
                self.inventoryMenu,
                self.registerLanguage,
                item,
                languageName)
        else
            local languageNameTranslated = LanguageManager.GetLanguageTranslated(languageName)
            if languageNameTranslated == nil then
                return
            end
            self.inventoryMenu.context:addOption(
                getText("ContextMenu_TRPC_learn_language", languageNameTranslated),
                self.inventoryMenu,
                self.registerLanguage,
                item,
                languageName)
        end
    end

    function self.registerLanguage(_p, item, languageName)
        ISTimedActionQueue.add(ISReadLanguageBook:new(getPlayer(), item, languageName, 1))
    end

    return self
end
