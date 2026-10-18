--[[--
The base of the Códice modules of the home that are text and not a row of covers (the greeting, the numbers, the note). `Plain.make{ id, name,
enabled_key, build(w, ctx, home) -> widget, height(ctx) -> number }` gives a module for the registry of the Simple UI. The home it draws from is the
last one the server sent, kept in a file (`codice/data.lua`), so the screen appears at once, with no network, and draws itself again when a new
one arrives.

The height is told before the widget is built (the Simple UI lays the page out first), so each module has a fixed number of lines: what is
longer is cut with an ellipsis, never grown.
]]--

local Device = require("device")
local Font = require("ui/font")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local SUIStyle = require("features/sui_style")
local UI = require("infra/sui_core")

local Data = require("codice/data")
local Row = require("codice/modules/row")

local Plain = {}

Plain.PAD = UI.PAD
Plain.PAD2 = UI.PAD2

--- The height of a line of text of this size.
function Plain.lineHeight(size, bold)
    local face = Font:getFace(bold and SUIStyle.FACE_BOLD or SUIStyle.FACE_REGULAR, size)
    return TextWidget:new{ text = "Ag", face = face }:getSize().h
end

--- A line of text, cut with an ellipsis at `max_width`. `sub` makes it the quiet color.
function Plain.text(str, size, opts)
    opts = opts or {}
    local face = Font:getFace(opts.bold and SUIStyle.FACE_BOLD or SUIStyle.FACE_REGULAR, size)
    return UI.makeColoredText{
        text = tostring(str or ""), face = face, bold = false,
        fgcolor = opts.sub and UI.CLR_TEXT_SUB or nil,
        max_width = opts.max_width, truncate_with_ellipsis = true, alignment = opts.alignment or "left",
    }
end

function Plain.scale(n)
    return Screen:scaleBySize(n)
end

--- Draws the screens again, from what is kept now.
Plain.redraw = Row.redraw
Plain.plugin = Row.plugin

function Plain.make(spec)
    local mod = {
        id          = spec.id,
        name        = spec.name,
        label       = nil,
        enabled_key = spec.enabled_key,
        default_on  = false,
        is_book_mod = true,
    }
    function mod.build(w, ctx)
        local home = Data.load()
        -- later, so that the build that asked is not held up: what is new comes after the screen is there
        UIManager:scheduleIn(0.3, function() Data.refresh(Row.redraw) end)
        -- a failure here is logged and leaves the space empty: it must not take the whole home with it
        local ok, widget = pcall(spec.build, w, ctx, home)
        if ok then return widget end
        require("logger").err("codice: module", spec.id, "failed:", widget)
        return VerticalSpan:new{ width = spec.height(ctx) }
    end
    function mod.getHeight(ctx)
        return spec.height(ctx)
    end
    return mod
end

return Plain
