-- Testes da lógica que não precisa do KOReader (codice/core.lua).
-- Rodar na raiz do repositório:  luajit tests/run.lua   (ou lua tests/run.lua)

package.path = "./?.lua;" .. package.path
local core = require("codice/core")

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

-- as seções da home, na ordem da home da web
local home = {
    user = { name = "Ana" }, stats = { worksTotal = 12 },
    continue = { { id = 1, title = "Duna" } },
    favorites = {},
    notes = { { text = "uma frase", title = "Duna" } },
    shelves = { { id = 3, title = "Ficção", total = 40, works = { { id = 2, title = "A" }, { id = 3, title = "B" } } }, { id = 4, title = "Vazia", works = {} } },
}
local sections = core.homeSections(home)
local kinds = {}
for _, sec in ipairs(sections) do kinds[#kinds + 1] = sec.kind .. ":" .. (sec.title or "") end
eq(table.concat(kinds, "|"), "greeting:|row:Continuar lendo|quotes:Das suas anotações|row:Ficção (40)", "greeting, continuar, anotações, prateleiras (sem favoritos vazios nem prateleira vazia)")
eq(sections[1].name, "Ana", "o nome")
eq(#core.homeSections(nil), 0, "sem home, sem seções")
eq(core.homeSections({})[1].kind, "greeting", "uma home vazia ainda cumprimenta")

-- as páginas
local blocks = { { h = 100 }, { h = 300 }, { h = 300 }, { h = 50 }, { h = 900 }, { h = 10 } }
local pages = core.paginate(blocks, 650)
eq(#pages, 4, "quatro páginas")
eq(#pages[1], 2, "100+300 cabem; +300 passa de 650")
eq(#pages[2], 2, "300+50")
eq(#pages[3], 1, "um bloco mais alto que a página fica sozinho")
eq(#pages[4], 1, "o resto")
eq(#core.paginate({}, 700), 0, "sem blocos, sem páginas")
local lines = core.lines({ 1, 2, 3, 4, 5, 6, 7 }, 3, 6)
eq(#lines, 2, "seis cartões em duas linhas de três")
eq(#core.lines({ 1, 2, 3, 4 }, 3), 2, "quatro: três e um")

-- arquivos
eq(core.safeName('Duna: o "livro" / 1'), "Duna o livro 1", "tira o que um sistema de arquivos recusa")
eq(core.safeName("  "), "livro", "vazio")
eq(core.safeName("Ação e coração", 4), "Aç", "corta em caractere inteiro, não no meio do UTF-8")
eq(core.bookFileName({ id = 7, title = "Duna", format = "EPUB" }), "7 - Duna.epub", "id, título, formato")
eq(core.bookFileName({ id = 8, title = "X", format = "" }), "8 - X.epub", "sem formato, epub")
eq(core.bookFileName({ id = 8, fileId = 80, title = "X", format = "pdf" }), "80 - X.pdf", "o id do arquivo separa dois arquivos da mesma obra")
eq(core.coverCacheName("/covers/abc-1.jpg"), "covers_abc_1_jpg.jpg", "o nome da capa guardada")

-- atualização
local release = { tag_name = "v0.2.0", assets = { { name = "codice-plugin.zip", browser_download_url = "https://x/z.zip" }, { name = "codice-plugin.zip.sha256", browser_download_url = "https://x/z.sha" } } }
local pick = core.pickRelease(release)
eq(pick.version, "0.2.0", "versão sem o v")
eq(pick.zip, "https://x/z.zip", "zip")
eq(pick.sha, "https://x/z.sha", "hash")
eq(core.pickRelease({ tag_name = "v0.2.0", assets = {} }), nil, "sem os arquivos, não atualiza")
eq(core.pickRelease({ tag_name = "nightly", assets = release.assets }), nil, "tag sem versão")
eq(core.pickRelease(nil), nil, "sem release")
eq(core.parseSha256("ABCDEF0123456789abcdef0123456789abcdef0123456789abcdef0123456789  codice-plugin.zip\n"), "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789", "hash em minúsculas")
eq(core.parseSha256("não é um hash"), nil, "texto sem hash")
eq(core.isNewer("0.5.0"), true, "mais nova")
eq(core.isNewer(core.PLUGIN_VERSION), false, "a mesma")
eq(core.isNewer("0.1.0"), false, "mais velha")

-- escolher o arquivo
eq(core.languageName("pt-BR"), "Português", "pt-BR é português")
eq(core.languageName("xx"), "XX", "idioma que não conhecemos")
eq(core.languageName(nil), "Idioma não informado", "sem idioma")
local choices = core.fileChoices({
    { id = 30, format = "pdf", language = "en", last = true, percent = 20 },
    { id = 10, format = "epub", language = "pt", primary = true },
    { id = 20, format = "epub", language = "en", completed = true },
})
eq(#choices, 3, "três opções")
eq(choices[1].id, 10, "o principal primeiro")
eq(choices[1].label, "Português - EPUB  (principal)", "principal")
eq(choices[2].id, 20, "depois os outros, pelo id")
eq(choices[2].label, "Inglês - EPUB  (lido)", "lido")
eq(choices[3].label, "Inglês - PDF  (último acessado, 20%)", "último acessado, com quanto foi lido")
eq(#core.fileChoices(nil), 0, "sem arquivos")

-- caminhos dentro do zip
eq(core.safeRelPath("main.lua"), "main.lua", "arquivo na raiz")
eq(core.safeRelPath("infra/sui_core.lua"), "infra/sui_core.lua", "arquivo numa pasta")
eq(core.safeRelPath("a/b/c/d/e/f.lua"), "a/b/c/d/e/f.lua", "seis níveis")
eq(core.safeRelPath("a/b/c/d/e/f/g.lua"), nil, "sete níveis")
for _, bad in ipairs({ "", "/etc/passwd", "../fora.lua", "a/../../b.lua", "a/./b.lua", "a//b.lua", "a\\b.lua", "a/b\0c.lua", "a/", string.rep("x", 201) }) do
    eq(core.safeRelPath(bad), nil, "caminho recusado: " .. bad:gsub("%c", "?"):sub(1, 20))
end
eq(core.safeRelPath(nil), nil, "sem caminho")

-- as linhas da home para a grade do Simple UI
local items = core.homeItems({ continue = { { id = 1, title = "A" }, { title = "sem id" }, { id = 2, title = "B", percent = 40 }, { id = 3 } } }, "continue", 2)
eq(#items, 2, "no máximo 2")
eq(items[1].key, "codice:1", "chave da grade")
eq(items[2].key, "codice:2", "pula quem não tem id")
eq(items[2].percent, 40, "os dados do cartão seguem")
eq(#core.homeItems(nil, "continue", 5), 0, "sem home")
eq(#core.homeItems({ continue = {} }, "favorites", 5), 0, "linha que não existe")
eq(#core.homeItems({ continue = { { id = 1 }, { id = 2 }, { id = 3 } } }, "continue"), 3, "padrão 5")
local a = { continue = { { id = 1, title = "A", percent = 10, cover = "/c/1" } }, user = { name = "Ana" } }
local b = { continue = { { id = 1, title = "A", percent = 10, cover = "/c/1" } }, user = { name = "Outra" } }
eq(core.sameRows(a, b), true, "o nome não conta")
b.continue[1].percent = 11
eq(core.sameRows(a, b), false, "o progresso conta")
eq(core.sameRows(nil, nil), true, "duas homes vazias")
eq(core.sameRows(a, nil), false, "uma com cartões, outra sem")

-- a pasta do plugin, pelo caminho de um arquivo dele
eq(core.pluginDirFromSource("@/mnt/us/koreader/plugins/codice.koplugin/codice/update.lua"), "/mnt/us/koreader/plugins/codice.koplugin", "caminho absoluto")
eq(core.pluginDirFromSource("@plugins/codice.koplugin/codice/update.lua", "/mnt/us/koreader"), "/mnt/us/koreader/plugins/codice.koplugin", "relativo vira absoluto")
eq(core.pluginDirFromSource("@./plugins/codice.koplugin/codice/update.lua", "/mnt/us/koreader/"), "/mnt/us/koreader/plugins/codice.koplugin", "tira o ./ e a barra do fim")
eq(core.pluginDirFromSource("@plugins/codice.koplugin/codice/update.lua"), "plugins/codice.koplugin", "relativo sem diretório atual fica como está")
eq(core.pluginDirFromSource("@./codice/update.lua", "/mnt/us/koreader"), "/mnt/us/koreader", "a pasta atual")
eq(core.pluginDirFromSource("=stdin"), nil, "não é arquivo")
eq(core.pluginDirFromSource("@/x/outro/arquivo.lua"), nil, "não é da pasta codice/")
eq(core.pluginDirFromSource("@/codice/update.lua"), nil, "sem pasta do plugin")
eq(core.pluginDirFromSource(nil), nil, "sem fonte")

eq(core.firstLine("erro curto\nstack traceback:\n\tx"), "erro curto", "só a primeira linha do erro")
eq(core.firstLine(nil), "", "sem erro")
eq(#core.firstLine(string.rep("x", 500)) > 240, true, "linha longa é cortada com reticências")

print(string.format("%d verificações, %d falhas", count, failures))
os.exit(failures == 0 and 0 or 1)
