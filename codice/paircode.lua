--[[--
The screen that shows the code of a reader that is being connected (DEC-194): what to do on the site, the code big, and two buttons (the QR, and cancel).
The pairing asks the server every few seconds while it is open; `codice/pairing.lua` closes it when the person answers.
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

local PairCode = InputContainer:extend{
    name = "codice_paircode",
    covers_fullscreen = true,
    code = "", -- what the person types on the site
    on_qr = nil,
    on_cancel = nil,
}

local function face(size, bold) return Font:getFace(bold and "tfont" or "cfont", size) end

function PairCode:init()
    local w, h = Screen:getWidth(), Screen:getHeight()
    local margin = Screen:scaleBySize(24)
    local inner = w - 2 * margin
    self.dimen = Geom:new{ x = 0, y = 0, w = w, h = h }
    self.ges_events = { TapPair = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    self.hits = {}
    local content = VerticalGroup:new{ align = "left" }
    local y = 0
    local function add(widget, height)
        content[#content + 1] = widget
        y = y + (height or widget:getSize().h)
    end
    local function row(widget) return HorizontalGroup:new{ HorizontalSpan:new{ width = margin }, widget } end
    add(VerticalSpan:new{ width = Screen:scaleBySize(36) })
    add(row(TextWidget:new{ text = "Conectar ao Códice", face = face(32, true), max_width = inner }))
    add(VerticalSpan:new{ width = Screen:scaleBySize(18) })
    add(row(TextBoxWidget:new{ text = "1. No site do seu Códice, abra Minha conta → Aplicativos → Conectar um leitor.", face = face(21), width = inner }))
    add(VerticalSpan:new{ width = Screen:scaleBySize(10) })
    add(row(TextBoxWidget:new{ text = "2. Digite este código:", face = face(21), width = inner }))
    add(VerticalSpan:new{ width = Screen:scaleBySize(24) })
    -- the code, as big as the line allows
    local size = 80
    local code = TextWidget:new{ text = tostring(self.code), face = face(size, true) }
    while code:getSize().w > inner and size > 30 do
        size = size - 6
        code = TextWidget:new{ text = tostring(self.code), face = face(size, true) }
    end
    add(CenterContainer:new{ dimen = Geom:new{ w = w, h = code:getSize().h + Screen:scaleBySize(20) }, code })
    add(VerticalSpan:new{ width = Screen:scaleBySize(24) })
    add(row(TextBoxWidget:new{ text = "3. Aprove no site. O leitor percebe sozinho e termina a conexão.", face = face(21), width = inner }))
    add(VerticalSpan:new{ width = Screen:scaleBySize(26) })
    add(LineWidget:new{ dimen = Geom:new{ w = w, h = Screen:scaleBySize(1) } })
    add(VerticalSpan:new{ width = Screen:scaleBySize(14) })
    add(row(TextBoxWidget:new{ text = "O código vale 10 minutos. Esperando a aprovação…", face = face(18), width = inner }))
    add(VerticalSpan:new{ width = Screen:scaleBySize(26) })
    local bh = Screen:scaleBySize(56)
    local function button(label, thick, fn)
        local top = y
        add(row(FrameContainer:new{ bordersize = Screen:scaleBySize(thick and 4 or 2), padding = 0, margin = 0, width = inner, height = bh,
            CenterContainer:new{ dimen = Geom:new{ w = inner - 8, h = bh - 8 }, TextWidget:new{ text = label, face = face(20, true), max_width = inner - 24 } } }), bh)
        self.hits[#self.hits + 1] = { x = margin, y = top, w = inner, h = bh, fn = fn }
        add(VerticalSpan:new{ width = Screen:scaleBySize(12) })
    end
    button("Mostrar QR", false, function() if self.on_qr then self.on_qr() end end)
    button("Cancelar", false, function() self:cancel() end)
    if h - y > 0 then add(VerticalSpan:new{ width = h - y }, h - y) end
    self[1] = FrameContainer:new{ background = Blitbuffer.COLOR_WHITE, bordersize = 0, padding = 0, margin = 0, content }
end

function PairCode:cancel()
    if self.cancelled then return end
    self.cancelled = true
    if self.on_cancel then self.on_cancel() end
end

function PairCode:onTapPair(_, ges)
    for _, hit in ipairs(self.hits) do
        local p = ges.pos
        if p.x >= hit.x and p.x < hit.x + hit.w and p.y >= hit.y and p.y < hit.y + hit.h then
            hit.fn()
            return true
        end
    end
    return true
end

function PairCode:onCloseWidget()
    UIManager:setDirty(nil, "full")
end

return PairCode
