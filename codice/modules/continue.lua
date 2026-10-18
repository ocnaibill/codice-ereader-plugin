--[[--
Home module "Códice: Continuar lendo": the books the person is reading in the Códice (the server says which and how much is left).
]]--

local core = require("codice/core")

return require("codice/modules/row").make{
    id    = "codice_continue",
    name  = "Códice: Continuar lendo",
    label = "Continuar lendo",
    items = function(home, max) return core.homeItems(home, "continue", max) end,
    -- the cover and, under it, one below the other: the title, the author and how much is read
    caption_lines = 3,
    caption = function(card)
        return {
            { text = card.title or "?", bold = true },
            { text = card.author or "", sub = true },
            { text = core.readLabel(card.percent), sub = true },
        }
    end,
}
