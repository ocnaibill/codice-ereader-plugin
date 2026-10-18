--[[--
The library of the Códice on a reader (DEC-198): a screen of its own, a page at a time (no scrolling: a tap on the foot, or a swipe, turns it),
with a header (back, title, search, order), the filters of a list, a body that is a list, a grid of covers three by two, or the sheet of a work, and
a foot that says which page this is.

It reads from the server when there is a network and from the shelf (`codice/shelf.lua`: what is on the device) when there is not, with a notice
that says so. What each screen shows and asks is in `codice/libview.lua`, tested apart; this file draws it and handles the touch.
]]--

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local ProgressWidget = require("ui/widget/progresswidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local Screen = Device.screen

local api = require("codice/http")
local core = require("codice/core")
local Coverimg = require("codice/coverimg")
local Covers = require("codice/covers")
local Libview = require("codice/libview")
local Shelf = require("codice/shelf")
local Store = require("codice/shelfstore")

local PER_PAGE = Libview.PER_PAGE
local COLS = 3
local COVERS_PER_STEP = 2

local Library = InputContainer:extend{
    name = "codice_library",
    plugin = nil, -- the plugin: it holds the connection and opens books
}

-- ---------------------------------------------------------------- measures and pieces

local function measures()
    local w, h = Screen:getWidth(), Screen:getHeight()
    local m = {
        w = w, h = h,
        margin = Screen:scaleBySize(14),
        gap = Screen:scaleBySize(10),
        header_h = Screen:scaleBySize(56),
        foot_h = Screen:scaleBySize(48),
        chips_h = Screen:scaleBySize(46),
        notice_h = Screen:scaleBySize(40),
    }
    m.content_w = w - 2 * m.margin
    m.card_w = math.floor((m.content_w - (COLS - 1) * m.gap) / COLS)
    m.cover_h = math.floor(m.card_w * 1.5)
    m.row_h = Screen:scaleBySize(64)
    return m
end

local function face(size, bold)
    return Font:getFace(bold and "tfont" or "cfont", size)
end

--- A line of text, cut with an ellipsis at `max_width`. The quiet color (`gray`) goes through the helper of the Simple UI, since the TextWidget of
--- some devices ignores the color; when it is not there, the text is plain black.
local function text(str, size, opts)
    opts = opts or {}
    local spec = { text = tostring(str or ""), face = face(size, opts.bold), max_width = opts.max_width, truncate_with_ellipsis = true }
    if opts.gray then
        local ok, UI = pcall(require, "infra/sui_core")
        if ok and UI and UI.makeColoredText then
            local made, widget = pcall(UI.makeColoredText, { text = spec.text, face = spec.face, fgcolor = UI.CLR_TEXT_SUB, max_width = spec.max_width,
                truncate_with_ellipsis = true, alignment = "left" })
            if made and widget then return widget end
        end
    end
    return TextWidget:new(spec)
end

--- The id of a JSON field that may be null (the decoder gives a marker for null, not nil).
local function numberOrNil(v)
    return type(v) == "number" and v or nil
end

local function rule(w)
    return LineWidget:new{ dimen = Geom:new{ w = w, h = Screen:scaleBySize(1) } }
end

--- A box of exactly w x h with `inner` at its left, so that every row and cell has the same size.
local function box(w, h, inner)
    return LeftContainer:new{ dimen = Geom:new{ w = w, h = h }, inner }
end

-- ---------------------------------------------------------------- the data

function Library:conn()
    return self.plugin:connection()
end

--- Whether the network can be used now (the Wi-Fi is on and the server did not just fail).
function Library:online()
    return Store.state() == "online"
end

--- Asks the server for something, with "Carregando…" over the screen while it does. Returns `code, data`; nil when there is no connection.
function Library:get(path, params)
    local c = self:conn()
    if not c then return nil end
    local url = c.url .. path .. (params and next(params) and ("?" .. Libview.queryString(params)) or "")
    local info = InfoMessage:new{ text = "Carregando…", timeout = 0 }
    UIManager:show(info)
    UIManager:forceRePaint()
    local code, data = api.request(url, { user = c.username, password = c.token })
    UIManager:close(info)
    return code, data
end

local function shelf() return Store.index() end

-- ---------------------------------------------------------------- the models of the screens
--
-- A model is { kind = "list" | "grid" | "detail", title, rows | cards | detail, page, pages, chips, search, sort, notice, empty }.
-- A row is { title, detail, go = function() ... end }.

--- The notice when what is shown comes from the device, or nil.
function Library:notice(offline)
    if not offline then return nil end
    return Store.notice() or "Sem conexão: mostrando só o que está no aparelho."
end

--- How many rows of a list fit the screen: what is left under the header, the notice and the foot (and `extra`, what the screen puts over the
--- list), at least three. A page that does not fit cannot be read: there is no scrolling.
function Library:rowsPerPage(extra)
    local m = self.m
    local avail = m.h - m.header_h - m.notice_h - m.foot_h - (extra or 0) - m.gap
    return math.max(3, math.floor(avail / (m.row_h + Screen:scaleBySize(1))))
end

--- The rows of a page out of all of them: `{ rows, page, pages }`.
local function pageOfRows(all, page, per)
    local pages = math.max(1, math.ceil(#all / per))
    page = math.min(math.max(1, page), pages)
    local rows = {}
    for i = (page - 1) * per + 1, math.min(#all, page * per) do rows[#rows + 1] = all[i] end
    return rows, page, pages
end

function Library:modelRoot()
    local works, bytes = Shelf.totals(shelf())
    local rows = {}
    for _, r in ipairs(Libview.rootRows(works, bytes)) do
        rows[#rows + 1] = { title = r.title, detail = r.detail, go = function() self:push(r.id) end }
    end
    return { kind = "list", title = "Biblioteca", rows = rows, search = true, notice = self:notice(not self:online()) }
end

--- Categories under `parent` (nil: the top ones).
function Library:modelCategories(view)
    local offline = not self:online()
    local list, children = {}, {}
    if not offline then
        local code, data = self:get("/device/categories")
        if code == 200 and type(data) == "table" and type(data.data) == "table" then
            for _, c in ipairs(data.data) do
                local parent = numberOrNil(c.parentId)
                if parent then children[parent] = true end
                if parent == view.parent and (c.works or 0) > 0 then
                    list[#list + 1] = { id = c.id, name = c.name, count = c.works }
                end
            end
        else
            offline = true
        end
    end
    if offline then
        list = Shelf.categories(shelf(), view.parent)
        for _, w in pairs(shelf().works) do
            for _, c in ipairs(w.categories or {}) do
                if c.parentId then children[c.parentId] = true end
            end
        end
    end
    local rows = {}
    if view.parent and view.parent_name then
        rows[#rows + 1] = { title = "Todas as obras de " .. view.parent_name, go = function()
            self:push("works", { spec = { category = view.parent, title = view.parent_name } })
        end }
    end
    for _, c in ipairs(list) do
        rows[#rows + 1] = { title = c.name, detail = tostring(c.count), go = function()
            if children[c.id] then
                self:push("categories", { parent = c.id, parent_name = c.name, title = c.name })
            else
                self:push("works", { spec = { category = c.id, title = c.name } })
            end
        end }
    end
    local page_rows, page, pages = pageOfRows(rows, view.page or 1, self:rowsPerPage())
    return { kind = "list", title = view.title or "Categorias", rows = page_rows, page = page, pages = pages,
             notice = self:notice(offline), empty = "Nenhuma categoria." }
end

--- The people who wrote what is in the library, a letter at a time (the first one there is, until the person picks another) and a page at a
--- time (as many rows as fit the screen).
function Library:modelPeople(view)
    local offline = not self:online()
    local letter = view.letter
    local rows, letters, page, pages = {}, {}, view.page or 1, 1
    local per = self:rowsPerPage(self.letters_h)
    local function letterList(list)
        local out = {}
        for _, l in ipairs(list or {}) do out[#out + 1] = l.letter end
        return out
    end
    if not offline then
        if not letter then
            -- the letters there are first, to open on the first of them
            local code, data = self:get("/device/people", { limit = 1 })
            if code == 200 and type(data) == "table" and type(data.letters) == "table" then
                letters = letterList(data.letters)
                letter = letters[1]
                view.letter = letter
            else
                offline = true
            end
        end
    end
    if not offline then
        local params = { page = page, limit = per }
        if letter then params.letter = letter end
        local code, data = self:get("/device/people", params)
        if code == 200 and type(data) == "table" and type(data.data) == "table" then
            for _, p in ipairs(data.data) do
                rows[#rows + 1] = { title = p.name, detail = tostring(p.works), go = function()
                    self:push("works", { spec = { person = p.id, title = p.name } })
                end }
            end
            letters = letterList(data.letters)
            page, pages = data.page or page, data.pages or 1
        else
            offline = true
        end
    end
    if offline then
        local seen, all = {}, Shelf.authors(shelf())
        letters = {}
        for _, a in ipairs(all) do
            local l = Shelf.letter(a.name)
            if not seen[l] then seen[l] = true; letters[#letters + 1] = l end
        end
        table.sort(letters, function(a, b)
            if a == "#" then return false end
            if b == "#" then return true end
            return a < b
        end)
        letter = view.letter
        if not letter or not seen[letter] then letter = letters[1]; view.letter = letter end
        rows = {}
        for _, a in ipairs(all) do
            if Shelf.letter(a.name) == letter then
                rows[#rows + 1] = { title = a.name, detail = tostring(a.count), go = function()
                    self:push("works", { spec = { author = a.id, title = a.name } })
                end }
            end
        end
        rows, page, pages = pageOfRows(rows, page, per)
    end
    return { kind = "list", title = view.title or "Autores", rows = rows, page = page, pages = pages, letters = letters, letter = letter,
             search = false, notice = self:notice(offline), empty = "Nenhum autor." }
end

function Library:modelCollections(view)
    local offline = not self:online()
    local rows, page, pages = {}, view.page or 1, 1
    if not offline then
        local per = self:rowsPerPage()
        local code, data = self:get("/device/collections", { page = page, limit = per })
        if code == 200 and type(data) == "table" and type(data.data) == "table" then
            for _, c in ipairs(data.data) do
                rows[#rows + 1] = { title = c.name, detail = tostring(c.workCount or ""), go = function()
                    self:push("collection", { id = c.id, title = c.name })
                end }
            end
            page = data.page or page
            pages = data.totalPages or math.max(1, math.ceil((data.total or #rows) / per))
        else
            offline = true
        end
    end
    if offline then
        rows = {}
        for _, s in ipairs(Shelf.series(shelf())) do
            rows[#rows + 1] = { title = s.name, detail = tostring(s.count), go = function()
                self:push("works", { spec = { series = s.name, title = s.name } })
            end }
        end
        rows, page, pages = pageOfRows(rows, page, self:rowsPerPage())
    end
    return { kind = "list", title = view.title or "Séries e coleções", rows = rows, page = page, pages = pages,
             notice = self:notice(offline), empty = "Nada por aqui." }
end

function Library:modelFormats(view)
    local offline = not self:online()
    local rows = {}
    if not offline then
        for _, g in ipairs(Libview.FORMAT_GROUPS) do
            rows[#rows + 1] = { title = g.title, go = function() self:push("works", { spec = { formatGroup = g.id, title = g.title } }) end }
        end
    else
        for _, f in ipairs(Shelf.formats(shelf())) do
            rows[#rows + 1] = { title = f.format:upper(), detail = tostring(f.count), go = function()
                self:push("works", { spec = { format = f.format, title = f.format:upper() } })
            end }
        end
    end
    return { kind = "list", title = view.title or "Formatos", rows = rows, page = 1, pages = 1, notice = self:notice(offline), empty = "Nenhum formato." }
end

--- The local list of works for a spec, with the filters the shelf knows.
local function shelfList(spec, chip)
    local opts = { sort = spec.sort == "author" and "author" or (spec.sort == "recent" and "recent" or "title") }
    opts.category = spec.category
    opts.author = spec.author or spec.person
    opts.series = spec.series
    opts.format = spec.format
    opts.search = spec.search
    opts.favorite = spec.favorite
    if chip == "reading" or spec.inProgress then opts.state = "reading" end
    return Shelf.list(shelf(), opts)
end

--- A grid of works: from the server when it can be asked, else from the shelf. The chips narrow it: all, only what is on the device, only what
--- is being read.
function Library:modelWorks(view)
    local spec = view.spec
    local chip = view.chip or "all"
    local offline = not self:online()
    local cards, page, pages
    local local_only = spec.downloaded or chip == "downloaded" or spec.format ~= nil or spec.series ~= nil or spec.author ~= nil
    if not offline and not local_only then
        local params = Libview.worksParams(spec, view.page or 1)
        if chip == "reading" then params.inProgress = "true"; params.series = nil end
        local code, data = self:get("/device/works", params)
        if code == 200 and type(data) == "table" and type(data.data) == "table" then
            cards = Libview.markDownloaded(Libview.cardsOf(data), shelf())
            page, pages = data.page or 1, data.totalPages or 1
        else
            offline = true
        end
    end
    if not cards then
        local all = shelfList(spec, chip)
        local pg = Shelf.page(all, view.page or 1, PER_PAGE)
        cards, page, pages = pg.items, pg.page, pg.pages
    end
    local chips
    if not spec.downloaded then chips = Libview.CHIPS end
    return { kind = "grid", title = Libview.listTitle(spec), cards = cards, page = page, pages = pages, chips = chips, chip = chip, search = true, sort = true,
             notice = self:notice(offline), empty = chip == "downloaded" and "Nenhuma obra no aparelho aqui." or "Nenhuma obra." }
end

--- The works of a collection.
function Library:modelCollection(view)
    local code, data = self:get("/device/collections/" .. tostring(view.id))
    local all = {}
    local offline = not (code == 200 and type(data) == "table")
    if not offline then all = Libview.markDownloaded(Libview.cardsOf(data, true), shelf()) end
    local pages = math.max(1, math.ceil(#all / PER_PAGE))
    local page = math.min(math.max(1, view.page or 1), pages)
    local cards = {}
    for i = (page - 1) * PER_PAGE + 1, math.min(#all, page * PER_PAGE) do cards[#cards + 1] = all[i] end
    return { kind = "grid", title = view.title or "Coleção", cards = cards, page = page, pages = pages, notice = self:notice(offline),
             empty = offline and "Não consegui abrir esta coleção." or "Nenhuma obra." }
end

--- The sheet of a work.
function Library:modelDetail(view)
    local card = view.card
    local work
    local online = self:online()
    if online then
        local code, data = self:get("/device/shelf", { works = card.id })
        if code == 200 and type(data) == "table" and type(data.works) == "table" and data.works[1] then work = data.works[1] end
        if not work then online = false end
    end
    local kept = shelf().works[tostring(card.id)]
    if not work then
        if not kept then
            return { kind = "list", title = card.title or "Obra", rows = {}, empty = "Sem conexão, e esta obra não está no aparelho.", notice = self:notice(true) }
        end
        work = kept
    end
    local detail = Libview.detail(work, kept, online)
    detail.card = card
    detail.cover = card.cover or work.cover or work.coverUrl
    return { kind = "detail", title = work.title or card.title or "Obra", detail = detail, notice = self:notice(not online) }
end

-- ---------------------------------------------------------------- navigation

--- Opens a screen of kind `kind` on top of the others; `extra` are the fields of its view.
function Library:push(kind, extra)
    local view = extra or {}
    view.kind = kind
    view.page = view.page or 1
    self.stack[#self.stack + 1] = view
    self:refresh()
end

function Library:back()
    if #self.stack <= 1 then
        UIManager:close(self)
        return
    end
    table.remove(self.stack)
    self:refresh()
end

local MODELS = {
    root = "modelRoot", categories = "modelCategories", people = "modelPeople", collections = "modelCollections", formats = "modelFormats",
    works = "modelWorks", collection = "modelCollection", detail = "modelDetail",
}

--- The entries of the root that open a list of works lead to it from here.
local ROOT_TO_VIEW = {
    all = function() return "works", { spec = { title = "Todas as obras" } } end,
    device = function() return "works", { spec = { downloaded = true, title = "No aparelho" } } end,
}

function Library:viewModel(view)
    local kind = view.kind
    if ROOT_TO_VIEW[kind] then
        local k, extra = ROOT_TO_VIEW[kind]()
        view.kind = k
        for key, v in pairs(extra) do view[key] = v end
        kind = k
    end
    local method = MODELS[kind]
    return self[method](self, view)
end

--- Draws the screen on top of the stack, guarded: a failure shows a message and keeps the screen before.
function Library:refresh()
    local view = self.stack[#self.stack]
    local ok, model = xpcall(function() return self:viewModel(view) end, debug.traceback)
    if not ok then
        logger.err("codice: library screen failed:", model)
        UIManager:show(InfoMessage:new{ text = "A biblioteca não conseguiu abrir esta tela.\n\n" .. core.firstLine(model) })
        if #self.stack > 1 then table.remove(self.stack) end
        return
    end
    -- a root entry that became a list of works (see ROOT_TO_VIEW) keeps its new kind in the view
    self.model = model
    self:render()
end

-- ---------------------------------------------------------------- drawing

--- The header: back, the title, and the search and order.
function Library:header(m, model)
    -- words, not symbols: not every font has the glyph of a magnifier or of two arrows
    local back = text(#self.stack > 1 and "‹ Voltar" or "Fechar", 22, { bold = true })
    local right = {}
    if model.sort then right[#right + 1] = { label = "Ordem", id = "sort" } end
    if model.search then right[#right + 1] = { label = "Buscar", id = "search" } end
    local group = HorizontalGroup:new{ align = "center" }
    self.hits[#self.hits + 1] = { x = 0, y = 0, w = m.margin + back:getSize().w + m.gap * 2, h = m.header_h, fn = function() self:back() end }
    group[#group + 1] = HorizontalSpan:new{ width = m.margin }
    group[#group + 1] = back
    group[#group + 1] = HorizontalSpan:new{ width = m.gap }
    local right_w = 0
    local widgets = {}
    for _, r in ipairs(right) do
        local t = text(r.label, 20, { bold = true })
        widgets[#widgets + 1] = { widget = t, id = r.id }
        right_w = right_w + t:getSize().w + m.gap * 2
    end
    local title = text(model.title, 24, { bold = true, max_width = m.w - 2 * m.margin - back:getSize().w - right_w - m.gap * 2 })
    group[#group + 1] = title
    group[#group + 1] = HorizontalSpan:new{ width = math.max(0, m.w - m.margin * 2 - back:getSize().w - m.gap - title:getSize().w - right_w) }
    local x = m.w - m.margin - right_w
    for _, w in ipairs(widgets) do
        group[#group + 1] = HorizontalSpan:new{ width = m.gap }
        group[#group + 1] = w.widget
        group[#group + 1] = HorizontalSpan:new{ width = m.gap }
        self.hits[#self.hits + 1] = { x = x, y = 0, w = w.widget:getSize().w + m.gap * 2, h = m.header_h, fn = function() self:onHeaderAction(w.id) end }
        x = x + w.widget:getSize().w + m.gap * 2
    end
    return VerticalGroup:new{
        align = "left",
        CenterContainer:new{ dimen = Geom:new{ w = m.w, h = m.header_h - Screen:scaleBySize(2) }, group },
        rule(m.w),
    }
end

--- The strip of filters of a list of works.
function Library:chips(m, model, top)
    local group = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = m.margin } }
    local x = m.margin
    for _, chip in ipairs(model.chips) do
        local on = (model.chip or "all") == chip.id
        local pad = Screen:scaleBySize(12)
        -- the one that is on has a thick border and bold letters (no inverted colors: they are not safe on every device)
        local cell = FrameContainer:new{
            bordersize = Screen:scaleBySize(on and 4 or 1), radius = Screen:scaleBySize(16), padding = Screen:scaleBySize(4), padding_left = pad, padding_right = pad, margin = 0,
            text(chip.title, 18, { bold = on }),
        }
        group[#group + 1] = cell
        group[#group + 1] = HorizontalSpan:new{ width = m.gap }
        local w = cell:getSize().w
        self.hits[#self.hits + 1] = { x = x, y = top, w = w, h = m.chips_h, fn = function() self:setChip(chip.id) end }
        x = x + w + m.gap
    end
    return CenterContainer:new{ dimen = Geom:new{ w = m.w, h = m.chips_h }, group }
end

--- The strip of letters of the list of authors.
function Library:letters(m, model, top)
    local rows = VerticalGroup:new{ align = "left" }
    local per_line = 14
    local line_h = Screen:scaleBySize(40)
    local list = model.letters or {}
    local cell_w = math.floor(m.content_w / per_line)
    local all = {}
    for _, l in ipairs(list) do all[#all + 1] = { label = l, letter = l } end
    local i = 1
    local y = top
    while i <= #all do
        local line = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = m.margin } }
        local x = m.margin
        local n = 0
        while i <= #all and n < per_line do
            local item = all[i]
            local w = cell_w
            local on = (model.letter == item.letter)
            local t = text(item.label, on and 22 or 18, { bold = on })
            line[#line + 1] = FrameContainer:new{ bordersize = on and Screen:scaleBySize(3) or 0, padding = 0, margin = 0,
                width = w, height = line_h, CenterContainer:new{ dimen = Geom:new{ w = w - 6, h = line_h - 6 }, t } }
            self.hits[#self.hits + 1] = { x = x, y = y, w = w, h = line_h, fn = function() self:setLetter(item.letter) end }
            x = x + w
            n = n + 1
            i = i + 1
        end
        rows[#rows + 1] = line
        y = y + line_h
    end
    self.letters_h = y - top
    return rows, y - top
end

--- A list: one row for each entry (the title, and at the end how many or what), a rule under each.
function Library:listBody(m, model, top)
    local group = VerticalGroup:new{ align = "left" }
    local y = top
    if #model.rows == 0 then
        group[#group + 1] = VerticalSpan:new{ width = m.gap * 2 }
        group[#group + 1] = box(m.w, m.row_h, HorizontalGroup:new{ HorizontalSpan:new{ width = m.margin },
            TextBoxWidget:new{ text = model.empty or "Nada por aqui.", face = face(20), width = m.content_w } })
        return group, y + m.gap * 2 + m.row_h
    end
    for _, row in ipairs(model.rows) do
        local detail = row.detail and text(row.detail, 18, { gray = true }) or nil
        local arrow = text("›", 26, { bold = true })
        local right_w = (detail and detail:getSize().w + m.gap or 0) + arrow:getSize().w
        local title = text(row.title, 22, { bold = true, max_width = m.content_w - right_w - m.gap })
        local line = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = m.margin }, title,
            HorizontalSpan:new{ width = math.max(0, m.content_w - title:getSize().w - right_w) } }
        if detail then
            line[#line + 1] = detail
            line[#line + 1] = HorizontalSpan:new{ width = m.gap }
        end
        line[#line + 1] = arrow
        group[#group + 1] = CenterContainer:new{ dimen = Geom:new{ w = m.w, h = m.row_h }, line }
        group[#group + 1] = rule(m.w)
        self.hits[#self.hits + 1] = { x = 0, y = y, w = m.w, h = m.row_h, fn = row.go }
        y = y + m.row_h + Screen:scaleBySize(1)
    end
    return group, y
end

--- The cover of a card, in a box of the size `m.card_w` x `m.cover_h`: its image when it is kept, its title while it is not (the image comes
--- after, into the box that is kept in `holders`).
function Library:coverBox(m, card, holders)
    local path = Covers.path(card)
    local inner
    local kept = Covers.kept(path)
    if kept then
        inner = Coverimg.widget(path, m.card_w, m.cover_h)
    else
        local pad = Screen:scaleBySize(6)
        inner = FrameContainer:new{ bordersize = 1, padding = pad, margin = 0, width = m.card_w, height = m.cover_h,
            TextBoxWidget:new{ text = card.title or "?", face = face(16), width = m.card_w - 2 * pad - 2 } }
    end
    local holder = FrameContainer:new{ bordersize = 0, padding = 0, margin = 0, width = m.card_w, height = m.cover_h, inner }
    if not kept and path then holders[#holders + 1] = { box = holder, card = card, w = m.card_w, h = m.cover_h } end
    return holder
end

--- A card: the cover, how far the person is, the title and the author, and the mark of a book that is on the device.
function Library:cardWidget(m, card, holders)
    local cover = self:coverBox(m, card, holders)
    local progress
    if (card.percent or 0) > 0 then
        progress = ProgressWidget:new{ width = m.card_w, height = Screen:scaleBySize(6), percentage = math.min(1, card.percent / 100), margin_h = 0, margin_v = 0 }
    else
        progress = VerticalSpan:new{ width = Screen:scaleBySize(6) }
    end
    local mark = card.downloaded and "↓ " or ""
    return VerticalGroup:new{
        align = "left",
        cover,
        VerticalSpan:new{ width = Screen:scaleBySize(4) },
        progress,
        VerticalSpan:new{ width = Screen:scaleBySize(4) },
        box(m.card_w, Screen:scaleBySize(22), text(mark .. (card.title or "?"), 16, { bold = true, max_width = m.card_w })),
        box(m.card_w, Screen:scaleBySize(20), text(card.subtitle or card.author or "", 14, { gray = true, max_width = m.card_w })),
    }
end

--- The grid: three covers by two, as big as the width allows, and smaller when two lines would not fit the height that is left.
function Library:gridBody(m, model, top, holders, avail)
    local group = VerticalGroup:new{ align = "left" }
    local y = top
    if #model.cards == 0 then
        group[#group + 1] = VerticalSpan:new{ width = m.gap * 2 }
        group[#group + 1] = box(m.w, m.row_h, HorizontalGroup:new{ HorizontalSpan:new{ width = m.margin },
            TextBoxWidget:new{ text = model.empty or "Nenhuma obra.", face = face(20), width = m.content_w } })
        return group, y + m.gap * 2 + m.row_h
    end
    local text_h = Screen:scaleBySize(4 + 6 + 4 + 22 + 20)
    local max_cover_h = math.floor((avail - 3 * m.gap - 2 * text_h) / 2)
    local card_w = math.min(m.card_w, math.floor(max_cover_h / 1.5))
    local cm = { card_w = card_w, cover_h = math.floor(card_w * 1.5) }
    local line_h = cm.cover_h + text_h + m.gap
    local left = math.floor((m.w - (COLS * card_w + (COLS - 1) * m.gap)) / 2)
    group[#group + 1] = VerticalSpan:new{ width = m.gap }
    y = y + m.gap
    local i = 1
    while i <= #model.cards do
        local line = HorizontalGroup:new{ align = "top", HorizontalSpan:new{ width = left } }
        for c = 1, COLS do
            local card = model.cards[i]
            if not card then break end
            if c > 1 then line[#line + 1] = HorizontalSpan:new{ width = m.gap } end
            line[#line + 1] = self:cardWidget(cm, card, holders)
            self.hits[#self.hits + 1] = { x = left + (c - 1) * (card_w + m.gap), y = y, w = card_w, h = line_h - m.gap, fn = function()
                if card.collection then
                    -- a series: its volumes and chapters, to choose which to read
                    self:push("collection", { id = card.collection.id, title = card.collection.name })
                else
                    self:push("detail", { card = card })
                end
            end }
            i = i + 1
        end
        group[#group + 1] = line
        group[#group + 1] = VerticalSpan:new{ width = m.gap }
        y = y + line_h
    end
    return group, y
end

--- The sheet of a work: the cover, the lines under the title, what to do, and the files.
function Library:detailBody(m, model, top, holders)
    local d = model.detail
    local group = VerticalGroup:new{ align = "left" }
    local y = top + m.gap
    group[#group + 1] = VerticalSpan:new{ width = m.gap }
    local cover_w = math.floor(m.w * 0.32)
    local cover_h = math.floor(cover_w * 1.5)
    local cm = { card_w = cover_w, cover_h = cover_h }
    local cover = self:coverBox(cm, d.card, holders)
    local info = VerticalGroup:new{ align = "left" }
    local info_w = m.content_w - cover_w - m.gap
    info[#info + 1] = TextBoxWidget:new{ text = d.title or "?", face = face(26, true), width = info_w }
    if d.author and d.author ~= "" then
        info[#info + 1] = VerticalSpan:new{ width = Screen:scaleBySize(4) }
        info[#info + 1] = TextBoxWidget:new{ text = d.author, face = face(20), width = info_w }
    end
    for _, line in ipairs(d.lines or {}) do
        info[#info + 1] = VerticalSpan:new{ width = Screen:scaleBySize(4) }
        info[#info + 1] = TextBoxWidget:new{ text = line, face = face(18), width = info_w, gray = true }
    end
    group[#group + 1] = HorizontalGroup:new{ align = "top", HorizontalSpan:new{ width = m.margin }, cover, HorizontalSpan:new{ width = m.gap }, info }
    y = y + math.max(cover_h, info:getSize().h) + m.gap
    group[#group + 1] = VerticalSpan:new{ width = m.gap }

    -- the actions
    local buttons = {}
    if d.can_read then buttons[#buttons + 1] = { label = d.read_text, fn = function() self:readBest(d) end, primary = true } end
    if d.can_remove then buttons[#buttons + 1] = { label = "Remover do aparelho", fn = function() self:confirmRemove(d) end } end
    if #buttons > 0 then
        local bw = math.floor((m.content_w - (#buttons - 1) * m.gap) / #buttons)
        local bh = Screen:scaleBySize(54)
        local line = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = m.margin } }
        for bi, b in ipairs(buttons) do
            if bi > 1 then line[#line + 1] = HorizontalSpan:new{ width = m.gap } end
            line[#line + 1] = FrameContainer:new{
                bordersize = Screen:scaleBySize(b.primary and 5 or 2), padding = 0, margin = 0, width = bw, height = bh,
                CenterContainer:new{ dimen = Geom:new{ w = bw - 10, h = bh - 10 }, text(b.label, 20, { bold = true, max_width = bw - 20 }) },
            }
            self.hits[#self.hits + 1] = { x = m.margin + (bi - 1) * (bw + m.gap), y = y, w = bw, h = bh, fn = b.fn }
        end
        group[#group + 1] = line
        group[#group + 1] = VerticalSpan:new{ width = m.gap }
        y = y + bh + m.gap
    end

    -- the files
    if #d.files > 0 then
        group[#group + 1] = box(m.w, Screen:scaleBySize(34), HorizontalGroup:new{ HorizontalSpan:new{ width = m.margin }, text("ARQUIVOS", 15, { bold = true }) })
        group[#group + 1] = rule(m.w)
        y = y + Screen:scaleBySize(34) + Screen:scaleBySize(1)
        for _, f in ipairs(d.files) do
            local state = text(f.state, 17, { gray = true })
            local label = text(f.label, 20, { bold = true, max_width = m.content_w - state:getSize().w - m.gap })
            local line = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = m.margin }, label,
                HorizontalSpan:new{ width = math.max(0, m.content_w - label:getSize().w - state:getSize().w) }, state }
            local h = Screen:scaleBySize(54)
            group[#group + 1] = CenterContainer:new{ dimen = Geom:new{ w = m.w, h = h }, line }
            group[#group + 1] = rule(m.w)
            if f.here or self:online() then
                self.hits[#self.hits + 1] = { x = 0, y = y, w = m.w, h = h, fn = function() self:openFile(d, f) end }
            end
            y = y + h + Screen:scaleBySize(1)
        end
    end
    return group, y
end

--- The foot: the page of how many, and the ways to turn it.
function Library:foot(m, model, top)
    local pages = model.pages or 1
    local label = Libview.pagerText(model.page or 1, pages)
    local group = HorizontalGroup:new{ align = "center" }
    local prev = text("‹ anterior", 18)
    local nxt = text("próxima ›", 18)
    local middle = text(label, 18, { bold = true })
    local third = math.floor(m.w / 3)
    local function slot(widget, align_right)
        return CenterContainer:new{ dimen = Geom:new{ w = third, h = m.foot_h }, widget }
    end
    group[#group + 1] = slot(prev)
    group[#group + 1] = slot(middle)
    group[#group + 1] = slot(nxt)
    self.hits[#self.hits + 1] = { x = 0, y = top, w = third, h = m.foot_h, fn = function() self:turn(-1) end }
    self.hits[#self.hits + 1] = { x = third * 2, y = top, w = m.w - third * 2, h = m.foot_h, fn = function() self:turn(1) end }
    return VerticalGroup:new{ align = "left", rule(m.w), group }
end

--- Builds the whole screen from the model and draws it.
function Library:render()
    local m = self.m
    local model = self.model
    self.hits = {}
    self.holders = {}
    self.generation = (self.generation or 0) + 1
    local content = VerticalGroup:new{ align = "left" }
    local y = 0
    local function push(widget, h)
        content[#content + 1] = widget
        y = y + (h or widget:getSize().h)
    end
    push(self:header(m, model))
    if model.notice then
        push(CenterContainer:new{ dimen = Geom:new{ w = m.w, h = m.notice_h }, TextBoxWidget:new{ text = model.notice, face = face(15), width = m.content_w, alignment = "center" } }, m.notice_h)
    end
    if model.chips then
        push(self:chips(m, model, y), m.chips_h)
        push(rule(m.w))
    end
    if model.letters then
        local strip, h = self:letters(m, model, y)
        push(strip, h)
        push(rule(m.w))
    end
    local body, body_end
    if model.kind == "grid" then
        body, body_end = self:gridBody(m, model, y, self.holders, m.h - y - m.foot_h - Screen:scaleBySize(1))
    elseif model.kind == "detail" then
        body, body_end = self:detailBody(m, model, y, self.holders)
    else
        body, body_end = self:listBody(m, model, y)
    end
    push(body, body_end - y)
    -- the foot is at the bottom of the screen
    local foot_top = m.h - m.foot_h - Screen:scaleBySize(1)
    local filler = foot_top - y
    if filler > 0 then push(VerticalSpan:new{ width = filler }, filler) end
    if (model.pages or 1) > 1 then
        push(self:foot(m, model, y), m.foot_h + Screen:scaleBySize(1))
    end
    self[1] = FrameContainer:new{ background = Blitbuffer.COLOR_WHITE, bordersize = 0, padding = 0, margin = 0, width = m.w, height = m.h, content }
    UIManager:setDirty(self, function() return "ui", self.dimen end)
    self:loadCovers()
end

--- Fetches the covers that are missing, a few at a time, and puts each in its box.
function Library:loadCovers()
    local generation, i = self.generation, 1
    local holders = self.holders
    local c = self:conn()
    local function step()
        if self.closed or generation ~= self.generation or not holders[i] or not c then return end
        if not self:online() then return end
        local fetched = 0
        while holders[i] and fetched < COVERS_PER_STEP do
            local h = holders[i]
            i = i + 1
            local path = Covers.fetch(c, h.card)
            if path and h.box then
                h.box[1] = Coverimg.widget(path, h.w, h.h)
                fetched = fetched + 1
            end
        end
        if fetched > 0 then UIManager:setDirty(self, function() return "ui", self.dimen end) end
        UIManager:scheduleIn(0.1, step)
    end
    UIManager:scheduleIn(0.3, step)
end

-- ---------------------------------------------------------------- touch

function Library:onTapLibrary(_, ges)
    local x, y = ges.pos.x, ges.pos.y
    for _, hit in ipairs(self.hits or {}) do
        if x >= hit.x and x < hit.x + hit.w and y >= hit.y and y < hit.y + hit.h then
            local ok, err = xpcall(hit.fn, debug.traceback)
            if not ok then
                logger.err("codice: library tap failed:", err)
                UIManager:show(InfoMessage:new{ text = "A biblioteca não conseguiu fazer isso.\n\n" .. core.firstLine(err) })
            end
            return true
        end
    end
    return true
end

function Library:onSwipeLibrary(_, ges)
    if ges.direction == "west" then
        self:turn(1)
    elseif ges.direction == "east" then
        self:turn(-1)
    end
    return true
end

--- Turns the page of the list on top by `step` (1 or -1), if there is one.
function Library:turn(step)
    local view = self.stack[#self.stack]
    local model = self.model
    local pages = model and model.pages or 1
    local page = (model and model.page or view.page or 1) + step
    if page < 1 or page > pages then return end
    view.page = page
    self:refresh()
end

function Library:setChip(id)
    local view = self.stack[#self.stack]
    if (view.chip or "all") == id then return end
    view.chip = id
    view.page = 1
    self:refresh()
end

function Library:setLetter(letter)
    local view = self.stack[#self.stack]
    view.letter = letter
    view.page = 1
    self:refresh()
end

function Library:onHeaderAction(id)
    if id == "search" then
        self:askSearch()
    elseif id == "sort" then
        self:askSort()
    end
end

function Library:askSearch()
    local dialog
    dialog = InputDialog:new{
        title = "Buscar por título ou autor",
        input = "",
        buttons = {{
            { text = "Cancelar", id = "close", callback = function() UIManager:close(dialog) end },
            { text = "Buscar", is_enter_default = true, callback = function()
                local term = dialog:getInputText()
                UIManager:close(dialog)
                if term and term:match("%S") then
                    self:push("works", { spec = { search = term, title = "Busca: " .. term } })
                end
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Library:askSort()
    local view = self.stack[#self.stack]
    if view.kind ~= "works" or not view.spec then return end
    local dialog
    local function choice(label, sort)
        return {{ text = label, callback = function()
            UIManager:close(dialog)
            view.spec.sort = sort
            view.page = 1
            self:refresh()
        end }}
    end
    dialog = ButtonDialog:new{
        title = "Ordenar por",
        title_align = "center",
        buttons = {
            choice("Título", "title"),
            choice("Autor", "author"),
            choice("Mais novas", "recent"),
        },
    }
    UIManager:show(dialog)
end

-- ---------------------------------------------------------------- actions on a work

--- The file to read of a sheet: the last read that is on the device, else the main one that is, else any on the device, else (with a network)
--- the last read or the main one.
local function bestFile(d, online)
    local pick
    for _, f in ipairs(d.files) do
        if f.here then
            if f.last then return f end
            if not pick or (f.primary and not pick.primary) then pick = f end
        end
    end
    if pick then return pick end
    if online then
        for _, f in ipairs(d.files) do
            if f.last then return f end
        end
        for _, f in ipairs(d.files) do
            if f.primary then return f end
        end
        return d.files[1]
    end
    return nil
end

function Library:readBest(d)
    local f = bestFile(d, self:online())
    if not f then
        self.plugin:say("Esta obra não tem um arquivo para abrir.")
        return
    end
    self:openFile(d, f)
end

function Library:openFile(d, f)
    local card = core.withFile(d.card, { id = f.id, format = f.format })
    card.title = d.title or card.title
    self.plugin:openBook(card, function() UIManager:close(self) end)
end

function Library:confirmRemove(d)
    UIManager:show(ConfirmBox:new{
        text = "Remover “" .. tostring(d.title) .. "” do aparelho?\n\nO arquivo sai daqui; o progresso fica guardado no Códice.",
        ok_text = "Remover",
        ok_callback = function()
            local ok, err = pcall(function()
                local idx = shelf()
                local w = idx.works[tostring(d.id)]
                local dir = self.plugin:booksDir()
                for _, f in pairs(w and w.downloaded or {}) do os.remove(dir .. "/" .. f.name) end
                Store.prune()
            end)
            if not ok then logger.warn("codice: removing a book failed:", err) end
            self:refresh()
        end,
    })
end

-- ---------------------------------------------------------------- the widget

function Library:init()
    self.m = measures()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.m.w, h = self.m.h }
    self.ges_events = {
        TapLibrary = { GestureRange:new{ ges = "tap", range = self.dimen } },
        SwipeLibrary = { GestureRange:new{ ges = "swipe", range = self.dimen } },
    }
    self.stack = { { kind = "root", page = 1 } }
    self.letters_h = 2 * Screen:scaleBySize(40) -- the strip of letters of the authors: two lines, until it is drawn once
    self.hits = {}
    self.plugin.library_open = self
    Store.configure(self.plugin:booksDir())
    pcall(Store.prune)
    self:refresh()
end

function Library:onCloseWidget()
    self.closed = true
    if self.plugin.library_open == self then self.plugin.library_open = nil end
    UIManager:setDirty(nil, "full")
end

return Library
