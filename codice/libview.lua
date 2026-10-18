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

--- A work as the web sends it (/device/works) as the card the grid draws.
function Libview.workCard(w)
    local card = {
        id = w.id, title = w.title, author = w.author, cover = w.coverUrl, percent = tonumber(w.percentComplete) or 0,
        inProgress = w.inProgress == true, completed = w.completed == true or w.finished == true, favorite = w.isFavorite == true,
        series = w.series, fileCount = w.fileCount, format = w.format, key = "codice:" .. tostring(w.id),
    }
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
    p.sort = spec.sort or "title"
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

--- The title of the header of a list from its spec.
function Libview.listTitle(spec)
    return spec.title or "Obras"
end

return Libview
