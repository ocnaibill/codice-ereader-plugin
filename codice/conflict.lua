--[[--
The question that is asked when the place of a book here is not the one the Códice has (DEC-196, on the screen of the reader): the two places one
over the other (who, how long ago, how far, the chapter and the passage), how far apart they are, and two buttons: go to the other place, or stay.
Closing is staying. The text is made in `core.placeQuestion`; this draws it and takes the touch.
]]--

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local Conflict = InputContainer:extend{
    name = "codice_conflict",
    covers_fullscreen = true,
    question = nil, -- the result of core.placeQuestion
    on_go = nil, -- called when the person goes to the other place
    on_stay = nil, -- called when the person stays (and when the screen is closed)
}

local function face(size, bold) return Font:getFace(bold and "tfont" or "cfont", size) end

local function line(text, size, opts)
    opts = opts or {}
    return TextWidget:new{ text = tostring(text or ""), face = face(size, opts.bold), max_width = opts.max_width }
end

--- One of the two places: who and when, how far (big), the chapter and the passage.
local function place(m, p, label)
    local g = VerticalGroup:new{ align = "left" }
    local head = p.who .. (p.when and (" · " .. p.when) or "")
    g[#g + 1] = line(head, 18, { bold = true, max_width = m.inner })
    g[#g + 1] = VerticalSpan:new{ width = m.gap }
    g[#g + 1] = line(p.percent .. "%", 44, { bold = true })
    if p.chapter and p.chapter ~= "" then
        g[#g + 1] = VerticalSpan:new{ width = m.gap }
        g[#g + 1] = TextBoxWidget:new{ text = p.chapter, face = face(19, true), width = m.inner, height = Screen:scaleBySize(26) * 2, height_adjust = true, height_overflow_show_ellipsis = true }
    end
    if p.snippet and p.snippet ~= "" then
        g[#g + 1] = VerticalSpan:new{ width = Screen:scaleBySize(4) }
        g[#g + 1] = TextBoxWidget:new{ text = "“" .. p.snippet .. "”", face = face(17), width = m.inner, height = Screen:scaleBySize(22) * 3, height_adjust = true, height_overflow_show_ellipsis = true }
    end
    return g
end

function Conflict:init()
    local w, h = Screen:getWidth(), Screen:getHeight()
    local m = { w = w, h = h, margin = Screen:scaleBySize(20), gap = Screen:scaleBySize(8) }
    m.inner = w - 2 * m.margin
    self.m = m
    self.dimen = Geom:new{ x = 0, y = 0, w = w, h = h }
    self.ges_events = { TapConflict = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    self.hits = {}
    local q = self.question
    local content = VerticalGroup:new{ align = "left" }
    local y = 0
    local function add(widget, height)
        content[#content + 1] = widget
        y = y + (height or widget:getSize().h)
    end
    local function row(widget) -- with the margin on the left
        return HorizontalGroup:new{ HorizontalSpan:new{ width = m.margin }, widget }
    end
    add(VerticalSpan:new{ width = Screen:scaleBySize(28) })
    add(row(line("Conflito de progresso detectado", 26, { bold = true, max_width = m.inner })))
    add(VerticalSpan:new{ width = m.gap })
    add(row(TextBoxWidget:new{ text = "O lugar deste livro aqui não é o que o Códice guardou. Escolha com qual continuar.", face = face(18), width = m.inner }))
    add(VerticalSpan:new{ width = Screen:scaleBySize(16) })
    add(LineWidget:new{ dimen = Geom:new{ w = w, h = Screen:scaleBySize(1) } })
    add(VerticalSpan:new{ width = Screen:scaleBySize(14) })
    add(row(place(m, q.there)))
    add(VerticalSpan:new{ width = Screen:scaleBySize(14) })
    add(LineWidget:new{ dimen = Geom:new{ w = w, h = Screen:scaleBySize(1) } })
    add(VerticalSpan:new{ width = Screen:scaleBySize(14) })
    add(row(place(m, q.here)))
    add(VerticalSpan:new{ width = Screen:scaleBySize(14) })
    add(LineWidget:new{ dimen = Geom:new{ w = w, h = Screen:scaleBySize(1) } })
    add(VerticalSpan:new{ width = Screen:scaleBySize(10) })
    add(row(line("Divergência: " .. q.gap .. " pontos percentuais", 17, { max_width = m.inner })))
    add(VerticalSpan:new{ width = Screen:scaleBySize(16) })
    -- the two buttons: the one that goes thick (it is the question), the one that stays thin
    local bh = Screen:scaleBySize(56)
    local function button(label, thick, fn)
        local top = y
        add(row(FrameContainer:new{ bordersize = Screen:scaleBySize(thick and 5 or 2), padding = 0, margin = 0, width = m.inner, height = bh,
            CenterContainer:new{ dimen = Geom:new{ w = m.inner - 10, h = bh - 10 }, line(label, 20, { bold = true, max_width = m.inner - 24 }) } }), bh)
        self.hits[#self.hits + 1] = { x = m.margin, y = top, w = m.inner, h = bh, fn = fn }
        add(VerticalSpan:new{ width = m.gap * 2 })
    end
    button(q.go_text, true, function() self:choose(true) end)
    button(q.stay_text, false, function() self:choose(false) end)
    -- all the screen (the white of the container reaches only as far as what is in it)
    if h - y > 0 then add(VerticalSpan:new{ width = h - y }, h - y) end
    self[1] = FrameContainer:new{ background = Blitbuffer.COLOR_WHITE, bordersize = 0, padding = 0, margin = 0, content }
end

function Conflict:choose(go)
    if self.chosen then return end
    self.chosen = true
    UIManager:close(self)
    local fn = go and self.on_go or self.on_stay
    if fn then fn() end
end

function Conflict:onTapConflict(_, ges)
    for _, hit in ipairs(self.hits) do
        local p = ges.pos
        if p.x >= hit.x and p.x < hit.x + hit.w and p.y >= hit.y and p.y < hit.y + hit.h then
            hit.fn()
            return true
        end
    end
    return true
end

function Conflict:onCloseWidget()
    UIManager:setDirty(nil, "full")
end

return Conflict
