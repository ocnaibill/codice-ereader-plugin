-- Testes da lógica que não precisa do KOReader (plugins/codice.koplugin/codice_core.lua).
-- Rodar na raiz do repositório:  luajit tests/run.lua   (ou lua tests/run.lua)

package.path = "plugins/codice.koplugin/?.lua;" .. package.path
local core = require("codice_core")

local failures, count = 0, 0
local function eq(got, want, label)
    count = count + 1
    if got ~= want then
        failures = failures + 1
        print(string.format("FALHOU %s: obtido %s, esperado %s", label, tostring(got), tostring(want)))
    end
end

-- o endereço da instância
eq(core.normalizeUrl("codice.exemplo.com"), "https://codice.exemplo.com", "sem esquema vira https")
eq(core.normalizeUrl("  https://codice.exemplo.com/  "), "https://codice.exemplo.com", "tira espaços e a barra")
eq(core.normalizeUrl("http://192.168.1.20:8080/opds/v1.2/catalog?x=1#y"), "http://192.168.1.20:8080", "fica só esquema, endereço e porta")
eq(core.normalizeUrl("https://codice.exemplo.com:8443"), "https://codice.exemplo.com:8443", "porta")
eq(select(2, core.normalizeUrl("")), "empty", "vazio")
eq(core.normalizeUrl("https://"), nil, "só o esquema")
eq(core.normalizeUrl("ftp://x.com"), nil, "esquema que não é http")
eq(core.normalizeUrl("https://user:pass@x.com"), nil, "sem credenciais no endereço")
eq(core.normalizeUrl("https://a b.com"), "https://a", "espaço corta o endereço (o resto é descartado)")

-- versões
eq(core.versionLess("0.1.0", "0.2.0"), true, "0.1.0 < 0.2.0")
eq(core.versionLess("0.2.0", "0.1.9"), false, "0.2.0 > 0.1.9")
eq(core.versionLess("0.1", "0.1.0"), false, "0.1 == 0.1.0")
eq(core.versionLess("0.9.0", "0.10.0"), true, "0.9.0 < 0.10.0 (número, não texto)")
eq(core.pluginMeets(nil), true, "sem mínimo, serve")
eq(core.pluginMeets("0.1.0"), true, "mínimo igual")
eq(core.pluginMeets("9.0.0"), false, "mínimo maior")

-- o código
eq(core.plainCode("bcdf-2345"), "BCDF2345", "código sem traço e em maiúsculas")

-- o que a resposta do pedido significa
eq(core.pollOutcome(200, { token = "abc", username = "ana" }), "ok", "aprovado")
eq(core.pollOutcome(200, {}), "error", "200 sem acesso não é aprovado")
eq(core.pollOutcome(400, { error = "authorization_pending" }), "pending", "pendente")
local outcome, interval = core.pollOutcome(400, { error = "slow_down", interval = 10 })
eq(outcome, "slow", "devagar")
eq(interval, 10, "novo intervalo")
eq(core.pollOutcome(400, { error = "expired_token" }), "expired", "venceu")
eq(core.pollOutcome(400, { error = "access_denied" }), "denied", "negado")
eq(core.pollOutcome(500, nil), "error", "erro do servidor")
eq(core.pollOutcome(nil, nil), "error", "sem resposta")
eq(core.requestFailure(429, { message = "Há pedidos demais." }), "Há pedidos demais.", "usa a mensagem do servidor")
eq(core.requestFailure(429, nil):find("pedidos demais") ~= nil, true, "429 sem corpo")

-- o catálogo (OPDS)
local cfg = { opds = { title = "Códice", url = "https://c.example/opds/v1.2/catalog" }, kosync = { url = "https://c.example/kosync" } }
local servers = { { title = "Gutenberg", url = "https://g.example" } }
eq(core.upsertOpds(servers, cfg, "ana", "tok"), true, "acrescenta")
eq(servers[1].title, "Códice", "fica em primeiro")
eq(servers[1].password, "tok", "com o acesso")
eq(#servers, 2, "sem apagar os outros")
eq(core.upsertOpds(servers, cfg, "ana", "tok"), false, "igual: nada muda")
servers[1].sync = true
cfg.opds.url = "https://c.example/novo/opds/v1.2/catalog"
eq(core.upsertOpds(servers, cfg, "ana", "tok2"), true, "troca o endereço e o acesso")
eq(#servers, 2, "troca a entrada, não acrescenta outra")
eq(servers[1].sync, true, "o que a pessoa pôs na entrada continua")
eq(servers[1].password, "tok2", "novo acesso")
eq(core.upsertOpds({}, {}, "a", "b"), false, "sem catálogo na configuração, nada")

-- a sincronização (KOSync)
local s = core.applyKosync({ sync_forward = 2 }, cfg, "ana", "chave")
eq(s.custom_server, "https://c.example/kosync", "servidor")
eq(s.username, "ana", "usuário")
eq(s.userkey, "chave", "chave")
eq(s.sync_forward, 2, "o que a pessoa escolheu fica")
eq(s.auto_sync, true, "o que falta recebe o padrão do Códice")
eq(s.checksum_method, 0, "checksum binário")
eq(s.sync_backward, 3, "não puxa para trás")
local fresh = core.applyKosync(nil, cfg, "ana", "k")
eq(fresh.auto_sync, true, "tabela nova")

-- a configuração guardada
eq(core.sameConfig('"abc"', '"abc"'), true, "mesmo ETag")
eq(core.sameConfig('"abc"', '"def"'), false, "ETag diferente")
eq(core.sameConfig(nil, '"def"'), false, "nada guardado")
eq(core.sameConfig('"abc"', nil), false, "sem ETag")

print(string.format("%d verificações, %d falhas", count, failures))
os.exit(failures == 0 and 0 or 1)
