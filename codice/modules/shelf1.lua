--[[--
Home module "Códice: Prateleira 1": the works of the category that is number 1 in the home of the server (the biggest categories come first). The
label over the row is the name of the category.
]]--

local core = require("codice/core")

local N = 1

return require("codice/modules/row").make{
    id       = "codice_shelf1",
    name     = "Códice: Prateleira 1",
    label    = "Prateleira 1",
    label_of = function(home) return core.shelfLabel(home, N) end,
    items    = function(home, max) return core.shelfItems(home, N, max) end,
}
