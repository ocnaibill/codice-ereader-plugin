--[[--
Home module "Códice: Nota": a note or highlight of the person, picked at random among the ones the server sent with the home (it picks them at random
too, a few each time). The pick holds for a while, so that the screen does not change at every drawing. Tapping it opens the work it came from.
]]--

local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Font = require("ui/font")
local LeftContainer = require("ui/widget/container/leftcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local SUIStyle = require("features/sui_style")

local core = require("codice/core")
local Plain = require("codice/modules/plain")

local LINES = 4
local HOLD = 600 -- seconds a pick is kept

local pick = { sig = nil, roll = 0, at = 0 }

local function sizes()
    local gap = Plain.scale(4)
    local body, attr = SUIStyle.FS_BODY, SUIStyle.FS_DETAIL
    local body_h = Plain.lineHeight(body) * LINES
    return { gap = gap, body = body, attr = attr, body_h = body_h,
             h = Plain.PAD + body_h + gap + Plain.lineHeight(attr) + Plain.PAD2 }
end

--- The note to show: the same one until the notes change or the hold ends.
local function current(home)
    local sig = core.noteSignature(home)
    local now = os.time()
    if sig ~= pick.sig or now - pick.at > HOLD then
        pick = { sig = sig, roll = math.random(1, 1000000), at = now }
    end
    return core.pickNote(home, pick.roll)
end

return Plain.make{
    id          = "codice_note",
    name        = "Códice: Nota aleatória",
    enabled_key = "codice_note_enabled",

    height = function() return sizes().h end,

    build = function(w, _ctx, home)
        local z = sizes()
        local note = current(home)
        local width = w - 2 * Plain.PAD
        if not note then
            -- nothing marked yet: the space stays, quietly
            return VerticalSpan:new{ width = z.h }
        end
        local attribution = "— " .. (note.title or "?") .. ((note.author and note.author ~= "") and (", " .. note.author) or "")
        local body = TextBoxWidget:new{
            text = "“" .. note.text .. "”",
            face = Font:getFace(SUIStyle.FACE_REGULAR, z.body),
            width = width, height = z.body_h, height_adjust = true, height_overflow_show_ellipsis = true,
            alignment = "left",
        }
        local content = LeftContainer:new{ dimen = Geom:new{ w = w, h = z.h }, VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = Plain.PAD },
            body,
            VerticalSpan:new{ width = z.gap },
            Plain.text(attribution, z.attr, { sub = true, max_width = width }),
        } }
        if not note.workId then return content end
        local tappable = InputContainer:new{ dimen = Geom:new{ w = w, h = z.h }, [1] = content }
        tappable.ges_events = {
            TapNote = { GestureRange:new{ ges = "tap", range = function() return tappable.dimen end } },
        }
        function tappable:onTapNote()
            -- an error here would end KOReader: it is shown instead, and the traceback goes to the log
            local ok, err = xpcall(function()
                local p = Plain.plugin()
                if p then
                    -- fileCount 2: the files of the work are asked, since the note does not say which one to open
                    p:chooseAndOpen({ id = note.workId, title = note.title, fileCount = 2 })
                end
            end, debug.traceback)
            if not ok then
                require("logger").err("codice: tap on a note failed:", err)
                UIManager:show(require("ui/widget/infomessage"):new{ text = "O Códice não conseguiu abrir a obra.\n\n" .. core.firstLine(err) })
            end
            return true
        end
        return tappable
    end,
}
