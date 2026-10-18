--[[--
The library of the reader, as data (DEC-198): what each screen shows and asks, with no KOReader in it so that it is tested with plain Lua
(tests/run.lua). `codice/library.lua` draws it; the books on the device come from `codice/shelf.lua`.

A "spec" says which works a list is of: `{ category, person, collection, formatGroup, search, favorite, inProgress, downloaded, sort, title }`.
]]--

local core = require("codice/core")

local Libview = {}

Libview.PER_PAGE = 6 -- covers in a page of the grid: three by two

Libview.FORMAT_GROUPS = {
    { id = "ebooks", title = "Livros" },
    { id = "comics", title = "Quadrinhos" },
    { id = "mangas", title = "Mangás" },
    { id = "audio", title = "Áudio" },
}

--- "5 volumes", "12 capítulos", "5 volumes · 3 capítulos" for a series (the `collapsed` of a work): what it holds.
function Libview.seriesCount(c)
    local out = {}
    local function add(n, one, many)
        n = tonumber(n) or 0
        if n > 0 then out[#out + 1] = n .. " " .. (n == 1 and one or many) end
    end
    add(c.volumes, "volume", "volumes")
    add(c.chapters, "capítulo", "capítulos")
    add(c.oneShots, "one-shot", "one-shots")
    return table.concat(out, " · ")
end

--- A work as the web sends it (/device/works) as the card the grid draws.
function Libview.workCard(w)
    local card = {
        id = w.id, title = w.title, author = w.author, cover = w.coverUrl, percent = tonumber(w.percentComplete) or 0,
        inProgress = w.inProgress == true, completed = w.completed == true or w.finished == true, favorite = w.isFavorite == true,
        series = w.series, fileCount = w.fileCount, format = w.format, key = "codice:" .. tostring(w.id),
    }
    -- a work that stands for its whole series in a grid (the newest of it): the card is the series', and tapping it opens the series
    if type(w.collapsed) == "table" and w.collapsed.collectionId then
        local c = w.collapsed
        card.collection = { id = c.collectionId, name = c.name }
        card.title = c.name or card.title
        card.cover = c.coverUrl or card.cover
        card.subtitle = Libview.seriesCount(c)
        -- who publishes it (DEC-203): kept on the card, and said before the count (the line is cut at the width of the card)
        if type(c.publisher) == "string" and c.publisher ~= "" then
            card.publisher = c.publisher
            card.subtitle = c.publisher .. " · " .. card.subtitle
        end
        card.percent = 0
        card.key = "codice:series:" .. tostring(c.collectionId)
    end
    if w.fileId then card.fileId = w.fileId end
    if type(w.continue) == "table" and w.continue.fileId then
        card.fileId, card.format = w.continue.fileId, w.continue.format or card.format
    end
    return card
end

--- A work of a collection (/device/collections/{id}) as a card: it has no file to open yet, so opening it asks which.
function Libview.collectionWorkCard(cw)
    return {
        id = cw.id, title = cw.title, author = cw.author, cover = cw.coverUrl, percent = tonumber(cw.percent) or 0,
        completed = cw.completed == true, fileCount = 2, key = "codice:" .. tostring(cw.id), unavailable = cw.available == false,
    }
end

--- The cards of an answer of the server: `{ data = works }` or, for a collection, `{ works = ... }`.
function Libview.cardsOf(answer, from_collection)
    local out = {}
    -- the answer of a collection is { collection, works, ... }; the one of a list of works is { data, total, ... }
    local list = type(answer) == "table" and (from_collection and answer.works or answer.data) or nil
    for _, w in ipairs(list or {}) do
        if type(w) == "table" and w.id and not (from_collection and w.available == false) then
            out[#out + 1] = from_collection and Libview.collectionWorkCard(w) or Libview.workCard(w)
        end
    end
    return out
end

--- Marks which cards have a file on the device (`shelf` is the index of codice/shelf.lua): `downloaded` is true for them.
function Libview.markDownloaded(cards, shelf)
    for _, card in ipairs(cards) do
        local w = shelf and shelf.works[tostring(card.id)]
        card.downloaded = w ~= nil and next(w.downloaded or {}) ~= nil
    end
    return cards
end

local function escape(s)
    return (tostring(s):gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", c:byte()) end))
end

--- `{ a = 1, b = "x y" }` as "a=1&b=x%20y", in the order of the keys.
function Libview.queryString(params)
    local keys = {}
    for k in pairs(params) do keys[#keys + 1] = k end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = k .. "=" .. escape(params[k]) end
    return table.concat(out, "&")
end

--- What is asked of /device/works for page `page` of the list a spec describes.
function Libview.worksParams(spec, page)
    local p = { page = page or 1, limit = Libview.PER_PAGE }
    if spec.category then p.category = spec.category end
    if spec.person then p.person = spec.person end
    if spec.formatGroup then p.formatGroup = spec.formatGroup end
    if spec.search and spec.search ~= "" then p.search = spec.search end
    if spec.favorite then p.favorite = "true" end
    if spec.inProgress then p.inProgress = "true" end
    -- what is being read comes the one opened last first (the server's own order for it); the rest by title unless another is asked
    if spec.sort or not spec.inProgress then p.sort = spec.sort or "title" end
    -- a series is shown by its volumes, each by itself, in the lists of a person or a category; the grid of the whole library folds them
    if not (spec.category or spec.person or spec.search or spec.favorite or spec.inProgress) then p.series = "collapse" end
    return p
end

--- "‹ 1 / 14 ›" for the foot of a list; empty when it has one page.
function Libview.pagerText(page, pages)
    if (pages or 1) <= 1 then return "" end
    return string.format("%d / %d", page, pages)
end

--- 1,2 MB, 340 KB, as the Portuguese writes it.
function Libview.sizeText(bytes)
    bytes = tonumber(bytes) or 0
    local text
    if bytes >= 1024 * 1024 * 1024 then
        text = string.format("%.1f GB", bytes / 1024 / 1024 / 1024)
    elseif bytes >= 1024 * 1024 then
        text = string.format("%.1f MB", bytes / 1024 / 1024)
    elseif bytes >= 1024 then
        text = string.format("%d KB", math.floor(bytes / 1024 + 0.5))
    else
        text = string.format("%d B", bytes)
    end
    return (text:gsub("%.", ","))
end

--- The rows of the root of the library. `shelf_works` and `bytes` are what is on the device (nil when it is not known).
function Libview.rootRows(shelf_works, bytes)
    local rows = {
        { id = "categories", title = "Categorias" },
        { id = "people", title = "Autores" },
        { id = "collections", title = "Séries e coleções" },
        { id = "formats", title = "Formatos" },
    }
    local device = { id = "device", title = "No aparelho" }
    if shelf_works then
        device.detail = shelf_works == 1 and "1 obra" or (shelf_works .. " obras")
        if bytes and bytes > 0 then device.detail = device.detail .. " · " .. Libview.sizeText(bytes) end
    end
    rows[#rows + 1] = device
    rows[#rows + 1] = { id = "all", title = "Todas as obras" }
    return rows
end

--- The filters over a list of works: which are offered, and which is on.
Libview.CHIPS = {
    { id = "all", title = "Todas" },
    { id = "downloaded", title = "Baixadas" },
    { id = "reading", title = "Lendo" },
}

--- The "11" of "Série · 11" without a decimal when it is a whole number.
local function indexText(n)
    n = tonumber(n)
    if not n or n <= 0 then return "" end
    if n == math.floor(n) then return tostring(math.floor(n)) end
    return tostring(n)
end

--- The sheet of a work, from what the server says of it (an entry of /device/shelf) and the shelf (what is on the device).
--- `{ title, author, lines, files, can_read, read_text, can_remove }`: the lines under the title (series, how far, categories), the files each with
--- its label, what it is ("no aparelho" or "baixar · size") and whether it is on the device.
function Libview.detail(work, shelf_work, online)
    local on_device = {}
    if shelf_work then
        for fid in pairs(shelf_work.downloaded or {}) do on_device[tonumber(fid)] = shelf_work.downloaded[fid] end
    end
    local lines = {}
    if work.series and work.series ~= "" then
        local n = indexText(work.seriesIndex)
        lines[#lines + 1] = work.series .. (n ~= "" and (" · " .. n) or "")
    end
    if work.completed or work.finished then
        lines[#lines + 1] = "Concluído"
    elseif (tonumber(work.percent) or 0) > 0 then
        lines[#lines + 1] = core.readLabel(work.percent)
    end
    -- the categories that are the most specific (the ones above are in the list because of them)
    local parents = {}
    for _, c in ipairs(work.categories or {}) do
        if c.parentId then parents[c.parentId] = true end
    end
    local names = {}
    for _, c in ipairs(work.categories or {}) do
        if not parents[c.id] then names[#names + 1] = c.name end
    end
    if #names > 0 then lines[#lines + 1] = table.concat(names, " · ") end

    local files, any_local = {}, false
    for _, f in ipairs(work.files or {}) do
        local here = on_device[f.id] ~= nil
        any_local = any_local or here
        local state
        if here then
            state = "no aparelho"
        elseif online then
            state = "baixar" .. ((tonumber(f.sizeBytes) or 0) > 0 and (" · " .. Libview.sizeText(f.sizeBytes)) or "")
        else
            state = "só com conexão"
        end
        local label = core.languageName(f.language) .. " · " .. tostring(f.format or "?"):upper()
        if f.primary then label = label .. " (principal)" end
        files[#files + 1] = { id = f.id, format = f.format, label = label, state = state, here = here, last = f.last == true, primary = f.primary == true }
    end
    local reading = (tonumber(work.percent) or 0) > 0 and not (work.completed or work.finished)
    return {
        id = work.id, title = work.title, author = work.author, lines = lines, files = files,
        can_read = any_local or online,
        read_text = reading and "Continuar lendo" or "Ler",
        can_remove = any_local,
    }
end

-- ------------------------------------------------------------ the page of a series (comics and manga: its chapters or volumes)

local UNITS = {
    volume = { short = "Vol.", one = { "volume", "volumes" }, heading = "VOLUMES" },
    chapter = { short = "Cap.", one = { "capítulo", "capítulos" }, heading = "CAPÍTULOS" },
    oneshot = { short = "Único", one = { "único", "únicos" }, heading = "ÚNICOS" },
    extra = { short = "Compl.", one = { "complementar", "complementares" }, heading = "COMPLEMENTARES" },
}

--- The number as the Portuguese writes it: 27.5 is "27,5", 3.0 is "3".
local function numberText(n)
    n = tonumber(n)
    if not n then return "—" end
    if n == math.floor(n) then return tostring(math.floor(n)) end
    return (tostring(n):gsub("%.", ","))
end

--- What a work is called in its series: "Vol. 3", "Cap. 27,5", "Único"; with no unit, the number alone, or nothing.
function Libview.unitLabel(unit, position)
    local u = UNITS[unit]
    if not u then return position and numberText(position) or "" end
    if unit == "oneshot" or unit == "extra" then return u.short end
    return u.short .. " " .. numberText(position)
end

--- What a step of the series is called on the button: "Cap. 5" when it has a unit and a number, else its title.
function Libview.stepText(step)
    if type(step) ~= "table" then return "" end
    if step.unit and UNITS[step.unit] and (step.position ~= nil or step.unit == "oneshot" or step.unit == "extra") then
        return Libview.unitLabel(step.unit, step.position)
    end
    return step.title or ""
end

--- "Continuar: Cap. 5", "Próximo: Cap. 6", "Começar: Cap. 1" (the web's wording).
function Libview.goOnText(step)
    local verb = step.started and "Continuar" or (step.begun and "Próximo" or "Começar")
    return verb .. ": " .. Libview.stepText(step)
end

--- The word of the unit when every work of the sequence has the same one ("capítulos"), else "obras". `heading` is the same in capitals.
local function sequenceWord(works)
    local units, n = {}, 0
    for _, w in ipairs(works) do
        if w.available ~= false and w.unit ~= "extra" then
            units[w.unit or ""] = true
            n = n + 1
        end
    end
    local only, count = nil, 0
    for u in pairs(units) do only, count = u, count + 1 end
    local def = count == 1 and UNITS[only] or nil
    if def then return def.one, def.heading end
    return { "obra", "obras" }, "OBRAS"
end

local function numText(n)
    return n == math.floor(n) and tostring(math.floor(n)) or tostring(n)
end

--- "caps 18 a 26", "cap 5": a stretch of chapters in words.
local function spanWords(from, to)
    if from == to then return "cap " .. numText(from) end
    return "caps " .. numText(from) .. " a " .. numText(to)
end

--- What a work is marked with in the list of the story (DEC-202): the volume it is in (a volume file is its own) or its arc; nil when it has none.
function Libview.markOf(w, mark)
    if w.unit == "extra" then return nil end
    if mark == "volume" then
        local n = w.unit == "volume" and w.position or w.volumeNumber
        return type(n) == "number" and n or nil
    end
    local arc = w.storyArc
    return (type(arc) == "string" and arc ~= "") and arc or nil
end

--- The mark the works of a series carry, the volume before the arc; nil when no work has one.
function Libview.markOfSeries(list)
    local volume, arc = false, false
    for _, w in ipairs(list) do
        if w.unit ~= "extra" and w.available ~= false then
            if type(w.volumeNumber) == "number" then volume = true end
            if type(w.storyArc) == "string" and w.storyArc ~= "" then arc = true end
        end
    end
    return volume and "volume" or (arc and "arc" or nil)
end

--- The divider before a work where the volume (or the arc) changes (DEC-202): `{ heading, note }`, or nil when nothing changes. `previous` is the
--- mark of the work before. It is made of the works that carry the mark; it is not a file.
function Libview.divider(list, w, mark, previous)
    local key = Libview.markOf(w, mark)
    if key == previous or (key == nil and previous == nil) then return nil end
    if key == nil then return { heading = mark == "volume" and "Sem volume" or "Sem arco" } end
    local lo, hi, chapters, members = nil, nil, 0, 0
    for _, o in ipairs(list) do
        if o.available ~= false and Libview.markOf(o, mark) == key then
            members = members + 1
            local a, b
            if o.unit == "chapter" and type(o.position) == "number" then
                chapters = chapters + 1
                a, b = o.position, o.position
            elseif type(o.coversFrom) == "number" and type(o.coversTo) == "number" then
                a, b = o.coversFrom, o.coversTo
            end
            if a then
                lo = lo and math.min(lo, a) or a
                hi = hi and math.max(hi, b) or b
            end
        end
    end
    local parts = {}
    if lo then parts[#parts + 1] = spanWords(lo, hi) end
    if chapters > 0 then
        parts[#parts + 1] = chapters .. (chapters == 1 and " capítulo" or " capítulos")
    else
        parts[#parts + 1] = members .. (members == 1 and " obra" or " obras")
    end
    return { heading = mark == "volume" and ("Volume " .. numText(key)) or key, note = table.concat(parts, " · ") }
end

--- The sheet of a series from the answer of /device/collections/{id} (`{ collection, works, continue, story }`), and the shelf (what is on the device):
--- `{ name, cover, subtitle, go_on, heading, rows }`; a row is `{ id, label, title, state, here, card }` in the order of the series, or, when
--- some work says what it contains or the chapters say their volume (DEC-202), in the order of the story, with `{ divider = { heading, note } }`
--- and `{ gap = "faltam os caps 10 a 11" }` rows between them (they are not works: nothing opens).
function Libview.seriesSheet(data, shelf)
    local c = type(data.collection) == "table" and data.collection or {}
    local rows, read, available = {}, 0, 0
    local list = type(data.works) == "table" and data.works or {}
    local words, heading = sequenceWord(list)
    local rowOf = {}
    for _, w in ipairs(list) do
        if w.available ~= false then
            available = available + 1
            if w.completed then read = read + 1 end
            local mine = shelf and shelf.works[tostring(w.id)]
            local here = mine ~= nil and next(mine.downloaded or {}) ~= nil
            local state
            if w.completed then
                state = "lido"
            elseif w.started or (tonumber(w.percent) or 0) > 0 then
                state = core.readLabel(w.percent):gsub(" lido", "")
            end
            local label = Libview.unitLabel(w.unit, w.position)
            local row = {
                id = w.id, label = label, title = w.title, state = state, here = here,
                card = { id = w.id, title = w.title, author = w.author, cover = w.coverUrl, percent = tonumber(w.percent) or 0, completed = w.completed == true,
                         fileCount = 2, key = "codice:" .. tostring(w.id) },
            }
            rows[#rows + 1] = row
            rowOf[w.id] = { row = row, work = w }
        end
    end
    local subtitle = available .. " " .. words[available == 1 and 1 or 2]
    if read > 0 then subtitle = subtitle .. " · " .. read .. (read == 1 and " lido" or " lidos") end

    -- the story: the order, the loose chapters folded under the volume that holds them, the stretches no file contains, and what is read by content
    local story = type(data.story) == "table" and data.story or nil
    local mark = Libview.markOfSeries(list)
    if story and type(story.order) == "table" and (story.ranged == true or mark) then
        local ordered = {}
        local previous
        local function endOf(w) return type(w.coversTo) == "number" and w.coversTo or (type(w.position) == "number" and w.position or 0) end
        for _, id in ipairs(story.order) do
            local item = rowOf[id]
            if item then
                if mark then
                    local d = Libview.divider(list, item.work, mark, previous)
                    if d then ordered[#ordered + 1] = { divider = d, label = d.heading, title = d.note or "" } end
                    previous = Libview.markOf(item.work, mark)
                end
                local nested = type(story.nested) == "table" and story.nested[tostring(id)]
                if type(item.work.coversFrom) == "number" and type(item.work.coversTo) == "number" then
                    local note = spanWords(item.work.coversFrom, item.work.coversTo)
                    if type(nested) == "table" and #nested > 0 then note = note .. " (+" .. #nested .. " avulsos)" end
                    item.row.title = note
                elseif type(nested) == "table" and #nested > 0 then
                    item.row.title = "+" .. #nested .. " avulsos"
                end
                ordered[#ordered + 1] = item.row
            end
        end
        -- a stretch no file contains is said right after the last work that ends before it
        for _, gap in ipairs(type(story.gaps) == "table" and story.gaps or {}) do
            local at
            for i, r in ipairs(ordered) do
                local item = r.id and rowOf[r.id]
                if item and endOf(item.work) < gap.from then at = i end
            end
            if at then
                local text = gap.from == gap.to and ("falta o cap " .. numText(gap.from)) or ("faltam os caps " .. numText(gap.from) .. " a " .. numText(gap.to))
                table.insert(ordered, at + 1, { gap = text, label = text, title = "" })
            end
        end
        local unplaced = {}
        for _, id in ipairs(type(story.unplaced) == "table" and story.unplaced or {}) do
            if rowOf[id] then unplaced[#unplaced + 1] = rowOf[id].row end
        end
        if #unplaced > 0 then
            ordered[#ordered + 1] = { divider = { heading = "Sem lugar na história" }, label = "Sem lugar na história", title = "" }
            for _, r in ipairs(unplaced) do ordered[#ordered + 1] = r end
        end
        for _, w in ipairs(list) do -- the complementary works end the list
            if w.unit == "extra" and rowOf[w.id] then ordered[#ordered + 1] = rowOf[w.id].row end
        end
        rows = ordered
        -- what is read by content: the chapters a volume holds count (DEC-202)
        if story.ranged == true and type(story.chapters) == "number" and story.chapters > 0 then
            local r = tonumber(story.read) or 0
            subtitle = story.chapters .. (story.chapters == 1 and " capítulo" or " capítulos")
            if r > 0 then subtitle = subtitle .. " · " .. r .. (r == 1 and " lido" or " lidos") end
        end
    end
    local go_on
    if type(data.continue) == "table" and data.continue.id then
        local step = data.continue
        local percent
        for _, r in ipairs(rows) do
            if r.id == step.id and r.card.percent > 0 and step.started then percent = r.card.percent end
        end
        go_on = { id = step.id, text = Libview.goOnText(step) .. (percent and (" (" .. math.floor(percent + 0.5) .. "%)") or ""), card = nil }
        for _, r in ipairs(rows) do
            if r.id == step.id then go_on.card = r.card end
        end
        go_on.card = go_on.card or { id = step.id, title = step.title, fileCount = 2, key = "codice:" .. tostring(step.id) }
    end
    local cover = c.coverUrl
    if (not cover or cover:find("placeholder", 1, true)) and rows[1] then cover = rows[1].card and rows[1].card.cover or nil end
    -- the publisher of the series (DEC-203), first: it is what the heading says of the whole
    local publisher = type(c.publisher) == "string" and c.publisher ~= "" and c.publisher or nil
    if publisher then subtitle = publisher .. " · " .. subtitle end
    return { name = c.name, cover = cover, subtitle = subtitle, publisher = publisher, go_on = go_on, heading = heading, rows = rows }
end

--- The title of the header of a list from its spec.
function Libview.listTitle(spec)
    return spec.title or "Obras"
end

return Libview
