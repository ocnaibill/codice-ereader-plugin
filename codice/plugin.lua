--[[--
O Códice dentro do plugin: conecta o leitor a uma instância do Códice por um código aprovado no site e mantém no aparelho a configuração do
catálogo (OPDS) e da sincronização de progresso (KOSync). Issue ocnaibill/codice#327, DEC-194.

Este arquivo é um MÓDULO que o plugin que o carrega (o SimpleUI, no `main.lua`) registra em cada tela principal do KOReader (o gerenciador
de arquivos e o leitor): `require("codice/plugin").install(self.ui)`. O módulo ouve os eventos, põe o menu "Códice" e abre a tela antiga do
Códice. Fica separado do código do SimpleUI para que as atualizações dele entrem sem conflito.
]]--

local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local NetworkMgr = require("ui/network/manager")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local md5 = require("ffi/sha2").md5

local core = require("codice/core")
local Data = require("codice/data")
local Store = require("codice/shelfstore")
local api = require("codice/http")
local Diag = require("codice/diag")
local Pairing = require("codice/pairing")
local Home = require("codice/home")
local Update = require("codice/update")
local lfs = require("libs/libkoreader-lfs")
local ltn12 = require("ltn12")
local util = require("util")

--- Runs `fn` so that an error is shown to the person and written to the log with its traceback (crash.log), instead of closing KOReader: an
--- error nobody catches in an event ends the program. `what` says what was being done ("abrir o livro").
local function guarded(what, fn)
    return function(...)
        local args = table.pack(...)
        local ok, err = xpcall(function() return fn(table.unpack(args, 1, args.n)) end, debug.traceback)
        if not ok then
            logger.err("codice: could not " .. what .. ":", err)
            UIManager:show(InfoMessage:new{ text = "O Códice não conseguiu " .. what .. ".\n\n" .. core.firstLine(err) })
        end
    end
end

local SYNC_EVERY = 6 * 3600 -- the configuration is asked again at most this often, when the network comes back
local UPDATE_EVERY = 24 * 3600 -- and a newer plugin is looked for at most this often (and the person is asked once for each version)

local Codice = WidgetContainer:extend{
    name = "codice",
    is_doc_only = false,
}

function Codice:init()
    self.settings_file = DataStorage:getSettingsDir() .. "/codice.lua"
    self.ui.menu:registerToMainMenu(self)
    -- The first screen of the plugin is the home of the SimpleUI (which starts the reader on it and takes it back when a book is closed).
    -- This older screen of the Códice stays for whoever asks for it: when it is turned on, it opens over the file manager at the start and
    -- every time a book is closed.
    if self.ui.name ~= "ReaderUI" and not self.ui.document and self:connection() and self:autostart() then
        UIManager:nextTick(function()
            local ok, err = pcall(self.showHome, self, nil, true)
            if not ok then logger.warn("codice: opening the home failed:", err) end
        end)
    end
end

--- Whether the older home of the Códice opens by itself (off unless the person turned it on: the SimpleUI has the first screen).
function Codice:autostart()
    return self:store():readSetting("autostart") == true
end

function Codice:setAutostart(on)
    self:store():saveSetting("autostart", on and true or false)
    self:store():flush()
end

-- ---------------------------------------------------------------- what is kept

function Codice:store()
    if not self._store then self._store = LuaSettings:open(self.settings_file) end
    return self._store
end

--- { url, username, token, etag, synced_at } or nil when this reader is not connected.
function Codice:connection()
    local c = self:store():readSetting("connection")
    if type(c) == "table" and c.url and c.username and c.token then return c end
    return nil
end

function Codice:say(text, timeout)
    UIManager:show(InfoMessage:new{ text = text, timeout = timeout })
end

-- ---------------------------------------------------------------- applying the configuration

function Codice:applyConfig(cfg)
    local c = self:connection()
    if not c or type(cfg) ~= "table" then return false end
    if not core.pluginMeets(cfg.minPlugin) then
        self:say("Esta versão do Códice precisa de um plugin mais novo (" .. tostring(cfg.minPlugin) .. " ou mais). Atualize o plugin no repositório codice-ereader-plugin.")
        return false
    end
    -- the catalog: through the plugin of OPDS when it is loaded (it keeps its list in memory), else in its file
    local opds = self.ui.opds
    if opds then
        opds:loadSettings()
        if core.upsertOpds(opds.servers, cfg, c.username, c.token) then
            opds.updated = true
            opds.settings:flush()
            opds.updated = nil
        end
    else
        local file = LuaSettings:open(DataStorage:getSettingsDir() .. "/opds.lua")
        local servers = file:readSetting("servers", {})
        if core.upsertOpds(servers, cfg, c.username, c.token) then file:flush() end
    end
    -- the sync of progress: see kosyncSettings for where it lives
    local settings, save = self:kosyncSettings()
    core.applyKosync(settings, cfg, c.username, md5(c.token))
    save()
    self:store():saveSetting("features", type(cfg.features) == "table" and cfg.features or {})
    self:store():flush()
    return true
end

--- The class of the KOSync plugin, when KOReader has it loaded in this run; nil otherwise.
local function kosyncClass()
    local ok, PluginLoader = pcall(require, "pluginloader")
    if not ok or type(PluginLoader) ~= "table" then return nil end
    local done, enabled = pcall(PluginLoader.loadPlugins, PluginLoader)
    if not done or type(enabled) ~= "table" then return nil end
    for _, plugin in ipairs(enabled) do
        if plugin.name == "kosync" then return plugin end
    end
    return nil
end

--- The settings of KOSync to change and the way to save them: `settings, save`. KOSync reads its file once per run, into an object of the class that
--- every book after the first one reuses (and writes back when it is flushed), so changing only the file, outside a book, leaves it with the user
--- that was there: the next book is synced as them, and the old settings go back over the file. Inside a book it is the instance's table; outside,
--- that object when the plugin already loaded it; and the file only when it did not.
function Codice:kosyncSettings()
    local kosync = self.ui.kosync
    if kosync and kosync.settings then
        return kosync.settings, function()
            kosync.updated = true
            if kosync.settings_obj then kosync.settings_obj:flush() end
        end
    end
    local class = kosyncClass()
    local obj = class and class.settings_obj
    if not obj then obj = LuaSettings:open(DataStorage:getSettingsDir() .. "/kosync.lua") end
    return obj:readSetting("settings", {}), function() obj:flush() end
end

--- Puts the sync of progress back on the user this reader is connected as, when something left it on another (an access that was replaced, a file
--- written outside a book before this was handled): only when its server is this Códice's. Returns whether it changed anything.
function Codice:healKosync()
    local c = self:connection()
    if not c then return false end
    local settings, save = self:kosyncSettings()
    local key = md5(c.token)
    if not core.kosyncIsStale(settings, c.url, c.username, key) then return false end
    settings.username, settings.userkey = c.username, key
    save()
    logger.info("codice: the sync of progress was set for another user; it is " .. c.username .. " again")
    return true
end

--- Asks the instance for its configuration and applies what changed. `silent`: say nothing unless something changed or went wrong.
function Codice:syncConfig(silent)
    local c = self:connection()
    if not c then
        if not silent then self:say("Este leitor ainda não está conectado a um Códice. Use Códice → Conectar.") end
        return
    end
    NetworkMgr:runWhenOnline(function()
        local headers = {}
        if c.etag and c.etag ~= "" then headers["If-None-Match"] = c.etag end
        local code, data, response_headers = api.request(c.url .. "/device/config", { user = c.username, password = c.token, headers = headers })
        if not code then
            if not silent then self:say("Não consegui falar com " .. c.url .. ".\n" .. tostring(data)) end
            return
        end
        c.synced_at = os.time()
        if code == 304 then
            self:store():saveSetting("connection", c)
            self:store():flush()
            if not silent then self:say("A configuração do Códice já está em dia.", 5) end
        elseif code == 200 and type(data) == "table" then
            c.etag = response_headers and response_headers.etag or c.etag
            self:store():saveSetting("connection", c)
            if self:applyConfig(data) then
                if silent then Notification:notify("Configuração do Códice atualizada.") else self:say("Configuração do Códice atualizada.", 5) end
            end
        elseif code == 401 then
            self:say("O Códice não reconhece mais este acesso (ele pode ter sido removido em Aplicativos). Conecte de novo em Códice → Conectar.")
        elseif not silent then
            self:say("O servidor respondeu " .. tostring(code) .. " ao pedir a configuração.")
        end
    end)
end

--- Called by the pairing when the person approved: keeps the access and applies the configuration that came with it.
function Codice:onPaired(url, data)
    self:store():saveSetting("connection", { url = url, username = data.username, token = data.token, token_id = data.tokenId, synced_at = os.time() })
    self:store():flush()
    -- the first time this reader is connected, the home is the Códice's (once: later it is the person's, and the menu has the entry to redo it)
    local mounted = false
    if not self:store():readSetting("home_mounted") then
        local ok, done = pcall(self.mountHome, self)
        if ok and done then
            mounted = true
            self:store():saveSetting("home_mounted", true)
            self:store():flush()
        elseif not ok then
            logger.warn("codice: mounting the home failed:", done)
        end
    end
    if self:applyConfig(data.config) then
        self:say(core.pairedNotice(data.username, mounted, self.ui.document ~= nil))
    end
end

function Codice:disconnect()
    local c = self:connection()
    if not c then return end
    local function drop(servers)
        for i = #servers, 1, -1 do
            if servers[i].url and servers[i].url:find(c.url, 1, true) == 1 then table.remove(servers, i) end
        end
    end
    if self.ui.opds then
        self.ui.opds:loadSettings()
        drop(self.ui.opds.servers)
        self.ui.opds.updated = true
        self.ui.opds.settings:flush()
        self.ui.opds.updated = nil
    else
        local file = LuaSettings:open(DataStorage:getSettingsDir() .. "/opds.lua")
        drop(file:readSetting("servers", {}))
        file:flush()
    end
    local function clear(settings)
        if settings.custom_server and settings.custom_server:find(c.url, 1, true) == 1 then
            settings.custom_server, settings.username, settings.userkey = nil, nil, nil
        end
    end
    local settings, save = self:kosyncSettings()
    clear(settings)
    save()
    self:store():delSetting("connection")
    self:store():flush()
    self:say("Este leitor foi desconectado do Códice.\nPara tirar o acesso também no servidor, remova-o em Minha conta → Aplicativos, no site.")
end


-- ---------------------------------------------------------------- the home, the books and the updates

--- Asks the server for the home. `done(data)` gets the answer, or nil and a sentence for the person.
function Codice:fetchHome(done)
    local c = self:connection()
    if not c then return done(nil, "Este leitor ainda não está conectado a um Códice. Use Códice → Conectar.") end
    NetworkMgr:runWhenOnline(function()
        local code, data = api.request(c.url .. "/device/home", { user = c.username, password = c.token })
        if not code then return done(nil, "Não consegui falar com " .. c.url .. ".\n" .. tostring(data)) end
        if code == 401 then return done(nil, "O Códice não reconhece mais este acesso (ele pode ter sido removido em Aplicativos). Conecte de novo.") end
        if code == 404 then return done(nil, "Este Códice ainda não tem a tela inicial para leitores. Peça a quem cuida dele para atualizar.") end
        if code ~= 200 or type(data) ~= "table" then return done(nil, "O servidor respondeu " .. tostring(code) .. " ao pedir a tela inicial.") end
        done(data)
    end)
end

local function homeCacheFile()
    return DataStorage:getDataDir() .. "/cache/codice/home.json"
end

--- The last home the server sent, kept to show at once when the reader starts (the network may be off or slow).
function Codice:loadHomeCache()
    local f = io.open(homeCacheFile(), "rb")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return api.decode(text)
end

function Codice:saveHomeCache(data)
    lfs.mkdir(DataStorage:getDataDir() .. "/cache")
    lfs.mkdir(DataStorage:getDataDir() .. "/cache/codice")
    local f = io.open(homeCacheFile(), "wb")
    if f then
        f:write(api.encode(data))
        f:close()
    end
end

--- Asks again, quietly, and redraws the open home when something changed.
function Codice:refreshHome()
    local c = self:connection()
    if not c or not self.home_open or not NetworkMgr:isOnline() then return end
    local code, data = api.request(c.url .. "/device/home", { user = c.username, password = c.token })
    if code ~= 200 or type(data) ~= "table" or not self.home_open then return end
    if api.encode(data) ~= api.encode(self.home_open.data) then
        self:saveHomeCache(data)
        self.home_open:setData(data)
    end
end

--- Shows the home (or draws it again, when `home` is the one already open). `quiet`: the reader just started or a book was closed; show
--- the last one at once and refresh it only if the network is already on, never ask for Wi-Fi.
function Codice:showHome(home, quiet)
    if quiet then
        if self.home_open then return end
        local cached = self:loadHomeCache()
        if cached then
            UIManager:show(Home:new{ plugin = self, data = cached })
            UIManager:scheduleIn(2, function()
                local ok, err = pcall(self.refreshHome, self)
                if not ok then logger.warn("codice: refreshing the home failed:", err) end
            end)
            return
        end
        if not NetworkMgr:isOnline() then return end
    elseif self.home_open and not home then
        return
    end
    UIManager:show(InfoMessage:new{ text = "Carregando o Códice…", timeout = 1 })
    UIManager:nextTick(function()
        self:fetchHome(function(data, problem)
            if not data then return self:say(problem) end
            self:saveHomeCache(data)
            if home and home.setData then
                home:setData(data)
            else
                UIManager:show(Home:new{ plugin = self, data = data })
            end
        end)
    end)
end

--- Where the books fetched by the home are kept: a folder of their own inside the one the person reads from.
function Codice:booksDir()
    local base = G_reader_settings:readSetting("home_dir") or G_reader_settings:readSetting("download_dir") or "/mnt/us/documents"
    local dir = base:gsub("/+$", "") .. "/Códice"
    util.makePath(dir)
    return dir
end

--- Opens a screen of the library (DEC-198): the root, or what a tab of the bar opens (`action_id`: codice_reading, codice_favorites, codice_notes).
--- With the bar of the Simple UI around it, the tab is lit.
function Codice:openLibrary(action_id, restore)
    if not self:connection() then
        return self:say("Conecte este leitor a um Códice primeiro: Códice → Conectar.")
    end
    action_id = action_id or "codice_library"
    local tab = core.libraryTab(action_id)
    local start
    if tab and tab.start then
        start = { kind = tab.start.kind, title = tab.start.title, page = 1 }
        if tab.start.spec then
            start.spec = {}
            for k, v in pairs(tab.start.spec) do start.spec[k] = v end
        end
    end
    guarded("abrir a biblioteca", function()
        UIManager:show(require("codice/library"):new{ plugin = self, start = start, action_id = action_id, restore = restore })
    end)()
end

--- The tabs of the Códice on the bar of the Simple UI: the home as "Acervo", then what is being read, the favorites, the notes and the library.
function Codice:mountTabs()
    local Config = require("infra/sui_config")
    local QA = require("features/sui_quickactions")
    Config.saveTabConfig(core.TAB_IDS)
    QA.setDefaultActionLabel("homescreen", core.HOME_TAB_LABEL)
    local su = self.ui[core.SIMPLEUI_SLOT or "codice"]
    if su and su._scheduleRebuild then su:_scheduleRebuild() end
end

--- Opens a book of the home: the file is fetched if it is not on the reader yet. `before` runs just before the reader opens.
function Codice:openBook(card, before)
    local c = self:connection()
    if not c then return end
    if not card.fileId or card.fileId == 0 then return self:say("Esta obra não tem um arquivo para abrir.") end
    local path = self:booksDir() .. "/" .. core.bookFileName(card)
    local open = guarded("abrir o livro", function()
        if before then before() end
        Data.noteOpening(path, card)
        require("apps/reader/readerui"):showReader(path)
    end)
    if lfs.attributes(path, "mode") == "file" and lfs.attributes(path, "size") > 0 then return open() end
    NetworkMgr:runWhenOnline(guarded("baixar o livro", function()
        UIManager:show(InfoMessage:new{ text = "Baixando “" .. tostring(card.title) .. "”…", timeout = 1 })
        UIManager:nextTick(guarded("baixar o livro", function()
            local part = path .. ".part"
            local handle = io.open(part, "wb")
            if not handle then return self:say("Não consegui gravar o livro em " .. self:booksDir()) end
            local code, err = api.request(c.url .. "/file/" .. card.fileId, { user = c.username, password = c.token, sink = ltn12.sink.file(handle) })
            if code ~= 200 then
                os.remove(part)
                return self:say("Não consegui baixar o livro (" .. tostring(code or err) .. ").")
            end
            if not os.rename(part, path) then
                os.remove(part)
                return self:say("Não consegui guardar o livro baixado.")
            end
            -- on the shelf: what the library shows with no network
            pcall(Store.record, c, card, core.bookFileName(card))
            open()
        end))
    end))
end

--- Opens a work: straight away when it has one file, else the person chooses which (the main one, the others, the last read marked).
function Codice:chooseAndOpen(card, before)
    return guarded("abrir a obra", function() return self:_chooseAndOpen(card, before) end)()
end

function Codice:_chooseAndOpen(card, before)
    if (card.fileCount or 1) <= 1 then return self:openBook(card, before) end
    local c = self:connection()
    if not c then return end
    NetworkMgr:runWhenOnline(guarded("escolher o arquivo", function()
        local code, data = api.request(c.url .. "/device/works/" .. card.id .. "/files", { user = c.username, password = c.token })
        if code ~= 200 or type(data) ~= "table" or type(data.files) ~= "table" or #data.files == 0 then
            return self:openBook(card, before) -- the choice cannot be had: the one the home pointed to
        end
        local choices = core.fileChoices(data.files)
        if #choices == 1 then
            return self:openBook(core.withFile(card, choices[1]), before)
        end
        local dialog
        local buttons = {}
        for _, choice in ipairs(choices) do
            buttons[#buttons + 1] = {{
                text = choice.label,
                callback = guarded("abrir o livro", function()
                    UIManager:close(dialog)
                    self:openBook(core.withFile(card, choice), before)
                end),
            }}
        end
        buttons[#buttons + 1] = {{ text = "Cancelar", callback = function() UIManager:close(dialog) end }}
        dialog = ButtonDialog:new{ title = (card.title or "?") .. "\n\nQual arquivo abrir?", title_align = "center", buttons = buttons }
        UIManager:show(dialog)
    end))
end

--- The place of the book here against the one the Códice has (DEC-196): when they are not the same (the web, or another reader, went on or went
--- back), the person is asked, with both places in words. This takes the place of the generic question of KOSync (turned off in its settings).
--- It also covers a copy of the book that was just downloaded: it starts at the first page, and the place the server has may be this very
--- reader's (KOSync takes that for known), so the next page turn would send "the start" over the real place.
function Codice:checkPlace()
    local ui = self.ui
    local kosync = ui.kosync
    if not (ui.document and kosync and kosync.settings) then return end
    local s = kosync.settings
    if not (s.custom_server and s.username and s.userkey) or not NetworkMgr:isOnline() then return end
    local code, body = api.request(s.custom_server .. "/syncs/progress/" .. kosync:getDocumentDigest(), {
        headers = { ["x-auth-user"] = s.username, ["x-auth-key"] = s.userkey, ["Accept"] = "application/vnd.koreader.v1+json" } })
    if code ~= 200 or type(body) ~= "table" or not body.percentage or not body.progress then return end
    local here = (kosync:getLastPercent() or 0) * 100
    local mine = body.device_id == kosync.device_id
    -- the last place this very reader wrote is its own: nothing to ask, unless the copy is new (at the start)
    if mine and here > 1 then return end
    -- the place elsewhere in words (chapter, passage), when the server can say it
    local web
    local fileId = core.fileIdOfPath(ui.document.file)
    local c = self:connection()
    if fileId and c then
        local ccode, cmp = api.request(c.url .. "/device/progress/files/" .. fileId .. "/compare", { user = c.username, password = c.token })
        if ccode == 200 and type(cmp) == "table" and type(cmp.web) == "table" then web = cmp.web end
    end
    local chapter
    if ui.toc and ui.toc.getTocTitleOfCurrentPage then
        local ok, title = pcall(ui.toc.getTocTitleOfCurrentPage, ui.toc)
        if ok and type(title) == "string" and title ~= "" then chapter = title end
    end
    -- the passage on the screen now, so that the two places are said the same way (the one of the Códice has its passage)
    local snippet
    local Screen = require("device").screen
    local okp, res = pcall(function()
        return ui.document:getTextFromPositions({ x = 0, y = 0 }, { x = Screen:getWidth(), y = Screen:getHeight() })
    end)
    if okp and type(res) == "table" and type(res.text) == "string" then snippet = core.passage(res.text, 200) end
    local question = core.placeQuestion({ percent = here, chapter = chapter, snippet = snippet }, body, web, mine and body.device or "", os.time())
    if not question then return end
    UIManager:show(require("codice/conflict"):new{
        question = question,
        on_go = guarded("ir para o outro lugar", function() kosync:syncToProgress(body.progress) end),
    })
end

function Codice:onReaderReady()
    pcall(self.healKosync, self)
    -- the notes of the book: what is waiting is sent, and what the Códice has is taken in (a little later, so that the book is on the screen first)
    UIManager:scheduleIn(6, function() require("codice/annotations").run(self, self.ui, true) end)
    if not (self.ui.kosync and self.ui.kosync.settings and self.ui.kosync.settings.auto_sync) then return end
    UIManager:scheduleIn(4, function()
        local ok, err = pcall(self.checkPlace, self)
        if not ok then logger.warn("codice: checking the place failed:", err) end
    end)
end

--- The reader is going to sleep: the lock screen is made sure of (see codice/lockscreen.lua).
function Codice:onSuspend()
    pcall(function() require("codice/lockscreen").ensure(self) end)
end

--- A highlight or a note was made, changed or deleted: what changed is sent when the person stops for a moment (not for each letter of a note).
function Codice:onAnnotationsModified()
    if self._notes_timer then UIManager:unschedule(self._notes_timer) end
    self._notes_timer = function()
        self._notes_timer = nil
        require("codice/annotations").run(self, self.ui, false)
    end
    UIManager:scheduleIn(5, self._notes_timer)
end

--- A book is being closed: the home of the Simple UI shows it first in "continue" when the person comes back to it, without waiting to ask.
function Codice:onCloseDocument()
    -- what was left to send of the notes goes now, while the book is still open (it needs the document)
    require("codice/annotations").run(self, self.ui, false)
    -- a book that was opened from the library is being closed: the library comes back where it was, once the file manager (or the home) is up
    if Data.return_to then
        UIManager:scheduleIn(2.5, function()
            local back = Data.return_to
            if not back then return end
            Data.return_to = nil
            local ok, err = pcall(function() ((package.loaded["codice/plugin"] or {}).live or self):openLibrary(back.action_id, back.stack) end)
            if not ok then logger.warn("codice: going back to the library failed:", err) end
        end)
    end
    local ok, err = pcall(function()
        local doc = self.ui.document
        local path = doc and doc.file
        if not path then return end
        local fraction
        if self.ui.kosync and self.ui.kosync.getLastPercent then fraction = self.ui.kosync:getLastPercent() end
        if not fraction and self.ui.doc_settings then fraction = self.ui.doc_settings:readSetting("percent_finished") end
        Data.afterReading(path, fraction and fraction * 100 or nil, function()
            local Row = package.loaded["codice/modules/row"]
            if Row then Row.redraw() end
        end)
    end)
    if not ok then logger.warn("codice: after closing a book:", err) end
end

function Codice:checkUpdate(silent)
    Update.check(self, silent)
end

-- ---------------------------------------------------------------- the menu and the events

function Codice:addToMainMenu(menu_items)
    menu_items.codice = {
        text = "Códice",
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text_func = function()
                    local c = self:connection()
                    return c and ("Conectado: " .. c.url) or "Não conectado"
                end,
                keep_menu_open = true,
                callback = function()
                    local c = self:connection()
                    self:say(c and ("Conectado a " .. c.url .. "\ncomo " .. c.username) or "Este leitor não está conectado a um Códice.")
                end,
            },
            {
                text_func = function() return self:connection() and "Conectar a outra instância" or "Conectar" end,
                callback = function() Pairing.start(self) end,
            },
            {
                text = "Biblioteca",
                enabled_func = function() return self:connection() ~= nil end,
                callback = function() self:openLibrary() end,
            },
            {
                text = "Abrir o Códice",
                enabled_func = function() return self:connection() ~= nil end,
                callback = function() self:showHome() end,
            },
            {
                text_func = function() return self:autostart() and "Abrir a tela antiga do Códice ao iniciar: sim" or "Abrir a tela antiga do Códice ao iniciar: não" end,
                keep_menu_open = true,
                enabled_func = function() return self:connection() ~= nil end,
                callback = function(touchmenu_instance)
                    self:setAutostart(not self:autostart())
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            },
            {
                text = "Atualizar a configuração",
                enabled_func = function() return self:connection() ~= nil end,
                callback = function() self:syncConfig(false) end,
            },
            {
                text = "Desconectar este leitor",
                enabled_func = function() return self:connection() ~= nil end,
                callback = function() self:disconnect() end,
            },
            {
                text = "Montar a barra de abas do Códice",
                callback = guarded("montar as abas", function()
                    self:mountTabs()
                    self:say("A barra de baixo agora tem: Acervo, Em leitura, Favoritos, Anotações e Biblioteca.")
                end),
            },
            {
                text = "Montar a home do Códice",
                callback = function() self:applyHomePreset() end,
            },
            {
                text_func = function()
                    return require("codice/lockscreen").enabled(self) and "Tela de bloqueio com as capas: sim" or "Tela de bloqueio com as capas: não"
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local Lockscreen = require("codice/lockscreen")
                    Lockscreen.set(self, not Lockscreen.enabled(self))
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            },
            {
                text = "Diagnóstico da tela de bloqueio",
                keep_menu_open = true,
                callback = function()
                    local Lockscreen = require("codice/lockscreen")
                    local ok, text = pcall(function()
                        pcall(Lockscreen.update, self)
                        return Lockscreen.report(self)
                    end)
                    self:say(ok and text or ("Não consegui montar o diagnóstico: " .. tostring(text)))
                end,
            },
            { text = "Procurar atualização do plugin", callback = function() self:checkUpdate(false) end },
            {
                text = "Voltar à versão anterior do plugin",
                enabled_func = function() return Update.hasPrevious(self) end,
                callback = function() Update.rollback(self) end,
            },
            { text = "Diagnóstico (protótipo)", sub_item_table = Diag.menu(self) },
        },
    }
end

--- Puts the ready-made home in the place of the layout of the home of the Simple UI. True when it was done.
function Codice:mountHome()
    local Presets = require("features/sui_presets")
    return require("infra/sui_core").applyPresetWithNotice(function()
        local applied = Presets.applyBuiltin(core.PRESET_ID)
        if applied then
            require("infra/sui_store"):set("simpleui_hs_active_preset", core.PRESET_ID)
            pcall(self.mountTabs, self)
        end
        return applied
    end, function()
        local HS = package.loaded["screens/sui_homescreen"]
        if HS and HS.rebuildLayout then HS.rebuildLayout() end
        local SE = package.loaded["engines/sui_screen_engine"]
        if SE and SE.refreshAllLiveImmediate then SE.refreshAllLiveImmediate(true) end
        -- the home is shown (a reader just connected is on the file browser): what was mounted is what the person sees
        pcall(function()
            local open_id = require("infra/sui_core").getOpenScreen()
            if open_id then return end
            local FM = package.loaded["apps/filemanager/filemanager"]
            require("features/sui_quickactions").execute("homescreen", { fm = FM and FM.instance })
        end)
    end)
end

--- The first time the file manager comes up on a reader that is not connected, offers to connect it (once: asking again would be nagging; the
--- menu has the entry for whoever said "later").
function Codice:welcome()
    local FM = package.loaded["apps/filemanager/filemanager"]
    if not (FM and FM.instance == self.ui) or self:connection() or self:store():readSetting("welcome_shown") then return end
    self:store():saveSetting("welcome_shown", true)
    self:store():flush()
    UIManager:show(ConfirmBox:new{
        text = "Bem-vindo ao Códice!\n\nPara ler seus livros e manter o progresso em dia, conecte este leitor à sua instância. Você digita o endereço, o leitor mostra um código e você o aprova no site: sem senha para digitar aqui.\n\nSe preferir, faça isso depois em Códice → Conectar.",
        ok_text = "Conectar agora",
        cancel_text = "Depois",
        ok_callback = guarded("conectar", function() Pairing.start(self) end),
    })
end

--- The menu entry: asks first, since it replaces the layout of the home, and what was there is lost unless the person saved it as a preset of
--- the Simple UI.
function Codice:applyHomePreset()
    UIManager:show(ConfirmBox:new{
        text = "Montar a home do Códice?\n\nIsso troca os módulos da home do Simple UI por uma página com saudação, números e continuar lendo.\n\nPara guardar a home atual, salve-a antes como predefinição no Simple UI.",
        ok_text = "Montar",
        ok_callback = guarded("montar a home", function()
            if not self:mountHome() then self:say("Não consegui montar a home.") end
        end),
    })
end

--- The network came back: the configuration is asked again, quietly, if it has been a while.
function Codice:onNetworkConnected()
    local c = self:connection()
    if not c then return end
    if self.ui.document then UIManager:scheduleIn(5, function() require("codice/annotations").run(self, self.ui, true) end) end
    if not (c.synced_at and os.time() - c.synced_at < SYNC_EVERY) then
        UIManager:scheduleIn(3, function()
            local ok, err = pcall(self.syncConfig, self, true)
            if not ok then logger.warn("codice: syncing the configuration failed:", err) end
        end)
    end
    local checked = self:store():readSetting("update_checked_at")
    if not (checked and os.time() - checked < UPDATE_EVERY) then
        UIManager:scheduleIn(8, function()
            local ok, err = pcall(self.checkUpdate, self, true)
            if not ok then logger.warn("codice: looking for an update failed:", err) end
        end)
    end
end

function Codice:onAnnotationsModified(items)
    Diag.onAnnotationsModified(self, items)
end

local M = { Codice = Codice }

--- The original Simple UI, installed next to this plugin, loads the same modules (`infra/sui_*`, `screens/...`) and the two would step on each
--- other: this plugin already holds all of it. If it is installed and on, it is turned off and the person is told to restart.
local function turnOffTheOriginalSimpleUI()
    local disabled = G_reader_settings and G_reader_settings:readSetting("plugins_disabled")
    if type(disabled) ~= "table" then disabled = {} end
    if disabled["simpleui"] ~= nil then return end
    local paths = { "plugins" }
    local extra = G_reader_settings and G_reader_settings:readSetting("extra_plugin_paths")
    if type(extra) == "string" then extra = { extra } end
    for _, path in ipairs(type(extra) == "table" and extra or {}) do paths[#paths + 1] = path end
    for _, path in ipairs(paths) do
        if type(path) == "string" and lfs.attributes(path:gsub("/+$", "") .. "/simpleui.koplugin", "mode") == "directory" then
            disabled["simpleui"] = true
            G_reader_settings:saveSetting("plugins_disabled", disabled)
            G_reader_settings:flush()
            UIManager:scheduleIn(1, function()
                UIManager:show(ConfirmBox:new{
                    text = "O Simple UI original foi desligado: este plugin já traz tudo dele.\n\nReinicie o KOReader para valer.",
                    ok_text = "Reiniciar agora",
                    ok_callback = function() UIManager:broadcastEvent(require("ui/event"):new("Restart")) end,
                })
            end)
            return
        end
    end
end

--- Starts the Códice for a main screen of KOReader (the file manager or the reader) and registers it there as a module, so that it is
--- given the events and the menu. Safe to call twice for the same screen.
function M.install(ui)
    if ui[core.MODULE_SLOT] then return ui[core.MODULE_SLOT] end
    if not M._compat_done then
        M._compat_done = true
        pcall(turnOffTheOriginalSimpleUI)
    end
    local ok, instance = pcall(Codice.new, Codice, { ui = ui })
    if not ok then
        logger.err("codice: could not start:", instance)
        return nil
    end
    ui:registerModule(core.MODULE_SLOT, instance)
    M.live = instance
    pcall(function() Store.configure(instance:booksDir()) end)
    -- before KOSync starts for this screen (the Códice comes first in the order of the plugins): the sync of progress is of the connected user
    pcall(instance.healKosync, instance)
    -- later, so that the screen of the file manager (and the Simple UI's own first-run) is there first
    UIManager:scheduleIn(6, function()
        local ok, err = pcall(instance.welcome, instance)
        if not ok then logger.warn("codice: welcome failed:", err) end
    end)
    -- the lock screen with the covers: pointed at its images from the start, not only when the reader is about to sleep
    UIManager:scheduleIn(10, function()
        pcall(function() require("codice/lockscreen").start(instance) end)
    end)
    if not M._modules_registered then
        M._modules_registered = true
        -- the modules of the Códice for the home of the Simple UI, by path: the registry loads them only when it lists the modules, so that
        -- the start of KOReader does not pay for them
        pcall(function()
            local Registry = require("modules/moduleregistry")
            Registry.register("codice/modules/continue")
            Registry.register("codice/modules/favorites")
            Registry.register("codice/modules/greeting")
            Registry.register("codice/modules/stats")
            Registry.register("codice/modules/note")
            for n = 1, core.SHELF_SLOTS do Registry.register("codice/modules/shelf" .. n) end
        end)
        -- the screens of the library as actions that are tabs of the bar of the Simple UI (or buttons of it), and the bar around them
        pcall(function()
            local QA = require("features/sui_quickactions")
            local Config = require("infra/sui_config")
            for _, tab in ipairs(core.LIBRARY_TABS) do
                QA.register{
                    id = tab.id, label = tab.label, icon = Config.ICON[tab.icon] or Config.ICON.library, is_in_place = false,
                    execute = function() if M.live then M.live:openLibrary(tab.id) end end,
                }
            end
            require("infra/sui_core").BarInjection.register{
                id = "codice_library", widget_name = "codice_library",
                get_active_action = function(widget) return widget.action_id or "codice_library" end,
                is_pageable = function(widget) return (widget.model and (widget.model.pages or 1) > 1) == true end,
            }
        end)
        -- the ready-made home, among the presets of the Simple UI (it hands out its list of built-in presets; no file of its own is changed)
        pcall(function()
            local list = require("features/sui_presets").getBuiltinPresets()
            for _, p in ipairs(list) do
                if p.id == core.PRESET_ID then return end
            end
            list[#list + 1] = core.homePreset()
        end)
    end
    return instance
end

--- Looks for a newer version of the plugin now (for the menu of the SimpleUI).
function M.checkUpdateNow()
    if M.live then M.live:checkUpdate(false) end
end

return M
