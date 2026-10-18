--[[--
The logic of the plugin that does not need KOReader: the address of the instance, the versions, what the answers of the server mean, and
what is written in the settings of the OPDS and of KOSync. It is here, apart from the screens, so that it can be tested with plain Lua
(tests/run.lua).
]]--

local M = {}

M.PLUGIN_VERSION = "0.14.6"
M.CLIENT = "codice-ereader/" .. M.PLUGIN_VERSION
-- The name the Códice's module is registered under on the main screens of KOReader (`ui.codice_module`). It must not be "codice": KOReader
-- registers every plugin under the name of its folder, which is "codice", right after the plugin's init, and that would take the place of the
-- module (it did: a tap on a book found the plugin of the Simple UI and called a method it does not have).
M.MODULE_SLOT = "codice_module"
M.SERVER_TITLE = "Códice" -- the title of the entry in the OPDS catalogs of KOReader: the one this plugin owns

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

--- What a person typed as the address of their instance, as the address to talk to: scheme, host and port, nothing else. Without a scheme it
--- is https. Returns nil and a reason when it cannot be one.
function M.normalizeUrl(typed)
    typed = trim(typed)
    if typed == "" then return nil, "empty" end
    if not typed:match("^%a[%w+.-]*://") then typed = "https://" .. typed end
    local scheme, host = typed:match("^(https?)://([^/%?#%s]+)")
    if not scheme or host == "" or host:find("@", 1, true) then return nil, "invalid" end
    return scheme .. "://" .. host
end

local function parts(version)
    local out = {}
    for n in tostring(version or ""):gmatch("%d+") do out[#out + 1] = tonumber(n) end
    return out
end

--- Whether version a is older than b ("0.1.0" < "0.2.0").
function M.versionLess(a, b)
    local x, y = parts(a), parts(b)
    for i = 1, math.max(#x, #y) do
        local p, q = x[i] or 0, y[i] or 0
        if p ~= q then return p < q end
    end
    return false
end

--- Whether this plugin is new enough for a configuration (it carries the oldest plugin that understands it).
function M.pluginMeets(minPlugin)
    return not minPlugin or not M.versionLess(M.PLUGIN_VERSION, minPlugin)
end

--- The code as the person types it: capitals, no dash.
function M.plainCode(code)
    return (tostring(code or ""):upper():gsub("[%s-]", ""))
end

--- What the answer to the ask for the token means: "ok", "pending", "slow", "expired", "denied", or "error". For "slow" the second value is
--- the new interval. `code` is the HTTP status and `data` the decoded body (a table, or nil).
function M.pollOutcome(code, data)
    if code == 200 and type(data) == "table" and data.token and data.token ~= "" then return "ok" end
    local err = type(data) == "table" and data.error or nil
    if err == "authorization_pending" then return "pending" end
    if err == "slow_down" then return "slow", tonumber(data.interval) end
    if err == "expired_token" then return "expired" end
    if err == "access_denied" then return "denied" end
    return "error"
end

--- A sentence for a person for what the server answered when asked for a code (not a transport failure).
function M.requestFailure(code, data)
    if type(data) == "table" and type(data.message) == "string" and data.message ~= "" then return data.message end
    if code == 429 then return "Há pedidos demais esperando. Espere alguns minutos." end
    return "O servidor não aceitou o pedido (HTTP " .. tostring(code) .. ")."
end

--- Puts the entry of the Códice in the list of OPDS servers: the one with the title of this plugin is replaced, else it is added first.
--- Returns whether the list changed.
function M.upsertOpds(servers, cfg, username, token)
    local entry = {
        title = (cfg.opds and cfg.opds.title) or M.SERVER_TITLE,
        url = cfg.opds and cfg.opds.url,
        username = username,
        password = token,
    }
    if not entry.url then return false end
    for i, s in ipairs(servers) do
        if s.title == entry.title then
            if s.url == entry.url and s.username == entry.username and s.password == entry.password then return false end
            -- what else the person set on it (a name for the downloads, sync) stays
            for k, v in pairs(entry) do s[k] = v end
            return true
        end
    end
    table.insert(servers, 1, entry)
    return true
end

local KOSYNC_DEFAULTS = {
    auto_sync = true,
    sync_forward = 3, -- KOSync does not ask by itself: the Códice asks (codice/conflict.lua), with both places in words
    sync_backward = 3, -- do not
    checksum_method = 0, -- the binary one: what the Códice calculates
    send_metadata = false,
}

--- The settings of KOSync with the Códice in them: the server, the user and the key (the MD5 of the access) are set; the rest keeps what the
--- person chose and, where there is nothing, the values the Códice starts with. Changes `settings` and returns it.
function M.applyKosync(settings, cfg, username, key)
    settings = settings or {}
    settings.custom_server = cfg.kosync and cfg.kosync.url or settings.custom_server
    settings.username = username
    settings.userkey = key
    for k, v in pairs(KOSYNC_DEFAULTS) do
        if settings[k] == nil then settings[k] = v end
    end
    -- the generic question of KOSync ("Sync to latest location?") gives way to ours; a person who chose to sync silently keeps that
    if settings.sync_forward == 1 then settings.sync_forward = KOSYNC_DEFAULTS.sync_forward end
    return settings
end

--- Whether a stored configuration is already what the server has: the same ETag.
function M.sameConfig(stored, etag)
    return etag ~= nil and etag ~= "" and stored == etag
end

-- ---------------------------------------------------------------- the home

--- The sections of the home, in the order of the home of the web: greeting and numbers, what to continue, favorites, a few marked
--- passages, and the library as shelves. A section with nothing in it is left out. `home` is the answer of GET /device/home.
function M.homeSections(home)
    local out = {}
    if type(home) ~= "table" then return out end
    local user, stats = home.user, home.stats
    out[#out + 1] = { kind = "greeting", name = user and user.name or nil, stats = stats }
    local function row(title, cards, extra)
        if type(cards) == "table" and #cards > 0 then
            out[#out + 1] = { kind = "row", title = title, cards = cards, total = extra }
        end
    end
    row("Continuar lendo", home.continue)
    row("Favoritos", home.favorites)
    if type(home.notes) == "table" and #home.notes > 0 then out[#out + 1] = { kind = "quotes", title = "Das suas anotações", notes = home.notes } end
    for _, shelf in ipairs(home.shelves or {}) do
        local title = shelf.title or "Acervo"
        if shelf.total and shelf.total > #(shelf.works or {}) then title = title .. " (" .. shelf.total .. ")" end
        row(title, shelf.works)
    end
    return out
end

--- Puts blocks (each `{h = height}`) into pages of `limit` height, in order, never splitting a block; a block taller than a page has a page
--- of its own. Returns a list of pages, each a list of blocks.
function M.paginate(blocks, limit)
    local pages, page, used = {}, {}, 0
    for _, block in ipairs(blocks) do
        if #page > 0 and used + block.h > limit then
            pages[#pages + 1] = page
            page, used = {}, 0
        end
        page[#page + 1] = block
        used = used + block.h
    end
    if #page > 0 then pages[#pages + 1] = page end
    return pages
end

--- Cards of a row, in lines of `per_line`.
function M.lines(cards, per_line, limit)
    local out, line = {}, {}
    for i, card in ipairs(cards) do
        if limit and i > limit then break end
        line[#line + 1] = card
        if #line == per_line then out[#out + 1], line = line, {} end
    end
    if #line > 0 then out[#out + 1] = line end
    return out
end

--- The books of a row of the home (`rows` is "continue", "favorites"...), at most `max`, each with a `key` the grid of the Simple UI keeps it
--- by ("codice:12"). Cards with no id are left out. `home` is the answer of GET /device/home (or its copy kept).
function M.homeItems(home, row, max)
    local out = {}
    if type(home) ~= "table" or type(home[row]) ~= "table" then return out end
    for _, card in ipairs(home[row]) do
        if #out >= (max or 5) then break end
        if type(card) == "table" and card.id then
            local item = {}
            for k, v in pairs(card) do item[k] = v end
            item.key = "codice:" .. tostring(card.id)
            out[#out + 1] = item
        end
    end
    return out
end

--- Whether two answers of the home are the same thing (so that the screen is drawn again only when something changed): the cards of every
--- row, by id, title, percent and cover. The greeting and the numbers do not count here.
function M.sameRows(a, b)
    local function sig(home)
        local parts = {}
        for _, row in ipairs({ "continue", "favorites" }) do
            for _, c in ipairs(type(home) == "table" and type(home[row]) == "table" and home[row] or {}) do
                parts[#parts + 1] = table.concat({ row, tostring(c.id), tostring(c.title), tostring(c.percent), tostring(c.cover), tostring(c.fileId) }, "|")
            end
        end
        local st = type(home) == "table" and home.stats
        if type(st) == "table" then
            parts[#parts + 1] = table.concat({ "stats", tostring(st.inProgressCount), M.formatBreakdown(st.inProgressBreakdown), tostring(st.completedThisMonth),
                M.formatBreakdown(st.completedBreakdown), tostring(st.totalReadingSeconds) }, "|")
        end
        parts[#parts + 1] = "user|" .. tostring(type(home) == "table" and type(home.user) == "table" and home.user.name)
        for _, note in ipairs(type(home) == "table" and type(home.notes) == "table" and home.notes or {}) do
            parts[#parts + 1] = "note|" .. tostring(note.text) .. "|" .. tostring(note.title)
        end
        for n, shelf in ipairs(type(home) == "table" and type(home.shelves) == "table" and home.shelves or {}) do
            parts[#parts + 1] = "shelf|" .. n .. "|" .. tostring(shelf.id) .. "|" .. tostring(shelf.title) .. "|" .. tostring(shelf.total)
            for _, c in ipairs(type(shelf.works) == "table" and shelf.works or {}) do
                parts[#parts + 1] = table.concat({ "s" .. n, tostring(c.id), tostring(c.title), tostring(c.percent), tostring(c.cover) }, "|")
            end
        end
        return table.concat(parts, "\n")
    end
    return sig(a) == sig(b)
end

--- The folder of the plugin, from the path of one of its files in the `codice/` folder (what `debug.getinfo(1, "S").source` says: "@" and the
--- path, absolute or relative to where KOReader runs). Nil when the path is not one of those. A relative path is made absolute with `cwd`.
function M.pluginDirFromSource(source, cwd)
    if type(source) ~= "string" or source:sub(1, 1) ~= "@" then return nil end
    local dir = source:sub(2):match("^(.*)/codice/[^/]+%.lua$")
    if not dir or dir == "" then return nil end
    dir = dir:gsub("^%./", "")
    if dir:sub(1, 1) ~= "/" and type(cwd) == "string" and cwd ~= "" then
        local base = cwd:gsub("/+$", "")
        dir = dir == "." and base or (base .. "/" .. dir)
    end
    return dir
end

--- The first line of an error message (the rest is the traceback), to show a person.
function M.firstLine(err)
    local line = tostring(err or ""):match("^[^\n]*") or ""
    if #line > 240 then line = line:sub(1, 240) .. "…" end
    return line
end

--- How many shelves (categories of the home) have a module of their own.
M.SHELF_SLOTS = 6

--- The works of shelf number `n` of the home, the way homeItems gives a row (each with its `key`), at most `max`. Keys carry the shelf id, so
--- that the same work on two shelves is two different cells.
function M.shelfItems(home, n, max)
    local out = {}
    local shelf = type(home) == "table" and type(home.shelves) == "table" and home.shelves[n] or nil
    if type(shelf) ~= "table" or type(shelf.works) ~= "table" then return out end
    for _, card in ipairs(shelf.works) do
        if #out >= (max or 5) then break end
        if type(card) == "table" and card.id then
            local item = {}
            for k, v in pairs(card) do item[k] = v end
            item.key = "codice:s" .. tostring(shelf.id or n) .. ":" .. tostring(card.id)
            out[#out + 1] = item
        end
    end
    return out
end

--- The title of shelf number `n` as the home shows it ("Ficção (40)" when there are more works than the shelf holds), or nil when there is no
--- such shelf.
function M.shelfLabel(home, n)
    local shelf = type(home) == "table" and type(home.shelves) == "table" and home.shelves[n] or nil
    if type(shelf) ~= "table" or not shelf.title then return nil end
    local shown = type(shelf.works) == "table" and #shelf.works or 0
    if tonumber(shelf.total) and shelf.total > shown then return shelf.title .. " (" .. shelf.total .. ")" end
    return shelf.title
end

-- ---------------------------------------------------------------- the first screen, as the web says it

local MONTHS = { "janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro" }

--- "18 de outubro de 2026" from a date table (what `os.date("*t")` gives).
function M.dateLabel(t)
    return string.format("%d de %s de %d", t.day, MONTHS[t.month] or "?", t.year)
end

local WEEKDAYS = { "domingo", "segunda-feira", "terça-feira", "quarta-feira", "quinta-feira", "sexta-feira", "sábado" }

--- "domingo, 18 de outubro" (the year is left out: it is a glance at the day).
function M.dayLabel(t)
    return string.format("%s, %d de %s", WEEKDAYS[t.wday] or "?", t.day, MONTHS[t.month] or "?")
end

--- "09:11".
function M.timeLabel(t)
    return string.format("%02d:%02d", t.hour, t.min)
end

--- "Bom dia, ana :)" (no name: "Bom dia"). The smiley is the web's.
function M.greeting(hour, name)
    local word = hour < 12 and "Bom dia" or (hour < 18 and "Boa tarde" or "Boa noite")
    name = trim(name)
    if name == "" then return word end
    return word .. ", " .. name .. " :)"
end

--- A count as the web writes it in pt-BR: 1.420.
function M.formatCount(n)
    n = math.floor(tonumber(n) or 0)
    local s = tostring(math.abs(n))
    s = s:reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "")
    return (n < 0 and "-" or "") .. s
end

local KINDS = {
    { "livros", "livro", "livros" },
    { "quadrinhos", "quadrinho", "quadrinhos" },
    { "mangas", "mangá", "mangás" },
    { "audio", "áudio", "áudios" },
}

--- "11 livros • 2 quadrinhos" from { livros = 11, quadrinhos = 2, ... }; the kinds that are zero are left out.
function M.formatBreakdown(b)
    local out = {}
    if type(b) == "table" then
        for _, kind in ipairs(KINDS) do
            local n = tonumber(b[kind[1]]) or 0
            if n > 0 then out[#out + 1] = n .. " " .. (n == 1 and kind[2] or kind[3]) end
        end
    end
    return table.concat(out, " • ")
end

--- "3h 15min", "45min", "2h", "0min".
function M.formatReadingTime(seconds)
    seconds = tonumber(seconds) or 0
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if h == 0 then return m .. "min" end
    if m == 0 then return h .. "h" end
    return h .. "h " .. m .. "min"
end

--- The two numbers cards of the home ("Em andamento" and "Sua atividade") from the home of the server, or nil when it carries no numbers.
function M.statsCards(home)
    local st = type(home) == "table" and home.stats or nil
    if type(st) ~= "table" then return nil end
    return {
        reading = {
            count = M.formatCount(st.inProgressCount),
            detail = M.formatBreakdown(st.inProgressBreakdown),
        },
        activity = {
            completed = M.formatCount(st.completedThisMonth),
            time = M.formatReadingTime(st.totalReadingSeconds),
            detail = M.formatBreakdown(st.completedBreakdown),
        },
    }
end

--- One of the notes of the home: the one that `roll` (any integer, for instance a random number) falls on. Nil when there is none to show.
function M.pickNote(home, roll)
    local notes = type(home) == "table" and type(home.notes) == "table" and home.notes or {}
    local usable = {}
    for _, n in ipairs(notes) do
        if type(n) == "table" and trim(n.text) ~= "" then usable[#usable + 1] = n end
    end
    if #usable == 0 then return nil end
    return usable[(math.floor(tonumber(roll) or 0) % #usable) + 1]
end

--- What identifies the set of notes of a home, so that a pick is kept while they are the same.
function M.noteSignature(home)
    local out = {}
    for _, n in ipairs(type(home) == "table" and type(home.notes) == "table" and home.notes or {}) do
        out[#out + 1] = tostring(n.text)
    end
    return table.concat(out, "\n")
end

--- The home of the Códice as a preset of the Simple UI: pages of module ids. One page: what the web has on top (the greeting and the numbers)
--- and what to continue. The favorites and the shelves are for the library screen, not for the home; their modules are there to be added.
M.PRESET_ID = "codice_home"
function M.homePreset()
    return {
        id = M.PRESET_ID,
        name = "Códice",
        desc = "Saudação, números e continuar lendo",
        layout = { pages = {
            { id = 1, modules = { "codice_greeting", "codice_stats", "codice_continue" } },
        } },
        settings = {},
    }
end

--- "15% lido" for a work that is being read (from 0 to 100, with decimals). A work with a little read says "1% lido", never "0%".
function M.readLabel(percent)
    percent = tonumber(percent) or 0
    if percent <= 0 then return "" end
    local n = math.floor(percent + 0.5)
    if n < 1 then n = 1 end
    if n > 100 then n = 100 end
    return n .. "% lido"
end

--- How to fill a box of w x h with an image of sw x sh without distorting it and cutting what overflows (what the web calls object-fit: cover):
--- the size the image is scaled to, and where the box starts inside it (the cut is even on both sides).
function M.coverCrop(sw, sh, w, h)
    local scale = math.max(w / sw, h / sh)
    local nw, nh = math.max(w, math.ceil(sw * scale)), math.max(h, math.ceil(sh * scale))
    return { w = nw, h = nh, x = math.floor((nw - w) / 2), y = math.floor((nh - h) / 2) }
end

--- The card of a work with the file that was chosen to open: everything the card had (cover, progress), and the file.
function M.withFile(card, file)
    local out = {}
    for k, v in pairs(card) do out[k] = v end
    out.fileId = file.id
    out.format = file.format
    return out
end

--- The home as it is after a book was read on this reader: that work comes first in "continue", with the percent where it stopped, before the
--- server is asked (it is, a little later). A work only opened, with nothing read, does not enter: opening is not beginning. Returns the home
--- (a new table) and whether anything changed.
function M.touchContinue(home, card, percent)
    if type(home) ~= "table" or type(card) ~= "table" or not card.id then return home, false end
    local list = type(home.continue) == "table" and home.continue or {}
    local found, rest = nil, {}
    for _, c in ipairs(list) do
        if c.id == card.id then found = c else rest[#rest + 1] = c end
    end
    percent = tonumber(percent)
    if not found and (not percent or percent <= 0) then return home, false end
    local moved = {}
    for k, v in pairs(found or card) do moved[k] = v end
    if found then
        for k, v in pairs(card) do if moved[k] == nil then moved[k] = v end end
    end
    moved.key = nil
    if percent and percent >= 0 then moved.percent = percent end
    table.insert(rest, 1, moved)
    local out = {}
    for k, v in pairs(home) do out[k] = v end
    out.continue = rest
    return out, true
end

--- The state of the connection, for the notice of the library: "online"; "wifi_off" (the reader has no network); or "server_down" (it has, and
--- the last call to the server failed not long ago: the server is not answering). `last` is `{ ok, at }` of the last call, or nil.
M.SERVER_DOWN_FOR = 300 -- seconds a failed call keeps saying the server is down; after that the next call is tried again
function M.connectivity(wifi_on, last, now)
    if not wifi_on then return "wifi_off" end
    if type(last) == "table" and last.ok == false and (now or 0) - (last.at or 0) < M.SERVER_DOWN_FOR then return "server_down" end
    return "online"
end

--- The notice of the library when it is showing only what is on the device: why, and how old what it shows is. `kept_at` is when the shelf was
--- last made up to date (seconds since the epoch, or nil), `date` formats it ("16/10").
function M.offlineNotice(state, kept_at, date)
    if state == "online" then return nil end
    local why = state == "wifi_off" and "Sem conexão" or "Servidor não responde"
    local text = why .. ": mostrando só o que está no aparelho."
    if kept_at and kept_at > 0 then text = text .. " Atualizado em " .. date(kept_at) .. "." end
    return text
end

--- The tabs of the bar of the Simple UI for the Códice (DEC-197): the home ("homescreen", called Acervo), what is being read, the favorites, the
--- notes, and the library. `start` says what each opens (see codice/library.lua); the library has none (its root).
M.LIBRARY_TABS = {
    { id = "codice_reading", label = "Em leitura", icon = "continue_", start = { kind = "works", spec = { inProgress = true, title = "Em leitura" } } },
    { id = "codice_favorites", label = "Favoritos", icon = "ko_star", start = { kind = "works", spec = { favorite = true, title = "Favoritos" } } },
    { id = "codice_notes", label = "Anotações", icon = "ko_bookmark", start = { kind = "notes", title = "Anotações" } },
    { id = "codice_library", label = "Biblioteca", icon = "library" },
}
M.TAB_IDS = { "homescreen", "codice_reading", "codice_favorites", "codice_notes", "codice_library" }
M.HOME_TAB_LABEL = "Acervo"

--- The tab of an action id, or nil.
function M.libraryTab(id)
    for _, t in ipairs(M.LIBRARY_TABS) do
        if t.id == id then return t end
    end
    return nil
end

-- ---------------------------------------------------------------- where the person is, here and elsewhere (DEC-196)

--- "agora há pouco", "há 20 min", "há 3h", "ontem", "há 5 dias": how long ago, from a number of seconds.
function M.agoText(seconds)
    seconds = tonumber(seconds) or 0
    if seconds < 90 then return "agora há pouco" end
    if seconds < 3600 then return string.format("há %d min", math.floor(seconds / 60 + 0.5)) end
    if seconds < 86400 then return string.format("há %dh", math.floor(seconds / 3600)) end
    local days = math.floor(seconds / 86400)
    if days < 2 then return "ontem" end
    return string.format("há %d dias", days)
end

--- The words of a page as a passage to put in a question: spaces collapsed, cut at a word at most `limit` characters long, with an ellipsis when it was cut.
function M.passage(text, limit)
    limit = limit or 200
    text = tostring(text or ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    if #text <= limit then return text end
    local cut = text:sub(1, limit)
    -- not in the middle of a letter that takes more than one byte
    while #cut > 0 and cut:byte(#cut) >= 0x80 and cut:byte(#cut) < 0xC0 do cut = cut:sub(1, #cut - 1) end
    if cut:byte(#cut) and cut:byte(#cut) >= 0xC0 then cut = cut:sub(1, #cut - 1) end
    -- at the end of a word: if the cut fell in the middle of one, back to the space before it
    if not text:sub(#cut + 1, #cut + 1):match("%s") then
        local at = cut:match("^.*()%s")
        if at and at > limit * 0.6 then cut = cut:sub(1, at - 1) end
    end
    return cut .. "…"
end

--- The id of the file of a book that was downloaded to the reader ("123 - Título.epub"), or nil for any other name.
function M.fileIdOfPath(path)
    local name = tostring(path or ""):match("([^/]+)$") or ""
    return tonumber(name:match("^(%d+) %- "))
end

--- The question that is asked when another place of the book (the web's, another reader's) is not the one of this reader, or nil when they are
--- the same for all that matters (less than a point apart). `here` is `{ percent (0-100), chapter }`; `remote` is what KOSync keeps
--- (`{ percentage (0-1), device, timestamp }`); `web`, when it could be had, is the place in words (`{ percent, device, chapter, snippet }`,
--- GET /device/progress/files/{id}/compare). `device_name` is how this reader calls itself; `now` is the time.
function M.placeQuestion(here, remote, web, device_name, now)
    if type(remote) ~= "table" or not tonumber(remote.percentage) then return nil end
    local there = remote.percentage * 100
    local diff = math.abs(there - (here.percent or 0))
    if diff < 1 then return nil end
    local who = (web and web.device) or remote.device or "outro aparelho"
    if who == "Web" then who = "Na web" elseif who == device_name then who = "Neste leitor" else who = "No " .. who end
    local when
    if tonumber(remote.timestamp) and now then when = M.agoText(now - remote.timestamp) end
    local forward = there > (here.percent or 0)
    local there_n, here_n = math.floor(there + 0.5), math.floor((here.percent or 0) + 0.5)
    return {
        here = { who = "Neste leitor", percent = here_n, chapter = here.chapter, snippet = here.snippet },
        there = { who = who, when = when, percent = there_n, chapter = web and web.chapter or nil, snippet = web and web.snippet or nil },
        gap = math.floor(diff + 0.5),
        forward = forward,
        go_text = (forward and "Avançar" or "Voltar") .. " para " .. there_n .. "% (" .. (who == "Na web" and "web" or who:gsub("^No ", "")) .. ")",
        stay_text = "Permanecer em " .. here_n .. "% (aqui)",
    }
end

-- ---------------------------------------------------------------- the lock screen

--- The books (cards) that have a cover to show, at most `max`, in the order they come: `has_cover(card)` says.
function M.lockscreenCovers(cards, has_cover, max)
    local out = {}
    for _, card in ipairs(cards or {}) do
        if #out >= (max or 12) then break end
        if has_cover(card) then out[#out + 1] = card end
    end
    return out
end

--- What the images were made from: the books and the size of the screen. When it is the same, they are not made again.
function M.lockscreenSignature(cards, w, h)
    local ids = {}
    for _, c in ipairs(cards) do ids[#ids + 1] = tostring(c.id) end
    -- (the 2: the look of the images; a change of it makes them again)
    return "2:" .. w .. "x" .. h .. ":" .. table.concat(ids, ",")
end

--- The notice after the plugin was updated: "Códice atualizado neste Kindle para a versão 0.14.0".
function M.updatedNotice(version, is_kindle)
    return "Códice atualizado neste " .. (is_kindle and "Kindle" or "leitor") .. " para a versão " .. tostring(version) .. "."
end

--- What is said when the reader got connected: who, and that the home and the tabs are mounted (when they were); the restart is only asked of
--- whoever already has a book open (KOSync reads its settings when the book is opened).
function M.pairedNotice(username, mounted, book_open)
    local text = "Conectado ao Códice como " .. tostring(username) .. "."
    if mounted then text = text .. "\n\nA home e a barra de abas do Códice foram montadas." end
    text = text .. "\n\nO catálogo e a sincronização já estão configurados."
    if book_open then text = text .. "\nComo há um livro aberto, reinicie o KOReader uma vez." end
    return text
end

-- ---------------------------------------------------------------- files

--- A name that is safe in a file system: no separators or characters a FAT card refuses, no control characters, and short, cut on a whole
--- character (never in the middle of a UTF-8 one).
function M.safeName(s, limit)
    limit = limit or 80
    s = tostring(s or ""):gsub("[%c/\\:*?\"<>|]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if #s > limit then
        local cut = limit
        while cut > 0 do
            local b = s:byte(cut + 1)
            if not b or b < 128 or b >= 192 then break end -- the next byte starts a character
            cut = cut - 1
        end
        s = s:sub(1, cut):gsub("%s+$", "")
    end
    if s == "" then s = "livro" end
    return s
end

--- Where a downloaded book goes inside the folder of the plugin: the id of the file keeps two files with the same title apart (the
--- EPUBs of two editions, or of two languages, are two files of one work).
function M.bookFileName(card)
    local ext = tostring(card.format or "epub"):lower():gsub("[^%w]", "")
    if ext == "" then ext = "epub" end
    return string.format("%d - %s.%s", card.fileId or card.id or 0, M.safeName(card.title, 70), ext)
end

local LANGUAGES = { pt = "Português", en = "Inglês", es = "Espanhol", fr = "Francês", it = "Italiano", de = "Alemão", ja = "Japonês", zh = "Chinês", la = "Latim", ru = "Russo" }

--- The name of a language from its code ("pt-BR" is Português).
function M.languageName(code)
    code = tostring(code or ""):lower():match("^(%a+)") or ""
    if code == "" then return "Idioma não informado" end
    return LANGUAGES[code] or code:upper()
end

--- The choices when a work has more than one file to open, from the answer of GET /device/works/{id}/files: the main file first and then the
--- others, each as "Português - EPUB", with "principal" and "último acessado" on the ones that are, and how far the person is.
function M.fileChoices(files)
    local out = {}
    for _, f in ipairs(files or {}) do
        local label = M.languageName(f.language) .. " - " .. tostring(f.format or "?"):upper()
        local marks = {}
        if f.primary then marks[#marks + 1] = "principal" end
        if f.last then marks[#marks + 1] = "último acessado" end
        if f.completed then
            marks[#marks + 1] = "lido"
        elseif (f.percent or 0) > 0 then
            marks[#marks + 1] = string.format("%d%%", math.floor(f.percent + 0.5))
        end
        if #marks > 0 then label = label .. "  (" .. table.concat(marks, ", ") .. ")" end
        out[#out + 1] = { id = f.id, format = f.format, label = label, primary = f.primary and true or false }
    end
    table.sort(out, function(a, b)
        if a.primary ~= b.primary then return a.primary end
        return a.id < b.id
    end)
    return out
end

--- The name a cover is kept under: its path, as letters and digits.
function M.coverCacheName(path)
    return (tostring(path or ""):gsub("^/", ""):gsub("[^%w]+", "_")) .. ".jpg"
end

--- A path inside the plugin as a zip says it ("infra/sui_core.lua"), if it is safe to write under the folder of the plugin: relative, with
--- plain names only (no "..", no ".", no empty step, no backslash or control character), not too long and not too deep. Nil otherwise.
function M.safeRelPath(name)
    if type(name) ~= "string" or name == "" or #name > 200 then return nil end
    if name:find("[%c\\]") or name:sub(1, 1) == "/" then return nil end
    local depth = 0
    for step in (name .. "/"):gmatch("([^/]*)/") do
        if step == "" or step == "." or step == ".." then return nil end
        depth = depth + 1
    end
    if depth > 6 then return nil end
    return name
end

-- ---------------------------------------------------------------- updates (OTA)

M.RELEASES_URL = "https://api.github.com/repos/ocnaibill/codice-ereader-plugin/releases/latest"
M.ZIP_ASSET = "codice-plugin.zip"
M.SHA_ASSET = "codice-plugin.zip.sha256"

--- What to download from the answer of the releases of GitHub: the version, the address of the zip and of its hash. Nil and a reason when
--- the release does not have what an update needs.
function M.pickRelease(release)
    if type(release) ~= "table" or type(release.tag_name) ~= "string" then return nil, "no release" end
    local version = release.tag_name:gsub("^v", "")
    if #parts(version) == 0 then return nil, "no version" end
    local zip, sha
    for _, asset in ipairs(release.assets or {}) do
        if asset.name == M.ZIP_ASSET then zip = asset.browser_download_url end
        if asset.name == M.SHA_ASSET then sha = asset.browser_download_url end
    end
    if not zip or not sha then return nil, "assets" end
    return { version = version, zip = zip, sha = sha }
end

--- The hash in a file of hashes ("<64 hex>  name"), in lower case; nil when there is none.
function M.parseSha256(text)
    local hex = tostring(text or ""):match("(%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x)")
    return hex and hex:lower() or nil
end

--- Whether a release is newer than this plugin.
function M.isNewer(version)
    return M.versionLess(M.PLUGIN_VERSION, version)
end

return M
