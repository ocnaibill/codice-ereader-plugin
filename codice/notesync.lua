--[[--
The highlights and notes of a book, the same on the reader and in the Códice (DEC-199): what is kept apart for the sync and the decisions about
what to send and what to take. No KOReader in this file, so it is tested with plain Lua (tests/run.lua); `codice/annotations.lua` touches the
document and the network.

What is kept for each book (in its own settings, with the rest of what KOReader keeps about it):
    { version = 1, items = { [ref] = { id, sig } }, pending = { [ref] = "put" | "delete" } }
`ref` is the identity of a highlight on this reader, `id` the number of the note in the Códice, `sig` what the highlight said the last time it was
sent (to know that it changed), `pending` what still has to be sent.
]]--

local bit = require("bit")

local Notesync = {}

Notesync.VERSION = 1

--- A new state for a book.
function Notesync.new()
    return { version = Notesync.VERSION, items = {}, pending = {} }
end

--- A usable state from whatever was read: a new one when it is not one.
function Notesync.sane(state)
    if type(state) ~= "table" or state.version ~= Notesync.VERSION or type(state.items) ~= "table" then return Notesync.new() end
    if type(state.pending) ~= "table" then state.pending = {} end
    return state
end

-- two 32 bit hashes of different seeds, written in hexadecimal: 16 characters, enough to tell the highlights of one book apart
local function fnv(text, seed)
    local h = seed
    for i = 1, #text do
        h = bit.bxor(h, text:byte(i))
        h = bit.tobit((h * 16777619) % 4294967296)
    end
    return bit.tohex(h, 8)
end

--- The identity of a highlight: the book and the two points it covers. The same highlight is always the same reference, on any day.
function Notesync.ref(file_id, pos0, pos1)
    local key = tostring(file_id) .. "|" .. tostring(pos0) .. "|" .. tostring(pos1)
    return fnv(key, 0x811c9dc5) .. fnv(key, 0x01000193)
end

--- What a highlight says, as one string: it changes when the passage or the note do.
function Notesync.sig(text, note)
    local key = tostring(text or "") .. "\0" .. tostring(note or "")
    return fnv(key, 0x811c9dc5) .. #key
end

--- The highlights a book has that are worth sending, from the annotations KOReader keeps (`items`): the ones with a passage and both ends (the
--- bookmarks and the page marks do not enter). Returns `{ [ref] = { ref, pos0, pos1, text, note, drawer, chapter, datetime, sig } }`.
function Notesync.current(file_id, items)
    local out = {}
    for _, a in ipairs(items or {}) do
        if type(a.pos0) == "string" and type(a.pos1) == "string" and type(a.text) == "string" and a.text:match("%S") then
            local ref = Notesync.ref(file_id, a.pos0, a.pos1)
            out[ref] = {
                ref = ref, pos0 = a.pos0, pos1 = a.pos1, text = a.text, note = a.note, drawer = a.drawer, chapter = a.chapter,
                datetime = a.datetime, sig = Notesync.sig(a.text, a.note),
            }
        end
    end
    return out
end

--- What changed on this reader since the last time: puts the new and the edited highlights in `state.pending` and the ones that were sent and are
--- not there any more as deletes. Returns whether something was added. A highlight that was received from the Códice and is edited here is sent
--- again with the number it has there (see `state.items[ref].id`).
function Notesync.plan(state, current)
    local changed = false
    for ref, a in pairs(current) do
        local kept = state.items[ref]
        if not kept then
            state.pending[ref] = "put"
            changed = true
        elseif kept.sig ~= a.sig and state.pending[ref] ~= "put" then
            state.pending[ref] = "put"
            changed = true
        end
    end
    for ref, kept in pairs(state.items) do
        if not current[ref] and state.pending[ref] ~= "delete" then
            state.pending[ref] = "delete"
            changed = true
        end
    end
    -- a highlight that was made and deleted before it was ever sent has nothing to delete in the Códice
    for ref, op in pairs(state.pending) do
        if op == "put" and not current[ref] then state.pending[ref] = nil end
        if op == "delete" and not state.items[ref] then state.pending[ref] = nil end
    end
    return changed
end

--- The body of the PUT for a highlight: what the Códice keeps of it. `id` is the number the note has in the Códice when it came from there.
function Notesync.body(a, device_name, id)
    return { pos0 = a.pos0, pos1 = a.pos1, text = a.text, note = a.note or "", drawer = a.drawer, chapter = a.chapter, datetime = a.datetime,
             device = device_name, id = id }
end

--- After a PUT answered: the highlight is sent, with the number it has in the Códice.
function Notesync.sent(state, a, id)
    state.items[a.ref] = { id = id, sig = a.sig }
    state.pending[a.ref] = nil
end

--- After a DELETE answered (or the note was not there any more): it is gone from the state.
function Notesync.deleted(state, ref)
    state.items[ref] = nil
    state.pending[ref] = nil
end

--- The numbers of the notes the Códice has to be asked about (`known`): the ones this book has in its state.
function Notesync.known(state)
    local out = {}
    for _, kept in pairs(state.items) do
        if kept.id then out[#out + 1] = kept.id end
    end
    table.sort(out)
    return out
end

local function refOf(state, id)
    for ref, kept in pairs(state.items) do
        if kept.id == id then return ref end
    end
    return nil
end

--- What to do here with the answer of the Códice (`{ notes, gone }`), given the state and what the book has now (`current`, from Notesync.current):
--- `add`: notes of the Códice that this book does not have (to be drawn); `update`: notes whose text the Códice changed and that were not
--- changed here (the new note text goes into the highlight); `remove`: highlights of this book whose note is gone from the Códice.
--- A highlight that has something waiting to be sent is the reader's: what the Códice says of it waits for the sending.
function Notesync.merge(state, current, answer)
    local actions = { add = {}, update = {}, remove = {} }
    for _, n in ipairs(answer.notes or {}) do
        local ref = refOf(state, n.id)
        if not ref and n.ref and current[n.ref] then ref = n.ref end -- it was made here and the state was lost: adopt it
        if ref then
            local kept, here = state.items[ref], current[ref]
            if not kept then
                state.items[ref] = { id = n.id, sig = here and here.sig or "" }
            elseif here and state.pending[ref] == nil and (n.body or "") ~= (here.note or "") then
                actions.update[#actions.update + 1] = { ref = ref, note = n.body, remote = n }
            end
        elseif n.pos0 and n.pos0 ~= "" and n.pos1 and n.pos1 ~= "" then
            -- made on a reader: the exact points are known
            actions.add[#actions.add + 1] = { remote = n, pos0 = n.pos0, pos1 = n.pos1 }
        else
            actions.add[#actions.add + 1] = { remote = n }
        end
    end
    for _, id in ipairs(answer.gone or {}) do
        local ref = refOf(state, id)
        if ref then actions.remove[#actions.remove + 1] = { ref = ref, id = id } end
    end
    return actions
end

return Notesync
