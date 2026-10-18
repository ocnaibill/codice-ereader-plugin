--[[--
The highlights and notes of the book that is open, the same here and in the Códice (DEC-199). What this reader changes is sent (or kept in line
to be sent when there is a network); what the Códice has and this book does not is drawn here; what was deleted on one side goes from the
other. The decisions are in `codice/notesync.lua` (tested apart); this touches the document, the settings of the book and the network.

Only EPUBs, for now: the Códice keeps the places of the other formats in another way and does not take their notes yet.
]]--

local Event = require("ui/event")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local api = require("codice/http")
local core = require("codice/core")
local Notesync = require("codice/notesync")

local Annotations = {}

local KEY = "codice_notes"
local LIMIT_PER_RUN = 40 -- sends in one go: more waits for the next

--- The file of the Códice this book is, and whether its notes are kept: `file_id` when it is an EPUB that came from the Códice, else nil.
local function fileId(ui)
    if not (ui and ui.document and ui.rolling and ui.annotation and ui.doc_settings) then return nil end
    local path = ui.document.file
    if not (path and path:lower():match("%.epub$")) then return nil end
    return core.fileIdOfPath(path)
end

local function loadState(ui)
    return Notesync.sane(ui.doc_settings:readSetting(KEY))
end

local function saveState(ui, state)
    ui.doc_settings:saveSetting(KEY, state)
end

local function request(conn, method, path, body)
    return api.request(conn.url .. path, { method = method, body = body, user = conn.username, password = conn.token })
end

--- Sends what is waiting (in the order of the highlights), until the network fails or the limit of the run is reached. Returns whether all went.
local function flush(plugin, ui, state, current, file_id)
    local conn = plugin:connection()
    if not conn or not NetworkMgr:isOnline() then return false end
    local device = require("device").model or "Leitor"
    local sent = 0
    for ref, op in pairs(state.pending) do
        if sent >= LIMIT_PER_RUN then return false end
        local path = "/device/files/" .. file_id .. "/notes/" .. ref
        if op == "put" and current[ref] then
            local kept = state.items[ref]
            local code, data = request(conn, "PUT", path, Notesync.body(current[ref], device, kept and kept.id or nil))
            if (code == 200 or code == 201) and type(data) == "table" and data.id then
                Notesync.sent(state, current[ref], data.id)
            elseif code == 422 or code == 400 then
                state.pending[ref] = nil -- the Códice does not take it (a format, a place): not tried again
            else
                return false
            end
        elseif op == "delete" then
            local kept = state.items[ref]
            local query = kept and kept.id and ("?id=" .. kept.id) or ""
            local code = request(conn, "DELETE", path .. query)
            if code == 204 or code == 404 or code == 200 then
                Notesync.deleted(state, ref)
            else
                return false
            end
        else
            state.pending[ref] = nil
        end
        sent = sent + 1
    end
    return true
end

--- The items of the book that are highlights, by reference.
local function itemsByRef(ui, file_id)
    local out = {}
    for index, a in ipairs(ui.annotation.annotations) do
        if type(a.pos0) == "string" and type(a.pos1) == "string" then
            out[Notesync.ref(file_id, a.pos0, a.pos1)] = { item = a, index = index }
        end
    end
    return out
end

--- The points of a passage of the Códice in this book: the exact ones when it came from a reader; else the passage is looked for by its text,
--- from the paragraph the Códice says it is in.
local function findRange(ui, remote)
    local doc = ui.document
    if remote.pos0 and remote.pos1 and doc:isXPointerInDocument(remote.pos0) and doc:isXPointerInDocument(remote.pos1) then
        return remote.pos0, remote.pos1
    end
    local quote = (remote.quote or ""):gsub("%s+", " ")
    if quote == "" then return nil end
    local function hits(pattern)
        local ok, res = pcall(doc.findAllText, doc, pattern, false, 0, 40, false)
        return ok and type(res) == "table" and res or {}
    end
    local head = quote:sub(1, 80)
    local starts = hits(head)
    local start
    -- the paragraph the Códice says is written without the index 1 of the steps; KOReader writes every one: both are made alike to compare
    local function plain(xp) return (tostring(xp or ""):gsub("%[1%]", "")) end
    local place = remote.place and plain(remote.place)
    for _, h in ipairs(starts) do
        if place and h.start and plain(h.start):sub(1, #place) == place then start = h; break end
    end
    start = start or starts[1]
    if not (start and start.start) then return nil end
    if #quote <= 80 then
        return start.start, start["end"]
    end
    -- longer than what was searched: the end is where the tail of the passage is, the first one after the start
    local tail = quote:sub(-80)
    for _, h in ipairs(hits(tail)) do
        if h.start and h["end"] and doc:compareXPointers(start.start, h.start) and doc:compareXPointers(start.start, h.start) >= 0 then
            return start.start, h["end"]
        end
    end
    return nil
end

local function stamp(iso)
    local y, m, d, hh, mm, ss = tostring(iso or ""):match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
    if not y then return os.date("%Y-%m-%d %H:%M:%S") end
    return string.format("%s-%s-%s %s:%s:%s", y, m, d, hh, mm, ss)
end

--- Draws, changes and removes in this book what the Códice said. Returns whether the book changed.
local function apply(ui, state, file_id, actions)
    local changed = false
    for _, act in ipairs(actions.add) do
        local ok, err = pcall(function()
            local pos0, pos1 = act.pos0, act.pos1
            if not pos0 then pos0, pos1 = findRange(ui, { quote = act.remote.quote, place = act.remote.place }) end
            if not (pos0 and pos1) then return end -- no place in this book: it stays in the Notes tab
            local body = act.remote.body
            local item = {
                page = pos0, pos0 = pos0, pos1 = pos1, text = act.remote.quote, note = (body and body ~= "") and body or nil,
                drawer = "lighten", datetime = stamp(act.remote.updatedAt),
            }
            if ui.toc and ui.toc.getTocTitleByPage then item.chapter = ui.toc:getTocTitleByPage(pos0) end
            local index = ui.annotation:addItem(item)
            local ref = Notesync.ref(file_id, pos0, pos1)
            state.items[ref] = { id = act.remote.id, sig = Notesync.sig(item.text, item.note) }
            ui:handleEvent(Event:new("AnnotationsModified", { item, nb_highlights_added = 1, index_modified = index }))
            changed = true
        end)
        if not ok then logger.warn("codice: adding a note of the Códice failed:", err) end
    end
    local by_ref = itemsByRef(ui, file_id)
    for _, act in ipairs(actions.update) do
        local at = by_ref[act.ref]
        if at then
            at.item.note = (act.note and act.note ~= "") and act.note or nil
            state.items[act.ref].sig = Notesync.sig(at.item.text, at.item.note)
            ui:handleEvent(Event:new("AnnotationsModified", { at.item, index_modified = at.index }))
            changed = true
        end
    end
    -- from the last to the first: removing one moves the ones after it
    local doomed = {}
    for _, act in ipairs(actions.remove) do
        local at = by_ref[act.ref]
        if at then doomed[#doomed + 1] = { index = at.index, ref = act.ref } else state.items[act.ref] = nil end
    end
    table.sort(doomed, function(a, b) return a.index > b.index end)
    for _, d in ipairs(doomed) do
        if ui.bookmark and ui.bookmark.removeItemByIndex then
            ui.bookmark:removeItemByIndex(d.index)
        else
            table.remove(ui.annotation.annotations, d.index)
        end
        state.items[d.ref] = nil
        state.pending[d.ref] = nil
        changed = true
    end
    if changed then UIManager:setDirty("all", "ui") end
    return changed
end

--- What changed here since the last time is planned and sent; with `pull`, what the Códice has is asked and taken in. Never raises.
function Annotations.run(plugin, ui, pull)
    local ok, err = pcall(function()
        local file_id = fileId(ui)
        if not file_id then return end
        local state = loadState(ui)
        local current = Notesync.current(file_id, ui.annotation.annotations)
        Notesync.plan(state, current)
        local all_sent = flush(plugin, ui, state, current, file_id)
        saveState(ui, state)
        local conn = plugin:connection()
        if pull and all_sent and conn and NetworkMgr:isOnline() then
            local known = Notesync.known(state)
            local code, data = request(conn, "GET", "/device/files/" .. file_id .. "/notes" .. (#known > 0 and ("?known=" .. table.concat(known, ",")) or ""))
            if code == 200 and type(data) == "table" and type(data.notes) == "table" then
                local actions = Notesync.merge(state, Notesync.current(file_id, ui.annotation.annotations), data)
                apply(ui, state, file_id, actions)
                saveState(ui, state)
            end
        end
    end)
    if not ok then logger.warn("codice: syncing the notes failed:", err) end
end

return Annotations
