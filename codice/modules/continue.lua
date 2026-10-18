--[[--
Home module "Códice: Continuar lendo": the books the person is reading in the Códice (the server says which and how much is left).
]]--

local core = require("codice/core")

return require("codice/modules/row").make{
    id    = "codice_continue",
    name  = "Códice: Continuar lendo",
    label = "Continuar lendo",
    items = function(home, max) return core.homeItems(home, "continue", max) end,
}
