--[[--
Home module "Códice: Prateleira 5": the works of the category that is number 5 in the home of the server (the biggest categories come first). The
label over the row is the name of the category.
]]--

local core = require("codice/core")

local N = 5

return require("codice/modules/row").make{
    id       = "codice_shelf5",
    name     = "Códice: Prateleira 5",
    label    = "Prateleira 5",
    label_of = function(home) return core.shelfLabel(home, N) end,
    items    = function(home, max) return core.shelfItems(home, N, max) end,
}
