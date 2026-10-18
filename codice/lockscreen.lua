--[[--
The lock screen of the reader (the screensaver of KOReader) with the covers of the books that are on the device: each time the reader sleeps it
shows another one, with "Códice" in the lower left corner; with no books, only the word in the corner. KOReader's own "random image" screensaver
does the choosing: this makes the images (the cover on white, the size of the screen, with the word) in a folder of its own and points it there.
The person's own screensaver setting is kept apart and comes back when this is turned off.
]]--

local Blitbuffer = require("ffi/blitbuffer")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local Screen = Device.screen

local core = require("codice/core")
local Covers = require("codice/covers")
local Shelf = require("codice/shelf")
local Store = require("codice/shelfstore")

local Lockscreen = {}

local MAX_COVERS = 12
local REBUILD_AFTER = 8 -- seconds with no change in the shelf before the images are made again

local function dir()
    lfs.mkdir(DataStorage:getDataDir() .. "/cache")
    lfs.mkdir(DataStorage:getDataDir() .. "/cache/codice")
    local d = DataStorage:getDataDir() .. "/cache/codice/lockscreen"
    lfs.mkdir(d)
    return d
end

--- One image: white, the cover (when there is one) in the middle at the biggest size that keeps it whole, and the word in the lower left corner.
local function compose(cover_path)
    local RenderText = require("ui/rendertext")
    local w, h = Screen:getWidth(), Screen:getHeight()
    local bb = Blitbuffer.new(w, h, Screen.bb and Screen.bb:getType() or nil)
    bb:fill(Blitbuffer.COLOR_WHITE)
    if cover_path then
        local ok, err = pcall(function()
            local RenderImage = require("ui/renderimage")
            local img = RenderImage:renderImageFile(cover_path, false)
            if not img then return end
            local plan = core.lockscreenFit(img:getWidth(), img:getHeight(), w, h)
            local scaled = RenderImage:scaleBlitBuffer(img, plan.w, plan.h, true)
            bb:blitFrom(scaled, plan.x, plan.y, 0, 0, plan.w, plan.h)
            -- a thin frame, so that a pale cover does not melt into the white
            local line = 2
            bb:paintRect(plan.x - line, plan.y - line, plan.w + 2 * line, line, Blitbuffer.COLOR_BLACK)
            bb:paintRect(plan.x - line, plan.y + plan.h, plan.w + 2 * line, line, Blitbuffer.COLOR_BLACK)
            bb:paintRect(plan.x - line, plan.y, line, plan.h, Blitbuffer.COLOR_BLACK)
            bb:paintRect(plan.x + plan.w, plan.y, line, plan.h, Blitbuffer.COLOR_BLACK)
            if scaled ~= img then scaled:free() end
        end)
        if not ok then logger.warn("codice: drawing a cover for the lock screen failed:", err) end
    end
    local margin = Screen:scaleBySize(28)
    RenderText:renderUtf8Text(bb, margin, h - margin, Font:getFace("tfont", 30), "Códice", true, true, Blitbuffer.COLOR_BLACK)
    return bb
end

local function save(bb, path)
    local ok, err = pcall(function() bb:writePNG(path) end)
    bb:free()
    if not ok then logger.warn("codice: saving a lock screen image failed:", err) end
    return ok
end

--- The images made so far, by name.
local function listImages(d)
    local out = {}
    if lfs.attributes(d, "mode") ~= "directory" then return out end
    for name in lfs.dir(d) do
        if name:match("%.png$") then out[#out + 1] = name end
    end
    return out
end

--- Makes the images again when the covers on the device are not the ones they were made from. Returns how many covers are in them.
function Lockscreen.update(plugin)
    local d = dir()
    local idx = Store.index()
    local cards = Shelf.list(idx, { sort = "recent" })
    local with_cover = core.lockscreenCovers(cards, function(card) return Covers.kept(Covers.path(card)) end, MAX_COVERS)
    local signature = core.lockscreenSignature(with_cover, Screen:getWidth(), Screen:getHeight())
    local store = plugin:store()
    if store:readSetting("lockscreen_signature") == signature and #listImages(d) > 0 then return #with_cover end
    for _, name in ipairs(listImages(d)) do os.remove(d .. "/" .. name) end
    if #with_cover == 0 then
        save(compose(nil), d .. "/codice.png")
    else
        for _, card in ipairs(with_cover) do
            save(compose(Covers.path(card)), string.format("%s/cover-%d.png", d, card.id))
        end
    end
    store:saveSetting("lockscreen_signature", signature)
    store:flush()
    return #with_cover
end

--- Whether the lock screen of the Códice is the one in use.
function Lockscreen.enabled(plugin)
    return plugin:store():readSetting("lockscreen") ~= false
end

--- Points the screensaver of KOReader at the images, keeping what the person had to give it back.
function Lockscreen.apply(plugin)
    local d = dir()
    local store = plugin:store()
    if not store:readSetting("lockscreen_prev") then
        store:saveSetting("lockscreen_prev", {
            type = G_reader_settings:readSetting("screensaver_type") or false,
            dir = G_reader_settings:readSetting("screensaver_dir") or false,
            message = G_reader_settings:isTrue("screensaver_show_message"),
        })
    end
    G_reader_settings:saveSetting("screensaver_type", "random_image")
    G_reader_settings:saveSetting("screensaver_dir", d)
    G_reader_settings:makeFalse("screensaver_show_message")
    G_reader_settings:flush()
    store:flush()
end

--- Gives the screensaver back to what the person had.
function Lockscreen.restore(plugin)
    local store = plugin:store()
    local prev = store:readSetting("lockscreen_prev")
    if type(prev) == "table" then
        if prev.type then G_reader_settings:saveSetting("screensaver_type", prev.type) else G_reader_settings:delSetting("screensaver_type") end
        if prev.dir then G_reader_settings:saveSetting("screensaver_dir", prev.dir) else G_reader_settings:delSetting("screensaver_dir") end
        if prev.message then G_reader_settings:makeTrue("screensaver_show_message") else G_reader_settings:makeFalse("screensaver_show_message") end
        G_reader_settings:flush()
        store:delSetting("lockscreen_prev")
    end
end

--- Turns the lock screen of the Códice on or off.
function Lockscreen.set(plugin, on)
    plugin:store():saveSetting("lockscreen", on and true or false)
    plugin:store():flush()
    if on then
        Lockscreen.apply(plugin)
        Lockscreen.update(plugin)
    else
        Lockscreen.restore(plugin)
    end
end

--- At the start: it is on unless the person turned it off; the images are made if they are not there or the covers changed.
function Lockscreen.start(plugin)
    if not Lockscreen.enabled(plugin) then return end
    local ok, err = pcall(function()
        Lockscreen.apply(plugin)
        Lockscreen.update(plugin)
    end)
    if not ok then logger.warn("codice: the lock screen failed:", err) end
end

--- The shelf changed: the images are made again when it has been quiet for a few seconds.
local timer
function Lockscreen.schedule()
    local plugin = (package.loaded["codice/plugin"] or {}).live
    if not plugin then return end
    if timer then UIManager:unschedule(timer) end
    timer = function()
        timer = nil
        if Lockscreen.enabled(plugin) then pcall(Lockscreen.update, plugin) end
    end
    UIManager:scheduleIn(REBUILD_AFTER, timer)
end

return Lockscreen
