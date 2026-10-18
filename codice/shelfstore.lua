--[[--
The shelf kept in a file, and the way it is made up to date (DEC-198): the logic is in `codice/shelf.lua`; here is what touches the device (the
file, the books folder, the network) and the server (`/device/shelf`).

The shelf is written when a book is downloaded, checked against the files that are really there every time it is opened, and made up to date
with the server whenever there is a network: never asked for when there is none, never raising.
]]--

local DataStorage = require("datastorage")
local NetworkMgr = require("ui/network/manager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local api = require("codice/http")
local core = require("codice/core")
local Shelf = require("codice/shelf")

local Store = {}

local PER_ASK = 50 -- works in one ask to the server
local MIN_GAP = 120 -- seconds between two refreshes, whatever asks

local index -- the shelf in memory, read once
local dir -- the folder of the books
local last_refresh = 0
local refreshing = false

--- The folder where the books are (set when the plugin starts).
function Store.configure(books_dir)
    dir = books_dir
end

local function file()
    return DataStorage:getSettingsDir() .. "/codice_shelf.json"
end

--- The shelf: read from the file the first time, then the one in memory.
function Store.index()
    if index then return index end
    local f = io.open(file(), "rb")
    local read
    if f then
        read = api.decode(f:read("*a"))
        f:close()
    end
    index = Shelf.sane(read)
    return index
end

function Store.save()
    if not index then return end
    -- the lock screen shows the covers of what is on the device: it is made again when this changes
    pcall(function() require("codice/lockscreen").schedule() end)
    local f = io.open(file(), "wb")
    if f then
        f:write(api.encode(index))
        f:close()
    end
end

local function exists(name)
    return dir ~= nil and lfs.attributes(dir .. "/" .. name, "mode") == "file"
end

--- Forgets what was deleted from the device. Returns how many works went.
function Store.prune()
    local gone = Shelf.prune(Store.index(), exists)
    if gone > 0 then Store.save() end
    return gone
end

--- The state of the connection (see core.connectivity).
function Store.state()
    return core.connectivity(NetworkMgr:isOnline(), api.last_contact, os.time())
end

--- The notice for the top of the library, or nil when everything is as it should be.
function Store.notice()
    return core.offlineNotice(Store.state(), Store.index().saved_at, function(t) return os.date("%d/%m", t) end)
end

local function ask(conn, query)
    local code, data = api.request(conn.url .. "/device/shelf?" .. query, { user = conn.username, password = conn.token })
    if code == 200 and type(data) == "table" and type(data.works) == "table" then return data end
    return nil
end

--- A book was downloaded: it goes on the shelf, with what the server says about it when it can be asked, with what the card has when not (the
--- rest comes at the next refresh).
function Store.record(conn, card, name)
    local idx = Store.index()
    local size = lfs.attributes((dir or "") .. "/" .. name, "size") or 0
    local work
    local answer = conn and NetworkMgr:isOnline() and ask(conn, "works=" .. tostring(card.id)) or nil
    if answer then
        for _, w in ipairs(answer.works) do
            if w.id == card.id then work = Shelf.workFrom(w) end
        end
    end
    work = work or Shelf.workFromCard(card)
    Shelf.noteDownload(idx, work, card.fileId, name, size, os.time())
    Store.save()
    -- the cover too, so that the library has it with no network
    if conn and NetworkMgr:isOnline() then pcall(require("codice/covers").fetch, conn, card) end
end

--- Makes the shelf up to date with the server, if there is a network and it has been a while: what the server says about the works that are on
--- the device, and the works that are there and that the shelf does not know yet (books downloaded before the shelf existed: the folder is
--- read, the name of each file starts with its id). `on_change()` runs when the shelf is different. Never asks for Wi-Fi, never raises.
function Store.refresh(conn, on_change, force)
    if refreshing or not conn or not dir or not NetworkMgr:isOnline() then return end
    if not force and os.time() - last_refresh < MIN_GAP then return end
    refreshing = true
    last_refresh = os.time()
    local ok, err = pcall(function()
        local idx = Store.index()
        local changed = Store.prune() > 0
        -- the files of the folder that the shelf does not know
        local unknown = {}
        if lfs.attributes(dir, "mode") == "directory" then
            for name in lfs.dir(dir) do
                local id = tonumber(name:match("^(%d+) %- "))
                if id and not Shelf.has(idx, id) then unknown[#unknown + 1] = { id = id, name = name } end
            end
        end
        for _, part in ipairs(Shelf.chunks(unknown, PER_ASK)) do
            local ids = {}
            for _, u in ipairs(part) do ids[#ids + 1] = u.id end
            local answer = ask(conn, "files=" .. table.concat(ids, ","))
            if answer then
                for _, w in ipairs(answer.works) do
                    local work = Shelf.workFrom(w)
                    for _, u in ipairs(part) do
                        for _, f in ipairs(work.files) do
                            if f.id == u.id then
                                Shelf.noteDownload(idx, work, u.id, u.name, lfs.attributes(dir .. "/" .. u.name, "size") or 0, os.time())
                                changed = true
                            end
                        end
                    end
                end
            end
        end
        for _, part in ipairs(Shelf.chunks(Shelf.ids(idx), PER_ASK)) do
            local answer = ask(conn, "works=" .. table.concat(part, ","))
            if answer then
                if Shelf.merge(idx, answer) then changed = true end
                idx.saved_at = os.time()
            end
        end
        Store.save()
        if changed and on_change then on_change() end
    end)
    refreshing = false
    if not ok then logger.warn("codice: refreshing the shelf failed:", err) end
end

return Store
