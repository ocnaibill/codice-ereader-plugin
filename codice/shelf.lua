--[[--
The shelf: what the reader keeps about the books it has on the device (DEC-198), so that the library can be browsed with no network and the
person's state in each book is known. This file is only the logic (no KOReader in it, so it is tested with plain Lua: tests/run.lua); keeping
it in a file and asking the server is `codice/shelfstore.lua`.

The index is `{ version, saved_at, works = { [id] = work } }`, a work being what the server answers for it in /device/shelf (title, authors,
categories, series, files, favorite, how far) plus `downloaded = { [fileId] = { name, size, at } }`: the files of it that are on the device. A
work is on the shelf while at least one of its files is.
]]--

local Shelf = {}

Shelf.VERSION = 1

function Shelf.new()
    return { version = Shelf.VERSION, saved_at = 0, works = {} }
end

--- A usable index from whatever was read from the file: a new one when it is not one.
function Shelf.sane(idx)
    if type(idx) ~= "table" or idx.version ~= Shelf.VERSION or type(idx.works) ~= "table" then return Shelf.new() end
    return idx
end

-- ------------------------------------------------------------------ text, for sorting and searching

local FOLD = {
    ["á"] = "a", ["à"] = "a", ["â"] = "a", ["ã"] = "a", ["ä"] = "a", ["å"] = "a", ["Á"] = "a", ["À"] = "a", ["Â"] = "a", ["Ã"] = "a", ["Ä"] = "a", ["Å"] = "a",
    ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Ë"] = "e",
    ["í"] = "i", ["ì"] = "i", ["î"] = "i", ["ï"] = "i", ["Í"] = "i", ["Ì"] = "i", ["Î"] = "i", ["Ï"] = "i",
    ["ó"] = "o", ["ò"] = "o", ["ô"] = "o", ["õ"] = "o", ["ö"] = "o", ["ø"] = "o", ["Ó"] = "o", ["Ò"] = "o", ["Ô"] = "o", ["Õ"] = "o", ["Ö"] = "o", ["Ø"] = "o",
    ["ú"] = "u", ["ù"] = "u", ["û"] = "u", ["ü"] = "u", ["Ú"] = "u", ["Ù"] = "u", ["Û"] = "u", ["Ü"] = "u",
    ["ç"] = "c", ["Ç"] = "c", ["ñ"] = "n", ["Ñ"] = "n", ["ý"] = "y", ["ÿ"] = "y", ["Ý"] = "y",
    ["ł"] = "l", ["Ł"] = "l", ["ś"] = "s", ["Ś"] = "s", ["š"] = "s", ["Š"] = "s", ["ž"] = "z", ["Ž"] = "z", ["ź"] = "z", ["ż"] = "z",
    ["ć"] = "c", ["č"] = "c", ["ń"] = "n", ["ę"] = "e", ["ą"] = "a", ["ß"] = "ss", ["æ"] = "ae", ["œ"] = "oe",
}

--- Lower case, with no accents: "Stanisław" and "stanislaw" are the same for order and for search.
function Shelf.fold(s)
    s = tostring(s or "")
    s = s:gsub("[\194-\244][\128-\191]*", function(ch) return FOLD[ch] or ch end)
    return s:lower()
end

--- The letter an entry goes under in an index of letters: its first letter, with no accent, or "#" for anything else.
function Shelf.letter(name)
    local first = Shelf.fold(name):match("^%s*([a-z])")
    return first and first:upper() or "#"
end

-- ------------------------------------------------------------------ keeping

local function copyFields(from, into, keys)
    for _, k in ipairs(keys) do into[k] = from[k] end
end

local WORK_FIELDS = { "id", "title", "author", "authors", "cover", "series", "seriesIndex", "categories", "favorite", "percent", "inProgress", "completed",
    "finished", "files" }

--- A work as the shelf keeps it, from the answer of the server for it (/device/shelf) or, when only the card of the home is known, from the card
--- (the rest comes at the next refresh).
function Shelf.workFrom(answer)
    local w = { authors = {}, categories = {}, files = {}, downloaded = {} }
    copyFields(answer, w, WORK_FIELDS)
    w.authors = answer.authors or {}
    w.categories = answer.categories or {}
    w.files = answer.files or {}
    w.favorite = answer.favorite == true
    w.percent = tonumber(answer.percent) or 0
    return w
end

function Shelf.workFromCard(card)
    local w = Shelf.workFrom({ id = card.id, title = card.title, author = card.author, cover = card.cover, percent = card.percent,
        inProgress = card.inProgress, completed = card.completed, series = card.series, seriesIndex = card.seriesIndex })
    if card.fileId then w.files = { { id = card.fileId, format = card.format } } end
    return w
end

--- The file `file_id` of work `work` (a table as workFrom gives, or the answer of the server) is on the device with this name and size.
function Shelf.noteDownload(idx, work, file_id, name, size, now)
    local key = tostring(work.id)
    local kept = idx.works[key]
    local w = (work.downloaded ~= nil) and work or Shelf.workFrom(work)
    if kept then
        -- what the server said is newer than what was kept; what is on the device is not lost
        for fid, f in pairs(kept.downloaded or {}) do w.downloaded[fid] = f end
    end
    w.downloaded[tostring(file_id)] = { name = name, size = size or 0, at = now or 0 }
    idx.works[key] = w
    return w
end

--- Forgets the files that are no longer on the device (`exists(name)` says), and the works that have none left. Returns how many works went.
function Shelf.prune(idx, exists)
    local gone = 0
    for key, w in pairs(idx.works) do
        for fid, f in pairs(w.downloaded or {}) do
            if not exists(f.name) then w.downloaded[fid] = nil end
        end
        if next(w.downloaded or {}) == nil then
            idx.works[key] = nil
            gone = gone + 1
        end
    end
    return gone
end

--- Takes in the answer of the server (`{ works, missing }`) for works of the shelf: what it says replaces what was kept, the files on the device
--- stay, and a work it does not know any more is forgotten. Returns whether something changed.
function Shelf.merge(idx, answer)
    local changed = false
    for _, fresh in ipairs(answer.works or {}) do
        local key = tostring(fresh.id)
        local kept = idx.works[key]
        if kept then
            local w = Shelf.workFrom(fresh)
            w.downloaded = kept.downloaded
            idx.works[key] = w
            changed = true
        end
    end
    for _, id in ipairs(answer.missing or {}) do
        if idx.works[tostring(id)] then
            idx.works[tostring(id)] = nil
            changed = true
        end
    end
    return changed
end

--- The ids of the works on the shelf, in order.
function Shelf.ids(idx)
    local out = {}
    for _, w in pairs(idx.works) do out[#out + 1] = w.id end
    table.sort(out)
    return out
end

--- A list in parts of at most `n`.
function Shelf.chunks(list, n)
    local out, cur = {}, nil
    for _, v in ipairs(list) do
        if not cur or #cur >= n then
            cur = {}
            out[#out + 1] = cur
        end
        cur[#cur + 1] = v
    end
    return out
end

--- Where a downloaded file is, by its id: the work and the name, or nil.
function Shelf.findFile(idx, file_id)
    local key = tostring(file_id)
    for _, w in pairs(idx.works) do
        if w.downloaded and w.downloaded[key] then return w, w.downloaded[key] end
    end
    return nil
end

--- Whether the file is on the shelf already.
function Shelf.has(idx, file_id)
    return Shelf.findFile(idx, file_id) ~= nil
end

-- ------------------------------------------------------------------ browsing

--- The card of a work for the grid of the library: what the home's cards have, plus that it is on the device.
function Shelf.card(w)
    -- the file to open: the last read, else the main one, else the first that is on the device
    local pick
    for _, f in ipairs(w.files or {}) do
        if w.downloaded[tostring(f.id)] then
            if f.last then pick = f; break end
            if not pick or (f.primary and not pick.primary) then pick = f end
        end
    end
    if not pick then
        local fid, f = next(w.downloaded or {})
        pick = { id = tonumber(fid), format = f and f.name and f.name:match("%.(%w+)$") }
    end
    local n = 0
    for _ in pairs(w.downloaded or {}) do n = n + 1 end
    return { id = w.id, title = w.title, author = w.author, cover = w.cover, percent = w.percent, inProgress = w.inProgress,
             completed = w.completed or w.finished, series = w.series, seriesIndex = w.seriesIndex, fileId = pick.id, format = pick.format,
             fileCount = n, downloaded = true, favorite = w.favorite, key = "codice:" .. tostring(w.id) }
end

local function inCategory(w, id)
    for _, c in ipairs(w.categories or {}) do
        if c.id == id then return true end
    end
    return false
end

local function byAuthor(w, id)
    for _, a in ipairs(w.authors or {}) do
        if a.id == id then return true end
    end
    return false
end

local function hasFormat(w, format)
    for fid, f in pairs(w.downloaded or {}) do
        local ext = tostring(f.name or ""):match("%.(%w+)$")
        if ext and ext:lower() == format then return true end
    end
    return false
end

local function stateOf(w)
    if w.completed or w.finished then return "finished" end
    if w.inProgress then return "reading" end
    return "unread"
end

local function matches(w, opts)
    if opts.category and not inCategory(w, opts.category) then return false end
    if opts.author and not byAuthor(w, opts.author) then return false end
    if opts.series and w.series ~= opts.series then return false end
    if opts.format and not hasFormat(w, opts.format) then return false end
    if opts.favorite and not w.favorite then return false end
    if opts.state and stateOf(w) ~= opts.state then return false end
    if opts.search and opts.search ~= "" then
        local hay = Shelf.fold((w.title or "") .. " " .. (w.author or ""))
        for term in Shelf.fold(opts.search):gmatch("%S+") do
            if not hay:find(term, 1, true) then return false end
        end
    end
    return true
end

--- The works of the shelf that match `opts` (category, author, series, format, favorite, state, search), as cards, in the order `opts.sort`
--- says: "title" (the default), "author" or "recent" (the newest in the library first).
function Shelf.list(idx, opts)
    opts = opts or {}
    local rows = {}
    for _, w in pairs(idx.works) do
        if matches(w, opts) then rows[#rows + 1] = w end
    end
    local sort = opts.sort or "title"
    table.sort(rows, function(a, b)
        if sort == "author" then
            local x, y = Shelf.fold(a.author), Shelf.fold(b.author)
            if x ~= y then return x < y end
        elseif sort == "recent" then
            if a.id ~= b.id then return a.id > b.id end
        end
        local x, y = Shelf.fold(a.title), Shelf.fold(b.title)
        if x ~= y then return x < y end
        return a.id < b.id
    end)
    local cards = {}
    for _, w in ipairs(rows) do cards[#cards + 1] = Shelf.card(w) end
    return cards
end

--- Page `page` (from 1) of `per` items of a list: `{ items, page, pages, total }`; a page out of range is the nearest one.
function Shelf.page(list, page, per)
    local total = #list
    local pages = math.max(1, math.ceil(total / per))
    page = math.min(math.max(1, math.floor(tonumber(page) or 1)), pages)
    local items = {}
    for i = (page - 1) * per + 1, math.min(total, page * per) do items[#items + 1] = list[i] end
    return { items = items, page = page, pages = pages, total = total }
end

local function sortedByName(rows)
    table.sort(rows, function(a, b)
        local x, y = Shelf.fold(a.name), Shelf.fold(b.name)
        if x ~= y then return x < y end
        return (a.id or 0) < (b.id or 0)
    end)
    return rows
end

--- The categories to browse: those under `parent` (nil: the top ones), each with how many works of the shelf are in it (a category counts the
--- works under it). Empty ones are left out.
function Shelf.categories(idx, parent)
    local seen, rows = {}, {}
    for _, w in pairs(idx.works) do
        for _, c in ipairs(w.categories or {}) do
            if c.parentId == parent or (parent == nil and c.parentId == nil) then
                local row = seen[c.id]
                if not row then
                    row = { id = c.id, name = c.name, count = 0 }
                    seen[c.id] = row
                    rows[#rows + 1] = row
                end
                row.count = row.count + 1
            end
        end
    end
    return sortedByName(rows)
end

--- The authors of the works on the shelf, each with how many.
function Shelf.authors(idx)
    local seen, rows = {}, {}
    for _, w in pairs(idx.works) do
        for _, a in ipairs(w.authors or {}) do
            local row = seen[a.id]
            if not row then
                row = { id = a.id, name = a.name, count = 0 }
                seen[a.id] = row
                rows[#rows + 1] = row
            end
            row.count = row.count + 1
        end
    end
    return sortedByName(rows)
end

--- The series of the works on the shelf, each with how many.
function Shelf.series(idx)
    local seen, rows = {}, {}
    for _, w in pairs(idx.works) do
        if w.series and w.series ~= "" then
            local row = seen[w.series]
            if not row then
                row = { name = w.series, count = 0 }
                seen[w.series] = row
                rows[#rows + 1] = row
            end
            row.count = row.count + 1
        end
    end
    return sortedByName(rows)
end

--- The formats of the files on the device, each with how many works have one: { format = "epub", count = 3 }.
function Shelf.formats(idx)
    local seen, rows = {}, {}
    for _, w in pairs(idx.works) do
        local mine = {}
        for _, f in pairs(w.downloaded or {}) do
            local ext = tostring(f.name or ""):match("%.(%w+)$")
            if ext then mine[ext:lower()] = true end
        end
        for ext in pairs(mine) do
            local row = seen[ext]
            if not row then
                row = { format = ext, count = 0 }
                seen[ext] = row
                rows[#rows + 1] = row
            end
            row.count = row.count + 1
        end
    end
    table.sort(rows, function(a, b) return a.format < b.format end)
    return rows
end

--- How many works are on the shelf, and how many bytes their files take.
function Shelf.totals(idx)
    local works, bytes = 0, 0
    for _, w in pairs(idx.works) do
        works = works + 1
        for _, f in pairs(w.downloaded or {}) do bytes = bytes + (tonumber(f.size) or 0) end
    end
    return works, bytes
end

return Shelf
