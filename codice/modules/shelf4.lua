--[[--
Home module "Códice: Prateleira 4": the works of the category that is number 4 in the home of the server (the biggest categories come first). The
label over the row is the name of the category.
]]--

local core = require("codice/core")

local N = 4

return require("codice/modules/row").make{
    id       = "codice_shelf4",
    name     = "Códice: Prateleira 4",
    label    = "Prateleira 4",
    label_of = function(home) return core.shelfLabel(home, N) end,
    items    = function(home, max) return core.shelfItems(home, N, max) end,
}
