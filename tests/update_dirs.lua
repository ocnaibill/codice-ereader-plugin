-- O OTA acha a pasta do plugin sem `plugin.path` (o módulo do Códice, registrado pelo Simple UI, não tem esse campo). Roda o código real de
-- codice/update.lua com os módulos do KOReader trocados por stubs.   Rodar na raiz:  luajit tests/update_dirs.lua

package.path = "./?.lua;" .. package.path
local function stub(name, value) package.preload[name] = function() return value end end
local widget = setmetatable({}, { __index = function() return function() end end })
for _, n in ipairs({ "ffi/archiver", "ui/widget/confirmbox", "ui/widget/infomessage", "ui/network/manager", "ui/widget/notification", "ui/uimanager", "logger" }) do
    stub(n, widget)
end
stub("datastorage", { getDataDir = function() return "/data" end })
stub("libs/libkoreader-lfs", { currentdir = function() return "/mnt/us/koreader" end, attributes = function() return nil end, mkdir = function() end })
stub("ltn12", widget)
stub("codice/http", {})

local Update = require("codice/update")
local failures = 0
local function eq(got, want, label)
    if got ~= want then
        failures = failures + 1
        print(string.format("FALHOU %s: obtido %s, esperado %s", label, tostring(got), tostring(want)))
    end
end

-- o módulo do Códice não tem `path`: a pasta sai do caminho do próprio arquivo (aqui o teste roda de "./codice/update.lua")
local dir, old, new = Update.dirs({})
eq(dir, "/mnt/us/koreader", "sem path, a pasta é a do arquivo")
eq(old, "/mnt/us/koreader.old", "a anterior")
eq(new, "/mnt/us/koreader.new", "a nova")
-- com `path` (o plugin que o KOReader carrega), vale o path, sem a barra do fim
dir = Update.dirs({ path = "/mnt/us/koreader/plugins/codice.koplugin/" })
eq(dir, "/mnt/us/koreader/plugins/codice.koplugin", "com path")
-- nunca vazio quando o caminho é conhecido: "Não sei onde o plugin está instalado" era o erro desta falha
eq(Update.dirs({}) ~= "", true, "a pasta não fica vazia")

print(failures == 0 and "update_dirs: ok" or (failures .. " falhas"))
os.exit(failures == 0 and 0 or 1)
