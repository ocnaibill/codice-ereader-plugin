--[[--
Home module "Códice: Saudação": the greeting with the name of the person and the question, as the top of the home of the web. The time is in the
bar of KOReader, so only the day is here, at the end of the line of the question.
]]--

local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local SUIStyle = require("features/sui_style")

local core = require("codice/core")
local Plain = require("codice/modules/plain")

local function sizes()
    local gap = Plain.scale(2)
    local head, ask = math.floor(SUIStyle.FS_TITLE * 1.5), SUIStyle.FS_DETAIL
    local h = Plain.PAD2 + Plain.lineHeight(head, true) + gap + Plain.lineHeight(ask) + Plain.PAD2
    return { gap = gap, head = head, ask = ask, h = h }
end

return Plain.make{
    id          = "codice_greeting",
    name        = "Códice: Saudação",
    enabled_key = "codice_greeting_enabled",

    height = function() return sizes().h end,

    build = function(w, _ctx, home)
        local z = sizes()
        local now = os.date("*t", os.time())
        local width = w - 2 * Plain.PAD
        local name = type(home.user) == "table" and home.user.name or nil
        local day = Plain.text(core.dayLabel(now), z.ask, { sub = true, max_width = math.floor(width / 2) })
        local question = Plain.text("O que queremos hoje?", z.ask, { sub = true, max_width = width - day:getSize().w })
        local gap_w = math.max(0, width - question:getSize().w - day:getSize().w)
        local group = VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = Plain.PAD2 },
            Plain.text(core.greeting(now.hour, name), z.head, { bold = true, max_width = width }),
            VerticalSpan:new{ width = z.gap },
            HorizontalGroup:new{ align = "center", question, HorizontalSpan:new{ width = gap_w }, day },
            VerticalSpan:new{ width = Plain.PAD2 },
        }
        return LeftContainer:new{ dimen = Geom:new{ w = w, h = z.h }, group }
    end,
}
