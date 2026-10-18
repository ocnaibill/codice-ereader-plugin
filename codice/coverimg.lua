--[[--
A cover as a widget that fills its box (the 2:3 of a book) without distorting the image: scaled until it covers the box and cut at the edges, as
the web does (object-fit: cover). Done once per file and size, kept for a while: drawing a screen again does not read and scale the file again.
]]--

local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local ImageWidget = require("ui/widget/imagewidget")

local core = require("codice/core")

local Coverimg = {}

local crops, crop_order = {}, {}
local MAX_CROPS = 24

--- The cover at `path` cut to w x h as a blit buffer, or nil when it cannot be done (the caller draws it the plain way).
local function cropped(path, w, h)
    local key = path .. "|" .. w .. "x" .. h
    if crops[key] then return crops[key] end
    local ok, bb = pcall(function()
        local RenderImage = require("ui/renderimage")
        local Blitbuffer = require("ffi/blitbuffer")
        local src = RenderImage:renderImageFile(path, false)
        if not src then return nil end
        local crop = core.coverCrop(src:getWidth(), src:getHeight(), w, h)
        local scaled = RenderImage:scaleBlitBuffer(src, crop.w, crop.h, true)
        local out = Blitbuffer.new(w, h, scaled:getType())
        out:blitFrom(scaled, 0, 0, crop.x, crop.y, w, h)
        if scaled ~= src then scaled:free() end
        return out
    end)
    if not ok or not bb then
        if not ok then require("logger").warn("codice: cutting a cover failed:", bb) end
        return nil
    end
    crops[key] = bb
    crop_order[#crop_order + 1] = key
    if #crop_order > MAX_CROPS then
        local old = table.remove(crop_order, 1)
        if crops[old] then crops[old]:free(); crops[old] = nil end
    end
    return bb
end

--- A framed cover of exactly `w` x `h` (the frame is one pixel), from the file at `path`.
function Coverimg.widget(path, w, h)
    local bb = cropped(path, w - 2, h - 2)
    local image
    if bb then
        image = ImageWidget:new{ image = bb, image_disposable = false }
    else
        image = CenterContainer:new{ dimen = Geom:new{ w = w - 2, h = h - 2 },
            ImageWidget:new{ file = path, width = w - 2, height = h - 2, scale_factor = 0 } }
    end
    return FrameContainer:new{ bordersize = 1, padding = 0, margin = 0, image }
end

return Coverimg
