-- Passa a biblioteca (codice/library.lua) por todas as telas com um KOReader de mentira: não prova que o desenho está certo, mas pega erro de
-- digitação, variável nula e tela que quebra com dados de verdade. Rodar na raiz:  luajit tests/library_stub.lua

package.path = "./?.lua;" .. package.path

local failures, count = 0, 0
local function check(cond, label)
    count = count + 1
    if not cond then
        failures = failures + 1
        print("FALHOU " .. label)
    end
end

-- ---------------------------------------------------------------- um KOReader de mentira
local function class(defaults)
    local C = {}
    C.__index = C
    function C:new(t)
        t = t or {}
        setmetatable(t, C)
        if C.init and not t._no_init then C.init(t) end
        return t
    end
    function C:extend(t)
        t = t or {}
        for k, v in pairs(C) do if t[k] == nil and k ~= "__index" then t[k] = v end end
        t.__index = t
        t.new = function(cls, o)
            o = o or {}
            setmetatable(o, t)
            if t.init then t.init(o) end
            return o
        end
        return t
    end
    function C:getSize()
        local w = self.width or (self.dimen and self.dimen.w) or 0
        local h = self.height or (self.dimen and self.dimen.h) or 0
        if self.text then w = w > 0 and w or #tostring(self.text) * 9; h = h > 0 and h or 24 end
        if #self > 0 and w == 0 and h == 0 then
            for _, c in ipairs(self) do
                if type(c) == "table" and c.getSize then
                    local s = c:getSize()
                    w, h = math.max(w, s.w), h + s.h
                end
            end
        end
        return { w = w, h = h }
    end
    for k, v in pairs(defaults or {}) do C[k] = v end
    return C
end

local shown = {}
local function stub(name, value) package.preload[name] = function() return value end end

local Geom = class()
function Geom:new(t) return setmetatable(t or {}, { __index = Geom }) end
function Geom:getSize() return { w = self.w or 0, h = self.h or 0 } end
stub("ui/geometry", Geom)

stub("ffi/blitbuffer", { COLOR_WHITE = 1, COLOR_BLACK = 0, COLOR_DARK_GRAY = 2, new = function() return { getType = function() return 1 end } end })
stub("ui/font", { getFace = function(_, name, size) return { name = name, size = size } end })
stub("device", { screen = { getWidth = function() return 1236 end, getHeight = function() return 1648 end, scaleBySize = function(_, n) return math.floor(n * 1.9) end } })
local Screen = require("device").screen
-- Screen:scaleBySize is called with a colon
Screen.scaleBySize = function(self, n) return math.floor(n * 1.9) end

local widgets = { "ui/widget/buttondialog", "ui/widget/container/centercontainer", "ui/widget/confirmbox", "ui/widget/container/framecontainer",
    "ui/widget/horizontalgroup", "ui/widget/horizontalspan", "ui/widget/infomessage", "ui/widget/container/inputcontainer", "ui/widget/inputdialog",
    "ui/widget/container/leftcontainer", "ui/widget/linewidget", "ui/widget/progresswidget", "ui/widget/textboxwidget", "ui/widget/textwidget",
    "ui/widget/verticalgroup", "ui/widget/verticalspan", "ui/widget/imagewidget" }
for _, name in ipairs(widgets) do stub(name, class()) end
stub("ui/gesturerange", class())

-- the groups add up their children
local function group(horizontal)
    local C = class()
    function C:getSize()
        local w, h = 0, 0
        for _, c in ipairs(self) do
            if type(c) == "table" and c.getSize then
                local s = c:getSize()
                if horizontal then w, h = w + s.w, math.max(h, s.h) else w, h = math.max(w, s.w), h + s.h end
            end
        end
        return { w = w, h = h }
    end
    return C
end
stub("ui/widget/horizontalgroup", group(true))
stub("ui/widget/verticalgroup", group(false))
local Span = class()
function Span:getSize() return { w = self.width or 0, h = self.width or 0 } end
stub("ui/widget/horizontalspan", Span)
stub("ui/widget/verticalspan", Span)
local Tw = class()
function Tw:getSize() return { w = math.min(self.max_width or 99999, #tostring(self.text) * 12), h = 36 } end
stub("ui/widget/textwidget", Tw)
local Tb = class()
function Tb:getSize() return { w = self.width or 100, h = self.height or 80 } end
stub("ui/widget/textboxwidget", Tb)

stub("ui/uimanager", {
    show = function(_, w) shown[#shown + 1] = w end, close = function() end, forceRePaint = function() end, setDirty = function() end,
    scheduleIn = function() end, nextTick = function() end,
})
stub("logger", { err = function(...) print("logger.err", ...) end, warn = function() end, dbg = function() end, info = function() end })
stub("datastorage", { getSettingsDir = function() return "/tmp/codice-stub-settings" end, getDataDir = function() return "/tmp/codice-stub-data" end })
os.execute("mkdir -p /tmp/codice-stub-settings /tmp/codice-stub-data/cache/codice")
os.remove("/tmp/codice-stub-settings/codice_shelf.json")
stub("libs/libkoreader-lfs", {
    attributes = function(path, what)
        local f = io.open(path, "rb")
        if not f then return nil end
        local size = f:seek("end")
        f:close()
        if what == "size" then return size end
        return "file"
    end,
    mkdir = function() end, dir = function() return function() return nil end end,
})
local online = true
stub("ui/network/manager", { isOnline = function() return online end })
stub("infra/sui_core", { makeColoredText = function(spec) return Tw:new(spec) end, CLR_TEXT_SUB = 3 })
stub("ui/renderimage", { renderImageFile = function() return nil end })
stub("ltn12", { sink = { file = function() end } })
stub("luasettings", { open = function() return { readSetting = function() return nil end } end })
stub("socket", { gettime = function() return os.time() end })

-- the network: canned answers
local calls = {}
local answers = {}
stub("codice/http", {
    request = function(url)
        calls[#calls + 1] = url
        for pattern, answer in pairs(answers) do
            if url:find(pattern, 1, true) then return answer.code or 200, answer.data end
        end
        return 404, nil
    end,
    decode = function(text)
        local ok, json = pcall(require, "json")
        return nil
    end,
    encode = function(t)
        local out = {}
        return "{}"
    end,
    last_contact = { ok = true, at = os.time() },
})

-- ---------------------------------------------------------------- the library
local core = require("codice/core")
local Library = require("codice/library")
local Store = require("codice/shelfstore")

local said = {}
local opened = {}
local plugin = {
    connection = function() return { url = "https://codice.test", username = "ana", token = "tok" } end,
    say = function(_, t) said[#said + 1] = t end,
    booksDir = function() return "/tmp/codice-stub-data/books" end,
    openBook = function(_, card) opened[#opened + 1] = card end,
    chooseAndOpen = function(_, card, before) if before then before() end opened[#opened + 1] = card end,
}
os.execute("mkdir -p /tmp/codice-stub-data/books")

answers["/device/categories"] = { data = { data = {
    { id = 1, name = "Ficção", works = 3 }, { id = 2, name = "Ficção científica", parentId = 1, works = 2 }, { id = 3, name = "Terror", parentId = 1, works = 1 },
    { id = 4, name = "Não ficção", works = 1 }, { id = 5, name = "Vazia", works = 0 } } } }
answers["/device/people"] = { data = { data = { { id = 11, name = "Frank Herbert", works = 3 }, { id = 12, name = "Stanisław Lem", works = 1 } }, total = 2, page = 1, pages = 1,
    letters = { { letter = "F", people = 1 }, { letter = "S", people = 1 } } } }
answers["/device/collections?"] = { data = { data = { { id = 21, name = "Duna", workCount = 6 } }, page = 1, total = 1, totalPages = 1 } }
answers["/device/collections/21"] = { data = { collection = { id = 21, name = "Duna" }, continue = { id = 1, title = "Duna", unit = "chapter", position = 1, started = true, begun = true }, works = { { id = 1, title = "Duna", author = "Frank Herbert", coverUrl = "/covers/1", percent = 10, available = true, unit = "chapter", position = 1, started = true },
    { id = 2, title = "Messias", author = "Frank Herbert", coverUrl = "/covers/2", available = true, unit = "chapter", position = 2 } } } }
answers["/device/works"] = { data = { data = { { id = 1, title = "Duna", author = "Frank Herbert", coverUrl = "/covers/1", percentComplete = 42, fileId = 10, format = "epub", fileCount = 1 },
    { id = 2, title = "Solaris", author = "Stanisław Lem", coverUrl = "/covers/2", percentComplete = 0, fileId = 20, format = "epub", fileCount = 1 },
    { id = 3, title = "Absolute Batman #5", author = "Scott Snyder", coverUrl = "/covers/3", percentComplete = 0, fileId = 30, format = "cbz", fileCount = 1,
      collapsed = { collectionId = 21, name = "Absolute Batman", volumes = 0, chapters = 5, oneShots = 0, coverUrl = "/covers/9" } } }, total = 14, page = 1, totalPages = 3 } }
answers["/device/shelf"] = { data = { works = { { id = 1, title = "Duna", author = "Frank Herbert", authors = { { id = 11, name = "Frank Herbert" } }, cover = "/covers/1",
    series = "Duna", seriesIndex = 1, percent = 42, inProgress = true, favorite = false, categories = { { id = 1, name = "Ficção" }, { id = 2, name = "Ficção científica", parentId = 1 } },
    files = { { id = 10, format = "epub", language = "pt", primary = true, last = true, sizeBytes = 900000 }, { id = 11, format = "pdf", language = "en", sizeBytes = 5000000 } } } } } }

-- some books on the shelf, for the offline screens
local idx = Store.index()
local Shelf = require("codice/shelf")
Store.configure("/tmp/codice-stub-data/books")
local f = io.open("/tmp/codice-stub-data/books/10 - Duna.epub", "wb"); f:write("x"); f:close()
Shelf.noteDownload(idx, Shelf.workFrom({ id = 1, title = "Duna", author = "Frank Herbert", authors = { { id = 11, name = "Frank Herbert" } }, cover = "/covers/1",
    series = "Duna", percent = 42, inProgress = true, categories = { { id = 1, name = "Ficção" }, { id = 2, name = "Ficção científica", parentId = 1 } },
    files = { { id = 10, format = "epub", primary = true, last = true } } }), 10, "10 - Duna.epub", 1, 1)

local function open()
    local lib = Library:new{ plugin = plugin }
    return lib
end

local function top(lib) return lib.stack[#lib.stack] end
local function tapRow(lib, i)
    local row = lib.model.rows[i]
    check(row ~= nil, "linha " .. i .. " existe em " .. tostring(lib.model.title))
    if row then row.go() end
end

for _, mode in ipairs({ "online", "offline" }) do
    online = (mode == "online")
    print("-- " .. mode)
    local lib = open()
    check(lib.model.kind == "list" and #lib.model.rows == 7, mode .. ": a raiz tem sete linhas (com Mais)")
    check((lib.model.notice ~= nil) == (mode == "offline"), mode .. ": aviso só sem conexão")
    check(#lib.hits > 0, mode .. ": a raiz tem lugares para tocar")

    tapRow(lib, 1) -- categories
    check(lib.model.title == "Categorias" and #lib.model.rows >= 1, mode .. ": categorias")
    tapRow(lib, 1) -- Ficção (has children)
    check(lib.model.title == "Ficção", mode .. ": entrou em Ficção")
    check(lib.model.rows[1].title:find("Todas as obras de Ficção", 1, true) ~= nil, mode .. ": primeira linha leva a todas as obras da categoria")
    lib.model.rows[1].go()
    check(lib.model.kind == "grid", mode .. ": categoria abre a grade")
    check(#lib.model.cards >= 1, mode .. ": há obras")
    check(lib.model.chips ~= nil, mode .. ": filtros na grade")
    lib:setChip("downloaded")
    check(lib.model.chip == "downloaded" and #lib.model.cards == 1, mode .. ": só as baixadas")
    lib:setChip("reading")
    lib:setChip("all")
    lib:onHeaderAction("sort")
    lib:turn(1); lib:turn(-1)
    -- the sheet
    local detail_view
    for _, hit in ipairs(lib.hits) do
        if hit.y > 150 and hit.w > 200 and hit.h > 300 then detail_view = hit; break end
    end
    check(detail_view ~= nil, mode .. ": uma capa para tocar")
    if detail_view then detail_view.fn() end
    check(lib.model.kind == "detail" or lib.model.kind == "list", mode .. ": abriu a ficha")
    if lib.model.kind == "detail" then
        check(lib.model.detail.title == "Duna", mode .. ": a ficha é de Duna")
        check(#lib.model.detail.files >= 1, mode .. ": a ficha lista os arquivos")
        lib:readBest(lib.model.detail)
        check(#opened >= 1 and opened[#opened].fileId == 10, mode .. ": ler abre o arquivo que está no aparelho")
    end
    while #lib.stack > 1 do lib:back() end
    check(lib.model.title == "Biblioteca", mode .. ": voltou à raiz")

    tapRow(lib, 2) -- people
    check(lib.model.title == "Autores" and #lib.model.rows >= 1, mode .. ": autores")
    check(lib.model.letters ~= nil and #lib.model.letters >= 1, mode .. ": letras")
    lib:setLetter(lib.model.letters[1])
    tapRow(lib, 1)
    check(lib.model.kind == "grid", mode .. ": autor abre a grade")
    while #lib.stack > 1 do lib:back() end

    tapRow(lib, 3) -- collections / series
    check(lib.model.kind == "list", mode .. ": séries e coleções")
    if #lib.model.rows >= 1 then
        tapRow(lib, 1)
        check(lib.model.kind == "series", mode .. ": a série ou coleção abre a página da série")
    end
    while #lib.stack > 1 do lib:back() end

    tapRow(lib, 4) -- formats
    check(lib.model.kind == "list" and #lib.model.rows >= 1, mode .. ": formatos")
    tapRow(lib, 1)
    check(lib.model.kind == "grid", mode .. ": formato abre a grade")
    while #lib.stack > 1 do lib:back() end

    tapRow(lib, 5) -- device
    check(lib.model.kind == "grid" and #lib.model.cards == 1 and lib.model.chips == nil, mode .. ": no aparelho: uma obra, sem filtros")
    while #lib.stack > 1 do lib:back() end

    tapRow(lib, 6) -- all
    check(lib.model.kind == "grid", mode .. ": todas as obras")
    while #lib.stack > 1 do lib:back() end
    lib:push("works", { spec = { search = "duna", title = "Busca: duna" } })
    check(lib.model.kind == "grid", mode .. ": busca")
end

-- the server answers with an error: the list falls back to the shelf, with the notice
online = true
answers["/device/works"] = { code = 500 }
local libf = open()
libf:push("works", { spec = { title = "Todas as obras" } })
check(libf.model.kind == "grid" and libf.model.notice ~= nil, "erro do servidor: cai para a prateleira e avisa")
check(#libf.model.cards == 1, "erro do servidor: mostra o que está no aparelho")
-- no connection of this reader
local lone = Library:new{ plugin = setmetatable({ connection = function() return nil end }, { __index = plugin }) }
check(lone.model ~= nil, "sem conexão cadastrada a biblioteca ainda abre")
-- removing a book from the device
local libr = open()
libr:push("detail", { card = { id = 1, title = "Duna", cover = "/covers/1" } })
check(libr.model.kind == "detail" and libr.model.detail.can_remove, "a ficha oferece remover")
libr:confirmRemove(libr.model.detail)
local confirm = shown[#shown]
check(confirm and confirm.ok_callback ~= nil, "pede confirmação antes de remover")
if confirm and confirm.ok_callback then confirm.ok_callback() end
check(io.open("/tmp/codice-stub-data/books/10 - Duna.epub", "rb") == nil, "o arquivo saiu do aparelho")
check(next(Store.index().works) == nil, "e saiu da prateleira")

-- a series in a grid opens the series, with all its chapters
online = true
answers["/device/works"] = { data = { data = { { id = 3, title = "Absolute Batman #5", author = "Scott Snyder", coverUrl = "/covers/3", fileId = 30, format = "cbz", fileCount = 1,
    collapsed = { collectionId = 21, name = "Absolute Batman", volumes = 0, chapters = 5, coverUrl = "/covers/9" } } }, total = 1, page = 1, totalPages = 1 } }
local libs = open()
libs:push("works", { spec = { formatGroup = "comics", title = "Quadrinhos" } })
check(libs.model.cards[1].title == "Absolute Batman" and libs.model.cards[1].subtitle == "5 capítulos", "a série aparece como série, com o que tem")
local series_hit
for _, hit in ipairs(libs.hits) do
    if hit.y > 150 and hit.w > 200 and hit.h > 300 then series_hit = hit; break end
end
series_hit.fn()
check(libs.model.kind == "series" and #libs.model.rows == 2 and libs.model.title == "Duna", "tocar na série abre a página dela, com os capítulos")
check(libs.model.series.go_on ~= nil and libs.model.series.go_on.text:find("Continuar", 1, true) ~= nil, "a página da série tem o botão de continuar")
opened = {}
for _, hit in ipairs(libs.hits) do if hit.w > 600 and hit.h > 50 and hit.y > 500 then hit.fn(); break end end
check(#opened == 1 and opened[1].fileCount == 2, "tocar num capítulo o abre (perguntando o arquivo se houver mais de um)")
-- the list of collections opens the works of the collection (the answer is { collection, works })
local libc = open()
libc:push("collections")
libc.model.rows[1].go()
check(libc.model.kind == "series" and #libc.model.rows == 2, "uma coleção da lista abre a página dela, com as obras")
-- the authors: a letter at a time, as many rows as fit, and the first letter is the one that opens
calls = {}
local libp = open()
libp:push("people")
check(libp.model.letter == "F", "os autores abrem na primeira letra")
local asked_limit = false
for _, u in ipairs(calls) do if u:find("limit=", 1, true) and u:find("letter=F", 1, true) then asked_limit = true end end
check(asked_limit, "pede só o que cabe na tela, da letra F")
check(libp.letters_h and libp.letters_h > 0, "o espaço das letras é descontado")

-- the tabs: each opens its own screen
answers["/device/notes"] = { data = { data = { { id = 1, workId = 1, workTitle = "Duna", workAuthor = "Frank Herbert", quote = "Uma frase marcada.", body = "" },
    { id = 2, workId = 2, workTitle = "Solaris", workAuthor = "Stanisław Lem", quote = "", body = "Minha nota." } }, total = 2 } }
online = true
local libn = Library:new{ plugin = plugin, start = { kind = "notes", title = "Anotações", page = 1 }, action_id = "codice_notes" }
check(libn.model.kind == "list" and #libn.model.rows == 2 and libn.model.rows[1].multiline, "anotações: duas linhas de várias linhas")
libn.model.rows[1].go()
check(libn.model.kind == "detail" or libn.model.kind == "list", "tocar numa anotação abre a obra dela")
online = false
local libno = Library:new{ plugin = plugin, start = { kind = "notes", title = "Anotações", page = 1 }, action_id = "codice_notes" }
check(libno.model.empty == "As anotações precisam de conexão." and libno.model.notice ~= nil, "anotações sem conexão: avisa")
online = true
answers["/device/works"] = { data = { data = { { id = 1, title = "Duna", author = "Frank Herbert", coverUrl = "/covers/1", percentComplete = 42, fileId = 10, format = "epub", fileCount = 1 } }, total = 1, page = 1, totalPages = 1 } }
calls = {}
local libr = Library:new{ plugin = plugin, start = { kind = "works", spec = { inProgress = true, title = "Em leitura" }, page = 1 }, action_id = "codice_reading" }
check(libr.model.kind == "grid" and libr.model.chips == nil and libr.model.title == "Em leitura", "em leitura: grade sem filtros")
local asked = false
for _, u in ipairs(calls) do if u:find("inProgress=true", 1, true) and not u:find("sort=", 1, true) then asked = true end end
check(asked, "em leitura pede o que se lê, na ordem do servidor")
local libf = Library:new{ plugin = plugin, start = { kind = "works", spec = { favorite = true, title = "Favoritos" }, page = 1 }, action_id = "codice_favorites" }
check(libf.model.kind == "grid" and libf.model.chips == nil, "favoritos: grade sem filtros")
-- the root of a tab has no way back; the "more" screen lists what is not in the bar
check(#libr.stack == 1, "a raiz de uma aba")
libr:back()
check(#libr.stack == 1, "voltar na raiz de uma aba não faz nada")
local libm = open()
libm:push("more")
check(libm.model.kind == "list" and #libm.model.rows == 4, "mais: arquivos, configurações, energia e atualizar o plugin")

-- a long series: the first page has the cover and the button, the next ones only rows, and there is a way to jump
local long = {}
for n = 1, 60 do long[#long + 1] = { id = 300 + n, title = "Mangá #" .. n, author = "A", coverUrl = "/c/" .. n, percent = 0, available = true, unit = "chapter", position = n } end
answers["/device/collections/77"] = { data = { collection = { id = 77, name = "Mangá longo" }, continue = { id = 301, title = "Mangá #1", unit = "chapter", position = 1, begun = false }, works = long } }
online = true
local libl = open()
libl:push("series", { id = 77, title = "Mangá longo" })
local m1 = libl.model
check(m1.kind == "series" and m1.pages > 2 and m1.total == 60 and not m1.compact, "série longa: várias páginas, a primeira com a capa")
check(#m1.rows < 60 and m1.series.go_on ~= nil, "a primeira página não traz tudo e tem o botão")
libl:turn(1)
local m2 = libl.model
check(m2.page == 2 and m2.compact and #m2.rows > #m1.rows, "as seguintes são só linhas, e cabem mais")
check(m2.from == #m1.rows + 1 and m2.rows[1].label == "Cap. " .. (#m1.rows + 1), "continua de onde a primeira parou")
libl:askJump(m2)
local jump = shown[#shown]
check(jump and #jump.buttons >= 3, "o diálogo de ir para tem as partes")
jump.buttons[2][1].callback()
check(libl.model.page > 1 and libl.model.rows[1].label ~= "Cap. 1", "ir para a segunda parte abre uma página mais adiante")
local last = libl
for _ = 1, 50 do last:turn(1) end
check(last.model.page == last.model.pages and last.model.rows[#last.model.rows].label == "Cap. 60", "a última página termina no último capítulo")

-- opening a book from the library keeps where the person was, to come back to it
local Data = require("codice/data")
Data.return_to = nil
local libb = open()
libb:push("series", { id = 77, title = "Mangá longo" })
libb:openChapter({ id = 301, title = "Mangá #1", fileCount = 2 })
check(Data.return_to ~= nil and #Data.return_to.stack == 2 and Data.return_to.stack[2].kind == "series", "ao abrir um capítulo, a biblioteca guarda onde estava")
local back = Library:new{ plugin = plugin, restore = Data.return_to.stack, action_id = Data.return_to.action_id }
check(back.model.kind == "series" and #back.stack == 2, "e volta para a mesma página da série")
-- a list of three or fewer is one line: bigger covers
answers["/device/works"] = { data = { data = { { id = 1, title = "Duna", author = "F", coverUrl = "/c/1", percentComplete = 42, fileId = 10, format = "epub", fileCount = 1 } }, total = 1, page = 1, totalPages = 1 } }
local few = Library:new{ plugin = plugin, start = { kind = "works", spec = { favorite = true, title = "Favoritos" }, page = 1 }, action_id = "codice_favorites" }
check(few.model.total == 1, "o total da lista vai no modelo")

print(string.format("%d verificações da biblioteca, %d falhas", count, failures))
os.exit(failures == 0 and 0 or 1)
