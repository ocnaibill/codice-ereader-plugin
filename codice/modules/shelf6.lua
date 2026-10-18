--[[--
Home module "Códice: Prateleira 6": the works of the category that is number 6 in the home of the server (the biggest categories come first). The
label over the row is the name of the category.
]]--

local core = require("codice/core")

local N = 6

return require("codice/modules/row").make{
    id       = "codice_shelf6",
    name     = "Códice: Prateleira 6",
    label    = "Prateleira 6",
    label_of = function(home) return core.shelfLabel(home, N) end,
    items    = function(home, max) return core.shelfItems(home, N, max) end,
}
