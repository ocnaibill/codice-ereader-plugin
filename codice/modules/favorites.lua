--[[--
Home module "Códice: Favoritos": the works the person marked in the Códice.
]]--

local core = require("codice/core")

return require("codice/modules/row").make{
    id    = "codice_favorites",
    name  = "Códice: Favoritos",
    label = "Favoritos",
    items = function(home, max) return core.homeItems(home, "favorites", max) end,
}
