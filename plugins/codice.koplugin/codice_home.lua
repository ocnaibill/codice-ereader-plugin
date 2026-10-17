--[[--
The home of the Códice on a reader: the same order as the home of the web (greeting and numbers, what to continue, favorites, a few
passages, the library as shelves), in pages, with covers, and a menu where the web has the side bar. The data is one answer of the
server (GET /device/home); the covers are fetched for the page that is shown.
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
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local ProgressWidget = require("ui/widget/progresswidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local lfs = require("libs/libkoreader-lfs")
local ltn12 = require("ltn12")
local Screen = Device.screen

local core = require("codice_core")
local api = require("codice_http")

local PER_LINE = 3
local SHELF_LIMIT = 6 -- works of a shelf drawn here (two lines); the rest is in the catalog

local Home = InputContainer:extend{
    plugin = nil, -- the plugin: it holds the connection and opens books
    data = nil, -- the answer of GET /device/home
    page = 1,
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
        foot = s:scaleBySize(46),
    }
    m.content_w = width - 2 * m.margin
    m.card_w = math.floor((m.content_w - (PER_LINE - 1) * m.gap) / PER_LINE)
    m.cover_h = math.floor(m.card_w * 1.5)
    m.title_h = s:scaleBySize(42)
    m.card_h = m.cover_h + s:scaleBySize(6) + s:scaleBySize(8) + m.title_h + m.gap
    m.header_h = s:scaleBySize(40)
    m.avail = height - m.top - m.foot
    return m
end

-- ---------------------------------------------------------------- the covers

local function coverDir()
    local dir = DataStorage:getDataDir() .. "/cache/codice"
    lfs.mkdir(DataStorage:getDataDir() .. "/cache")
    lfs.mkdir(dir)
    return dir
end

--- The file of the cover of a card, fetched if it is not kept yet; nil when there is none or it cannot be had.
local function coverFile(plugin, card)
    local cover = card.cover
    if not cover or cover == "" or cover:find("%.svg") then return nil end
    local path = coverDir() .. "/" .. core.coverCacheName(cover)
    if lfs.attributes(path, "mode") == "file" and lfs.attributes(path, "size") > 0 then return path end
    local c = plugin:connection()
    if not c then return nil end
    local handle = io.open(path, "wb")
    if not handle then return nil end
    local url = c.url .. cover .. (cover:find("?", 1, true) and "&" or "?") .. "w=240"
    local code = api.request(url, { user = c.username, password = c.token, sink = ltn12.sink.file(handle) })
    if code ~= 200 then
        os.remove(path)
        return nil
    end
    return path
end

-- ---------------------------------------------------------------- blocks

--- One card: the cover (or a frame with the title), how far the person is, and the title.
local function cardWidget(m, plugin, card)
    local file = coverFile(plugin, card)
    local cover
    if file then
        cover = FrameContainer:new{
            bordersize = 1, padding = 0, margin = 0,
            CenterContainer:new{ dimen = Geom:new{ w = m.card_w - 2, h = m.cover_h - 2 },
                ImageWidget:new{ file = file, width = m.card_w - 2, height = m.cover_h - 2, scale_factor = 0 } },
        }
    else
        cover = FrameContainer:new{
            bordersize = 1, padding = Screen:scaleBySize(6), margin = 0, width = m.card_w, height = m.cover_h,
            TextBoxWidget:new{ text = card.title or "?", face = Font:getFace("cfont", 16), width = m.card_w - 2 * Screen:scaleBySize(6) - 2 },
        }
    end
    local progress
    if (card.percent or 0) > 0 then
        progress = ProgressWidget:new{ width = m.card_w, height = Screen:scaleBySize(6), percentage = math.min(1, card.percent / 100), margin_h = 0, margin_v = 0 }
    else
        progress = VerticalSpan:new{ width = Screen:scaleBySize(6) }
    end
    return VerticalGroup:new{
        align = "left",
        cover,
        VerticalSpan:new{ width = Screen:scaleBySize(4) },
        progress,
        VerticalSpan:new{ width = Screen:scaleBySize(4) },
        FrameContainer:new{ -- a box of the exact height, so that the rows have the height the pages were laid out with
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

--- The blocks of the home, each with its height and how to draw it. `build()` returns the widget and the places that can be tapped,
--- relative to the block.
local function blocksOf(m, plugin, data)
    local blocks = {}
    for _, section in ipairs(core.homeSections(data)) do
        if section.kind == "greeting" then
            blocks[#blocks + 1] = {
                h = Screen:scaleBySize(88),
                build = function()
                    local bits = {}
                    local st = section.stats
                    if type(st) == "table" then
                        if (st.inProgressCount or 0) > 0 then bits[#bits + 1] = st.inProgressCount .. " em andamento" end
                        if (st.completedThisMonth or 0) > 0 then bits[#bits + 1] = st.completedThisMonth .. " lidos neste mês" end
                        if (st.worksTotal or 0) > 0 then bits[#bits + 1] = st.worksTotal .. " obras" end
                    end
                    return VerticalGroup:new{
                        align = "left",
                        TextWidget:new{ text = section.name and ("Olá, " .. section.name) or "Olá", face = Font:getFace("tfont", 28), max_width = m.content_w },
                        VerticalSpan:new{ width = Screen:scaleBySize(6) },
                        TextBoxWidget:new{ text = table.concat(bits, "  ·  "), face = Font:getFace("cfont", 16), width = m.content_w },
                    }, {}
                end,
            }
        elseif section.kind == "row" then
            local lines = core.lines(section.cards, PER_LINE, SHELF_LIMIT)
            blocks[#blocks + 1] = {
                h = m.header_h + #lines * m.card_h,
                build = function()
                    local group = VerticalGroup:new{ align = "left" }
                    group[#group + 1] = header(m, section.title)
                    local taps = {}
                    for li, line in ipairs(lines) do
                        local row = HorizontalGroup:new{ align = "top" }
                        for ci, card in ipairs(line) do
                            if ci > 1 then row[#row + 1] = HorizontalSpan:new{ width = m.gap } end
                            row[#row + 1] = cardWidget(m, plugin, card)
                            taps[#taps + 1] = { x = (ci - 1) * (m.card_w + m.gap), y = m.header_h + (li - 1) * m.card_h, w = m.card_w, h = m.card_h, card = card }
                        end
                        group[#group + 1] = row
                        group[#group + 1] = VerticalSpan:new{ width = m.card_h - m.cover_h - Screen:scaleBySize(6) - Screen:scaleBySize(8) - m.title_h }
                    end
                    return group, taps
                end,
            }
        elseif section.kind == "quotes" then
            local widgets = {}
            local height = m.header_h
            for _, note in ipairs(section.notes) do
                local text = TextBoxWidget:new{ text = "“" .. note.text .. "”", face = Font:getFace("cfont", 16), width = m.content_w }
                local who = TextBoxWidget:new{ text = "— " .. (note.title or "") .. ((note.author and note.author ~= "") and (", " .. note.author) or ""),
                    face = Font:getFace("cfont", 14), width = m.content_w }
                widgets[#widgets + 1] = { text = text, who = who }
                height = height + text:getSize().h + who:getSize().h + m.gap
            end
            blocks[#blocks + 1] = {
                h = height,
                build = function()
                    local group = VerticalGroup:new{ align = "left" }
                    group[#group + 1] = header(m, section.title)
                    for _, w in ipairs(widgets) do
                        group[#group + 1] = w.text
                        group[#group + 1] = w.who
                        group[#group + 1] = VerticalSpan:new{ width = m.gap }
                    end
                    return group, {}
                end,
            }
        end
    end
    return blocks
end

-- ---------------------------------------------------------------- the widget

function Home:init()
    self.m = measures()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.m.w, h = self.m.h }
    self.ges_events = {
        TapHome = { GestureRange:new{ ges = "tap", range = self.dimen } },
        SwipeHome = { GestureRange:new{ ges = "swipe", range = self.dimen } },
    }
    self:setData(self.data)
end

--- New data from the server: the pages are laid out again, from the first.
function Home:setData(data)
    self.data = data
    self.blocks = blocksOf(self.m, self.plugin, data)
    self.pages = core.paginate(self.blocks, self.m.avail)
    if #self.pages == 0 then self.pages = { {} } end
    if self.page > #self.pages then self.page = 1 end
    self:render()
end

function Home:render()
    local m = self.m
    self.taps = {}
    local page = self.pages[self.page] or {}

    local title = TextWidget:new{ text = "Códice", face = Font:getFace("tfont", 26) }
    local menu = TextWidget:new{ text = "Menu", face = Font:getFace("cfont", 20) }
    local top = HorizontalGroup:new{
        align = "center",
        HorizontalSpan:new{ width = m.margin },
        title,
        HorizontalSpan:new{ width = m.w - 2 * m.margin - title:getSize().w - menu:getSize().w },
        menu,
    }
    self.taps[#self.taps + 1] = { x = m.w - m.margin - menu:getSize().w - m.gap, y = 0, w = menu:getSize().w + m.margin + m.gap, h = m.top, action = "menu" }

    local content = VerticalGroup:new{ align = "left" }
    local y = m.top
    for _, block in ipairs(page) do
        local widget, taps = block.build()
        content[#content + 1] = widget
        for _, t in ipairs(taps or {}) do
            self.taps[#self.taps + 1] = { x = m.margin + t.x, y = y + t.y, w = t.w, h = t.h, card = t.card }
        end
        y = y + block.h
    end

    local foot = TextWidget:new{ text = string.format("<    %d / %d    >", self.page, #self.pages), face = Font:getFace("cfont", 18) }
    local footer = CenterContainer:new{ dimen = Geom:new{ w = m.w, h = m.foot }, foot }
    self.taps[#self.taps + 1] = { x = 0, y = m.h - m.foot, w = m.w / 2, h = m.foot, action = "prev" }
    self.taps[#self.taps + 1] = { x = m.w / 2, y = m.h - m.foot, w = m.w / 2, h = m.foot, action = "next" }

    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE, bordersize = 0, padding = 0, margin = 0, width = m.w, height = m.h,
        VerticalGroup:new{
            align = "left",
            CenterContainer:new{ dimen = Geom:new{ w = m.w, h = m.top }, top },
            HorizontalGroup:new{ HorizontalSpan:new{ width = m.margin }, content },
            VerticalSpan:new{ width = math.max(0, m.avail - (y - m.top)) },
            footer,
        },
    }
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function Home:go(delta)
    local target = self.page + delta
    if target < 1 or target > #self.pages then return true end
    self.page = target
    self:render()
    return true
end

function Home:onTapHome(_, ges)
    local x, y = ges.pos.x, ges.pos.y
    for _, t in ipairs(self.taps) do
        if x >= t.x and x < t.x + t.w and y >= t.y and y < t.y + t.h then
            if t.action == "menu" then self:openMenu()
            elseif t.action == "prev" then self:go(-1)
            elseif t.action == "next" then self:go(1)
            elseif t.card then self:openCard(t.card) end
            return true
        end
    end
    return true
end

function Home:onSwipeHome(_, ges)
    if ges.direction == "west" then return self:go(1) end
    if ges.direction == "east" then return self:go(-1) end
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
                    self.plugin:openBook(card, function() UIManager:close(self) end)
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
    dialog = ButtonDialog:new{
        title = "Códice",
        title_align = "center",
        buttons = {
            item("Atualizar esta tela", function() self.plugin:showHome(self) end),
            item("Catálogo completo (OPDS)", function()
                UIManager:close(self)
                if self.plugin.ui.opds then self.plugin.ui.opds:onShowOPDSCatalog() end
            end),
            item("Atualizar a configuração", function() self.plugin:syncConfig(false) end),
            item("Procurar atualização do plugin", function() self.plugin:checkUpdate(false) end),
            item("Fechar o Códice", function() UIManager:close(self) end),
        },
    }
    UIManager:show(dialog)
end

function Home:onCloseWidget()
    UIManager:setDirty(nil, "full")
end

return Home
