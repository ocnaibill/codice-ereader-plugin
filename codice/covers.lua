--[[--
The covers of the books of the Códice, kept as files in the cache folder of the plugin: fetched from the server (a size that fits a small
screen), reused, and never fetched while the network is off.
]]--

local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local ltn12 = require("ltn12")

local core = require("codice/core")
local api = require("codice/http")

local Covers = {}

local function dir()
    lfs.mkdir(DataStorage:getDataDir() .. "/cache")
    local d = DataStorage:getDataDir() .. "/cache/codice"
    lfs.mkdir(d)
    return d
end

--- The file a card's cover is kept in, or nil when the card has no cover that can be drawn (no cover, or the stand-in of the server, an SVG).
function Covers.path(card)
    local cover = card and card.cover
    if type(cover) ~= "string" or cover == "" or cover:find("%.svg") then return nil end
    return dir() .. "/" .. core.coverCacheName(cover)
end

--- Whether the file of a cover is there and has something in it.
function Covers.kept(path)
    return path ~= nil and lfs.attributes(path, "mode") == "file" and (lfs.attributes(path, "size") or 0) > 0
end

--- Fetches the cover of a card if it is not kept. Returns its file, or nil.
function Covers.fetch(conn, card)
    local path = Covers.path(card)
    if not path then return nil end
    if Covers.kept(path) then return path end
    local handle = io.open(path, "wb")
    if not handle then return nil end
    local url = conn.url .. card.cover .. (card.cover:find("?", 1, true) and "&" or "?") .. "w=240"
    local code = api.request(url, { user = conn.username, password = conn.token, sink = ltn12.sink.file(handle) })
    if code ~= 200 then
        os.remove(path)
        return nil
    end
    return path
end

return Covers
