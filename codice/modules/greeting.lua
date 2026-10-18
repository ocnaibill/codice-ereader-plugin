--[[--
Home module "Códice: Saudação": the date and the time, the greeting with the name of the person, and the question, as the top of the home of the web.
]]--

local Geom = require("ui/geometry")
local LeftContainer = require("ui/widget/container/leftcontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local SUIStyle = require("features/sui_style")

local core = require("codice/core")
local Plain = require("codice/modules/plain")

local function sizes()
    local gap = Plain.scale(4)
    local eyebrow, head, ask = SUIStyle.FS_DETAIL, SUIStyle.FS_TITLE * 2, SUIStyle.FS_BODY
    local h = Plain.PAD + Plain.lineHeight(eyebrow) + gap + Plain.lineHeight(head, true) + gap + Plain.lineHeight(ask) + Plain.PAD2
    return { gap = gap, eyebrow = eyebrow, head = head, ask = ask, h = h }
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
        local group = VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = Plain.PAD },
            Plain.text(core.dateLabel(now) .. ". " .. core.timeLabel(now), z.eyebrow, { sub = true, max_width = width }),
            VerticalSpan:new{ width = z.gap },
            Plain.text(core.greeting(now.hour, name), z.head, { bold = true, max_width = width }),
            VerticalSpan:new{ width = z.gap },
            Plain.text("O que queremos hoje?", z.ask, { sub = true, max_width = width }),
            VerticalSpan:new{ width = Plain.PAD2 },
        }
        return LeftContainer:new{ dimen = Geom:new{ w = w, h = z.h }, group }
    end,
}
