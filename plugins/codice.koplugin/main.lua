--[[--
Plugin do Códice para o KOReader: conecta o leitor a uma instância do Códice por um código aprovado no site e mantém no aparelho a
configuração do catálogo (OPDS) e da sincronização de progresso (KOSync). Issue ocnaibill/codice#327, DEC-194.
]]--

local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local NetworkMgr = require("ui/network/manager")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local md5 = require("ffi/sha2").md5

local core = require("codice_core")
local api = require("codice_http")
local Diag = require("codice_diag")
local Pairing = require("codice_pairing")
local Home = require("codice_home")
local Update = require("codice_update")
local lfs = require("libs/libkoreader-lfs")
local ltn12 = require("ltn12")
local util = require("util")

local SYNC_EVERY = 6 * 3600 -- the configuration is asked again at most this often, when the network comes back
local UPDATE_EVERY = 7 * 24 * 3600 -- and a newer plugin is looked for at most this often

local Codice = WidgetContainer:extend{
    name = "codice",
    is_doc_only = false,
}

function Codice:init()
    self.settings_file = DataStorage:getSettingsDir() .. "/codice.lua"
    self.ui.menu:registerToMainMenu(self)
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
    -- the sync of progress: the plugin of KOSync lives only inside a book, and reads its table at every call
    local key = md5(c.token)
    local kosync = self.ui.kosync
    if kosync and kosync.settings then
        core.applyKosync(kosync.settings, cfg, c.username, key)
        kosync.updated = true
        if kosync.settings_obj then kosync.settings_obj:flush() end
    else
        local file = LuaSettings:open(DataStorage:getSettingsDir() .. "/kosync.lua")
        core.applyKosync(file:readSetting("settings", {}), cfg, c.username, key)
        file:flush()
    end
    self:store():saveSetting("features", type(cfg.features) == "table" and cfg.features or {})
    self:store():flush()
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
    if self:applyConfig(data.config) then
        self:say("Conectado ao Códice como " .. tostring(data.username) .. ".\nO catálogo e a sincronização já estão configurados. Se você já abriu um livro nesta sessão, reinicie o KOReader uma vez.")
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
    if self.ui.kosync and self.ui.kosync.settings then
        clear(self.ui.kosync.settings)
        self.ui.kosync.updated = true
        if self.ui.kosync.settings_obj then self.ui.kosync.settings_obj:flush() end
    else
        local file = LuaSettings:open(DataStorage:getSettingsDir() .. "/kosync.lua")
        clear(file:readSetting("settings", {}))
        file:flush()
    end
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

--- Shows the home (or draws it again, when `home` is the one already open).
function Codice:showHome(home)
    UIManager:show(InfoMessage:new{ text = "Carregando o Códice…", timeout = 1 })
    UIManager:nextTick(function()
        self:fetchHome(function(data, problem)
            if not data then return self:say(problem) end
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

--- Opens a book of the home: the file is fetched if it is not on the reader yet. `before` runs just before the reader opens.
function Codice:openBook(card, before)
    local c = self:connection()
    if not c then return end
    if not card.fileId or card.fileId == 0 then return self:say("Esta obra não tem um arquivo para abrir.") end
    local path = self:booksDir() .. "/" .. core.bookFileName(card)
    local function open()
        if before then before() end
        require("apps/reader/readerui"):showReader(path)
    end
    if lfs.attributes(path, "mode") == "file" and lfs.attributes(path, "size") > 0 then return open() end
    NetworkMgr:runWhenOnline(function()
        UIManager:show(InfoMessage:new{ text = "Baixando “" .. tostring(card.title) .. "”…", timeout = 1 })
        UIManager:nextTick(function()
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
            open()
        end)
    end)
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
                text = "Abrir o Códice",
                enabled_func = function() return self:connection() ~= nil end,
                callback = function() self:showHome() end,
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

--- The network came back: the configuration is asked again, quietly, if it has been a while.
function Codice:onNetworkConnected()
    local c = self:connection()
    if not c then return end
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

return Codice
