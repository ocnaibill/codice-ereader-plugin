--[[--
What the Códice's modules of the home draw from: the last home the server sent (kept in a file, so that the screen is there at once, with no
network), and the way to ask for a newer one, quietly, when the network is already on.
]]--

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local NetworkMgr = require("ui/network/manager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local socket = require("socket")
local UIManager = require("ui/uimanager")

local core = require("codice/core")
local api = require("codice/http")

local Data = {}

local MIN_GAP = 120 -- seconds between two asks to the server, whatever asks

local last_asked = 0
local asking = false

local function cacheDir()
    lfs.mkdir(DataStorage:getDataDir() .. "/cache")
    local dir = DataStorage:getDataDir() .. "/cache/codice"
    lfs.mkdir(dir)
    return dir
end

local function cacheFile()
    return cacheDir() .. "/home.json"
end

--- { url, username, token, ... } of this reader, read from its own settings file, or nil when it is not connected.
function Data.connection()
    local ok, store = pcall(LuaSettings.open, LuaSettings, DataStorage:getSettingsDir() .. "/codice.lua")
    if not ok then return nil end
    local c = store:readSetting("connection")
    if type(c) == "table" and c.url and c.username and c.token then return c end
    return nil
end

--- The last home that was kept, or nil.
function Data.load()
    local f = io.open(cacheFile(), "rb")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return api.decode(text)
end

function Data.save(home)
    local f = io.open(cacheFile(), "wb")
    if f then
        f:write(api.encode(home))
        f:close()
    end
end

--- Asks the server for the home, if the network is already on and it has been a while; keeps the answer. `on_change()` runs when what the
--- rows show is different from what was kept. Never asks for Wi-Fi, never raises.
function Data.refresh(on_change, force)
    if asking or (not force and socket.gettime() - last_asked < MIN_GAP) then return end
    local c = Data.connection()
    if not c or not NetworkMgr:isOnline() then return end
    asking = true
    last_asked = socket.gettime()
    local ok, err = pcall(function()
        local code, home = api.request(c.url .. "/device/home", { user = c.username, password = c.token })
        if code == 200 and type(home) == "table" then
            local before = Data.load()
            Data.save(home)
            if not core.sameRows(before, home) and on_change then on_change() end
        end
    end)
    asking = false
    if not ok then logger.warn("codice: refreshing the home failed:", err) end
end

-- the books opened from the home, by the path of the file: so that when one is closed the home knows which work it was
local opened = {}

--- Notes that the file at `path` was opened as this work (the card of the home, with the file that was chosen).
function Data.noteOpening(path, card)
    opened[path] = card
end

--- A book was closed at `path`, with `percent` read (0-100, or nil when it is not known): the work goes to the front of "continue" at once, from
--- what is here, and the server is asked a little later (what the reader sent when it closed the book has to arrive first). `on_change()` runs
--- when the screen has to be drawn again. Returns whether the home kept changed.
function Data.afterReading(path, percent, on_change)
    local card = opened[path]
    if not card then return false end
    local home = Data.load()
    local moved, changed = core.touchContinue(home, card, percent)
    if changed then Data.save(moved) end
    UIManager:scheduleIn(8, function() Data.refresh(on_change, true) end)
    return changed
end

return Data
