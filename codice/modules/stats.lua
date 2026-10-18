--[[--
Home module "Códice: Números": "Em andamento" (how many works are being read, and of what) and "Sua atividade" (works finished this month, and the
time spent reading), side by side, as the cards of the top of the home of the web.
]]--

local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local LeftContainer = require("ui/widget/container/leftcontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local SUIStyle = require("features/sui_style")

local core = require("codice/core")
local Plain = require("codice/modules/plain")

local function sizes()
    local gap = Plain.scale(3)
    local label, big, detail = SUIStyle.FS_DETAIL, SUIStyle.FS_TITLE * 2, SUIStyle.FS_DETAIL
    local h = Plain.PAD + Plain.lineHeight(label) + gap + Plain.lineHeight(big, true) + gap + 2 * Plain.lineHeight(detail) + Plain.PAD2
    return { gap = gap, label = label, big = big, detail = detail, h = h }
end

return Plain.make{
    id          = "codice_stats",
    name        = "Códice: Em andamento e atividade",
    enabled_key = "codice_stats_enabled",

    height = function() return sizes().h end,

    build = function(w, _ctx, home)
        local z = sizes()
        local cards = core.statsCards(home) or {
            reading = { count = "–", detail = "" },
            activity = { completed = "–", time = "–", detail = "" },
        }
        local col_w = math.floor(w / 2)
        local text_w = col_w - 2 * Plain.PAD
        local function column(label, big, line1, line2)
            return LeftContainer:new{ dimen = Geom:new{ w = col_w, h = z.h }, VerticalGroup:new{
                align = "left",
                VerticalSpan:new{ width = Plain.PAD },
                Plain.text(label, z.label, { sub = true, max_width = text_w }),
                VerticalSpan:new{ width = z.gap },
                Plain.text(big, z.big, { bold = true, max_width = text_w }),
                VerticalSpan:new{ width = z.gap },
                Plain.text(line1, z.detail, { sub = true, max_width = text_w }),
                Plain.text(line2, z.detail, { sub = true, max_width = text_w }),
            } }
        end
        local reading = cards.reading
        local activity = cards.activity
        return HorizontalGroup:new{
            align = "top",
            column("Em andamento", reading.count, reading.detail ~= "" and reading.detail or "Uma nova leitura espera", ""),
            column("Sua atividade", activity.completed, "obras completas neste mês", activity.time .. " de leitura, no total"),
        }
    end,
}
