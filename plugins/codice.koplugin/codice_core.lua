--[[--
The logic of the plugin that does not need KOReader: the address of the instance, the versions, what the answers of the server mean, and
what is written in the settings of the OPDS and of KOSync. It is here, apart from the screens, so that it can be tested with plain Lua
(tests/run.lua).
]]--

local M = {}

M.PLUGIN_VERSION = "0.2.0"
M.CLIENT = "codice-ereader/" .. M.PLUGIN_VERSION
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
    sync_forward = 1, -- ask
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

--- Where a downloaded book goes inside the folder of the plugin: the id keeps two works with the same title apart.
function M.bookFileName(card)
    local ext = tostring(card.format or "epub"):lower():gsub("[^%w]", "")
    if ext == "" then ext = "epub" end
    return string.format("%d - %s.%s", card.id or 0, M.safeName(card.title, 70), ext)
end

--- The name a cover is kept under: its path, as letters and digits.
function M.coverCacheName(path)
    return (tostring(path or ""):gsub("^/", ""):gsub("[^%w]+", "_")) .. ".jpg"
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
