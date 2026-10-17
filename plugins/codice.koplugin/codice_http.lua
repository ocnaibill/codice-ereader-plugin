--[[--
Requests to the instance: JSON in and out, with the timeouts of KOReader. Everything returns `code, data` where `code` is the HTTP status
(nil if there was no answer) and `data` the decoded body (or the error text when there was no answer).
]]--

local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local http = require("socket.http")

local ok_json, json = pcall(require, "rapidjson")
if not ok_json then json = require("json") end

local M = {}

local function decode(text)
    if not text or text == "" then return nil end
    local ok, value = pcall(json.decode, text)
    if ok and type(value) == "table" then return value end
    return nil
end

--- `opts`: method, body (a table, sent as JSON), user and password (Basic), headers, sink (to save a file instead of reading the answer).
function M.request(url, opts)
    opts = opts or {}
    local chunks = {}
    local headers = { ["User-Agent"] = "Codice-ereader/0.1", ["Accept"] = "application/json" }
    local source
    if opts.body then
        local payload = json.encode(opts.body)
        headers["Content-Type"] = "application/json"
        headers["Content-Length"] = tostring(#payload)
        source = ltn12.source.string(payload)
    end
    for k, v in pairs(opts.headers or {}) do headers[k] = v end
    socketutil:set_timeout(15, 45)
    local code, response_headers, status = socket.skip(1, http.request{
        url = url,
        method = opts.method or (opts.body and "POST" or "GET"),
        headers = headers,
        source = source,
        user = opts.user,
        password = opts.password,
        sink = opts.sink or socketutil.table_sink(chunks),
    })
    socketutil:reset_timeout()
    if type(code) ~= "number" then return nil, tostring(code or status) end
    return code, decode(table.concat(chunks)), response_headers
end

return M
