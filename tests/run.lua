-- Testes da lógica que não precisa do KOReader (codice/core.lua).
-- Rodar na raiz do repositório:  luajit tests/run.lua   (ou lua tests/run.lua)

package.path = "./?.lua;" .. package.path
local core = require("codice/core")
local Shelf = require("codice/shelf")
local Libview = require("codice/libview")
local Notesync = require("codice/notesync")

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
eq(core.applyKosync({ sync_forward = 1 }, cfg, "ana", "k").sync_forward, 3, "a pergunta genérica do KOSync dá lugar à do Códice")
eq(core.applyKosync(nil, cfg, "ana", "k").sync_forward, 3, "e o padrão é o mesmo")
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
eq(core.isNewer("9.0.0"), true, "mais nova")
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
eq(core.sameRows(a, b), false, "o nome conta: a saudação o mostra")
eq(core.sameRows(a, a), true, "a mesma home")
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

-- o módulo do Códice não pode ser pego por `ui.codice`: o KOReader registra o plugin da pasta (o do Simple UI) com esse nome, depois do init
eq(core.MODULE_SLOT ~= "codice", true, "o nome do módulo não é o da pasta do plugin")
do
    local offenders = {}
    local p = io.popen('find codice -name "*.lua"')
    for path in p:lines() do
        local f = io.open(path, "r")
        local n = 0
        for line in f:lines() do
            n = n + 1
            -- `x.codice` followed by something that is not part of a name (`ui.codice)`, `ui.codice then`), outside comments
            local code = line:gsub("%-%-.*$", "")
            if (code:find("[%w_%]]%.codice%f[^%w_]") and not code:find("menu_items%.codice")) or code:find('registerModule%("codice"') then offenders[#offenders + 1] = path .. ":" .. n end
        end
        f:close()
    end
    p:close()
    eq(#offenders, 0, "nenhum arquivo usa ui.codice nem registra o módulo como \"codice\": " .. table.concat(offenders, ", "))
end

-- prateleiras da home
local shelfHome = { shelves = {
    { id = 7, title = "Ficção", total = 40, works = { { id = 1, title = "A" }, { title = "sem id" }, { id = 2, title = "B" }, { id = 3, title = "C" } } },
    { id = 9, title = "Quadrinhos", total = 2, works = { { id = 1, title = "A" }, { id = 5, title = "E" } } },
} }
local sh = core.shelfItems(shelfHome, 1, 2)
eq(#sh, 2, "no máximo 2 da prateleira")
eq(sh[1].key, "codice:s7:1", "a chave leva o id da prateleira")
eq(sh[2].key, "codice:s7:2", "pula quem não tem id")
eq(core.shelfItems(shelfHome, 2, 5)[1].key, "codice:s9:1", "a mesma obra em outra prateleira é outra célula")
eq(#core.shelfItems(shelfHome, 3, 5), 0, "prateleira que não existe")
eq(#core.shelfItems(nil, 1, 5), 0, "sem home")
eq(core.shelfLabel(shelfHome, 1), "Ficção (40)", "mais obras do que a prateleira mostra")
eq(core.shelfLabel(shelfHome, 2), "Quadrinhos", "a prateleira mostra todas")
eq(core.shelfLabel(shelfHome, 3), nil, "sem prateleira")
eq(core.SHELF_SLOTS, 6, "seis prateleiras")
local h1 = { shelves = { { id = 1, title = "X", total = 1, works = { { id = 1, title = "A", percent = 0 } } } } }
local h2 = { shelves = { { id = 1, title = "X", total = 1, works = { { id = 1, title = "A", percent = 0 } } } } }
eq(core.sameRows(h1, h2), true, "prateleiras iguais")
h2.shelves[1].works[1].title = "B"
eq(core.sameRows(h1, h2), false, "uma obra mudou numa prateleira")
h2.shelves[1].works[1].title = "A"; h2.shelves[1].total = 5
eq(core.sameRows(h1, h2), false, "o total da prateleira mudou")

-- a primeira tela, como a web diz
eq(core.dateLabel({ day = 18, month = 10, year = 2026 }), "18 de outubro de 2026", "data por extenso")
eq(core.timeLabel({ hour = 9, min = 11 }), "09:11", "hora com zero à esquerda")
eq(core.dayLabel({ wday = 1, day = 18, month = 10, year = 2026 }), "domingo, 18 de outubro", "dia da semana e data")
eq(core.dayLabel({ wday = 4, day = 1, month = 3, year = 2026 }), "quarta-feira, 1 de março", "dia 1")
eq(core.greeting(9, "binaco"), "Bom dia, binaco :)", "de manhã")
eq(core.greeting(12, "ana"), "Boa tarde, ana :)", "ao meio-dia já é tarde")
eq(core.greeting(18, "ana"), "Boa noite, ana :)", "às 18h é noite")
eq(core.greeting(5, ""), "Bom dia", "sem nome")
eq(core.greeting(5, nil), "Bom dia", "sem nome (nil)")
eq(core.formatCount(0), "0", "zero")
eq(core.formatCount(13), "13", "pequeno")
eq(core.formatCount(1420), "1.420", "milhar")
eq(core.formatCount(1234567), "1.234.567", "milhões")
eq(core.formatCount(nil), "0", "sem número")
eq(core.formatBreakdown({ livros = 11, quadrinhos = 2, mangas = 0, audio = 0 }), "11 livros • 2 quadrinhos", "zeros ficam de fora")
eq(core.formatBreakdown({ livros = 1, quadrinhos = 1, mangas = 1, audio = 1 }), "1 livro • 1 quadrinho • 1 mangá • 1 áudio", "singular")
eq(core.formatBreakdown({}), "", "nada")
eq(core.formatBreakdown(nil), "", "sem tabela")
eq(core.formatReadingTime(11700), "3h 15min", "horas e minutos")
eq(core.formatReadingTime(2700), "45min", "só minutos")
eq(core.formatReadingTime(7200), "2h", "horas cheias")
eq(core.formatReadingTime(0), "0min", "nada")
local cards = core.statsCards({ stats = { inProgressCount = 13, inProgressBreakdown = { livros = 11, quadrinhos = 2 },
    completedThisMonth = 3, completedBreakdown = { livros = 2, mangas = 1 }, totalReadingSeconds = 11700 } })
eq(cards.reading.count, "13", "em andamento")
eq(cards.reading.detail, "11 livros • 2 quadrinhos", "em andamento por formato")
eq(cards.activity.completed, "3", "completas no mês")
eq(cards.activity.time, "3h 15min", "tempo de leitura")
eq(cards.activity.detail, "2 livros • 1 mangá", "completas por formato")
eq(core.statsCards({}), nil, "sem números")
eq(core.statsCards(nil), nil, "sem home")
local noteHome = { notes = { { text = "primeira", title = "A" }, { text = "  " }, { text = "segunda", title = "B" } } }
eq(core.pickNote(noteHome, 0).text, "primeira", "a primeira")
eq(core.pickNote(noteHome, 1).text, "segunda", "pula a vazia")
eq(core.pickNote(noteHome, 2).text, "primeira", "dá a volta")
eq(core.pickNote({ notes = {} }, 3), nil, "sem notas")
eq(core.pickNote(nil, 3), nil, "sem home")
eq(core.noteSignature(noteHome), "primeira\n  \nsegunda", "assinatura das notas")
eq(core.noteSignature(nil), "", "sem home")
local nh2 = { notes = { { text = "outra" } } }
eq(core.sameRows(noteHome, nh2), false, "as notas mudaram")
eq(core.sameRows({ stats = { inProgressCount = 1 } }, { stats = { inProgressCount = 2 } }), false, "os números mudaram")
eq(core.sameRows({ user = { name = "a" } }, { user = { name = "a" } }), true, "mesmo nome")

-- a home pronta
local preset = core.homePreset()
eq(preset.id, core.PRESET_ID, "id da predefinição")
eq(#preset.layout.pages, 1, "uma página")
local seen, dup = {}, false
for _, page in ipairs(preset.layout.pages) do
    for _, id in ipairs(page.modules) do
        if seen[id] then dup = true end
        seen[id] = true
    end
end
eq(dup, false, "nenhum módulo repetido")
for _, id in ipairs({ "codice_greeting", "codice_stats", "codice_continue" }) do
    eq(seen[id], true, "a predefinição tem " .. id)
end
-- every module of the preset exists as a file, with that id
for id in pairs(seen) do
    local f = io.open("codice/modules/" .. id:gsub("^codice_", "") .. ".lua")
    eq(f ~= nil, true, "o arquivo do módulo " .. id)
    if f then
        local text = f:read("*a")
        f:close()
        eq(text:find('id%s*=%s*"' .. id .. '"') ~= nil, true, "o módulo " .. id .. " tem esse id")
    end
end

-- cartão: lido, recorte, arquivo escolhido
eq(core.readLabel(15), "15% lido", "quinze por cento")
eq(core.readLabel(15.4), "15% lido", "arredonda para baixo")
eq(core.readLabel(15.6), "16% lido", "arredonda para cima")
eq(core.readLabel(0.2), "1% lido", "um pouco lido nunca é zero")
eq(core.readLabel(0), "", "nada lido")
eq(core.readLabel(nil), "", "sem número")
eq(core.readLabel(130), "100% lido", "no máximo cem")
local crop = core.coverCrop(200, 400, 100, 150)
eq(crop.w, 100, "mais fina que a caixa: ocupa a largura") ; eq(crop.h, 200, "e corta em cima e embaixo"); eq(crop.y, 25, "corte igual dos dois lados"); eq(crop.x, 0, "sem corte lateral")
crop = core.coverCrop(300, 300, 100, 150)
eq(crop.h, 150, "mais larga que a caixa: ocupa a altura"); eq(crop.w, 150, "e corta dos lados"); eq(crop.x, 25, "corte lateral igual")
crop = core.coverCrop(200, 300, 100, 150)
eq(crop.w == 100 and crop.h == 150 and crop.x == 0 and crop.y == 0, true, "mesma proporção: sem corte")
local withFile = core.withFile({ id = 5, title = "T", cover = "/c/5", percent = 12, fileId = 1, format = "pdf" }, { id = 9, format = "epub" })
eq(withFile.fileId, 9, "o arquivo escolhido"); eq(withFile.format, "epub", "o formato dele"); eq(withFile.cover, "/c/5", "a capa continua"); eq(withFile.percent, 12, "o progresso continua")
local base = { user = { name = "a" }, continue = { { id = 1, title = "A", percent = 10, cover = "/c/1", key = "codice:1" }, { id = 2, title = "B", percent = 50 }, { id = 3, title = "C", percent = 70 } } }
local h2, changed = core.touchContinue(base, { id = 3, title = "C", fileId = 30 }, 75)
eq(changed, true, "mudou")
eq(h2.continue[1].id, 3, "o último lido vai para a frente"); eq(h2.continue[1].percent, 75, "com o novo percentual"); eq(h2.continue[2].id, 1, "os outros mantêm a ordem"); eq(h2.continue[3].id, 2, "e o resto")
eq(#h2.continue, 3, "ninguém some nem se repete"); eq(h2.user.name, "a", "o resto da home continua")
eq(base.continue[1].id, 1, "a home original não foi alterada")
eq(h2.continue[1].fileId, 30, "o arquivo aberto vem junto")
local h3 = core.touchContinue(base, { id = 9, title = "Novo", cover = "/c/9" }, 4)
eq(h3.continue[1].id, 9, "uma obra que começou entra na frente"); eq(h3.continue[1].cover, "/c/9", "com a capa"); eq(#h3.continue, 4, "e a lista cresce")
local h4, ch4 = core.touchContinue(base, { id = 9, title = "Novo" }, 0)
eq(ch4, false, "abrir sem ler não entra"); eq(#h4.continue, 3, "a lista fica")
local h5 = core.touchContinue(base, { id = 2, title = "B" }, nil)
eq(h5.continue[1].id, 2, "sem percentual, só sobe"); eq(h5.continue[1].percent, 50, "mantém o que tinha")
eq(select(2, core.touchContinue(nil, { id = 1 }, 5)), false, "sem home")

-- a prateleira (o que o leitor guarda dos livros que tem)
eq(Shelf.fold("Stanisław Lem"), "stanislaw lem", "sem acento nem maiúscula")
eq(Shelf.fold("Ação & Emoção"), "acao & emocao", "acentos do português")
eq(Shelf.letter("Álvaro"), "A", "letra sem acento")
eq(Shelf.letter("  zé"), "Z", "tira espaços")
eq(Shelf.letter("1984"), "#", "número vai para #")

local function work(id, title, author, extra)
    local w = { id = id, title = title, author = author, authors = { { id = id * 10, name = author } }, cover = "/c/" .. id, percent = 0,
        categories = {}, files = { { id = id * 100, format = "epub", primary = true } }, favorite = false, inProgress = false, completed = false }
    for k, v in pairs(extra or {}) do w[k] = v end
    return w
end
local idx = Shelf.new()
local fiction = { id = 1, name = "Ficção" }
local scifi = { id = 2, name = "Ficção científica", parentId = 1 }
local horror = { id = 3, name = "Terror", parentId = 1 }
local nonfic = { id = 4, name = "Não ficção" }
Shelf.noteDownload(idx, work(1, "Duna", "Frank Herbert", { categories = { fiction, scifi }, series = "Duna", favorite = true, inProgress = true, percent = 42 }), 100, "100 - Duna.epub", 900, 1)
Shelf.noteDownload(idx, work(2, "Solaris", "Stanisław Lem", { categories = { fiction, scifi } }), 200, "200 - Solaris.epub", 700, 1)
Shelf.noteDownload(idx, work(3, "O Iluminado", "Stephen King", { categories = { fiction, horror }, completed = true }), 300, "300 - O Iluminado.epub", 800, 1)
Shelf.noteDownload(idx, work(4, "Sapiens", "Yuval Harari", { categories = { nonfic }, files = { { id = 400, format = "pdf", primary = true }, { id = 401, format = "epub" } } }), 400, "400 - Sapiens.pdf", 5000, 1)
local t = function(cards) local o = {} for _, c in ipairs(cards) do o[#o + 1] = c.title end return table.concat(o, "|") end

eq(select(1, Shelf.totals(idx)), 4, "quatro obras no aparelho")
eq(select(2, Shelf.totals(idx)), 7400, "bytes dos arquivos")
eq(t(Shelf.list(idx)), "Duna|O Iluminado|Sapiens|Solaris", "por título, sem acento")
eq(t(Shelf.list(idx, { sort = "author" })), "Duna|Solaris|O Iluminado|Sapiens", "por autor")
eq(t(Shelf.list(idx, { sort = "recent" })), "Sapiens|O Iluminado|Solaris|Duna", "mais novas primeiro")
eq(t(Shelf.list(idx, { category = 1 })), "Duna|O Iluminado|Solaris", "a categoria de cima conta as de baixo")
eq(t(Shelf.list(idx, { category = 2 })), "Duna|Solaris", "a categoria de baixo")
eq(t(Shelf.list(idx, { author = 20 })), "Solaris", "por autor (id)")
eq(t(Shelf.list(idx, { series = "Duna" })), "Duna", "por série")
eq(t(Shelf.list(idx, { favorite = true })), "Duna", "favoritos")
eq(t(Shelf.list(idx, { state = "reading" })), "Duna", "lendo")
eq(t(Shelf.list(idx, { state = "finished" })), "O Iluminado", "concluídas")
eq(t(Shelf.list(idx, { state = "unread" })), "Sapiens|Solaris", "não lidas")
eq(t(Shelf.list(idx, { format = "pdf" })), "Sapiens", "por formato do arquivo que está no aparelho")
eq(t(Shelf.list(idx, { search = "stanislaw" })), "Solaris", "busca sem acento")
eq(t(Shelf.list(idx, { search = "ILUMIN king" })), "O Iluminado", "busca por título e autor, várias palavras")
eq(t(Shelf.list(idx, { search = "nada disso" })), "", "busca sem resultado")
eq(t(Shelf.list(idx, { category = 1, favorite = true })), "Duna", "filtros juntos")

local card = Shelf.list(idx, { search = "sapiens" })[1]
eq(card.fileId, 400, "o arquivo que está no aparelho"); eq(card.format, "pdf", "o formato dele"); eq(card.downloaded, true, "marcada como baixada"); eq(card.key, "codice:4", "a chave")
eq(Shelf.list(idx, { search = "duna" })[1].percent, 42, "o progresso vem junto")

local cats = Shelf.categories(idx)
eq(#cats, 2, "duas categorias de cima"); eq(cats[1].name, "Ficção", "em ordem"); eq(cats[1].count, 3, "com a contagem do aparelho"); eq(cats[2].name, "Não ficção", "a outra")
local sub = Shelf.categories(idx, 1)
eq(#sub, 2, "duas dentro de Ficção"); eq(sub[1].name, "Ficção científica", "científica primeiro"); eq(sub[1].count, 2, "duas obras"); eq(sub[2].name, "Terror", "terror"); eq(sub[2].count, 1, "uma obra")
eq(#Shelf.categories(idx, 4), 0, "categoria sem filhas")
local authors = Shelf.authors(idx)
eq(#authors, 4, "quatro autores"); eq(authors[1].name, "Frank Herbert", "ordem alfabética"); eq(authors[2].name, "Stanisław Lem", "Lem depois de Herbert, sem o acento atrapalhar")
eq(#Shelf.series(idx), 1, "uma série"); eq(Shelf.series(idx)[1].name, "Duna", "a série")
local fm = Shelf.formats(idx)
eq(#fm, 2, "dois formatos"); eq(fm[1].format, "epub", "epub"); eq(fm[1].count, 3, "três obras em epub"); eq(fm[2].format, "pdf", "pdf"); eq(fm[2].count, 1, "uma em pdf")

local pg = Shelf.page(Shelf.list(idx), 1, 3)
eq(#pg.items, 3, "três por página"); eq(pg.pages, 2, "duas páginas"); eq(pg.total, 4, "quatro no total")
eq(Shelf.page(Shelf.list(idx), 2, 3).items[1].title, "Solaris", "a segunda página")
eq(Shelf.page(Shelf.list(idx), 99, 3).page, 2, "página além do fim vira a última")
eq(Shelf.page(Shelf.list(idx), -4, 3).page, 1, "página negativa vira a primeira")
eq(Shelf.page({}, 1, 3).pages, 1, "lista vazia tem uma página")

-- o arquivo e o que sobrou
eq(Shelf.has(idx, 300), true, "o arquivo está na prateleira"); eq(Shelf.has(idx, 999), false, "outro não")
eq(select(1, Shelf.findFile(idx, 100)).title, "Duna", "de que obra é o arquivo")
local gone = Shelf.prune(idx, function(name) return name ~= "300 - O Iluminado.epub" end)
eq(gone, 1, "uma obra saiu: o arquivo foi apagado do aparelho"); eq(Shelf.has(idx, 300), false, "e some da prateleira"); eq(select(1, Shelf.totals(idx)), 3, "três ficam")

-- um segundo arquivo da mesma obra, e o que o servidor diz depois
Shelf.noteDownload(idx, work(4, "Sapiens", "Yuval Noah Harari", { categories = { nonfic } , files = { { id = 400, format = "pdf", primary = true }, { id = 401, format = "epub" } } }), 401, "401 - Sapiens.epub", 1000, 2)
eq(select(1, Shelf.totals(idx)), 3, "a mesma obra, dois arquivos: continua uma"); eq(select(2, Shelf.totals(idx)), 7400 - 800 + 1000 - 0, "mas os bytes dos dois")
eq(Shelf.list(idx, { search = "sapiens" })[1].fileCount, 2, "a obra tem dois arquivos aqui")
eq(Shelf.has(idx, 400) and Shelf.has(idx, 401), true, "os dois arquivos estão na prateleira")
local changed = Shelf.merge(idx, { works = { work(1, "Duna", "Frank Herbert", { favorite = false, percent = 80, inProgress = true, categories = { fiction, scifi } }), work(77, "Outra", "X") }, missing = { 2 } })
eq(changed, true, "o servidor mudou coisas")
eq(Shelf.list(idx, { search = "duna" })[1].percent, 80, "o progresso novo"); eq(Shelf.list(idx, { favorite = true })[1], nil, "deixou de ser favorita")
eq(Shelf.has(idx, 100), true, "o arquivo continua no aparelho depois de atualizar")
eq(Shelf.has(idx, 200), false, "obra que o servidor não conhece mais é esquecida")
eq(Shelf.findFile(idx, 77), nil, "o servidor não põe na prateleira obra que não está no aparelho")
eq(Shelf.merge(idx, { works = {}, missing = {} }), false, "nada mudou")
local ids = Shelf.ids(idx)
eq(table.concat(ids, ","), "1,4", "ids em ordem")
local ch = Shelf.chunks({ 1, 2, 3, 4, 5 }, 2)
eq(#ch, 3, "três partes"); eq(#ch[3], 1, "a última com um só"); eq(#Shelf.chunks({}, 2), 0, "nada em partes")
eq(Shelf.sane(nil).version, 1, "sem arquivo, prateleira nova"); eq(Shelf.sane({ version = 0 }).version, 1, "versão desconhecida, nova"); eq(Shelf.sane(idx), idx, "prateleira boa fica")
local fromCard = Shelf.workFromCard({ id = 9, title = "Cartão", author = "Alguém", fileId = 900, format = "epub", percent = 5 })
eq(fromCard.files[1].id, 900, "do cartão, o arquivo"); eq(#fromCard.categories, 0, "sem categorias até o servidor dizer")

-- a conexão e o aviso da biblioteca
eq(core.connectivity(true, nil, 1000), "online", "com rede e sem chamada: online")
eq(core.connectivity(true, { ok = true, at = 990 }, 1000), "online", "última chamada deu certo")
eq(core.connectivity(false, { ok = true, at = 990 }, 1000), "wifi_off", "sem rede, mesmo que a última tenha dado certo")
eq(core.connectivity(true, { ok = false, at = 990 }, 1000), "server_down", "a chamada de agora há pouco falhou")
eq(core.connectivity(true, { ok = false, at = 100 }, 1000), "online", "falha antiga: tenta de novo")
eq(core.connectivity(false, { ok = false, at = 990 }, 1000), "wifi_off", "sem rede é o primeiro motivo")
local fmtDate = function(t) return "16/10" end
eq(core.offlineNotice("online", 5, fmtDate), nil, "online não avisa")
eq(core.offlineNotice("wifi_off", 5, fmtDate), "Sem conexão: mostrando só o que está no aparelho. Atualizado em 16/10.", "sem rede")
eq(core.offlineNotice("server_down", 5, fmtDate), "Servidor não responde: mostrando só o que está no aparelho. Atualizado em 16/10.", "servidor fora")
eq(core.offlineNotice("wifi_off", nil, fmtDate), "Sem conexão: mostrando só o que está no aparelho.", "sem data de atualização")
eq(core.offlineNotice("wifi_off", 0, fmtDate), "Sem conexão: mostrando só o que está no aparelho.", "data zero é nenhuma")

-- a biblioteca, como dados
local wc = Libview.workCard({ id = 7, title = "Duna", author = "Frank Herbert", coverUrl = "/covers/7", percentComplete = 42, inProgress = true, isFavorite = true,
    fileId = 70, format = "epub", fileCount = 2, series = "Duna", continue = { fileId = 71, format = "pdf" } })
eq(wc.id, 7, "id do cartão"); eq(wc.cover, "/covers/7", "capa"); eq(wc.percent, 42, "progresso"); eq(wc.favorite, true, "favorita")
eq(wc.fileId, 71, "o arquivo é o que se lê"); eq(wc.format, "pdf", "e o formato dele"); eq(wc.key, "codice:7", "chave")
eq(Libview.workCard({ id = 1, title = "X" }).percent, 0, "sem progresso, zero")
local cc = Libview.collectionWorkCard({ id = 3, title = "Vol 1", author = "A", coverUrl = "/c/3", percent = 10, completed = true })
eq(cc.fileCount, 2, "obra de coleção: pergunta os arquivos ao abrir"); eq(cc.completed, true, "concluída"); eq(cc.percent, 10, "progresso")
local cards = Libview.cardsOf({ data = { { id = 1, title = "A" }, { title = "sem id" }, { id = 2, title = "B" } } })
eq(#cards, 2, "ignora o que não tem id"); eq(cards[2].title, "B", "em ordem")
cards = Libview.cardsOf({ works = { { id = 1, title = "A", available = true }, { id = 2, title = "Sumiu", available = false } } }, true)
eq(#cards, 1, "em coleção, as indisponíveis ficam de fora")
eq(#Libview.cardsOf(nil), 0, "sem resposta, sem cartões"); eq(#Libview.cardsOf({}), 0, "resposta vazia")
local shelfIdx = Shelf.new()
Shelf.noteDownload(shelfIdx, { id = 1, title = "A", authors = {}, categories = {}, files = {} }, 10, "10 - A.epub", 5, 1)
local marked = Libview.markDownloaded({ { id = 1 }, { id = 2 } }, shelfIdx)
eq(marked[1].downloaded, true, "A está no aparelho"); eq(marked[2].downloaded, false, "B não")
eq(Libview.queryString({ b = "x y", a = 1, c = "ã&" }), "a=1&b=x%20y&c=%C3%A3%26", "texto de consulta em ordem, com escape")
local pr = Libview.worksParams({ category = 5 }, 3)
eq(pr.category, 5, "categoria"); eq(pr.page, 3, "página"); eq(pr.limit, 6, "seis por página"); eq(pr.series, nil, "em categoria, a série não se dobra"); eq(pr.sort, "title", "por título")
eq(Libview.worksParams({}, 1).series, "collapse", "na biblioteca toda, a série se dobra")
eq(Libview.worksParams({ search = "duna" }, 1).search, "duna", "busca"); eq(Libview.worksParams({ search = "" }, 1).search, nil, "busca vazia não vai")
eq(Libview.worksParams({ favorite = true, inProgress = true }, 1).favorite, "true", "favoritas"); eq(Libview.worksParams({ inProgress = true }, 1).inProgress, "true", "lendo")
eq(Libview.pagerText(2, 14), "2 / 14", "contagem de páginas"); eq(Libview.pagerText(1, 1), "", "uma página não mostra"); eq(Libview.pagerText(1, nil), "", "sem total")
eq(Libview.sizeText(0), "0 B", "zero"); eq(Libview.sizeText(2048), "2 KB", "KB"); eq(Libview.sizeText(1.2 * 1024 * 1024), "1,2 MB", "MB com vírgula"); eq(Libview.sizeText(3 * 1024 * 1024 * 1024), "3,0 GB", "GB")
local rr = Libview.rootRows(9, 340 * 1024 * 1024)
eq(#rr, 6, "seis linhas na raiz"); eq(rr[1].id, "categories", "categorias primeiro"); eq(rr[5].detail, "9 obras · 340,0 MB", "no aparelho: obras e tamanho"); eq(rr[6].id, "all", "todas por último")
eq(Libview.rootRows(1, 0)[5].detail, "1 obra", "uma obra"); eq(Libview.rootRows(nil)[5].detail, nil, "sem saber, sem detalhe")
local det = Libview.detail({ id = 4, title = "Scythe", author = "Neal Shusterman", series = "Arc of a Scythe", seriesIndex = 1, percent = 42,
    categories = { { id = 1, name = "Ficção" }, { id = 2, name = "Distopia", parentId = 1 } },
    files = { { id = 40, format = "epub", language = "pt", primary = true, sizeBytes = 1258291 }, { id = 41, format = "epub", language = "en", sizeBytes = 900 } } },
    { downloaded = { ["40"] = { name = "40 - S.epub" } } }, true)
eq(det.lines[1], "Arc of a Scythe · 1", "série e número"); eq(det.lines[2], "42% lido", "quanto leu"); eq(det.lines[3], "Distopia", "a categoria mais específica")
eq(det.files[1].label, "Português · EPUB (principal)", "o principal"); eq(det.files[1].state, "no aparelho", "está no aparelho"); eq(det.files[1].here, true, "marcado")
eq(det.files[2].state, "baixar · 900 B", "o outro se baixa"); eq(det.files[2].label, "Inglês · EPUB", "idioma")
eq(det.read_text, "Continuar lendo", "em andamento"); eq(det.can_read, true, "dá para ler"); eq(det.can_remove, true, "dá para remover do aparelho")
local off = Libview.detail({ id = 5, title = "Y", files = { { id = 50, format = "pdf" } } }, nil, false)
eq(off.can_read, false, "sem conexão e sem arquivo local, não se lê"); eq(off.files[1].state, "só com conexão", "avisa"); eq(off.can_remove, false, "nada a remover"); eq(off.read_text, "Ler", "ainda não começou")
local done = Libview.detail({ id = 6, title = "Z", completed = true, percent = 100, series = "S", seriesIndex = 2.5, files = {} }, nil, true)
eq(done.lines[1], "S · 2.5", "índice fracionado"); eq(done.lines[2], "Concluído", "concluído"); eq(done.read_text, "Ler", "concluído lê de novo")

-- séries nas grades
eq(Libview.seriesCount({ volumes = 5 }), "5 volumes", "volumes"); eq(Libview.seriesCount({ chapters = 1 }), "1 capítulo", "um capítulo")
eq(Libview.seriesCount({ volumes = 2, chapters = 3, oneShots = 1 }), "2 volumes · 3 capítulos · 1 one-shot", "tudo junto"); eq(Libview.seriesCount({}), "", "nada")
local sc = Libview.workCard({ id = 3, title = "Absolute Batman #5", author = "Scott", coverUrl = "/c/3", percentComplete = 40, fileId = 30,
    collapsed = { collectionId = 21, name = "Absolute Batman", chapters = 5, coverUrl = "/c/9" } })
eq(sc.title, "Absolute Batman", "o cartão é o da série"); eq(sc.cover, "/c/9", "com a capa da série"); eq(sc.subtitle, "5 capítulos", "e o que ela tem")
eq(sc.collection.id, 21, "e a coleção que abre"); eq(sc.percent, 0, "sem o progresso da obra mais nova"); eq(sc.key, "codice:series:21", "chave própria")
eq(Libview.workCard({ id = 1, title = "X", collapsed = nil }).collection, nil, "obra comum não é série")

-- as abas
eq(#core.TAB_IDS, 5, "cinco abas"); eq(core.TAB_IDS[1], "homescreen", "Acervo é a home"); eq(core.TAB_IDS[5], "codice_library", "Biblioteca por último")
eq(core.libraryTab("codice_reading").start.spec.inProgress, true, "Em leitura lista o que se lê"); eq(core.libraryTab("codice_favorites").start.spec.favorite, true, "Favoritos")
eq(core.libraryTab("codice_notes").start.kind, "notes", "Anotações"); eq(core.libraryTab("codice_library").start, nil, "Biblioteca abre na raiz"); eq(core.libraryTab("outra"), nil, "aba que não existe")
for i = 2, 5 do eq(core.libraryTab(core.TAB_IDS[i]) ~= nil, true, "a aba " .. core.TAB_IDS[i] .. " está definida") end
eq(Libview.worksParams({ inProgress = true }, 1).sort, nil, "em leitura: a ordem é a do servidor (o último aberto)")
eq(Libview.worksParams({ inProgress = true, sort = "title" }, 1).sort, "title", "mas se pedirem uma ordem, vale")
eq(Libview.worksParams({ favorite = true }, 1).sort, "title", "favoritas por título")

-- a página de uma série
eq(Libview.unitLabel("chapter", 5), "Cap. 5", "capítulo"); eq(Libview.unitLabel("volume", 27.5), "Vol. 27,5", "volume fracionado"); eq(Libview.unitLabel("oneshot", nil), "Único", "único")
eq(Libview.unitLabel("extra", nil), "Compl.", "complementar"); eq(Libview.unitLabel(nil, 3), "3", "sem unidade, o número"); eq(Libview.unitLabel(nil, nil), "", "nada")
eq(Libview.stepText({ unit = "chapter", position = 5, title = "Batman #5" }), "Cap. 5", "o passo pelo número"); eq(Libview.stepText({ title = "Sem número" }), "Sem número", "ou pelo título")
eq(Libview.goOnText({ unit = "chapter", position = 5, started = true }), "Continuar: Cap. 5", "continuar"); eq(Libview.goOnText({ unit = "chapter", position = 6, begun = true }), "Próximo: Cap. 6", "próximo")
eq(Libview.goOnText({ unit = "chapter", position = 1 }), "Começar: Cap. 1", "começar")
local ss = Libview.seriesSheet({ collection = { id = 21, name = "Absolute Batman", coverUrl = "/covers/placeholder.svg" },
    works = { { id = 31, title = "AB #1", author = "S", coverUrl = "/c/31", unit = "chapter", position = 1, completed = true, available = true },
              { id = 32, title = "AB #2", coverUrl = "/c/32", unit = "chapter", position = 2, percent = 40, started = true, available = true },
              { id = 33, title = "AB #3", coverUrl = "/c/33", unit = "chapter", position = 3, available = true },
              { id = 34, title = "Sumiu", unit = "chapter", position = 4, available = false } },
    continue = { id = 32, title = "AB #2", unit = "chapter", position = 2, started = true, begun = true } }, shelfIdx)
eq(ss.name, "Absolute Batman", "nome"); eq(ss.subtitle, "3 capítulos · 1 lido", "quantos e quantos lidos"); eq(ss.heading, "CAPÍTULOS", "título da lista")
eq(#ss.rows, 3, "as indisponíveis ficam de fora"); eq(ss.rows[1].label, "Cap. 1", "rótulo"); eq(ss.rows[1].state, "lido", "lido"); eq(ss.rows[2].state, "40%", "em andamento"); eq(ss.rows[3].state, nil, "não começado")
eq(ss.go_on.text, "Continuar: Cap. 2 (40%)", "o botão"); eq(ss.go_on.card.id, 32, "abre o capítulo certo"); eq(ss.cover, "/c/31", "sem capa própria, a do primeiro")
eq(ss.rows[1].card.fileCount, 2, "abrir um capítulo pergunta os arquivos, se houver mais de um")
local sp = Libview.seriesSheet({ collection = { name = "Berserk", publisher = "Panini, JBC" }, works = { { id = 1, title = "A", unit = "volume", position = 1, available = true, completed = true }, { id = 2, title = "B", unit = "volume", position = 2, available = true } } }, nil)
eq(sp.subtitle, "Panini, JBC · 2 volumes · 1 lido", "a editora vem antes das contas"); eq(sp.publisher, "Panini, JBC", "a editora da ficha")
eq(Libview.seriesSheet({ collection = { name = "X", publisher = "" }, works = {} }, nil).publisher, nil, "sem editora, nada")
local pc = Libview.workCard({ id = 9, title = "Berserk 3", collapsed = { collectionId = 4, name = "Berserk", volumes = 3, publisher = "Panini" } })
eq(pc.publisher, "Panini", "o cartão da série guarda a editora"); eq(pc.subtitle, "Panini · 3 volumes", "a editora vem antes das contas")
eq(Libview.workCard({ id = 9, title = "x", collapsed = { collectionId = 4, name = "Y", volumes = 1 } }).publisher, nil, "sem editora no cartão")
-- the story of a series (DEC-202): the order, the loose chapters folded under the volume, the dividers, the stretches no file contains
local sw = {
    { id = 1, title = "Cap 1", unit = "chapter", position = 1, available = true, volumeNumber = 1, completed = true },
    { id = 2, title = "Cap 2", unit = "chapter", position = 2, available = true, volumeNumber = 1 },
    { id = 30, title = "Vol 1", unit = "volume", position = 1, available = true, coversFrom = 1, coversTo = 2 },
    { id = 8, title = "Cap 8", unit = "chapter", position = 8, available = true, volumeNumber = 2 },
    { id = 50, title = "Vol 9", unit = "volume", position = 9, available = true },
}
local st = Libview.seriesSheet({ collection = { name = "Berserk" }, works = sw, continue = { id = 2, title = "Cap 2", unit = "chapter", position = 2 },
    story = { ranged = true, order = { 30, 8 }, nested = { ["30"] = { 1, 2 } }, unplaced = { 50 }, gaps = { { from = 3, to = 7 } }, chapters = 3, read = 2 } }, nil)
local kinds = {}
for _, r in ipairs(st.rows) do kinds[#kinds + 1] = r.divider and ("D:" .. r.divider.heading) or (r.gap and ("G:" .. r.gap) or ("W:" .. r.id)) end
eq(table.concat(kinds, ","), "D:Volume 1,W:30,G:faltam os caps 3 a 7,D:Volume 2,W:8,D:Sem lugar na história,W:50", "a ordem da história, com divisores, buracos e obras sem lugar")
eq(st.rows[1].divider.note, "caps 1 a 2 · 2 capítulos", "o divisor diz a faixa e quantos capítulos")
eq(st.rows[2].title, "caps 1 a 2 (+2 avulsos)", "o volume diz o que reúne e quantos avulsos estão nele")
eq(st.subtitle, "3 capítulos · 2 lidos", "o lido é por conteúdo")
eq(st.go_on.id, 2, "o continuar vem do servidor")
-- no range anywhere and no volume or arc said: the sheet is what it was
local plain = Libview.seriesSheet({ collection = { name = "Uma" }, works = { { id = 1, title = "A", unit = "chapter", position = 1, available = true } },
    story = { ranged = false, order = { 1 }, nested = {}, unplaced = {}, gaps = {} } }, nil)
eq(#plain.rows, 1, "sem faixa nem volume, nada de divisor"); eq(plain.rows[1].divider, nil, "e a primeira linha é a obra")
-- chapters that only say their volume read in the order of the story too, with the dividers made of them
local marked = Libview.seriesSheet({ collection = { name = "M" }, works = { { id = 1, title = "A", unit = "chapter", position = 1, available = true, volumeNumber = 1 },
    { id = 2, title = "B", unit = "chapter", position = 2, available = true, volumeNumber = 2 } }, story = { ranged = false, order = { 1, 2 }, nested = {}, unplaced = {}, gaps = {} } }, nil)
eq(#marked.rows, 4, "dois divisores e duas obras"); eq(marked.rows[3].divider.heading, "Volume 2", "o segundo volume")
eq(Libview.markOf({ unit = "volume", position = 4 }, "volume"), 4, "o volume é o seu próprio"); eq(Libview.markOf({ unit = "extra", volumeNumber = 1 }, "volume"), nil, "a complementar não tem marca")
eq(Libview.markOfSeries({ { unit = "chapter", storyArc = "Eclipse", available = true } }), "arc", "o arco, se não há volume")
local ss2 = Libview.seriesSheet({ collection = { name = "Mista" }, works = { { id = 1, title = "A", unit = "volume", position = 1, available = true }, { id = 2, title = "B", unit = "chapter", position = 1, available = true } } }, nil)
eq(ss2.subtitle, "2 obras", "unidades misturadas: obras"); eq(ss2.heading, "OBRAS", "título"); eq(ss2.go_on, nil, "sem passo, sem botão")
local ss3 = Libview.seriesSheet({ collection = { name = "Uma" }, works = { { id = 99, title = "A", unit = "volume", position = 1, available = true } } }, shelfIdx)
eq(ss3.subtitle, "1 volume", "singular"); eq(ss3.rows[1].here, false, "não está no aparelho")

-- a pergunta de conflito
eq(core.agoText(30), "agora há pouco", "há segundos"); eq(core.agoText(1200), "há 20 min", "minutos"); eq(core.agoText(3 * 3600), "há 3h", "horas")
eq(core.agoText(30 * 3600), "ontem", "ontem"); eq(core.agoText(5 * 86400), "há 5 dias", "dias"); eq(core.agoText(nil), "agora há pouco", "sem número")
eq(core.fileIdOfPath("/mnt/us/documents/Códice/123 - Duna.epub"), 123, "o id do arquivo no nome"); eq(core.fileIdOfPath("livro qualquer.epub"), nil, "outro nome")
eq(core.fileIdOfPath(nil), nil, "sem caminho")
local q = core.placeQuestion({ percent = 50, chapter = "Cap. 14" }, { percentage = 0.64, device = "Web", timestamp = 1000 }, { device = "Web", chapter = "Cap. 18", snippet = "A caminhada noturna" }, "Kindle", 1000 + 5 * 86400)
eq(q.forward, true, "a web está à frente"); eq(q.gap, 14, "diferença em pontos"); eq(q.there.who, "Na web", "quem"); eq(q.there.when, "há 5 dias", "quando"); eq(q.there.percent, 64, "onde")
eq(q.there.chapter, "Cap. 18", "capítulo da web"); eq(q.there.snippet, "A caminhada noturna", "trecho"); eq(q.here.percent, 50, "aqui"); eq(q.here.chapter, "Cap. 14", "capítulo daqui")
eq(q.go_text, "Avançar para 64% (web)", "botão de ir"); eq(q.stay_text, "Permanecer em 50% (aqui)", "botão de ficar")
local back = core.placeQuestion({ percent = 80 }, { percentage = 0.5, device = "Kindle de Ana", timestamp = 10 }, nil, "Kindle de Binaco", 10 + 3600 * 3)
eq(back.forward, false, "o outro está atrás"); eq(back.go_text, "Voltar para 50% (Kindle de Ana)", "voltar, de outro aparelho"); eq(back.there.who, "No Kindle de Ana", "quem é outro aparelho"); eq(back.there.when, "há 3h", "horas")
eq(core.placeQuestion({ percent = 50 }, { percentage = 0.505 }, nil, "K", 0), nil, "menos de um ponto: é o mesmo lugar")
eq(core.placeQuestion({ percent = 50 }, nil, nil, "K", 0), nil, "sem lugar do servidor"); eq(core.placeQuestion({ percent = 50 }, {}, nil, "K", 0), nil, "sem percentual")
eq(core.placeQuestion({ percent = 0 }, { percentage = 0.4, device = "K", timestamp = 1 }, nil, "K", 100).there.who, "Neste leitor", "o mesmo aparelho (cópia nova): neste leitor")

-- destaques e notas: a identidade, o que mudou, o que fazer com a resposta
eq(#Notesync.ref(5, "/body/DocFragment[2]/body/p[1]/text().0", "/body/DocFragment[2]/body/p[1]/text().9"), 16, "a referência tem 16 caracteres")
eq(Notesync.ref(5, "a", "b"), Notesync.ref(5, "a", "b"), "a mesma passagem é sempre a mesma referência")
eq(Notesync.ref(5, "a", "b") ~= Notesync.ref(5, "a", "c"), true, "outro fim, outra referência"); eq(Notesync.ref(5, "a", "b") ~= Notesync.ref(6, "a", "b"), true, "outro livro, outra")
eq(Notesync.sig("x", "y") ~= Notesync.sig("x", "z"), true, "a nota mudou: a assinatura muda"); eq(Notesync.sig("x", nil), Notesync.sig("x", nil), "a mesma coisa, a mesma")
local items = {
    { pos0 = "p1", pos1 = "p2", text = "trecho um", note = "minha nota", drawer = "lighten", chapter = "Cap 1", datetime = "2026-10-18 10:00:00" },
    { pos0 = "p3", pos1 = "p4", text = "trecho dois", drawer = "underscore", datetime = "2026-10-18 10:05:00" },
    { page = "p9", text = "" , pos0 = nil },            -- um marcador de página: não entra
    { pos0 = "p5", pos1 = "p6", text = "   " },          -- sem trecho: não entra
}
local cur = Notesync.current(77, items)
local nref = 0; for _ in pairs(cur) do nref = nref + 1 end
eq(nref, 2, "só os destaques com trecho entram")
local st = Notesync.new()
eq(Notesync.plan(st, cur), true, "tudo é novo: há o que enviar")
local puts = 0; for _, op in pairs(st.pending) do if op == "put" then puts = puts + 1 end end
eq(puts, 2, "dois envios na fila")
local r1 = Notesync.ref(77, "p1", "p2")
Notesync.sent(st, cur[r1], 901); Notesync.sent(st, cur[Notesync.ref(77, "p3", "p4")], 902)
eq(st.items[r1].id, 901, "o número no Códice fica guardado"); eq(next(st.pending), nil, "fila vazia depois de enviar")
eq(Notesync.plan(st, cur), false, "nada mudou: nada a enviar")
items[1].note = "nota editada"
cur = Notesync.current(77, items)
eq(Notesync.plan(st, cur), true, "a nota mudou"); eq(st.pending[r1], "put", "vai de novo")
Notesync.sent(st, cur[r1], 901)
local without = { items[2] }
cur = Notesync.current(77, without)
eq(Notesync.plan(st, cur), true, "um destaque sumiu"); eq(st.pending[r1], "delete", "apagar no Códice")
Notesync.deleted(st, r1)
eq(st.items[r1], nil, "saiu do estado"); eq(Notesync.plan(st, cur), false, "nada mais")
-- feito e apagado antes de enviar: nada a apagar
local st2 = Notesync.new()
local c2 = Notesync.current(1, { { pos0 = "a", pos1 = "b", text = "x" } })
Notesync.plan(st2, c2)
eq(Notesync.plan(st2, {}), false, "feito e apagado antes de enviar"); eq(next(st2.pending), nil, "não sobra nada na fila")
eq(table.concat(Notesync.known(st), ","), "902", "os números que se perguntam ao Códice")
local b = Notesync.body(cur[Notesync.ref(77, "p3", "p4")], "Kindle", 902)
eq(b.text, "trecho dois", "corpo do envio"); eq(b.note, "", "sem nota, vazia"); eq(b.id, 902, "com o número que tem no Códice"); eq(b.device, "Kindle", "o aparelho")
-- a resposta do Códice
local st3 = Notesync.new()
local cur3 = Notesync.current(77, { { pos0 = "p1", pos1 = "p2", text = "um", note = "local" }, { pos0 = "p3", pos1 = "p4", text = "dois" } })
Notesync.plan(st3, cur3)
local ref1, ref2 = Notesync.ref(77, "p1", "p2"), Notesync.ref(77, "p3", "p4")
Notesync.sent(st3, cur3[ref1], 11); Notesync.sent(st3, cur3[ref2], 12)
local act = Notesync.merge(st3, cur3, { notes = {
    { id = 11, ref = ref1, kind = "note", body = "local" },                    -- igual: nada
    { id = 12, ref = ref2, kind = "note", body = "editada na web" },           -- a web mudou a nota
    { id = 13, kind = "highlight", quote = "da web", body = "", place = "/body/DocFragment[3]/body/p[10]" }, -- nova, só o parágrafo
    { id = 14, ref = "outroaparelho1", kind = "highlight", quote = "de outro", body = "", pos0 = "q1", pos1 = "q2" }, -- nova, de um leitor
}, gone = { 99 } })
eq(#act.update, 1, "uma nota mudou na web"); eq(act.update[1].ref, ref2, "a certa"); eq(act.update[1].note, "editada na web", "o texto novo")
eq(#act.add, 2, "duas novas"); eq(act.add[1].pos0, nil, "a da web não tem pontos exatos"); eq(act.add[2].pos0, "q1", "a de outro leitor tem")
eq(#act.remove, 0, "nada a remover: o número 99 não é nosso")
Notesync.plan(st3, cur3)
st3.pending[ref1] = "put"
local act2 = Notesync.merge(st3, cur3, { notes = { { id = 11, ref = ref1, kind = "note", body = "diferente na web" } }, gone = { 12 } })
eq(#act2.update, 0, "o que está esperando para ser enviado é do leitor: o Códice espera"); eq(#act2.remove, 1, "a nota 12 sumiu do Códice"); eq(act2.remove[1].ref, ref2, "remove o destaque certo")
local st4 = Notesync.new()
local act3 = Notesync.merge(st4, Notesync.current(77, { { pos0 = "p1", pos1 = "p2", text = "um" } }), { notes = { { id = 50, ref = ref1, kind = "highlight", body = "" } }, gone = {} })
eq(st4.items[ref1].id, 50, "o estado se perdeu: adota o destaque que já tinha o mesmo identificador"); eq(#act3.add, 0, "e não o põe duas vezes")
eq(Notesync.sane(nil).version, 1, "sem estado, um novo"); eq(Notesync.sane({ version = 9 }).version, 1, "versão desconhecida, novo")

eq(core.passage("  uma   frase\ncom  espaços  ", 200), "uma frase com espaços", "espaços juntos e pontas aparadas")
eq(core.passage("um dois três quatro cinco seis sete", 20), "um dois três quatro…", "corta numa palavra")
eq(core.passage("", 20), "", "vazio"); eq(core.passage(nil, 20), "", "sem texto")
eq(core.passage("abcdefghijklmnopqrstuvwxyz", 10), "abcdefghij…", "palavra maior que o limite: corta no limite")
local qs = core.placeQuestion({ percent = 50, chapter = "C", snippet = "daqui" }, { percentage = 0.64, device = "Web", timestamp = 1 }, nil, "K", 10)
eq(qs.here.snippet, "daqui", "o trecho daqui entra na pergunta")

-- a tela de bloqueio
local cs = core.lockscreenCovers({ { id = 1 }, { id = 2 }, { id = 3 }, { id = 4 } }, function(c) return c.id ~= 2 end, 2)
eq(#cs, 2, "no máximo dois"); eq(cs[1].id, 1, "em ordem"); eq(cs[2].id, 3, "pula quem não tem capa")
eq(#core.lockscreenCovers({}, function() return true end), 0, "sem livros, sem capas"); eq(#core.lockscreenCovers(nil, function() return true end), 0, "sem lista")
eq(core.lockscreenSignature({ { id = 1 }, { id = 3 } }, 600, 800), "2:600x800:1,3", "assinatura"); eq(core.lockscreenSignature({}, 600, 800), "2:600x800:", "sem livros")
eq(core.updatedNotice("0.14.0", true), "Códice atualizado neste Kindle para a versão 0.14.0.", "aviso no Kindle"); eq(core.updatedNotice("0.14.0", false), "Códice atualizado neste leitor para a versão 0.14.0.", "em outro leitor")

eq(core.pairedNotice("ana", true, false), "Conectado ao Códice como ana.\n\nA home e a barra de abas do Códice foram montadas.\n\nO catálogo e a sincronização já estão configurados.", "conectado, sem livro aberto")
eq(core.pairedNotice("ana", false, true):find("reinicie", 1, true) ~= nil, true, "com livro aberto, pede para reiniciar"); eq(core.pairedNotice("ana", false, false):find("reinicie", 1, true), nil, "sem livro, não pede")

print(string.format("%d verificações, %d falhas", count, failures))
os.exit(failures == 0 and 0 or 1)
