--[[--
The rows of works of the Simple UI home, from the Códice: "Continuar lendo", "Favoritos" and the shelves by category. Each row is a module made
over the `GridRenderer.makeModule` of the Simple UI, as the Collections one is: every cell is a work of the server, not a file of the device.

This file is the factory: `Row.make{ id, name, label, items, caption, caption_lines }` gives a module, where `items(home, max)` picks the cards of the row from the last
home the server sent (`codice/core.lua` has the pure part). That home is kept in a file (`codice/data.lua`): the screen appears at once, with no
network, and updates itself when a new one arrives. The covers come after the screen, a few at a time. Tapping a work opens it (downloading the
file if it is not on the device yet, and asking which when there is more than one).
]]--

local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local ProgressWidget = require("ui/widget/progresswidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Device = require("device")
local Screen = Device.screen

local GridRenderer = require("engines/sui_book_grid")
local SUIStyle = require("features/sui_style")
local UI = require("infra/sui_core")

local core = require("codice/core")
local Data = require("codice/data")
local Covers = require("codice/covers")

local MAX_ITEMS = 5
local COVERS_PER_STEP = 3

local fetching = false
local failed = {} -- covers that could not be had, by file, with when: not tried again for a while
local RETRY_AFTER = 600

--- Draws the screens again, from what is kept now.
local function redraw()
    local SE = package.loaded["engines/sui_screen_engine"]
    if SE and SE.refreshAllLiveImmediate then SE.refreshAllLiveImmediate(false) end
end

--- Fetches the covers that are missing, a few at a time, and draws the screen again after each few, until none is missing.
local function fetchMissing(cards)
    if fetching then return end
    local conn = Data.connection()
    local NetworkMgr = require("ui/network/manager")
    if not conn or not NetworkMgr:isOnline() then return end
    local pending = {}
    for _, card in ipairs(cards) do
        local path = Covers.path(card)
        if path and not Covers.kept(path) and not (failed[path] and os.time() - failed[path] < RETRY_AFTER) then pending[#pending + 1] = card end
    end
    if #pending == 0 then return end
    fetching = true
    local i = 1
    local function step()
        local got = 0
        while pending[i] and got < COVERS_PER_STEP do
            local card = pending[i]
            i = i + 1
            if Covers.fetch(conn, card) then
                got = got + 1
            else
                failed[Covers.path(card)] = os.time()
            end
        end
        if got > 0 then redraw() end
        if pending[i] then
            UIManager:scheduleIn(0.2, step)
        else
            fetching = false
        end
    end
    UIManager:scheduleIn(0.5, step)
end

local function plugin()
    local FM = package.loaded["apps/filemanager/filemanager"]
    local ui = FM and FM.instance
    return (ui and ui[core.MODULE_SLOT]) or (package.loaded["codice/plugin"] or {}).live
end

-- ---------------------------------------------------------------------------
-- the cell
-- ---------------------------------------------------------------------------

local function dims(cw, caption_lines)
    local pad = Screen:scaleBySize(4)
    local w = math.max(10, cw - 2 * pad)
    local h = math.floor(w * 1.5)
    local face = Font:getFace(SUIStyle.FACE_REGULAR, SUIStyle.FS_DETAIL)
    local bold_face = Font:getFace(SUIStyle.FACE_BOLD, SUIStyle.FS_DETAIL)
    local text_h = TextWidget:new{ text = "Ag", face = face }:getSize().h
    local bar_h = Screen:scaleBySize(5)
    local gap = Screen:scaleBySize(4)
    if caption_lines then
        -- only the cover and, under it, the lines of the caption (the title, the author, how much is read)
        return { pad = pad, cover_w = w, cover_h = h, face = face, bold_face = bold_face, text_h = text_h, bar_h = 0, gap = gap,
                 cell_h = h + gap + caption_lines * text_h + gap }
    end
    return { pad = pad, cover_w = w, cover_h = h, face = face, text_h = text_h, bar_h = bar_h, gap = gap,
             cell_h = h + gap + bar_h + gap + text_h + gap }
end

-- the covers already cut to the box, by file and size: drawing again does not read and scale the file again
local crops, crop_order = {}, {}
local MAX_CROPS = 16

--- The cover at `path` filling a box of w x h without distortion, cutting what overflows (the box is always full). Nil when it cannot be done:
--- the caller then draws the cover the plain way.
local function croppedCover(path, w, h)
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

local function coverWidget(d, card)
    local path = Covers.path(card)
    if Covers.kept(path) then
        local bb = croppedCover(path, d.cover_w - 2, d.cover_h - 2)
        local image
        if bb then
            image = ImageWidget:new{ image = bb, image_disposable = false }
        else
            image = CenterContainer:new{ dimen = Geom:new{ w = d.cover_w - 2, h = d.cover_h - 2 },
                ImageWidget:new{ file = path, width = d.cover_w - 2, height = d.cover_h - 2, scale_factor = 0 } }
        end
        return FrameContainer:new{ bordersize = 1, padding = 0, margin = 0, image }
    end
    -- no cover (yet): the stand-in of the Simple UI, with the title, the same one it draws for a book with no cover
    local SH = package.loaded["modules/module_books_shared"]
    if SH and SH.coverPlaceholder then
        local ok, w = pcall(SH.coverPlaceholder, card.title, card.author, d.cover_w, d.cover_h, false)
        if ok and w then return w end
    end
    return FrameContainer:new{ bordersize = 1, padding = 0, margin = 0, width = d.cover_w, height = d.cover_h,
        TextWidget:new{ text = tostring(card.title or "?"), face = d.face, max_width = d.cover_w - 4 } }
end

local function renderCell(by_key, spec, key, cw, cell_h)
    local card = by_key[key]
    if not card then return VerticalSpan:new{ width = cell_h } end
    local d = dims(cw, spec.caption and spec.caption_lines)
    local content
    if spec.caption then
        content = VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ width = 0 },
            coverWidget(d, card),
            VerticalSpan:new{ width = d.gap },
        }
        local lines = spec.caption(card)
        for i = 1, spec.caption_lines do
            local line = lines[i] or {}
            -- every line takes its place, empty or not, so that the covers of a row line up
            content[#content + 1] = UI.makeColoredText{
                text = tostring(line.text or ""), face = line.bold and d.bold_face or d.face,
                fgcolor = line.sub and UI.CLR_TEXT_SUB or nil,
                max_width = d.cover_w, truncate_with_ellipsis = true, alignment = "center",
            }
        end
    else
        local bar
        if (card.percent or 0) > 0 then
            bar = ProgressWidget:new{ width = d.cover_w, height = d.bar_h, percentage = math.min(1, card.percent / 100), margin_h = 0, margin_v = 0 }
        else
            bar = VerticalSpan:new{ width = d.bar_h }
        end
        content = VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ width = 0 },
            coverWidget(d, card),
            VerticalSpan:new{ width = d.gap },
            bar,
            VerticalSpan:new{ width = d.gap },
            UI.makeColoredText{
                text = tostring(card.title or "?"), face = d.face, fgcolor = UI.CLR_TEXT_SUB,
                max_width = d.cover_w, truncate_with_ellipsis = true, alignment = "center",
            },
        }
    end
    local tappable = InputContainer:new{ dimen = Geom:new{ w = cw, h = cell_h }, [1] = content }
    tappable.ges_events = {
        TapCodice = { GestureRange:new{ ges = "tap", range = function() return tappable.dimen end } },
    }
    function tappable:onTapCodice()
        -- an error here would end KOReader: it is shown instead, and the traceback goes to the log
        local ok, err = xpcall(function()
            local p = plugin()
            if p then
                p:chooseAndOpen(card)
            else
                UIManager:show(require("ui/widget/infomessage"):new{ text = "O Códice não está pronto. Tente de novo." })
            end
        end, debug.traceback)
        if not ok then
            require("logger").err("codice: tap on a book failed:", err)
            UIManager:show(require("ui/widget/infomessage"):new{ text = "O Códice não conseguiu abrir a obra.\n\n" .. core.firstLine(err) })
        end
        return true
    end
    return tappable
end

local Row = {}
Row.redraw = redraw
Row.plugin = plugin

--- A module for a row of works. `spec`: id, name (in the list of modules), label (over the row) or label(home) -> string, items(home, max) -> cards.
function Row.make(spec)
    local by_key = {} -- the cards of the last list, by the key the grid keeps them by

    local function listBooks()
        local home = Data.load()
        local cards = spec.items(home, MAX_ITEMS)
        by_key = {}
        local keys = {}
        for _, card in ipairs(cards) do
            by_key[card.key] = card
            keys[#keys + 1] = card.key
        end
        -- later, so that the build that asked is not held up: what is missing comes after the screen is there
        UIManager:scheduleIn(0.3, function()
            Data.refresh(redraw)
            fetchMissing(cards)
        end)
        return keys
    end

    local def = {
        id          = spec.id,
        name        = spec.name,
        label       = spec.label,
        default_on  = false,
        is_book_mod = true,
        max_items   = MAX_ITEMS,
        paged       = false,

        getFileList   = listBooks,
        renderCell    = function(key, cw, cell_h) return renderCell(by_key, spec, key, cw, cell_h) end,
        getCellHeight = function(cw) return dims(cw, spec.caption and spec.caption_lines).cell_h end,

        -- the progress is drawn by the cell itself
        progress_style = { locked = "none" },

        grid         = true,
        default_rows = 1,
        default_cols = 3,
    }
    if spec.label_of then
        def.label_fn = function() return spec.label_of(Data.load()) or spec.label end
    end
    return GridRenderer.makeModule(def)
end

return Row
