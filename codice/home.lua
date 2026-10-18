--[[--
The home of the Códice on a reader: the same order as the home of the web (greeting and numbers, what to continue, favorites, a few
passages, the library as shelves), in one column that is scrolled (a swipe goes a screen at a time and lands on the start of a row), with a
menu where the web has the side bar. The data is one answer of the server (GET /device/home). The covers come in after the screen is
drawn, a few at a time, so that the home is there at once.
]]--

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local NetworkMgr = require("ui/network/manager")
local ProgressWidget = require("ui/widget/progresswidget")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local lfs = require("libs/libkoreader-lfs")
local ltn12 = require("ltn12")
local Screen = Device.screen

local core = require("codice/core")
local api = require("codice/http")

local PER_LINE = 3
local SHELF_LIMIT = 6 -- works of a shelf drawn here (two lines); the rest is in the catalog
local COVERS_PER_STEP = 3 -- covers fetched before the screen is drawn again

local Home = InputContainer:extend{
    plugin = nil, -- the plugin: it holds the connection and opens books
    data = nil, -- the answer of GET /device/home
}

-- ---------------------------------------------------------------- measures

local function measures()
    local s = Screen
    local width, height = s:getWidth(), s:getHeight()
    local m = {
        w = width, h = height,
        margin = s:scaleBySize(14),
        gap = s:scaleBySize(10),
        top = s:scaleBySize(54),
    }
    m.avail = height - m.top
    -- the scroll bar takes room on the right when there is more than a screen
    m.content_w = width - 2 * m.margin - ScrollableContainer:getScrollbarWidth()
    m.card_w = math.floor((m.content_w - (PER_LINE - 1) * m.gap) / PER_LINE)
    m.cover_h = math.floor(m.card_w * 1.5)
    m.title_h = s:scaleBySize(42)
    m.header_h = s:scaleBySize(40)
    return m
end

-- ---------------------------------------------------------------- the covers

local function coverDir()
    local dir = DataStorage:getDataDir() .. "/cache/codice"
    lfs.mkdir(DataStorage:getDataDir() .. "/cache")
    lfs.mkdir(dir)
    return dir
end

local function coverPath(card)
    local cover = card.cover
    if not cover or cover == "" or cover:find("%.svg") then return nil end
    return coverDir() .. "/" .. core.coverCacheName(cover)
end

local function kept(path)
    return path and lfs.attributes(path, "mode") == "file" and (lfs.attributes(path, "size") or 0) > 0
end

--- Fetches the cover of a card when it is not kept yet; returns its file, or nil when there is none or it cannot be had.
local function fetchCover(plugin, card)
    local path = coverPath(card)
    if not path then return nil end
    if kept(path) then return path end
    local c = plugin:connection()
    if not c then return nil end
    local handle = io.open(path, "wb")
    if not handle then return nil end
    local url = c.url .. card.cover .. (card.cover:find("?", 1, true) and "&" or "?") .. "w=240"
    local code = api.request(url, { user = c.username, password = c.token, sink = ltn12.sink.file(handle) })
    if code ~= 200 then
        os.remove(path)
        return nil
    end
    return path
end

local function coverImage(m, file)
    return CenterContainer:new{
        dimen = Geom:new{ w = m.card_w - 2, h = m.cover_h - 2 },
        ImageWidget:new{ file = file, width = m.card_w - 2, height = m.cover_h - 2, scale_factor = 0 },
    }
end

local function coverPlaceholder(m, card)
    local pad = Screen:scaleBySize(6)
    return TextBoxWidget:new{ text = card.title or "?", face = Font:getFace("cfont", 16), width = m.card_w - 2 * pad - 2 }
end

-- ---------------------------------------------------------------- pieces

--- One card: the cover (or its title while the cover is not there), how far the person is, and the title. `holders` gets the boxes whose
--- cover is still to come.
local function cardWidget(m, card, holders)
    local file = coverPath(card)
    local box = FrameContainer:new{
        bordersize = 1, padding = 0, margin = 0, width = m.card_w, height = m.cover_h,
        kept(file) and coverImage(m, file) or coverPlaceholder(m, card),
    }
    if not kept(file) and file then holders[#holders + 1] = { box = box, card = card } end
    local progress
    if (card.percent or 0) > 0 then
        progress = ProgressWidget:new{ width = m.card_w, height = Screen:scaleBySize(6), percentage = math.min(1, card.percent / 100), margin_h = 0, margin_v = 0 }
    else
        progress = VerticalSpan:new{ width = Screen:scaleBySize(6) }
    end
    return VerticalGroup:new{
        align = "left",
        box,
        VerticalSpan:new{ width = Screen:scaleBySize(4) },
        progress,
        VerticalSpan:new{ width = Screen:scaleBySize(4) },
        FrameContainer:new{ -- a box of the exact height, so that every row has the same
            bordersize = 0, padding = 0, margin = 0, width = m.card_w, height = m.title_h,
            TextBoxWidget:new{
                text = card.title or "?", face = Font:getFace("cfont", 15), width = m.card_w,
                height = m.title_h, height_adjust = true, height_overflow_show_ellipsis = true,
            },
        },
    }
end

--- The title of a section and a rule under it, exactly `m.header_h` high.
local function header(m, text)
    local title = TextWidget:new{ text = text, face = Font:getFace("tfont", 20), max_width = m.content_w }
    local rule = Screen:scaleBySize(1)
    local pad = math.max(0, m.header_h - title:getSize().h - Screen:scaleBySize(4) - rule)
    return VerticalGroup:new{
        align = "left",
        title,
        VerticalSpan:new{ width = Screen:scaleBySize(4) },
        LineWidget:new{ dimen = Geom:new{ w = m.content_w, h = rule } },
        VerticalSpan:new{ width = pad },
    }
end

--- The whole column. Returns the widget, the places that can be tapped (in the coordinates of the column), the rows a swipe may land on,
--- and the boxes waiting for a cover.
local function column(m, data)
    local content = VerticalGroup:new{ align = "left" }
    local taps, grid, holders = {}, {}, {}
    local y = 0
    local function push(widget, row)
        local top = y
        content[#content + 1] = widget
        y = y + widget:getSize().h
        if row then grid[#grid + 1] = { top = top, bottom = y - 1 } end
        return top
    end
    local function space(h) push(VerticalSpan:new{ width = h }) end

    for _, section in ipairs(core.homeSections(data)) do
        if section.kind == "greeting" then
            local bits = {}
            local st = section.stats
            if type(st) == "table" then
                if (st.inProgressCount or 0) > 0 then bits[#bits + 1] = st.inProgressCount .. " em andamento" end
                if (st.completedThisMonth or 0) > 0 then bits[#bits + 1] = st.completedThisMonth .. " lidos neste mês" end
                if (st.worksTotal or 0) > 0 then bits[#bits + 1] = st.worksTotal .. " obras" end
            end
            push(VerticalGroup:new{
                align = "left",
                TextWidget:new{ text = section.name and ("Olá, " .. section.name) or "Olá", face = Font:getFace("tfont", 28), max_width = m.content_w },
                VerticalSpan:new{ width = Screen:scaleBySize(4) },
                TextBoxWidget:new{ text = table.concat(bits, "  ·  "), face = Font:getFace("cfont", 16), width = m.content_w },
            }, true)
            space(m.gap)
        elseif section.kind == "row" then
            push(header(m, section.title), true)
            for _, line in ipairs(core.lines(section.cards, PER_LINE, SHELF_LIMIT)) do
                local row = HorizontalGroup:new{ align = "top" }
                for ci, card in ipairs(line) do
                    if ci > 1 then row[#row + 1] = HorizontalSpan:new{ width = m.gap } end
                    row[#row + 1] = cardWidget(m, card, holders)
                end
                local top = push(row, true)
                for ci, card in ipairs(line) do
                    taps[#taps + 1] = { x = (ci - 1) * (m.card_w + m.gap), y = top, w = m.card_w, h = row:getSize().h, card = card }
                end
                space(m.gap)
            end
        elseif section.kind == "quotes" then
            push(header(m, section.title), true)
            for _, note in ipairs(section.notes) do
                push(TextBoxWidget:new{ text = "“" .. note.text .. "”", face = Font:getFace("cfont", 16), width = m.content_w }, true)
                push(TextBoxWidget:new{ text = "— " .. (note.title or "") .. ((note.author and note.author ~= "") and (", " .. note.author) or ""),
                    face = Font:getFace("cfont", 14), width = m.content_w })
                space(m.gap)
            end
        end
    end
    space(m.gap * 2)
    return HorizontalGroup:new{ HorizontalSpan:new{ width = m.margin }, content }, taps, grid, holders
end

-- ---------------------------------------------------------------- the widget

function Home:init()
    self.m = measures()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.m.w, h = self.m.h }
    self.ges_events = { TapHome = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    self.plugin.home_open = self
    self:setData(self.data)
end

--- New data from the server: the column is built again, from the top.
function Home:setData(data)
    self.data = data
    self.generation = (self.generation or 0) + 1
    local m = self.m
    local body, taps, grid, holders = column(m, data)
    self.taps, self.holders = taps, holders

    local title = TextWidget:new{ text = "Códice", face = Font:getFace("tfont", 26) }
    local menu = TextWidget:new{ text = "Menu", face = Font:getFace("cfont", 20) }
    local top = HorizontalGroup:new{
        align = "center",
        HorizontalSpan:new{ width = m.margin },
        title,
        HorizontalSpan:new{ width = m.w - 2 * m.margin - title:getSize().w - menu:getSize().w },
        menu,
    }
    self.menu_x = m.w - m.margin - menu:getSize().w - m.gap

    self.scroller = ScrollableContainer:new{
        dimen = Geom:new{ w = m.w, h = m.avail },
        show_parent = self,
        step_scroll_grid = grid,
        body,
    }
    self.cropping_widget = self.scroller
    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE, bordersize = 0, padding = 0, margin = 0, width = m.w, height = m.h,
        VerticalGroup:new{
            align = "left",
            CenterContainer:new{ dimen = Geom:new{ w = m.w, h = m.top }, top },
            self.scroller,
        },
    }
    UIManager:setDirty(self, function() return "ui", self.dimen end)
    self:loadCovers()
end

--- Fetches the covers that are missing, a few at a time, and puts each in its box.
function Home:loadCovers()
    local generation, i = self.generation, 1
    local holders = self.holders
    local function step()
        if self.closed or generation ~= self.generation or not holders[i] then return end
        if not NetworkMgr:isOnline() then return end -- offline: the titles stay where the covers would be
        local fetched = 0
        while holders[i] and fetched < COVERS_PER_STEP do
            local h = holders[i]
            i = i + 1
            local file = fetchCover(self.plugin, h.card)
            if file then
                if h.box[1] and h.box[1].free then h.box[1]:free() end
                h.box[1] = coverImage(self.m, file)
                fetched = fetched + 1
            end
        end
        if fetched > 0 then UIManager:setDirty(self, function() return "ui", self.dimen end) end
        UIManager:scheduleIn(0.1, step)
    end
    UIManager:scheduleIn(0.3, step)
end

function Home:onTapHome(_, ges)
    local m = self.m
    local x, y = ges.pos.x, ges.pos.y
    if y < m.top then
        if x >= self.menu_x then self:openMenu() end
        return true
    end
    local offset = self.scroller:getScrolledOffset()
    local cx, cy = x - m.margin, y - m.top + offset.y
    for _, t in ipairs(self.taps) do
        if cx >= t.x and cx < t.x + t.w and cy >= t.y and cy < t.y + t.h then
            self:openCard(t.card)
            return true
        end
    end
    return true
end

function Home:openCard(card)
    local dialog
    local bits = { card.title or "?" }
    if card.author and card.author ~= "" then bits[#bits + 1] = card.author end
    if (card.percent or 0) > 0 then bits[#bits + 1] = string.format("%d%% lido", math.floor(card.percent + 0.5)) end
    dialog = ButtonDialog:new{
        title = table.concat(bits, "\n"),
        title_align = "center",
        buttons = {{
            { text = "Fechar", callback = function() UIManager:close(dialog) end },
            {
                text = (card.percent or 0) > 0 and not card.completed and "Continuar" or "Ler",
                callback = function()
                    UIManager:close(dialog)
                    self.plugin:chooseAndOpen(card, function() UIManager:close(self) end)
                end,
            },
        }},
    }
    UIManager:show(dialog)
end

function Home:openMenu()
    local dialog
    local function item(text, fn)
        return { { text = text, callback = function() UIManager:close(dialog); fn() end } }
    end
    local autostart = self.plugin:autostart()
    dialog = ButtonDialog:new{
        title = "Códice",
        title_align = "center",
        buttons = {
            item("Atualizar esta tela", function() self.plugin:showHome(self) end),
            item("Catálogo completo (OPDS)", function()
                UIManager:close(self)
                if self.plugin.ui.opds then self.plugin.ui.opds:onShowOPDSCatalog() end
            end),
            item("Arquivos do KOReader", function() UIManager:close(self) end),
            item(autostart and "Não abrir o Códice ao iniciar" or "Abrir o Códice ao iniciar", function() self.plugin:setAutostart(not autostart) end),
            item("Atualizar a configuração", function() self.plugin:syncConfig(false) end),
            item("Procurar atualização do plugin", function() self.plugin:checkUpdate(false) end),
        },
    }
    UIManager:show(dialog)
end

function Home:onCloseWidget()
    self.closed = true
    if self.plugin.home_open == self then self.plugin.home_open = nil end
    UIManager:setDirty(nil, "full")
end

return Home
