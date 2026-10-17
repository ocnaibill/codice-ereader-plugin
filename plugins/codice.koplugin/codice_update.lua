--[[--
Updating the plugin over the air (DEC-195): the newest release of the plugin on GitHub is looked up, and when it is newer it is downloaded to a
temporary place, checked (the SHA-256 published with it, and the syntax of every file) and only then put in place of the plugin, which is
kept to go back to. The code that is downloaded is run by KOReader, so nothing is put in place that did not pass the checks; the trust is
the one of the owner of the repository and of HTTPS, the same as the update of KOReader itself.
]]--

local Archiver = require("ffi/archiver")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local ltn12 = require("ltn12")
local logger = require("logger")

local core = require("codice_core")
local api = require("codice_http")

local Update = {}

local PREFIX = "plugins/codice.koplugin/" -- where the files are inside the zip

local function say(text, timeout)
    UIManager:show(InfoMessage:new{ text = text, timeout = timeout })
end

local function rmdir(path)
    if lfs.attributes(path, "mode") ~= "directory" then return end
    for name in lfs.dir(path) do
        if name ~= "." and name ~= ".." then
            local child = path .. "/" .. name
            if lfs.attributes(child, "mode") == "directory" then rmdir(child) else os.remove(child) end
        end
    end
    lfs.rmdir(path)
end

local function readAll(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

--- The SHA-256 of a file, in lower case: by the library of KOReader when it has one, else by the `sha256sum` of the system; nil when neither.
function Update.sha256(path)
    local ok, sha2 = pcall(require, "ffi/sha2")
    if ok and type(sha2.sha256) == "function" then
        local data = readAll(path)
        local done, hex = pcall(sha2.sha256, data or "")
        if data and done and type(hex) == "string" and #hex == 64 then return hex:lower() end
    end
    local pipe = io.popen("sha256sum '" .. path:gsub("'", "") .. "' 2>/dev/null")
    if pipe then
        local out = pipe:read("*a")
        pipe:close()
        return core.parseSha256(out)
    end
    return nil
end

--- The folder of this plugin (where main.lua is) and the one next to it where the previous version is kept.
function Update.dirs(plugin)
    local dir = tostring(plugin.path or ""):gsub("/+$", "")
    return dir, dir .. ".old", dir .. ".new"
end

function Update.hasPrevious(plugin)
    local _, old = Update.dirs(plugin)
    return lfs.attributes(old, "mode") == "directory"
end

--- Looks for a newer release. `silent`: only says something when there is an update (and a short notice, not a question).
function Update.check(plugin, silent)
    NetworkMgr:runWhenOnline(function()
        local code, release = api.request(core.RELEASES_URL, { headers = { Accept = "application/vnd.github+json" } })
        if not code then
            if not silent then say("Não consegui procurar atualizações.\n" .. tostring(release)) end
            return
        end
        if code ~= 200 then
            if not silent then say("O GitHub respondeu " .. tostring(code) .. " ao procurar atualizações.") end
            return
        end
        local pick = core.pickRelease(release)
        plugin:store():saveSetting("update_checked_at", os.time())
        plugin:store():flush()
        if not pick then
            if not silent then say("A versão mais nova ainda não tem os arquivos de atualização. Tente mais tarde.") end
            return
        end
        if not core.isNewer(pick.version) then
            if not silent then say("O plugin do Códice está em dia (versão " .. core.PLUGIN_VERSION .. ").", 5) end
            return
        end
        if silent then
            Notification:notify("Há uma atualização do plugin do Códice (" .. pick.version .. "). Veja em Códice → Procurar atualização.")
            return
        end
        UIManager:show(ConfirmBox:new{
            text = "Atualizar o plugin do Códice de " .. core.PLUGIN_VERSION .. " para " .. pick.version .. "?\n\nO KOReader precisa reiniciar depois. A versão atual fica guardada para voltar atrás.",
            ok_text = "Atualizar",
            ok_callback = function() Update.install(plugin, pick) end,
        })
    end)
end

local function fail(work, text)
    rmdir(work)
    say("A atualização não foi feita: " .. text .. "\nO plugin continua como estava.")
end

--- Downloads, checks and puts in place a release.
function Update.install(plugin, pick)
    local dir, old, new = Update.dirs(plugin)
    if dir == "" then return say("Não sei onde o plugin está instalado; atualize pela pasta, por USB.") end
    say("Baixando a atualização…", 2)
    UIManager:nextTick(function()
        local cache = DataStorage:getDataDir() .. "/cache/codice"
        lfs.mkdir(DataStorage:getDataDir() .. "/cache")
        lfs.mkdir(cache)
        local zip = cache .. "/update.zip"
        os.remove(zip)

        -- the hash published with the release
        local code, text = api.request(pick.sha, { raw = true })
        local want = code == 200 and core.parseSha256(text) or nil
        if not want then return fail(new, "não consegui o arquivo de verificação da atualização.") end

        local handle = io.open(zip, "wb")
        if not handle then return fail(new, "não consegui gravar o arquivo baixado.") end
        local status = api.request(pick.zip, { sink = ltn12.sink.file(handle) })
        if status ~= 200 then
            os.remove(zip)
            return fail(new, "o download falhou (" .. tostring(status) .. ").")
        end

        -- 1. the hash
        local got = Update.sha256(zip)
        if not got then return fail(new, "não consigo verificar o arquivo (este aparelho não calcula SHA-256).") end
        if got ~= want then
            os.remove(zip)
            return fail(new, "o arquivo baixado não confere com o hash publicado.")
        end

        -- 2. extracted next to the plugin, never over it
        rmdir(new)
        lfs.mkdir(new)
        local arc = Archiver.Reader:new()
        if not arc:open(zip) then return fail(new, "o arquivo baixado não abre como zip.") end
        local files = 0
        for entry in arc:iterate() do
            if entry.mode == "file" and entry.path:sub(1, #PREFIX) == PREFIX then
                local name = entry.path:sub(#PREFIX + 1)
                if name:find("..", 1, true) or name:find("/", 1, true) then
                    arc:close()
                    return fail(new, "o arquivo tem um caminho que não esperávamos.")
                end
                if not arc:extractToPath(entry.path, new .. "/" .. name) then
                    arc:close()
                    return fail(new, "não consegui extrair " .. name .. ".")
                end
                files = files + 1
            end
        end
        arc:close()
        os.remove(zip)

        -- 3. what was extracted is a plugin: the files are there and every one of them loads
        if files == 0 or lfs.attributes(new .. "/main.lua", "mode") ~= "file" or lfs.attributes(new .. "/_meta.lua", "mode") ~= "file" then
            return fail(new, "o arquivo não traz o plugin completo.")
        end
        for name in lfs.dir(new) do
            if name:match("%.lua$") then
                local chunk, err = loadfile(new .. "/" .. name)
                if not chunk then
                    logger.warn("codice: the update has a file that does not load:", name, err)
                    return fail(new, name .. " não é um arquivo válido.")
                end
            end
        end

        -- 4. in place, keeping the previous one
        rmdir(old)
        if not os.rename(dir, old) then return fail(new, "não consegui guardar a versão atual.") end
        if not os.rename(new, dir) then
            os.rename(old, dir) -- put the previous back
            return fail(new, "não consegui colocar a versão nova no lugar.")
        end
        plugin:store():saveSetting("updated_from", core.PLUGIN_VERSION)
        plugin:store():flush()
        UIManager:askForRestart("Plugin do Códice atualizado para " .. pick.version .. ".\n\nO KOReader precisa reiniciar para usar a versão nova.")
    end)
end

--- Puts the previous version back.
function Update.rollback(plugin)
    local dir, old, new = Update.dirs(plugin)
    if not Update.hasPrevious(plugin) then return say("Não há versão anterior guardada.") end
    UIManager:show(ConfirmBox:new{
        text = "Voltar à versão anterior do plugin do Códice?\n\nO KOReader precisa reiniciar depois.",
        ok_text = "Voltar",
        ok_callback = function()
            rmdir(new)
            if not os.rename(dir, new) then return say("Não consegui voltar à versão anterior.") end
            if not os.rename(old, dir) then
                os.rename(new, dir)
                return say("Não consegui voltar à versão anterior.")
            end
            rmdir(new) -- the one that was running
            UIManager:askForRestart("Versão anterior do plugin do Códice de volta.\n\nO KOReader precisa reiniciar.")
        end,
    })
end

return Update
