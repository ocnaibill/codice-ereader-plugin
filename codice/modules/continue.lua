--[[--
Módulo da home do Simple UI: "Continuar lendo", com os livros que a pessoa está lendo no Códice (o servidor diz quais e quanto falta). É feito
sobre o `GridRenderer.makeModule` dele, como o módulo de Coleções: cada célula é uma obra do servidor, não um arquivo do aparelho.

Os dados vêm da última home que o servidor mandou, guardada em arquivo (`codice/data.lua`): a tela aparece na hora, sem rede, e se atualiza
sozinha quando chega uma nova. As capas chegam depois da tela, algumas por vez. Tocar numa obra a abre (baixando o arquivo se ele ainda não
está no aparelho, e perguntando qual quando há mais de um).
]]--

local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local ProgressWidget = require("ui/widget/progresswidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Device = require("device")
local Screen = Device.screen

local GridRenderer = require("engines/sui_book_grid")
local SUIStyle = require("features/sui_style")
local UI = require("infra/sui_core")

local core = require("codice/core")
local Data = require("codice/data")
local Covers = require("codice/covers")

local MODULE_ID = "codice_continue"
local MAX_ITEMS = 5
local COVERS_PER_STEP = 3

local by_key = {} -- the cards of the last list, by the key the grid keeps them by
local fetching = false
local failed = {} -- covers that could not be had, by file, with when: not tried again for a while
local RETRY_AFTER = 600

--- Draws the screens again, from what is kept now.
local function redraw()
    local SE = package.loaded["engines/sui_screen_engine"]
    if SE and SE.refreshAllLiveImmediate then SE.refreshAllLiveImmediate(false) end
end

--- Fetches the covers that are missing, a few at a time, and draws the screen again after each few, until none is missing.
local function fetchMissing(cards)
    if fetching then return end
    local conn = Data.connection()
    local NetworkMgr = require("ui/network/manager")
    if not conn or not NetworkMgr:isOnline() then return end
    local pending = {}
    for _, card in ipairs(cards) do
        local path = Covers.path(card)
        if path and not Covers.kept(path) and not (failed[path] and os.time() - failed[path] < RETRY_AFTER) then pending[#pending + 1] = card end
    end
    if #pending == 0 then return end
    fetching = true
    local i = 1
    local function step()
        local got = 0
        while pending[i] and got < COVERS_PER_STEP do
            local card = pending[i]
            i = i + 1
            if Covers.fetch(conn, card) then
                got = got + 1
            else
                failed[Covers.path(card)] = os.time()
            end
        end
        if got > 0 then redraw() end
        if pending[i] then
            UIManager:scheduleIn(0.2, step)
        else
            fetching = false
        end
    end
    UIManager:scheduleIn(0.5, step)
end

local function plugin()
    local FM = package.loaded["apps/filemanager/filemanager"]
    local ui = FM and FM.instance
    return (ui and ui.codice) or (package.loaded["codice/plugin"] or {}).live
end

local function listBooks()
    local home = Data.load()
    local cards = core.homeItems(home, "continue", MAX_ITEMS)
    by_key = {}
    local keys = {}
    for _, card in ipairs(cards) do
        by_key[card.key] = card
        keys[#keys + 1] = card.key
    end
    -- later, so that the build that asked is not held up: what is missing comes after the screen is there
    UIManager:scheduleIn(0.3, function()
        Data.refresh(redraw)
        fetchMissing(cards)
    end)
    return keys
end

-- ---------------------------------------------------------------------------
-- the cell
-- ---------------------------------------------------------------------------

local function dims(cw)
    local pad = Screen:scaleBySize(4)
    local w = math.max(10, cw - 2 * pad)
    local h = math.floor(w * 1.5)
    local face = Font:getFace(SUIStyle.FACE_REGULAR, SUIStyle.FS_DETAIL)
    local text_h = TextWidget:new{ text = "Ag", face = face }:getSize().h
    local bar_h = Screen:scaleBySize(5)
    local gap = Screen:scaleBySize(4)
    return { pad = pad, cover_w = w, cover_h = h, face = face, text_h = text_h, bar_h = bar_h, gap = gap,
             cell_h = h + gap + bar_h + gap + text_h + gap }
end

local function cellHeight(cw)
    return dims(cw).cell_h
end

local function coverWidget(d, card)
    local path = Covers.path(card)
    if Covers.kept(path) then
        return FrameContainer:new{
            bordersize = 1, padding = 0, margin = 0,
            CenterContainer:new{ dimen = Geom:new{ w = d.cover_w - 2, h = d.cover_h - 2 },
                ImageWidget:new{ file = path, width = d.cover_w - 2, height = d.cover_h - 2, scale_factor = 0 } },
        }
    end
    -- no cover (yet): the stand-in of the Simple UI, with the title, the same one it draws for a book with no cover
    local SH = package.loaded["modules/module_books_shared"]
    if SH and SH.coverPlaceholder then
        local ok, w = pcall(SH.coverPlaceholder, card.title, card.author, d.cover_w, d.cover_h, false)
        if ok and w then return w end
    end
    return FrameContainer:new{ bordersize = 1, padding = 0, margin = 0, width = d.cover_w, height = d.cover_h,
        TextWidget:new{ text = tostring(card.title or "?"), face = d.face, max_width = d.cover_w - 4 } }
end

local function renderCell(key, cw, cell_h)
    local card = by_key[key]
    if not card then return VerticalSpan:new{ width = cell_h } end
    local d = dims(cw)
    local bar
    if (card.percent or 0) > 0 then
        bar = ProgressWidget:new{ width = d.cover_w, height = d.bar_h, percentage = math.min(1, card.percent / 100), margin_h = 0, margin_v = 0 }
    else
        bar = VerticalSpan:new{ width = d.bar_h }
    end
    local content = VerticalGroup:new{
        align = "center",
        VerticalSpan:new{ width = 0 },
        coverWidget(d, card),
        VerticalSpan:new{ width = d.gap },
        bar,
        VerticalSpan:new{ width = d.gap },
        UI.makeColoredText{
            text = tostring(card.title or "?"), face = d.face, fgcolor = UI.CLR_TEXT_SUB,
            max_width = d.cover_w, truncate_with_ellipsis = true, alignment = "center",
        },
    }
    local tappable = InputContainer:new{ dimen = Geom:new{ w = cw, h = cell_h }, [1] = content }
    tappable.ges_events = {
        TapCodice = { GestureRange:new{ ges = "tap", range = function() return tappable.dimen end } },
    }
    function tappable:onTapCodice()
        local p = plugin()
        if p then
            p:chooseAndOpen(card)
        else
            UIManager:show(require("ui/widget/infomessage"):new{ text = "O Códice não está pronto. Tente de novo." })
        end
        return true
    end
    return tappable
end

local mod = GridRenderer.makeModule{
    id          = MODULE_ID,
    name        = "Códice: Continuar lendo",
    label       = "Continuar lendo",
    default_on  = false,
    is_book_mod = true,
    max_items   = MAX_ITEMS,
    paged       = false,

    getFileList   = listBooks,
    renderCell    = renderCell,
    getCellHeight = cellHeight,

    -- the progress is drawn by the cell itself
    progress_style = { locked = "none" },

    grid         = true,
    default_rows = 1,
    default_cols = 3,
}

return mod
