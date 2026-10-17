--[[--
The logic of the plugin that does not need KOReader: the address of the instance, the versions, what the answers of the server mean, and
what is written in the settings of the OPDS and of KOSync. It is here, apart from the screens, so that it can be tested with plain Lua
(tests/run.lua).
]]--

local M = {}

M.PLUGIN_VERSION = "0.1.0"
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

return M
