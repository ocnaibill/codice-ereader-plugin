--[[--
Home module "Códice: Prateleira 3": the works of the category that is number 3 in the home of the server (the biggest categories come first). The
label over the row is the name of the category.
]]--

local core = require("codice/core")

local N = 3

return require("codice/modules/row").make{
    id       = "codice_shelf3",
    name     = "Códice: Prateleira 3",
    label    = "Prateleira 3",
    label_of = function(home) return core.shelfLabel(home, N) end,
    items    = function(home, max) return core.shelfItems(home, N, max) end,
}
