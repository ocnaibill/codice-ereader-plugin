--[[--
Diagnóstico: os testes do protótipo (issue ocnaibill/codice#327), mantidos num submenu para conferir um aparelho novo.

Responde, no aparelho, às perguntas que decidem se dá para fazer o leitor sem fork:
  1. um plugin fala HTTPS com a instância, com o acesso que o Códice já gera?
  2. a configuração do OPDS e do KOSync se aplica ao vivo, sem reiniciar?
  3. dá para desenhar capas numa lista própria?
  4. o plugin recebe os eventos de anotação do leitor?

Nada aqui grava senha nem token: os dados da instância vêm do `settings/opds.lua` que o Códice já gera. Tudo o que o plugin faz fica
em `codice_proto.log`, na pasta do KOReader.
]]--

local Blitbuffer = require("ffi/blitbuffer")
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
local LuaSettings = require("luasettings")
local NetworkMgr = require("ui/network/manager")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local ltn12 = require("ltn12")
local logger = require("logger")
local socket = require("socket")
local socketutil = require("socketutil")
local http = require("socket.http")
local Screen = Device.screen

local LOG_FILE = DataStorage:getDataDir() .. "/codice_proto.log"
local CACHE_DIR = DataStorage:getDataDir() .. "/cache/codice_proto"
local PROTO_TITLE = "Códice (protótipo)"

local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local line = os.date("%Y-%m-%d %H:%M:%S") .. "  " .. table.concat(parts, " ")
    logger.info("codice-proto:", line)
    local f = io.open(LOG_FILE, "a")
    if f then
        f:write(line, "\n")
        f:close()
    end
    return line
end

-- ---------------------------------------------------------------- the instance

--- The server the Códice generated in settings/opds.lua: the one with an /opds/ address and a user.
local function findServer()
    local settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/opds.lua")
    for _, server in ipairs(settings:readSetting("servers") or {}) do
        if server.url and server.url:find("/opds/", 1, true) and server.username and server.username ~= "" and server.title ~= PROTO_TITLE then
            return server
        end
    end
    return nil
end

local function originOf(url)
    return url:match("^(https?://[^/]+)")
end

local function feedUrl(server, name)
    return (server.url:gsub("/catalog/?$", "")) .. "/" .. name
end

--- GET with the access of the server. Returns code, body (or nil, error).
local function get(url, server, sink)
    local chunks = {}
    socketutil:set_timeout(15, 45)
    local code, _, status = socket.skip(1, http.request{
        url = url,
        method = "GET",
        user = server.username,
        password = server.password,
        sink = sink or socketutil.table_sink(chunks),
        headers = { ["User-Agent"] = "Codice-proto/0" },
    })
    socketutil:reset_timeout()
    if type(code) ~= "number" then return nil, tostring(code or status) end
    return code, table.concat(chunks)
end

local function entriesOf(body)
    local out = {}
    for entry in body:gmatch("<entry>(.-)</entry>") do
        local title = entry:match("<title>(.-)</title>") or "?"
        local thumb
        for tag in entry:gmatch("<link[^>]*>") do
            if tag:find("image/thumbnail", 1, true) then thumb = tag:match('href="([^"]+)"') end
        end
        out[#out + 1] = {
            title = (title:gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&#39;", "'")),
            thumb = thumb and thumb:gsub("&amp;", "&") or nil,
        }
    end
    return out
end

-- ---------------------------------------------------------------- a list with covers

local CoverList = InputContainer:extend{
    modal = true,
    rows = nil, -- { { title =, file = } }
}

function CoverList:init()
    local width, height = Screen:getWidth(), Screen:getHeight()
    local thumb_h = Screen:scaleBySize(120)
    local thumb_w = math.floor(thumb_h * 2 / 3)
    local gap = Screen:scaleBySize(12)
    local list = VerticalGroup:new{ align = "left" }
    list[#list + 1] = TextBoxWidget:new{
        text = PROTO_TITLE .. ": capas numa lista (toque para fechar)",
        face = Font:getFace("cfont", 18),
        width = width - 2 * gap,
    }
    list[#list + 1] = VerticalSpan:new{ width = gap }
    for _, row in ipairs(self.rows) do
        local cover
        if row.file then
            cover = ImageWidget:new{ file = row.file, width = thumb_w, height = thumb_h, scale_factor = 0 }
        else
            cover = VerticalSpan:new{ width = thumb_h } -- no cover: keeps the height of the row
        end
        list[#list + 1] = HorizontalGroup:new{
            align = "center",
            cover,
            HorizontalSpan:new{ width = gap },
            TextBoxWidget:new{ text = row.title, face = Font:getFace("cfont", 22), width = width - thumb_w - 3 * gap },
        }
        list[#list + 1] = VerticalSpan:new{ width = gap }
    end
    self.ges_events.TapClose = { GestureRange:new{ ges = "tap", range = Geom:new{ x = 0, y = 0, w = width, h = height } } }
    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = gap,
        width = width,
        height = height,
        list,
    }
end

function CoverList:onTapClose()
    UIManager:close(self)
    return true
end

function CoverList:onShow()
    UIManager:setDirty(self, function() return "ui", self[1].dimen end)
end

function CoverList:onCloseWidget()
    UIManager:setDirty(nil, "full")
end

-- ---------------------------------------------------------------- the plugin

local Diag = { annotation_events = 0 }

function Diag.say(self, text)
    UIManager:show(InfoMessage:new{ text = text, timeout = 15 })
end


function Diag.testEnvironment(self)
    local Version = require("version")
    local lines = {
        "KOReader: " .. tostring(Version:getCurrentRevision()),
        "Aparelho: " .. tostring(Device.model) .. (Device:isKindle() and " (Kindle)" or ""),
        "Tela: " .. Screen:getWidth() .. "x" .. Screen:getHeight(),
        "Dentro de um livro: " .. tostring(self.ui.document ~= nil),
        "ui.opds existe: " .. tostring(self.ui.opds ~= nil),
        "ui.kosync existe: " .. tostring(self.ui.kosync ~= nil) .. " (só dentro de um livro)",
        "Servidor do Códice em opds.lua: " .. tostring(findServer() and findServer().url or "nenhum"),
    }
    Diag.say(self, log("ambiente | " .. table.concat(lines, " | ")):gsub(" | ", "\n"))
end

function Diag.testConnection(self)
    local server = findServer()
    if not server then return Diag.say(self, "Nenhum servidor do Códice em settings/opds.lua. Copie o opds.lua que o Códice gera.") end
    NetworkMgr:runWhenOnline(function()
        local started = socket.gettime()
        local code, body = get(feedUrl(server, "recent"), server)
        local took = socket.gettime() - started
        if not code then
            return Diag.say(self, log("1 conexão FALHOU: " .. tostring(body)))
        end
        local n = #entriesOf(body)
        Diag.say(self, log(string.format("1 conexão: HTTP %s em %.1f s, %d bytes, %d entradas no feed 'recentes'", code, took, #body, n)))
    end)
end

function Diag.testLiveConfig(self)
    local server = findServer()
    if not server then return Diag.say(self, "Nenhum servidor do Códice em settings/opds.lua.") end
    local report = {}
    -- OPDS: the instance of the plugin keeps its servers in memory; the entry is added to that table and the file is written
    local opds = self.ui.opds
    if opds then
        opds:loadSettings()
        local found
        for _, s in ipairs(opds.servers) do
            if s.title == PROTO_TITLE then found = s end
        end
        if not found then
            table.insert(opds.servers, { title = PROTO_TITLE, url = server.url, username = server.username, password = server.password })
            opds.updated = true
            opds.settings:flush()
            opds.updated = nil
        end
        report[#report + 1] = "OPDS: a entrada '" .. PROTO_TITLE .. "' " .. (found and "já existia" or "foi acrescentada") ..
            ". Abra Catálogo OPDS SEM reiniciar o KOReader: ela deve estar na lista."
    else
        report[#report + 1] = "OPDS: ui.opds não existe aqui."
    end
    -- KOSync: its settings table is read at every call (custom_server, username, userkey), so changing the table is live
    local kosync = self.ui.kosync
    if kosync and kosync.settings then
        report[#report + 1] = "KOSync: servidor atual = " .. tostring(kosync.settings.custom_server) ..
            " (lido a cada chamada; mudar kosync.settings vale na hora)"
    else
        report[#report + 1] = "KOSync: só existe dentro de um livro. Abra um livro e repita para ver o servidor atual."
    end
    Diag.say(self, log("2 config ao vivo | " .. table.concat(report, " | ")):gsub(" | ", "\n"))
end

function Diag.testCovers(self)
    local server = findServer()
    if not server then return Diag.say(self, "Nenhum servidor do Códice em settings/opds.lua.") end
    NetworkMgr:runWhenOnline(function()
        local started = socket.gettime()
        local code, body = get(feedUrl(server, "recent"), server)
        if not code or code ~= 200 then return Diag.say(self, log("3 capas: o feed falhou: " .. tostring(code or body))) end
        os.execute("mkdir -p '" .. CACHE_DIR .. "'")
        local origin = originOf(server.url)
        local rows, fetched, failed = {}, 0, 0
        for i, entry in ipairs(entriesOf(body)) do
            if i > 6 then break end
            local row = { title = entry.title }
            if entry.thumb then
                local href = entry.thumb
                local url = href:find("^https?://") and href or (origin .. (href:sub(1, 1) == "/" and "" or "/") .. href)
                local path = CACHE_DIR .. "/cover" .. i .. ".jpg"
                local handle = io.open(path, "wb")
                if handle then
                    local c = get(url, server, ltn12.sink.file(handle))
                    if c == 200 then
                        row.file = path
                        fetched = fetched + 1
                    else
                        failed = failed + 1
                    end
                end
            end
            rows[#rows + 1] = row
        end
        log(string.format("3 capas: %d baixadas, %d falharam, em %.1f s; abrindo a lista", fetched, failed, socket.gettime() - started))
        if #rows == 0 then return Diag.say(self, "O feed não trouxe nenhuma entrada.") end
        UIManager:show(CoverList:new{ rows = rows })
    end)
end

function Diag.testAnnotations(self)
    Diag.say(self, log("4 anotações: o plugin está ouvindo. Abra um livro, destaque um trecho e depois veja o log (item 5). Eventos até agora: " ..
        (self.annotation_events or 0)))
end

--- Fired by the reader when a highlight, note or bookmark is created, changed or removed.
function Diag.onAnnotationsModified(self, items)
    self.annotation_events = (self.annotation_events or 0) + 1
    local first = type(items) == "table" and items[1] or nil
    local keys = {}
    if type(first) == "table" then
        for k in pairs(first) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
    end
    log(string.format("4 anotações: evento %d, %d item(ns); campos do primeiro: %s", self.annotation_events,
        type(items) == "table" and #items or 0, table.concat(keys, ",")))
end

function Diag.showLog(self)
    local f = io.open(LOG_FILE, "r")
    local text = f and f:read("*a") or "(vazio)"
    if f then f:close() end
    UIManager:show(TextViewer:new{ title = "codice_proto.log", text = text })
end
function Diag.menu(plugin)
    return {
            { text = "0. Ambiente", callback = function() Diag.testEnvironment(plugin) end },
            { text = "1. Conexão com a instância (HTTPS)", callback = function() Diag.testConnection(plugin) end },
            { text = "2. Configuração ao vivo (OPDS e KOSync)", callback = function() Diag.testLiveConfig(plugin) end },
            { text = "3. Capas numa lista", callback = function() Diag.testCovers(plugin) end },
            { text = "4. Eventos de anotação (veja o log)", callback = function() Diag.testAnnotations(plugin) end },
            { text = "5. Ver o log", callback = function() Diag.showLog(plugin) end },
        }
end

return Diag
