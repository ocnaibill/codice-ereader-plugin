--[[--
Connecting to a Códice by a code (DEC-194): the person gives the address of the instance, the reader shows a code, the person approves it on
the site, and the reader is given its access and the configuration. The access is never typed: it comes in the answer, once.
]]--

local ButtonDialog = require("ui/widget/buttondialog")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local NetworkMgr = require("ui/network/manager")
local QRMessage = require("ui/widget/qrmessage")
local UIManager = require("ui/uimanager")
local Screen = Device.screen

local core = require("codice/core")
local api = require("codice/http")

local Pairing = {}

local function say(text, timeout)
    UIManager:show(InfoMessage:new{ text = text, timeout = timeout })
end

local function platform()
    if Device:isKindle() then return "kindle" end
    if Device:isKobo() then return "kobo" end
    if Device:isAndroid() then return "android" end
    return "other"
end

local function deviceName()
    local label = ({ kindle = "Kindle", kobo = "Kobo", android = "Android" })[platform()] or "Leitor"
    local model = tostring(Device.model or "")
    return model ~= "" and (label .. " (" .. model .. ")") or label
end

--- Step 1: asks for the address of the instance.
function Pairing.start(plugin)
    local dialog
    dialog = InputDialog:new{
        title = "Conectar ao Códice",
        description = "Digite o endereço da sua instância, por exemplo codice.exemplo.com",
        input = plugin:connection() and plugin:connection().url or "https://",
        input_hint = "https://codice.exemplo.com",
        buttons = {{
            { text = "Cancelar", id = "close", callback = function() UIManager:close(dialog) end },
            {
                text = "Continuar",
                is_enter_default = true,
                callback = function()
                    local url, reason = core.normalizeUrl(dialog:getInputText())
                    if not url then
                        say(reason == "empty" and "Digite o endereço da instância." or "Esse endereço não parece válido. Exemplo: codice.exemplo.com")
                        return
                    end
                    UIManager:close(dialog)
                    NetworkMgr:runWhenOnline(function() Pairing.request(plugin, url) end)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--- Step 2: checks that it is a Códice that connects readers by code, and asks for a code.
function Pairing.request(plugin, url)
    local code, info = api.request(url .. "/device/info")
    if not code then
        return say("Não consegui falar com " .. url .. ".\n" .. tostring(info))
    end
    if code ~= 200 or type(info) ~= "table" or info.name ~= "Códice" then
        return say("Esse endereço não parece ser um Códice (ou o Códice é antigo e ainda não conecta leitores por código).")
    end
    if not info.pairing then
        return say("O dono deste Códice desligou a conexão de leitores por código. Peça a ele para ligar, ou use os arquivos de configuração de Minha conta → Aplicativos.")
    end
    local status, answer = api.request(url .. "/device/code", { body = { client = core.CLIENT, platform = platform(), name = deviceName() } })
    if status ~= 200 or type(answer) ~= "table" or not answer.deviceCode then
        return say("Não foi possível pedir um código.\n" .. (status and core.requestFailure(status, answer) or tostring(answer)))
    end
    Pairing.wait(plugin, url, answer)
end

--- Step 3: shows the code and asks every few seconds until the person has answered, the request expires, or it is cancelled.
function Pairing.wait(plugin, url, answer)
    local state = {
        interval = tonumber(answer.interval) or 5,
        deadline = os.time() + (tonumber(answer.expiresIn) or 600),
        standby = true,
    }
    UIManager:preventStandby() -- the reader must stay awake and online while the person goes to the site

    local dialog, poll
    local function finish()
        state.cancelled = true
        if state.standby then
            state.standby = false
            UIManager:allowStandby()
        end
        if poll then UIManager:unschedule(poll) end
        if dialog then UIManager:close(dialog) end
    end

    dialog = require("codice/paircode"):new{
        code = tostring(answer.userCode),
        on_qr = function()
            UIManager:show(QRMessage:new{
                text = answer.verificationUriComplete,
                width = Screen:getWidth() * 0.8,
                height = Screen:getWidth() * 0.8,
            })
        end,
        on_cancel = finish,
    }
    UIManager:show(dialog)

    poll = function()
        if state.cancelled then return end
        if os.time() >= state.deadline then
            finish()
            return say("O código venceu. Peça um novo em Códice → Conectar.")
        end
        if not NetworkMgr:isOnline() then -- the Wi-Fi went away: keep trying until the request expires
            return UIManager:scheduleIn(state.interval, poll)
        end
        local code, data = api.request(url .. "/device/token", { body = { deviceCode = answer.deviceCode } })
        local outcome, newInterval = core.pollOutcome(code, data)
        if outcome == "ok" then
            finish()
            return plugin:onPaired(url, data)
        elseif outcome == "expired" then
            finish()
            return say("O pedido venceu. Peça um novo código em Códice → Conectar.")
        elseif outcome == "denied" then
            finish()
            return say("O pedido foi negado no site.")
        elseif outcome == "slow" and newInterval then
            state.interval = newInterval
        end
        -- pending, a slow answer or a failure of the network: ask again
        UIManager:scheduleIn(state.interval, poll)
    end
    UIManager:scheduleIn(state.interval, poll)
end

return Pairing
