script_name('Ranger Helper')
script_author('Avenix')
script_version('1.0')

require 'lib.moonloader'
local imgui       = require 'mimgui'
local ffi         = require 'ffi'
local vkeys       = require 'vkeys'
local faicons     = require 'fAwesome6'
local encoding    = require 'encoding'
encoding.default  = 'CP1251'
local u8          = encoding.UTF8
local bit         = require 'bit'
pcall(ffi.cdef, 'short GetAsyncKeyState(int vKey);')

local new = imgui.new
local logoFont = nil
local panelFont, panelFontB, fontKeep = nil, nil, {}
local iconRanges = nil

local WIN_W, WIN_H  = 880, 480
local ED_W, ED_H    = 1000, 580
local ROUNDING      = 15
local MARGIN        = 14
local SB_FULL       = 188
local SB_MIN        = 56
local SB_ICON_DX    = 3
local ANIM_SPEED    = 12

local GA, DT = 1, 0.016
local UI_ALPHA = 1

local function V(x, y) return imgui.ImVec2(x, y) end
local function C(r, g, b, a) return imgui.ImVec4(r / 255, g / 255, b / 255, (a or 255) / 255) end

local function U(c, m)
    local a = c.w * (m or 1) * GA * UI_ALPHA
    local r, g, b = c.x, c.y, c.z
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    if r < 0 then r = 0 elseif r > 1 then r = 1 end
    if g < 0 then g = 0 elseif g > 1 then g = 1 end
    if b < 0 then b = 0 elseif b > 1 then b = 1 end
    a, r, g, b = a * 255 + 0.5, r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5
    return (a - a % 1) * 16777216 + (b - b % 1) * 65536 + (g - g % 1) * 256 + (r - r % 1)
end
local function clamp(v, a, b) return math.max(a, math.min(b, v)) end
local function containsText(value, query)
    query = tostring(query or ''):lower()
    if query == '' then return true end
    return tostring(value or ''):lower():find(query, 1, true) ~= nil
end
local function ease(t) return t * t * (3 - 2 * t) end
local function lerp(a, b, t) return a + (b - a) * t end
local function lerpC(a, b, t)
    return imgui.ImVec4(lerp(a.x, b.x, t), lerp(a.y, b.y, t), lerp(a.z, b.z, t), lerp(a.w, b.w, t))
end

local icoCache = {}
local function ico(name)
    local s = icoCache[name]
    if s == nil then
        local ok, r = pcall(faicons, name)
        s = (ok and type(r) == 'string') and r or ''
        icoCache[name] = s
    end
    return s
end

local rrBroken = false
local SM = {}
SM.N = 3.0
SM.EXT = 1.4

SM.cc = {}
function SM.corner(seg, n)
    local key = seg * 100 + n * 10
    local t = SM.cc[key]
    if t then return t[1], t[2] end
    local X, Y, e, hp = {}, {}, 2 / n, math.pi / 2
    for j = 0, seg do
        local ang = j / seg * hp
        X[j], Y[j] = math.cos(ang) ^ e, math.sin(ang) ^ e
    end
    SM.cc[key] = { X, Y }
    return X, Y
end

SM.tc, SM.tn = {}, 0
function SM.tsz(text)
    local c = SM.tc[text]
    if not c then
        local ts = imgui.CalcTextSize(text)
        c = { ts.x, ts.y }
        SM.tn = SM.tn + 1
        if SM.tn > 4000 then SM.tc, SM.tn = {}, 0 end
        SM.tc[text] = c
    end
    return c[1], c[2]
end
function SM.tw(text) return (SM.tsz(text)) end

SM.edR, SM.edOn, SM.low = { x = 0, y = 0, w = 0, h = 0 }, false, false
function SM.edBox(pos, w, h)
    local er = SM.edR
    er.x, er.y, er.w, er.h = pos.x, pos.y, w, h
    SM.edOn = true
end

local function rrPath(dl, p1, p2, r)
    local x1, y1, x2, y2 = p1.x, p1.y, p2.x, p2.y
    local w, h = x2 - x1, y2 - y1
    local half = math.min(w, h) / 2
    r = math.min(r, half)
    local n, s = SM.N, r * SM.EXT
    if r >= half - 0.5 then n, s = 2.0, r end
    s = math.min(s, w / 2, h / 2)
    local seg = math.max(10, math.min(32, math.ceil(s * 0.95)))
    local X, Y = SM.corner(seg, n)
    local tmp = SM.pt
    if not tmp then tmp = imgui.ImVec2(0, 0); SM.pt = tmp end
    dl:PathClear()
    local cx, cy = x2 - s, y1 + s
    for j = seg, 0, -1 do tmp.x, tmp.y = cx + s * X[j], cy - s * Y[j]; dl:PathLineTo(tmp) end
    cy = y2 - s
    for j = 0, seg do tmp.x, tmp.y = cx + s * X[j], cy + s * Y[j]; dl:PathLineTo(tmp) end
    cx = x1 + s
    for j = seg, 0, -1 do tmp.x, tmp.y = cx - s * X[j], cy + s * Y[j]; dl:PathLineTo(tmp) end
    cy = y1 + s
    for j = 0, seg do tmp.x, tmp.y = cx - s * X[j], cy - s * Y[j]; dl:PathLineTo(tmp) end
end

function SM.build(p1, p2, r)
    local x1, y1, x2, y2 = p1.x, p1.y, p2.x, p2.y
    local w, h = x2 - x1, y2 - y1
    local half = math.min(w, h) / 2
    r = math.min(r, half)
    local n, s = SM.N, r * SM.EXT
    if r >= half - 0.5 then n, s = 2.0, r end
    s = math.min(s, w / 2, h / 2)
    local seg = math.max(10, math.min(32, math.ceil(s * 0.95)))
    local X, Y = SM.corner(seg, n)
    local a = SM.arr
    if not a then a = ffi.new('ImVec2[160]'); SM.arr = a end
    local k = 0
    local cx, cy = x2 - s, y1 + s
    for j = seg, 0, -1 do a[k].x, a[k].y = cx + s * X[j], cy - s * Y[j]; k = k + 1 end
    cy = y2 - s
    for j = 0, seg do a[k].x, a[k].y = cx + s * X[j], cy + s * Y[j]; k = k + 1 end
    cx = x1 + s
    for j = seg, 0, -1 do a[k].x, a[k].y = cx - s * X[j], cy + s * Y[j]; k = k + 1 end
    cy = y1 + s
    for j = 0, seg do a[k].x, a[k].y = cx - s * X[j], cy - s * Y[j]; k = k + 1 end
    return a, k
end
function SM.fastFill(dl, p1, p2, col, r)
    local a, k = SM.build(p1, p2, r)
    dl:AddConvexPolyFilled(a, k, col)
end
function SM.fastStroke(dl, p1, p2, col, r, th)
    local a, k = SM.build(p1, p2, r)
    dl:AddPolyline(a, k, col, 1, th or 1)
end
function SM.fill(dl, p1, p2, col, r)
    local f = SM.fastOk
    if f then return SM.fastFill(dl, p1, p2, col, r) end
    if f == nil then
        if pcall(SM.fastFill, dl, p1, p2, col, r) then SM.fastOk = true; return end
        SM.fastOk = false
    end
    rrPath(dl, p1, p2, r); dl:PathFillConvex(col)
end
function SM.stroke(dl, p1, p2, col, r, th)
    local f = SM.fastOk
    if f then return SM.fastStroke(dl, p1, p2, col, r, th) end
    if f == nil then
        if pcall(SM.fastStroke, dl, p1, p2, col, r, th) then return end
        SM.fastOk = false
    end
    rrPath(dl, p1, p2, r); dl:PathStroke(col, 1, th or 1)
end

local function rrf(dl, p1, p2, col, r, flags)
    r = r or 0
    if col < 16777216 then return end
    if r >= 4 and not rrBroken then
        if SM.low then dl:AddRectFilled(p1, p2, col, r); return end
        if SM.fastOk then SM.fastFill(dl, p1, p2, col, r); return end
        if pcall(SM.fill, dl, p1, p2, col, r) then return end
        rrBroken = true
        pcall(dl.PathClear, dl)
    end
    dl:AddRectFilled(p1, p2, col, r)
end
local function rr(dl, p1, p2, col, r, flags, th)
    r = r or 0
    if col < 16777216 then return end
    if r >= 4 and not rrBroken then
        if SM.low then dl:AddRect(p1, p2, col, r, flags or 15, th or 1); return end
        if SM.fastOk then SM.fastStroke(dl, p1, p2, col, r, th); return end
        if pcall(SM.stroke, dl, p1, p2, col, r, th) then return end
        rrBroken = true
        pcall(dl.PathClear, dl)
    end
    dl:AddRect(p1, p2, col, r, flags or 15, th or 1)
end

function SM.clipOff(dl) return (pcall(dl.PushClipRectFullScreen, dl)) end
function SM.clipOn(dl, ok) if ok then pcall(dl.PopClipRect, dl) end end

local P = {
    bg         = C(20, 24, 38, 240),
    outline    = C(90, 120, 220, 120),
    text       = C(235, 238, 250),
    muted      = C(154, 163, 196),
    card       = C(28, 34, 54),
    cardHover  = C(38, 46, 76),
    item       = C(23, 28, 45),
    chip       = C(18, 22, 36),
    active     = C(38, 48, 90),
    accent     = C(91, 120, 238),
    accentHov  = C(110, 138, 250),
    accentSoft = C(183, 195, 255),
    off        = C(58, 66, 98),
    line       = C(35, 42, 64),
    danger     = C(224, 108, 108),
}

local LV = {
    C(86, 184, 122), C(86, 184, 122), C(226, 176, 70),
    C(226, 176, 70), C(226, 98, 98),  C(226, 98, 98),
}

local smoothAnimations = true
local showTooltips = true
local cfgDirty = false
SM.toggleKey = true
SM.greet     = true
SM.cmd       = 'rhelp'
SM.cmdBuf    = new.char[32]()
imgui.StrCopy(SM.cmdBuf, 'rhelp')
SM.cmdMsg, SM.cmdMsgT, SM.cmdWas = nil, 0, false

local binder = {
    ready    = false,
    busy     = false,
    needSave = false,
    needSync = false,
    cmds     = {},
    GAP      = 500,
}

local hv = {}
local function anim(id, target, spd)
    if not smoothAnimations or SM.low then hv[id] = target; return target end
    local t = hv[id] or 0
    t = t + (target - t) * clamp(DT * (spd or 14), 0, 1)
    if math.abs(target - t) < 0.004 then t = target end
    hv[id] = t
    return t
end
local function hot(id, hovered) return anim(id, hovered and 1 or 0, 16) end

local window      = new.bool(false)
local editor      = new.bool(false)
local tab         = 2
local tabChosen   = false
local sideT       = 0
local sideTarget  = 0
local collapseTimer = 0
local openedAt    = 0
local pageStart   = 0
local scrollReset = 0

local kpkSec      = 1
local kpkPre      = { 1, 1, 1 }
local kpkOpen     = {}
local hotCap      = 0
local settingsTab = 1
local palIdx      = 1

local editIdx     = 0
local editMode    = 'bind'
local justOpened  = false
local edT         = 0
local edOpenAt    = 0
local mainCenter  = { x = 0, y = 0 }

local rowDrag = { on = false, idx = 0, tgt = 0, grab = 0 }
binder.kdrag = { on = false, kind = 'item', ci = 0, ii = 0, tgtC = 0, tgtI = 0, grab = 0 }
local btnDrag = { on = false, idx = 0, tgt = 0, grab = 0 }
local searchBuf = { new.char[64](), new.char[64](), new.char[64]() }

local profile = {
    name = new.char[64](), surname = new.char[64](), fraction = new.char[96](),
    rank = new.char[64](), phone = new.char[32](), callsign = new.char[64](), sex = 0,
}

local ed = {
    name      = new.char[128](),
    cmd       = new.char[32](),
    content   = new.char[4096](),
    key       = 'Не задана',
    capture   = false,
    weaponIdx = 1,
    phase     = 1,
    texts     = { '', '' },
    btns      = {},
    sel       = 0,
    btnTitle  = new.char[128](),
}

local TABS = {
    { name = 'Главная',          ico = 'HOUSE' },
    { name = 'Биндер',           ico = 'KEYBOARD' },
    { name = 'Круговое меню',    ico = 'BULLSEYE' },
    { name = 'Отыгровка оружий', ico = 'GUN', sub = true },
    { name = 'Диалоги',          ico = 'LIST' },
    { name = 'Заметки',          ico = 'NOTE_STICKY' },
    { name = 'КПК',              ico = 'DESKTOP' },
    { name = 'Профили',          ico = 'USERS', hidden = true, parent = 1 },
    { name = 'Настройки',        ico = 'GEAR' },
}

binder.MOVED = { cuff = true, uncuff = true, gotome = true, ungotome = true, cg = true, setcarc = true, frisk = true, pull = true }
binder.DEFAULT_BINDS = {
    { title = 'Наручники', cmd = 'cuff', text = '/me одной рукой держит подозреваемого, другой рукой достает из подсумка наручники ...\n/cuff {param1}\n<1500>\n/me ... и скрестив руки подозреваемого, нацепил их на него.', cat = 2 },
    { title = 'Снять наручники', cmd = 'uncuff', text = '/me сунув руку в карман, извлек ключи от наручников.\n/uncuff {param1}\n<1500>\n/me вставил ключ в замок и медленно расковал подозреваемого, освобождая его руки.', cat = 2 },
    { title = 'Следовать', cmd = 'gotome', text = '/me схватил подозреваемого за плечо и с силой сжимает запястье человека.\n/gotome {param1}\n<1500>\n/todo Без резких движений!*повысив тембр голоса', cat = 2 },
    { title = 'Отпустить', cmd = 'ungotome', text = '/me убрал руку с плеча и отпустил запястье человека.\n/ungotome {param1}', cat = 2 },
    { title = 'Наручники + Следовать', cmd = 'cg', text = '/me одной рукой держит подозреваемого, другой рукой достает из подсумка наручники ...\n/cuff {param1}\n<1500>\n/me ... и скрестив руки подозреваемого, нацепил их на него.\n<2500>\n/me схватил подозреваемого за плечо и с силой сжимает запястье человека.\n/gotome {param1}\n<1500>\n/todo Без резких движений!*повысив тембр голоса', cat = 2 },
    { title = 'Обыск', cmd = 'frisk', text = '/me надев резиновые перчатки, начал прощупывать человека по всему телу...\n/frisk {param1}\n<1500>\n/me ... затем начал тщательно обыскивать гражданина, выкладывая все для изучения', on = false, cat = 2 },
    { title = 'Вытащить из транспорта', cmd = 'pull', text = '/me схватил дубинку с пояса и начал бить по окну водителя.\n<1500>\n/me разбив стекло, открыл дверь изнутри и схватил водителя.\n<1500>\n/pull {param1}\n/me вытащил водителя и заломал руки.', cat = 3 },
    { title = 'Приветствие игрока', cmd = 'zd', text = '{greeting}, я - <namesurname()> {rank} {fraction}.\n<1500>\nЧем я могу Вам помочь?', cat = 1 },
    { title = 'Оставить отпечаток на фаре', cmd = 'fara', text = '/me коснулся левой фары <carname({nearcar})>.\n<1500>\n/do Отпечаток успешно оставлен на левой фаре транспортного средства.', cat = 1 },
    { title = 'Запрос документов', cmd = 'pas', text = 'Здравствуйте, управление {fraction}, я {rank} <namesurname()>\n<1500>\n/do Слева на груди жетон сотрудника {fraction}, справа именная нашивка с именем.\n<1500>\n/me достаёт своё удостоверение из кармана.\n<1500>\n/showbadge {param1}\n<1500>\nПрошу предъявить документ, удостоверяющий вашу личность.', cat = 1 },
    { title = 'Поиск игрока', cmd = 'find', text = '/me достал{?} свой КПК и зайдя в базу данных {fraction} открыл{?} дело гражданина {rpId({param1})}.\n<1500>\n/me нажал{?} на кнопку GPS отслеживания местоположения гражданина.\n/find {param1}', cat = 1 },
    { title = 'Изъятие предмета', cmd = 'take', text = '/do В подсумке находится небольшой зип-пакет.\n<1500>\n/me достаёт из подсумка зип-пакет, открывает его и кладёт в него изъятые предметы.\n/take {param1}\n<1500>\n/do Изъятые предметы в зип-пакете.', cat = 1 },
    { title = 'Затащить в транспорт', cmd = 'incar', text = '/me открывает заднюю дверь транспорта.\n<1500>\n/todo Наклоните голову, здесь дверь*заталкивая задержанного в транспортное средство\n/incar {param1} {param2}\n<1500>\n/me закрывает заднюю дверь транспорта.\n<1500>\n/do Задержанный в транспортном средстве.', cat = 3 },
    { title = 'Снять маску с игрока', cmd = 'unmask', text = '/me стягивает балаклаву с головы задержанного.\n/unmask {param1}', cat = 2 },
    { title = 'Арест', cmd = 'arr', text = '/me включает свой бортовой компьютер и вводит код доступа сотрудника.\n<1500>\n/me заходит в раздел оформления протоколов задержаний и указывает данные.\n<1500>\n/do Протокол задержания заполнен.\n<1500>\n/me вызывает по рации дежурный наряд участка и передаёт им задержанного человека.\n/arrest {param1}', cat = 3 },
    { title = 'Взятка', cmd = 'bribe', text = '/do Гражданин сейчас ведёт запись через аудио-видео устройства?\n<1500>\n/n @<namesurname({param1})>, отвечайте на РП, например /do Нет.\n<1500>\n<!>\n/do Телефон в кармане.\n<1500>\n/me достал{?} телефон, открыл{?} заметки, и что-то туда написал{?}.\n<1500>\n/do В заметках телефона написан такой текст: {param2}$\n<1500>\n/todo Что скажете?*показав телефон преступнику возле себя\n<!>\n/bribe {param1} {param2} 1', cat = 3 },
    { title = 'Расследование', cmd = 'delo', text = '/do Сотрудник прибыл на место убийства.\n<1500>\n/todo Такс, что же здесь произошло*осматривая место убийства\n<1500>\n/me осматривает и изучает все улики.\n<!>\n/me достаёт из подсумка бланк для расследования и ручку.\n<1500>\n/me заполняет бланк расследования записывая все изученные улики.\n<!>\n/me записывает в бланк точную дату и время убийства.\n<!>\n/do Найдено орудие убийства.\n<1500>\n/me записывает в бланк орудие убийства.\n<!>\n/do Бланк расследования убийства полностью заполнен.\n<1500>\n/todo Отлично, расследование окончено*убирая бланк в карман', cat = 3 },
    { title = 'Выдача разрешений на номера', cmd = 'giveplate', text = '/do Бланк и ручка в нагрудном кармане.\n<1500>\n/me достаёт ручку и бланк из нагрудного кармана.\n<1500>\n/me заполняет бланк для выдачи разрешения на номерной знак.\n<1500>\n/do Бланк полностью заполнен.\n<1500>\n/todo Вот ваше разрешение, берите*убирая ручку в нагрудный карман\n/giveplate {param1} {param2}', cat = 1 },
    { title = 'Пересадка в карцере', cmd = 'setcarc', text = '/do Ключ от карцера находится в правом кармане.\n<1500>\n/me извлекает ключ от карцера из правого кармана.\n<1500>\n/me открывает дверь карцера, поворачивая ключ по часовой стрелке.\n<1500>\n/do Дверь карцера открыта.\n<1500>\n/me переводит заключенного в другую камеру карцера.\n/setcarcer {param1} {param2}\n<1500>\n/me берет ключ от камеры и закрывает дверь, повернув ключ против часовой стрелки.\n<1500>\n/do Заключенный в камере №{param2}, дверь карцера закрыта.', cat = 1 },
    { title = 'Повестка', cmd = 'agenda', text = '/agenda {param1}\n/do В папке с документами лежит ручка и пустой бланк с надписью "Повестка".\n<1500>\n/me достаёт из папки ручку с пустым бланком повестки.\n<1500>\n/me начинает заполнять все необходимые поля на бланке повестки.\n<1500>\n/do Все данные в повестке заполнены.\n<1500>\n/me ставит на повестку штамп и печать {fraction}.\n<1500>\n/do Готовый бланк повестки в руках.\n<1500>\n/todo Не забудьте явиться в военкомат по указанному адресу и времени*передавая повестку', cat = 1 },
}

function binder.defaultBinds()
    local out = {}
    for _, d in ipairs(binder.DEFAULT_BINDS) do
        local b = { title = d.title, cmd = d.cmd, key = 'Нет', on = (d.on ~= false), text = d.text, preview = '', cat = d.cat or 1 }
        if binder.preview then b.preview = binder.preview(d.text) end
        out[#out + 1] = b
    end
    return out
end

local binds = binder.defaultBinds()

binder.MAX_CATS     = 6
binder.DEF_CATS     = { 'Стандартные', 'Задержание', 'Арест' }
binder.cats    = {}
binder.catNext = 1
binder.catSel  = nil

function binder.catFind(uid)
    for i, c in ipairs(binder.cats) do if c.uid == uid then return c, i end end
end

function binder.catOf(b)
    if b.cat and binder.catFind(b.cat) then return b.cat end
    return binder.cats[1].uid
end

function binder.catCur()
    if binder.catSel == 'sys' then return 'sys' end
    if binder.catSel and binder.catFind(binder.catSel) then return binder.catSel end
    return binder.cats[1].uid
end

function binder.catResetDefault()
    binder.cats, binder.catNext = {}, #binder.DEF_CATS + 1
    for i, nm in ipairs(binder.DEF_CATS) do binder.cats[i] = { uid = i, name = nm } end
end

function binder.catAdd()
    if #binder.cats >= binder.MAX_CATS then return nil end
    local c = { uid = binder.catNext, name = 'Категория ' .. binder.catNext }
    binder.catNext = binder.catNext + 1
    binder.cats[#binder.cats + 1] = c
    binder.needSave = true
    return c
end

function binder.catDelete(uid)
    if #binder.cats <= 1 then return nil end
    local _, i = binder.catFind(uid)
    if not i then return nil end
    table.remove(binder.cats, i)
    local to = binder.cats[math.max(1, i - 1)].uid
    for _, b in ipairs(binds) do if b.cat == uid then b.cat = to end end
    binder.needSave = true
    return to
end

binder.catResetDefault()
binder.DEF_CAT_OF = {}
for _, d in ipairs(binder.DEFAULT_BINDS) do binder.DEF_CAT_OF[d.cmd] = d.cat end

function binder.bindIdx(b)
    for k, v in ipairs(binds) do if v == b then return k end end
    return 0
end

function binder.reorder(fl, from, to)
    local slots = {}
    for k, b in ipairs(fl) do slots[k] = binder.bindIdx(b) end
    local m = table.remove(fl, from)
    table.insert(fl, to, m)
    for k, b in ipairs(fl) do binds[slots[k]] = b end
end

binder.pie = {
    enabled = true,
    mode    = 0,
    btn     = 0x04,
    key     = '',
    cap     = false,
    BTNS    = { { 0x01, 'ЛКМ' }, { 0x02, 'ПКМ' }, { 0x04, 'СКМ' }, { 0x05, 'X1' }, { 0x06, 'X2' } },
    curOn   = false,
    items   = {},
    MAX     = 6,
    MAX_KIDS = 8,
    open    = false, needRelease = false,
    vis = {}, act = 0, lastAct = 0, t0 = 0, cx = 0, cy = 0,
    cache = {},
    ed = { list = {}, idx = 0, kind = 'item', parent = nil, on = true, err = nil, delAsk = nil },
}

binder.mark = {
    cmd     = 'mark',
    blip    = true,
    blipH   = nil,
    blipFor = -1,
    tickAt  = 0,
}
binder.HK_MARK = 'Захват цели (ПКМ +)'
binder.HK_PIE  = 'Круговое меню (ПКМ +)'
binder.HK_DEP  = 'Рация департамента'

local weaponRP = true
local weaponOnRmb = true

local PANEL = {
    enabled = false, x = nil, y = nil,
    city = true, area = true, square = true,
    dir = true, ping = true, fps = true,
    date = true, time = true, secs = true,
}
local panelMove, panelMoveAt, panelOld = false, 0, nil
local panelStartMove, panelPreview

local function iniEsc(s)
    s = s:gsub('\\', '\\\\')
    s = s:gsub('\r?\n', '\\n')
    return s
end
local function iniUnesc(s)
    return (s:gsub('\\(.)', function(c)
        if c == 'n' then return '\n' elseif c == '\\' then return '\\' end
    end))
end

local function prettyTags(s)
    s = s:gsub('{%?%?%?}', '(ла)'):gsub('{%?%?}', '(ась)'):gsub('{%?}', '(а)')
    return s
end
local function weaponPreview(take) return prettyTags(take:match('[^\r\n]+') or '') end

local WEAPON_HOLD = {
    { 'из-за спины', 'за спину' },
    { 'из кармана',  'в карман' },
    { 'с пояса',     'на пояс' },
    { 'из кобуры',   'в кобуру' },
}

local WEAPON_DEFS = {
    { 3,   'дубинку',                    'Дубинка',                    3, true },
    { 109, 'электрошокер',               'Электрошокер',               4, true },
    { 4,   'нож',                        'Нож',                        3, false },
    { 6,   'лопату',                     'Лопата',                     1, false },
    { 8,   'катану',                     'Катана',                     1, false },
    { 16,  'гранату',                    'Граната',                    3, false },
    { 17,  'гранату со слезоточивым газом', 'Tear Gas',                3, false },
    { 22,  'пистолет 9mm',               '9mm',                        4, false },
    { 24,  'пистолет Desert Eagle',      'Desert Eagle',               4, true },
    { 25,  'дробовик',                   'Дробовик',                   1, false },
    { 26,  'обрез',                      'Sawnoff Shotgun',            4, false },
    { 27,  'боевой дробовик',            'Combat Shotgun',             1, false },
    { 28,  'ПП Micro Uzi',               'Micro Uzi',                  3, false },
    { 29,  'ПП MP5',                     'MP5',                        4, false },
    { 30,  'автомат AK-47',              'AK-47',                      1, false },
    { 31,  'автомат M4',                 'M4',                         1, true },
    { 32,  'ПП Tec-9',                   'Tec-9',                      4, false },
    { 33,  'винтовку',                   'Винтовка',                   1, false },
    { 34,  'снайперскую винтовку',       'Снайперская винтовка',       1, true },
    { 41,  'перцовый баллончик',         'Перцовый баллончик',         2, false },
}

local weapons = {}
for _, d in ipairs(WEAPON_DEFS) do
    local id, hold = d[1], WEAPON_HOLD[d[4]]
    local takeVerb = (id == 3 or (id >= 16 and id <= 18)) and 'снял{?}' or 'достал{?}'
    local putVerb  = (id == 3 or (id >= 16 and id <= 18) or id == 39 or id == 40) and 'повесил{?}' or 'убрал{?}'
    local take = '/me ' .. takeVerb .. ' ' .. d[2] .. ' ' .. hold[1]
    local put  = '/me ' .. putVerb  .. ' ' .. d[2] .. ' ' .. hold[2]
    weapons[#weapons + 1] = {
        id = id, title = d[3], on = d[5], take = take, put = put,
        defTitle = d[3], defTake = take, defPut = put,
        preview = weaponPreview(take), text = take,
        cmd = '', key = '', badge = tostring(id),
    }
end

local dialogs = {}

local kpkSecs = {
    { name = 'Розыск', kind = 'su', cmd = 'asu', defCmd = 'asu',          head = 'Розыск (1-6)',    mode = 'pips',    max = 6,  reason = true,
      valueLabel = 'Уровень розыска (1-6)',               chapters = {} },
    { name = 'Штраф', kind = 'ticket', cmd = 'aticket', defCmd = 'aticket',           head = 'Сумма',           mode = 'money',   reason = true,
      valueLabel = 'Сумма штрафа (100 000 - 3 000 000)',      chapters = {} },
    { name = 'Повышение срока', tabName = 'Срок', kind = 'punish', cmd = 'pun', defCmd = 'pun', head = 'Срок (1-10)',  mode = 'pips',    max = 10, reason = true,
      valueLabel = 'Степень изменения срока (1-10)',      chapters = {} },
    { name = 'Карцер', kind = 'carcer', cmd = 'carc', defCmd = 'carc',          head = 'Карцер',          mode = 'minutes', reason = true,
      valueLabel = 'Время в карцере (1-30 минут)',        chapters = {} },
}

local KPK_TABS = 4

binder.kpk = {
    enabled = true,
    bufs    = {},
    pop = { open = false, sec = 0, id = -1, cell = 0, q = new.char[64](), exp = {},
            first = nil, focusNext = false, focusInput = false, focused = false, typing = false },
    curOn = false,
}

binder.sysSub = 1
binder.sysEd  = { e = nil, on = true, justOpened = false }

local SYS_HINT_KPK = 'Играется перед командой раздела. {kpkcmd} - место команды, иначе она уйдёт через 1.5 сек.'
binder.sys = {
    { id = 'kpk1',  kind = 'kpk', si = 1, f = 'rp',      group = 'КПК', title = 'Розыск',          defOn = true, def = '/me связавшись с диспетчером, продиктовал{?} ему приметы подозреваемого и запросил{?} объявление в розыск.\n{kpkcmd}', hint = SYS_HINT_KPK },
    { id = 'wantedreq', kind = 'wanted', group = 'КПК', title = 'Запрос розыска', defOn = true,
      def = '/me зажал{?} кнопку на рации и запросил{?} объявление в розыск.\n<1500>\n/r Запрашиваю объявление в розыск {kpkvalue} уровня дело {rpId({kpkID})}. Причина: {kpkreason}.',
      hint = 'Играется при нажатии кнопки «Запросить розыск» в окне статей /asu. {kpkID} - ID игрока из окна /asu, {kpkarticle} {kpkreason} {kpkvalue} - статья из окна /asu, {rpId()} - ID в виде 0-0-0.' },

    { id = 'kpk2',  kind = 'kpk', si = 2, f = 'rp',      group = 'КПК', title = 'Штраф',           defOn = true, def = '/do Планшет находится в кармане формы.\n{kpkcmd}\n<1500>\n/me достает планшет и вносит изменения в базу штрафов.\n<1500>\n/todo Оплатите штраф*убирая планшет обратно в карман', hint = SYS_HINT_KPK },
    { id = 'kpk3',  kind = 'kpk', si = 3, f = 'rp',      group = 'КПК', title = 'Повышение срока', defOn = true, def = '/do КПК лежит в кармане сотрудника.\n<1500>\n/me достал КПК, ввел пароль, нашёл нужное дело и выбрал раздел "Срок".\n{kpkcmd}\n<1500>\n/me нажал на пункт "повысить" и указал причину.\n<1500>\n/do Срок успешно повышен по причине: {kpkreason}.\n<1500>\n/me заблокировал КПК, после - убрал его в карман.', hint = SYS_HINT_KPK },
    { id = 'kpk4',  kind = 'kpk', si = 4, f = 'rp',      group = 'КПК', title = 'Карцер',          defOn = true, def = '/do Связка ключей находится на поясном держателе.\n<1500>\n/me нащупав нужный ключ, вставил его в замочную скважину двери ...\n<1500>\n/me ... карцера, после - повернул по часовой стрелке.\n<1500>\n/do Дверь карцера открылась.\n<1500>\n{kpkcmd}\n<1500>\n/todo Это твой новый дом на ближайшее время.*толкая заключенного в карцер\n<1500>\n/me закрыл дверь карцера, тщательно прижав ее, затем повернул ключ против часовой стрелки.\n<1500>\n/do Дверь карцера захлопнулась, заключенный в карцере номер {param2}.', hint = SYS_HINT_KPK },

    { id = 'afind', kind = 'afind', group = 'Автопоиск /afind', title = 'Начало автопоиска', defOn = true,
      def = '/me достал{?} КПК и включил{?} отслеживание <namesurname({param1})>.',
      hint = 'Играется при запуске автопоиска, сам поиск стартует после отыгровки. {param1} - ID игрока.' },
    { id = 'afindstop', kind = 'afind', group = 'Автопоиск /afind', title = 'Остановка автопоиска', defOn = true,
      def = '/me отключил{?} слежение на КПК.',
      hint = 'Играется, когда автопоиск остановлен вручную. {param1} - ID игрока.' },

    { id = 'pursuit', kind = 'pursuit', group = 'Розыск /wanteds (погоня)', title = 'Начало погони', defOn = true,
      def = '/me достал{?} КПК и включил{?} отслеживание <namesurname({param1})>.',
      hint = 'Играется при начале погони. {syscmd} - место команды, иначе она уйдёт через 1.5 сек.' },
    { id = 'pursuitstop', kind = 'pursuit', group = 'Розыск /wanteds (погоня)', title = 'Остановка погони', defOn = true,
      def = '/me нажал{?} на КПК кнопку остановки отслеживания.',
      hint = 'Играется при остановке погони. {syscmd} - место команды, иначе она уйдёт через 1.5 сек.' },
}
for _, e in ipairs(binder.sys) do
    e.on, e.key, e.cmd, e.preview = e.defOn, '', '', ''
    if e.kind ~= 'kpk' then e.text = e.def end
end

function binder.sysReset()
    for _, e in ipairs(binder.sys) do
        e.on, e._was = e.defOn, nil
        if e.kind == 'kpk' then kpkSecs[e.si].rp = e.def or '' else e.text = e.def end
    end
end

function binder.sysText(e)
    if e.kind == 'kpk' then return kpkSecs[e.si][e.f] or '' end
    return e.text or ''
end

function binder.sysSetText(e, v)
    if e.kind == 'kpk' then kpkSecs[e.si][e.f] = v else e.text = v end
end

function binder.sysFind(id)
    for _, e in ipairs(binder.sys) do if e.id == id then return e end end
end

function binder.sysKpk(si)
    for _, e in ipairs(binder.sys) do
        if e.kind == 'kpk' and e.si == si then return e end
    end
end

function binder.sysKpkText(si)
    local e = binder.sysKpk(si)
    if not e or not e.on then return '' end
    return binder.sysText(e)
end

function binder.sysPlay(id, plid, ctx)
    local e = binder.sysFind(id)
    if not e or not e.on then return nil end
    local text = binder.sysText(e)
    if binder.trim(text) == '' then return nil end

    if id == 'wantedreq' then
        ctx = ctx or {}
        for _, tag in ipairs({ 'kpkarticle', 'kpkreason', 'kpkvalue', 'kpkID' }) do
            text = text:gsub('{' .. tag .. '}', function() return ctx[tag] or '' end)
        end
    end
    local a = tostring(plid)
    if binder.play(text, { a }, a) then return binder.threads[#binder.threads] end
    return nil
end

function binder.sysCmd(id, plid, cmd)
    local e = binder.sysFind(id)
    if not e or not e.on then return false end
    local rp = binder.sysText(e)
    if binder.trim(rp) == '' then return false end
    local direct = '\1' .. cmd
    local out, found = {}, false
    for ln in (rp .. '\n'):gmatch('(.-)\r?\n') do
        if binder.trim(ln) == '{syscmd}' then
            out[#out + 1], found = direct, true
        elseif ln:find('{syscmd}', 1, true) then
            out[#out + 1], found = (ln:gsub('{syscmd}', function() return cmd end)), true
        else
            out[#out + 1] = ln
        end
    end
    local text = table.concat(out, '\n')
    if not found then text = text .. '\n<1500>\n' .. direct end
    local a = tostring(plid)
    return binder.play(text, { a }, a) and true or false
end

function binder.sysWait(th)
    while th do
        local st = th:status()
        if st == 'dead' or st == 'error' then break end
        wait(50)
    end
end

local PAL = {
    { 91, 120, 238 }, { 52, 168, 176 }, { 76, 172, 112 }, { 214, 164, 62 },
    { 214, 92, 92 },  { 152, 104, 226 }, { 214, 104, 164 }, { 128, 138, 166 },
}
local PAL_NAMES = { 'Синий', 'Бирюзовый', 'Зелёный', 'Золотой', 'Красный', 'Фиолетовый', 'Розовый', 'Графит' }

local function applyPalette(index)
    palIdx = clamp(index, 1, #PAL)
    local c = PAL[palIdx]
    local r, g, b = c[1], c[2], c[3]
    P.accent = C(r, g, b)
    P.accentHov = C(clamp(r + 22, 0, 255), clamp(g + 22, 0, 255), clamp(b + 22, 0, 255))
    P.accentSoft = C(clamp(r + (255 - r) * 0.42, 0, 255),
                      clamp(g + (255 - g) * 0.42, 0, 255),
                      clamp(b + (255 - b) * 0.42, 0, 255))

    P.outline = C(r, g, b, 165)
    P.bg = C(lerp(20, r, 0.075), lerp(24, g, 0.075), lerp(38, b, 0.075), 246)
    P.card = C(lerp(28, r, 0.13), lerp(34, g, 0.13), lerp(54, b, 0.13))
    P.item = C(lerp(23, r, 0.09), lerp(28, g, 0.09), lerp(45, b, 0.09))
    P.chip = C(lerp(18, r, 0.06), lerp(22, g, 0.06), lerp(36, b, 0.06))
    P.off = C(lerp(58, r, 0.16), lerp(66, g, 0.16), lerp(98, b, 0.16))
    P.cardHover = C(lerp(38, r, 0.24), lerp(46, g, 0.24), lerp(76, b, 0.24))
    P.line = C(lerp(35, r, 0.30), lerp(42, g, 0.30), lerp(64, b, 0.30))
    P.active = C(clamp(r * 0.28 + 10, 0, 255),
                 clamp(g * 0.28 + 12, 0, 255),
                 clamp(b * 0.28 + 22, 0, 255))
end
applyPalette(1)

local hotkeys = {
    { 'Открыть хелпер',                        'F2' },
    { 'Принудительно завершить отыгровку',     'Backspace' },
    { 'Продолжить приостановленную отыгровку', 'Ctrl+Enter' },
    { 'Приостановить отыгровку',               'Pause' },
    { 'Захват цели (ПКМ +)',                   ',' },
    { 'Круговое меню (ПКМ +)',                 'R' },
    { 'Рация департамента',                    'Не задана' },
}

local function resetUi()
    sideT, sideTarget, tabChosen, collapseTimer = 0, 0, false, 0
    openedAt  = os.clock()
    pageStart = openedAt
    kpkSec, kpkPre, hotCap = 1, { 1, 1, 1 }, 0
    binder.sysSub = 1
    binder.catSel = nil
    binder.note.cap, binder.note.delAsk = false, nil
    kpkOpen = {}
    for k in pairs(hv) do hv[k] = nil end
    editor[0] = false
    edT = 0
    scrollReset = 3
end

local function setOpen(v)
    window[0] = v
    if v then resetUi() else editor[0] = false end
end

local function setTab(i)
    if tab ~= i then pageStart = os.clock(); scrollReset = 2 end
    tab = i
    tabChosen = true
    hotCap = 0
    binder.pie.cap = false
    binder.note.cap = false
end
function SM.goTab(i) setTab(i) end

local function centerText(dl, x, y, w, h, text, col)
    local tx, ty = SM.tsz(text)
    if tx > w - 8 then
        dl:PushClipRect(V(x + 4, y), V(x + w - 4, y + h), true)
        dl:AddText(V(x + 6, y + (h - ty) / 2), col, text)
        dl:PopClipRect()
        return
    end
    dl:AddText(V(x + (w - tx) / 2, y + (h - ty) / 2), col, text)
end

local function card(dl, x, y, w, h, r, fill, border, bm)
    rrf(dl, V(x, y), V(x + w, y + h), U(fill), r)
    rr(dl, V(x + 0.5, y + 0.5), V(x + w - 0.5, y + h - 0.5), U(border or P.line, bm or 0.9), r, 15, 1)
end

local function hairline(dl, x1, x2, y, col, a)
    local mid = (x1 + x2) / 2
    local c0, c1 = U(col, 0), U(col, a)
    dl:AddRectFilledMultiColor(V(x1, y), V(mid, y + 1.5), c0, c1, c1, c0)
    dl:AddRectFilledMultiColor(V(mid, y), V(x2, y + 1.5), c1, c0, c0, c1)
end

local function iconBadge(dl, x, y, size, name, filled, glow)
    local r = size / 2
    if glow and glow > 0.01 and not SM.low then
        dl:AddCircleFilled(V(x + r, y + r), r + 4, U(P.accent, 0.20 * glow), 36)
    end
    dl:AddCircleFilled(V(x + r, y + r), r, U(filled), 36)
    centerText(dl, x, y, size, size, ico(name), U(P.text))
end

local function heading(dl, x, y, title, sub)
    local t = TABS[tab]

    rrf(dl, V(x, y - 2), V(x + 40, y + 38), U(P.active), 12)
    rr(dl, V(x + 0.5, y - 1.5), V(x + 39.5, y + 37.5), U(P.accent, 0.45), 12, 15, 1)
    centerText(dl, x, y - 2, 40, 40, t and ico(t.ico) or '', U(P.accentSoft))
    dl:AddTextFontPtr(imgui.GetFont(), 20, V(x + 52, y), U(P.text), title)
    if sub then dl:AddText(V(x + 52, y + 26), U(P.muted), sub) end
end

local function button(dl, id, x, y, w, h, text, primary)
    imgui.SetCursorScreenPos(V(x, y))
    local clicked = imgui.InvisibleButton(id, V(w, h))
    local t = hot(id, imgui.IsItemHovered())
    if primary then
        if not SM.low then
            for i = 3, 1, -1 do
                rrf(dl, V(x - i, y - i + 3), V(x + w + i, y + h + i + 3),
                    U(P.accent, 0.05 + 0.05 * t), 9 + i)
            end
        end
        rrf(dl, V(x, y), V(x + w, y + h), U(lerpC(P.accent, P.accentHov, t)), 9)
        dl:AddLine(V(x + 9, y + 1.5), V(x + w - 9, y + 1.5), U(C(255, 255, 255, 60)), 1)
    else
        card(dl, x, y, w, h, 9, lerpC(P.card, P.cardHover, t), lerpC(P.line, P.accent, t * 0.8))
    end
    centerText(dl, x, y, w, h, text, U(C(255, 255, 255)))
    return clicked
end

local function chipR(dl, rx, y, text, bg, fg)
    local w = SM.tw(text) + 16
    rrf(dl, V(rx - w, y), V(rx, y + 22), U(bg), 7)
    rr(dl, V(rx - w + 0.5, y + 0.5), V(rx - 0.5, y + 21.5), U(P.line, 0.8), 7, 15, 1)
    dl:AddText(V(rx - w + 8, y + 4), U(fg), text)
    return rx - w - 6
end

local function chipL(dl, x, y, text, bg, fg)
    local w = SM.tw(text) + 16
    rrf(dl, V(x, y), V(x + w, y + 22), U(bg), 7)
    rr(dl, V(x + 0.5, y + 0.5), V(x + w - 0.5, y + 21.5), U(P.line, 0.8), 7, 15, 1)
    dl:AddText(V(x + 8, y + 4), U(fg), text)
    return x + w + 6
end

local function switchDraw(dl, id, x, y, on, w, h)
    w, h = w or 36, h or 18
    if hv[id] == nil then hv[id] = on and 1 or 0 end
    local t = anim(id, on and 1 or 0, 16)
    if t > 0.02 and not SM.low then
        rrf(dl, V(x - 2, y - 2), V(x + w + 2, y + h + 2), U(P.accent, 0.20 * t), h / 2 + 2)
    end
    rrf(dl, V(x, y), V(x + w, y + h), U(lerpC(P.off, P.accent, t)), h / 2)
    local r = h * 0.36
    local kx = x + h / 2 + (w - h) * t
    if not SM.low then dl:AddCircleFilled(V(kx, y + h / 2 + 1), r + 1.5, U(C(0, 0, 0, 70)), 24) end
    dl:AddCircleFilled(V(kx, y + h / 2), r, U(lerpC(P.muted, C(255, 255, 255), t)), 24)
end

local function checkDraw(dl, id, x, y, on, label)
    local size = 20
    local tw = label and SM.tw(label) or 0
    local w = size + (label and (10 + tw) or 0)
    imgui.SetCursorScreenPos(V(x, y))
    local clicked = imgui.InvisibleButton(id, V(w + 4, size + 4))
    local h = hot(id, imgui.IsItemHovered())
    if hv[id .. 'c'] == nil then hv[id .. 'c'] = on and 1 or 0 end
    local t = anim(id .. 'c', on and 1 or 0, 18)
    local bx, by = x, y + 2
    if t > 0.02 and not SM.low then
        rrf(dl, V(bx - 2, by - 2), V(bx + size + 2, by + size + 2), U(P.accent, 0.20 * t), 8)
    end
    rrf(dl, V(bx, by), V(bx + size, by + size), U(lerpC(lerpC(P.chip, P.cardHover, h), P.accent, t)), 6)
    rr(dl, V(bx + 0.5, by + 0.5), V(bx + size - 0.5, by + size - 0.5),
        U(lerpC(lerpC(P.line, P.accentSoft, h * 0.6), P.accent, t)), 6, 15, 1.2)
    if t > 0.02 then
        local c = U(C(255, 255, 255), t)
        local k = 0.8 + 0.2 * t
        local mx, my = bx + 8.6, by + 14.2
        dl:AddLine(V(bx + 5 + (1 - k) * 2, by + 10.5), V(mx, my), c, 2.2)
        dl:AddLine(V(mx, my), V(bx + 15.4, by + 6.4 + (1 - k) * 3), c, 2.2)
    end
    if label then
        dl:AddText(V(bx + size + 10, by + (size - imgui.GetTextLineHeight()) / 2),
            U(on and P.text or lerpC(P.muted, P.text, h)), label)
    end
    return clicked
end

local function chevron(dl, cx, cy, p, col)
    local a = ease(p) * math.pi / 2
    local ca, sa = math.cos(a), math.sin(a)
    local function rot(x, y) return V(cx + x * ca - y * sa, cy + x * sa + y * ca) end
    local p1, p2, p3 = rot(-2.5, -4.5), rot(2.5, 0), rot(-2.5, 4.5)
    dl:AddLine(p1, p2, col, 1.8)
    dl:AddLine(p2, p3, col, 1.8)
end

local SEG_SEP = 16
local function segWidth(items, sep)
    local total = 6 + (sep and SEG_SEP or 0)
    for _, s in ipairs(items) do total = total + SM.tw(s) + 28 end
    return total
end

local function segTabs(dl, id, x, y, items, cur, sep, hl)
    card(dl, x, y, segWidth(items, sep), 32, 10, P.chip, P.line)
    local px, res = x + 3, nil
    for i, s in ipairs(items) do
        local w = SM.tw(s) + 28
        imgui.SetCursorScreenPos(V(px, y + 3))
        if imgui.InvisibleButton(id .. i, V(w, 26)) then res = i end
        local t = hot(id .. i, imgui.IsItemHovered())
        if hl == i then

            rrf(dl, V(px + 2, y + 5), V(px + w - 2, y + 27), U(P.accent, 0.28 + 0.22 * t), 7)
            rr(dl, V(px + 2.5, y + 5.5), V(px + w - 2.5, y + 26.5), U(P.accent, 0.85), 7, 15, 1)
            centerText(dl, px, y + 3, w, 26, s, U(lerpC(P.accentSoft, P.text, t)))
        else
            if cur == i then
                rrf(dl, V(px, y + 3), V(px + w, y + 29), U(P.active), 8)
                rr(dl, V(px + 0.5, y + 3.5), V(px + w - 0.5, y + 28.5), U(P.accent, 0.55), 8, 15, 1)
            elseif t > 0.01 then
                rrf(dl, V(px, y + 3), V(px + w, y + 29), U(P.card, t), 8)
            end
            centerText(dl, px, y + 3, w, 26, s, U(cur == i and P.text or lerpC(P.muted, P.text, t * 0.6)))
        end
        px = px + w
        if sep and i == sep then
            local lx = px + SEG_SEP / 2
            dl:AddLine(V(lx, y + 8), V(lx, y + 24), U(P.muted, 0.6), 1.5)
            px = px + SEG_SEP
        end
    end
    return res
end

SM.on = false
SM.state = {}
function SM.cv(idx)
    return imgui.GetStyleColorVec4(idx)
end
function SM.wrapFrame(name, isButton, rectFn)
    local orig = imgui[name]
    if type(orig) ~= 'function' then return end
    rawset(imgui, name, function(...)
        if not SM.on or rrBroken or SM.low then return orig(...) end
        local okc, w, h = pcall(rectFn, ...)
        local label = tostring((...))
        local st = SM.state[label]
        if not st then st = { hov = false, act = false, hid = 'wf_' .. label }; SM.state[label] = st end
        local pushed = false
        if okc and w and w > 2 and h and h > 2 then
            local p = imgui.GetCursorScreenPos()
            local base, hovC, actC
            if isButton then
                base, hovC, actC = SM.cv(imgui.Col.Button), SM.cv(imgui.Col.ButtonHovered), SM.cv(imgui.Col.ButtonActive)
            else
                base, hovC, actC = SM.cv(imgui.Col.FrameBg), SM.cv(imgui.Col.FrameBgHovered), SM.cv(imgui.Col.FrameBgActive)
            end
            local t = hot(st.hid, st.hov)
            local col = lerpC(base, hovC, t)
            if st.act then col = actC end
            rrf(imgui.GetWindowDrawList(), p, V(p.x + w, p.y + h), U(col), 9)
            local z = SM.zero
            if not z then z = imgui.ImVec4(0, 0, 0, 0); SM.zero = z end
            if isButton then
                imgui.PushStyleColor(imgui.Col.Button, z)
                imgui.PushStyleColor(imgui.Col.ButtonHovered, z)
                imgui.PushStyleColor(imgui.Col.ButtonActive, z)
            else
                imgui.PushStyleColor(imgui.Col.FrameBg, z)
                imgui.PushStyleColor(imgui.Col.FrameBgHovered, z)
                imgui.PushStyleColor(imgui.Col.FrameBgActive, z)
            end
            pushed = true
        end
        local r1, r2 = orig(...)
        if pushed then imgui.PopStyleColor(3) end
        pcall(SM.hovAct, st)
        return r1, r2
    end)
end
function SM.frameRect() return imgui.CalcItemWidth(), imgui.GetFrameHeight() end
function SM.hovAct(st) st.hov, st.act = imgui.IsItemHovered(), imgui.IsItemActive() end
SM.wrapFrame('InputText', false, SM.frameRect)
SM.wrapFrame('InputTextWithHint', false, SM.frameRect)
SM.wrapFrame('SliderInt', false, SM.frameRect)
SM.wrapFrame('InputTextMultiline', false, function(_, _, _, size)
    local w = (size and size.x > 0) and size.x or imgui.CalcItemWidth()
    local h = (size and size.y > 0) and size.y or imgui.GetTextLineHeight() * 8
    return w, h
end)
SM.wrapFrame('Button', true, function(lbl, size)
    local txt = tostring(lbl):gsub('##.*$', '')
    local st = imgui.GetStyle()
    local w = (size and size.x > 0) and size.x or SM.tw(txt) + st.FramePadding.x * 2
    local h = (size and size.y > 0) and size.y or imgui.GetFrameHeight()
    return w, h
end)

function SM.tip(text)
    text = tostring(text)
    local pad = imgui.GetStyle().WindowPadding
    local ts = imgui.CalcTextSize(text)
    imgui.PushStyleColor(imgui.Col.PopupBg, imgui.ImVec4(0, 0, 0, 0))
    imgui.BeginTooltip()
    local dl, p = imgui.GetWindowDrawList(), imgui.GetWindowPos()
    local q = V(p.x + ts.x + pad.x * 2, p.y + ts.y + pad.y * 2)
    rrf(dl, p, q, U(P.card), 9)
    rr(dl, V(p.x + 0.5, p.y + 0.5), V(q.x - 0.5, q.y - 0.5), U(P.line, 0.9), 9, 15, 1)
    imgui.Text(text)
    imgui.EndTooltip()
    imgui.PopStyleColor(1)
end

local function pushInput()
    SM.on = true
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 9)
    imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, V(10, 7))
    imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, math.max(GA * UI_ALPHA, 0.02))
    imgui.PushStyleColor(imgui.Col.FrameBg, P.card)
    imgui.PushStyleColor(imgui.Col.FrameBgHovered, P.cardHover)
    imgui.PushStyleColor(imgui.Col.FrameBgActive, P.cardHover)
    imgui.PushStyleColor(imgui.Col.Button, P.card)
    imgui.PushStyleColor(imgui.Col.ButtonHovered, P.cardHover)
    imgui.PushStyleColor(imgui.Col.ButtonActive, P.active)
    imgui.PushStyleColor(imgui.Col.Text, P.text)
end
local function popInput()
    SM.on = false
    imgui.PopStyleColor(7)
    imgui.PopStyleVar(3)
end

local function beginList(id, x, y, w, h)
    imgui.SetCursorScreenPos(V(x, y))
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V(0, 0))
    imgui.BeginChild(id, V(w, h), false, imgui.WindowFlags.NoBackground)
    imgui.PopStyleVar(1)
    if scrollReset > 0 then imgui.SetScrollY(0) end
    return imgui.GetCursorScreenPos(), imgui.GetWindowDrawList()
end

local function endList(base, total)
    imgui.SetCursorScreenPos(V(base.x, base.y + total - 1))
    imgui.Dummy(V(1, 1))
    imgui.EndChild()
end

local function openEditor(i, mode)
    editIdx, editMode = i, mode
    btnDrag.on = false
    local list = (mode == 'weapon') and weapons or (mode == 'dialog') and dialogs or binds
    local b = list[i]
    imgui.StrCopy(ed.name, b and b.title or '')
    imgui.StrCopy(ed.cmd,  b and b.cmd or '')
    if mode == 'weapon' then
        ed.texts     = { b and b.take or '', b and b.put or '' }
        ed.weaponIdx = (i > 0) and i or 1
        ed.phase     = 1
        imgui.StrCopy(ed.content, ed.texts[1])
    elseif mode == 'dialog' then
        ed.btns = {}
        if b then
            for _, x in ipairs(b.buttons) do ed.btns[#ed.btns + 1] = { title = x.title, text = x.text } end
        end
        ed.sel = 0
        binder.edLoad(#ed.btns > 0 and 1 or 0)
    else
        imgui.StrCopy(ed.content, b and b.text or '')
    end
    ed.key     = b and b.key or 'Не задана'
    if ed.key == 'Нет' or ed.key == 'Чат' then ed.key = 'Не задана' end
    ed.err, ed.delAsk = nil, nil
    ed.capture = false
    ed.curS, ed.curE, ed.setCursor, ed.refocus = nil, nil, nil, nil
    if mode == 'bind' then
        local cc = b and binder.catOf(b) or binder.catCur()
        ed.catSel = (cc ~= 'sys' and binder.catFind(cc)) and cc or binder.cats[1].uid
    end
    edOpenAt   = os.clock()
    editor[0]  = true
    justOpened = true
end

local function tabY(i)
    local t = TABS[i]
    if t and t.hidden then i = t.parent or 1 end
    if i >= #TABS then return WIN_H - 52 end
    local n = 0
    for j = 1, i - 1 do if not TABS[j].hidden then n = n + 1 end end
    return 64 + n * 42
end

local function drawSidebar(dl, pos, sbW, la)

    dl:AddLine(V(pos.x + sbW, pos.y + 16), V(pos.x + sbW, pos.y + WIN_H - 16), U(P.line), 1)

    local titleY = pos.y + 18
    local font = logoFont or imgui.GetFont()
    local logoCollapse = ease(clamp(sideT, 0, 1))
    local fullAlpha = clamp(1 - logoCollapse * 3.2, 0, 1)

    if SM.fwFont ~= font then SM.fwFont, SM.fwc = font, {} end
    local fwc = SM.fwc
    local function fw(text, size)
        local base = fwc[text]
        if not base then
            imgui.PushFont(font)
            base = imgui.CalcTextSize(text).x
            imgui.PopFont()
            fwc[text] = base
        end
        return base * size / 24
    end

    local lc = SM.logoLay
    if not lc or SM.logoFont ~= font then lc = {}; SM.logoLay, SM.logoFont = lc, font end
    local function layout(size, text, gap)
        local key = text .. size .. ':' .. gap
        local L = lc[key]
        if not L then
            L = { n = 0, w = 0 }
            local x = 0
            for ch in text:gmatch('.') do
                L.n = L.n + 1
                L[L.n] = { ch, x }
                x = x + fw(ch, size) + gap
            end
            L.w = x - gap
            lc[key] = L
        end
        return L
    end
    local function spaced(size, x, y, col, text, gap)
        local L = layout(size, text, gap)
        for i = 1, L.n do
            local c = L[i]
            dl:AddTextFontPtr(font, size, V(x + c[2], y), col, c[1])
        end
    end
    local function spacedW(size, text, gap) return layout(size, text, gap).w end
    local logoCx = pos.x + sbW / 2 + 1
    local ly = pos.y + 20
    if fullAlpha > 0.01 then
        local size, gap, space = 22, 2, 9
        local w1, w2 = spacedW(size, 'RANGER', gap), spacedW(size, 'HELPER', gap)
        local x = logoCx - (w1 + space + w2) / 2
        spaced(size, x, ly, U(P.text, fullAlpha), 'RANGER', gap)
        spaced(size, x + w1 + space, ly, U(P.accentSoft, fullAlpha), 'HELPER', gap)
    end
    local rhAlpha = clamp((logoCollapse - 0.3) * 2.5, 0, 1)
    if rhAlpha > 0.01 then
        local size, gap = 25, 2
        local w = spacedW(size, 'RH', gap)
        local x = logoCx - w / 2
        spaced(size, x, ly - 1, U(P.text, rhAlpha), 'R', gap)
        spaced(size, x + fw('R', size) + gap, ly - 1, U(P.accentSoft, rhAlpha), 'H', gap)
    end
    local lineAlpha = clamp(1 - sideT * 1.8, 0, 1)
    if lineAlpha > 0.01 then
        hairline(dl, pos.x + 16, pos.x + sbW - 16, pos.y + 53, P.accent, 0.7 * lineAlpha)
    end

    local ty = tabY(tab)
    if hv.pillY == nil then hv.pillY = ty end
    local pillY = anim('pillY', ty, 14)
    local px1, px2 = pos.x + 9, pos.x + sbW - 7
    local py1, py2 = pos.y + pillY, pos.y + pillY + 36
    rrf(dl, V(px1, py1), V(px2, py2), U(P.active), 10)
    rr(dl, V(px1 + 0.5, py1 + 0.5), V(px2 - 0.5, py2 - 0.5), U(P.accent, 0.45), 10, 15, 1)
    rrf(dl, V(px1 + 1.5, py1 + 9), V(px1 + 4.5, py2 - 9), U(P.accent), 2)

    for i, t in ipairs(TABS) do if not t.hidden then
        local y = tabY(i)
        local x, w = pos.x + 9, sbW - 16
        local p1, p2 = V(x, pos.y + y), V(x + w, pos.y + y + 36)

        imgui.SetCursorScreenPos(p1)
        if imgui.InvisibleButton('##tab' .. i, V(w, 36)) then setTab(i) end
        local hov = imgui.IsItemHovered()
        local ht = hot('tab' .. i, hov)
        local isAct = (tab == i)

        if not isAct and ht > 0.01 then
            rrf(dl, p1, p2, U(P.cardHover, ht * 0.9), 10)
        end

        local k = ease(clamp(sideT, 0, 1))
        local cx, cy = lerp(x + 20, pos.x + sbW / 2 + SB_ICON_DX, k), pos.y + y + 18
        local iconText = ico(t.ico)
        local isz = 14 + 4 * k
        local tsx, tsy = SM.tsz(iconText)
        local sc = isz / 14
        dl:AddTextFontPtr(imgui.GetFont(), isz, V(cx - tsx * sc / 2, cy - tsy * sc / 2),
            U(isAct and C(255, 255, 255) or lerpC(P.muted, P.text, ht)), iconText)

        if la > 0.02 then
            dl:AddText(V(x + 40, pos.y + y + 10),
                U(isAct and P.text or lerpC(P.muted, P.text, ht), la), t.name)
        end
        if showTooltips and hov and sideT > 0.7 then SM.tip(t.name) end
    end end
end

local function rollRow(dl, id, x, y, w, it, badge, selected, ghost)
    local clicked, active, t = false, false, 1
    if ghost then

        rrf(dl, V(x - 2, y + 2), V(x + w + 2, y + 50), U(C(0, 0, 0, 90)), 12)
    else
        imgui.SetCursorScreenPos(V(x, y))
        clicked = imgui.InvisibleButton(id, V(w - 62, 44))
        active = imgui.IsItemActive()
        t = hot(id, imgui.IsItemHovered())
    end
    local bg = selected and P.active or lerpC(P.card, P.cardHover, t)
    card(dl, x, y, w, 44, 10, bg, lerpC(P.line, P.accent, selected and 0.9 or t * 0.7))

    local a  = it.on and 1 or 0.5

    if it.on then rrf(dl, V(x + 4, y + 11), V(x + 7, y + 33), U(P.accent), 2) end

    local tx = x + 18
    if badge then
        card(dl, x + 16, y + 7, 30, 30, 8, P.chip, P.line, a)
        centerText(dl, x + 16, y + 7, 30, 30, badge, U(P.accentSoft, a))
        tx = x + 58
    end

    local rx = x + w - 62
    local limit = rx - (SM.tw(it.key) + 22)
    if it.cmd ~= '' then limit = limit - (SM.tw('/' .. it.cmd) + 22) end
    dl:PushClipRect(V(tx, y), V(limit - 6, y + 44), true)
    dl:AddText(V(tx, y + 7),  U(P.text, a),  it.title)
    dl:AddText(V(tx, y + 25), U(P.muted, a), it.preview)
    dl:PopClipRect()

    if it.key ~= '' then rx = chipR(dl, rx, y + 11, it.key, P.chip, P.accentSoft) end
    if it.cmd ~= '' then chipR(dl, rx, y + 11, '/' .. it.cmd, P.chip, P.accentSoft) end

    if not ghost then
        imgui.SetCursorScreenPos(V(x + w - 48, y + 13))
        if imgui.InvisibleButton(id .. 'tg', V(36, 18)) then
            it.on = not it.on; cfgDirty = true
            binder.needSave = true; binder.needSync = true
        end
    end
    switchDraw(dl, id .. 'sw', x + w - 48, y + 13, it.on)
    return clicked, active
end

local pages = {}

pages[1] = function(dl, pos, cx, cw)
    heading(dl, cx, pos.y + 18, 'Главная', 'Биндер, диалоги, КПК, круговое меню и функции')

    if not SM.ver then
        local ok, v = pcall(function() return thisScript().version end)
        SM.ver = (ok and v) and tostring(v):match('^[%d%.]+') or '0.9'
    end

    local hy = pos.y + 70
    card(dl, cx, hy, cw, 84, 14, P.card)
    rrf(dl, V(cx + 1, hy + 18), V(cx + 5, hy + 66), U(P.accent), 2)
    dl:AddTextFontPtr(imgui.GetFont(), 20, V(cx + 24, hy + 14), U(P.text), 'Добро пожаловать')
    dl:AddText(V(cx + 24, hy + 42), U(P.muted), 'Выберите вкладку слева, чтобы перейти в нужный раздел.')
    dl:AddText(V(cx + 24, hy + 60), U(P.muted), 'Меню сворачивается, когда курсор уходит с него; раскрыть - курсор к левому краю.')
    chipR(dl, cx + cw - 16, hy + 14, 'v' .. SM.ver, P.chip, P.accentSoft)

    local STH, SCOLS = 60, 3
    local KH, TH = 66, 52
    local sw3 = (cw - 10 * (SCOLS - 1)) / SCOLS
    local sy = hy + 98
    do
        local PFh = binder.pf
        local list = PFh.list or {}
        local n = #list
        local MAXS, AH = 6, 100
        dl:AddText(V(cx + 2, sy + 4), U(P.muted), 'ПРОФИЛИ  ' .. n .. ' / ' .. (PFh.max or 6))
        local mw = 124
        imgui.SetCursorScreenPos(V(cx + cw - mw, sy))
        if imgui.InvisibleButton('##mainpf_manage', V(mw, 22)) then SM.goTab(8) end
        local mt = hot('mainpf_manage', imgui.IsItemHovered())
        card(dl, cx + cw - mw, sy, mw, 22, 11, lerpC(P.chip, P.cardHover, mt), lerpC(P.line, P.accent, 0.4 + 0.5 * mt))
        centerText(dl, cx + cw - mw, sy, mw, 22, ico('USERS') .. ' Управление', U(lerpC(P.accentSoft, P.text, mt)))

        local slots, showN = {}, n
        if n > MAXS then showN = MAXS - 1 end
        for i = 1, showN do slots[#slots + 1] = { id = list[i] } end
        if n > MAXS then slots[#slots + 1] = { more = n - showN }
        elseif n < MAXS and n < (PFh.max or 6) then slots[#slots + 1] = { new = true } end

        local k = #slots
        local rich = (k <= 3)
        local cols = rich and math.max(k, 1) or 3
        local CH = rich and AH or math.floor((AH - 8) / 2)
        local sw = (cw - 10 * (cols - 1)) / cols
        local cy0 = sy + 28
        local font = imgui.GetFont()
        local badgeW = SM.tw(ico('CHECK') .. ' Активен') + 24
        local function fitText(text, px, scale)
            if SM.tw(text) * scale <= px then return text end
            local chars = {}
            for c in text:gmatch('[%z\1-\127\194-\244][\128-\191]*') do chars[#chars + 1] = c end
            for cnt = #chars - 1, 1, -1 do
                local c = table.concat(chars, '', 1, cnt)
                if SM.tw(c) * scale <= px then return c end
            end
            return chars[1] or ''
        end
        local animOn = smoothAnimations and not SM.low
        local gaSaved = GA
        local now = os.clock()

        for i, sl in ipairs(slots) do
            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            local x, y = cx + col * (sw + 10), cy0 + row * (CH + 8)
            local id = sl.id and ('##mainpf_' .. sl.id) or (sl.new and '##mainpf_new' or '##mainpf_more')
            imgui.SetCursorScreenPos(V(x, y))
            local clicked = imgui.InvisibleButton(id, V(sw, CH))
            local hovered = imgui.IsItemHovered()
            local t = hot(id, hovered)
            local ta = 1
            if animOn then ta = ease(clamp((now - pageStart - 0.12 - 0.07 * (i - 1)) / 0.30, 0, 1)) end
            GA = gaSaved * ta
            y = y + (1 - ta) * 14 - 2 * t

            if sl.id then
                local m = PFh.meta[sl.id]
                local isAct = (sl.id == PFh.active)
                local st = PFh.stat(sl.id)
                if clicked and not isAct then PFh.switch(sl.id) end
                local pc = PAL[m.color] or PAL[1]
                local cc = C(pc[1], pc[2], pc[3])
                card(dl, x, y, sw, CH, 12, isAct and P.active or lerpC(P.card, P.cardHover, t),
                    isAct and P.accent or lerpC(P.line, P.accent, t * 0.7))
                rrf(dl, V(x + 1, y + 14), V(x + 5, y + CH - 14), U(cc), 2)
                local ch = (m.name:match('^[%z\1-\127\194-\244][\128-\191]*') or '?'):upper()

                if rich then
                    if isAct and animOn then
                        local ph = (now * 0.8) % 1
                        dl:AddCircle(V(x + 42, y + 38), 26 + 8 * ph, U(cc, 0.55 * (1 - ph)), 40, 2)
                    end
                    dl:AddCircleFilled(V(x + 42, y + 38), 24, U(cc, 0.95), 40)
                    centerText(dl, x + 18, y + 14, 48, 48, ch, U(C(255, 255, 255)))
                    local nameAvail = sw - 78 - 12 - badgeW
                    dl:PushClipRect(V(x + 78, y), V(x + sw - 12 - badgeW, y + CH), true)
                    dl:AddTextFontPtr(font, 18, V(x + 78, y + 14), U(P.text),
                        fitText(m.name, nameAvail, 18 / imgui.GetFontSize()))
                    dl:AddText(V(x + 78, y + 40), U(P.muted),
                        (m.created and m.created > 0) and ('Создан ' .. os.date('%d.%m.%Y', m.created)) or 'Профиль')
                    dl:PopClipRect()
                    if isAct then
                        chipR(dl, x + sw - 12, y + 12, ico('CHECK') .. ' Активен', P.chip, P.accentSoft)
                    elseif t > 0.05 then
                        chipR(dl, x + sw - 12, y + 12, 'Выбрать', P.active, P.text)
                    end
                    local items = {
                        { 'Бинды', st.binds }, { 'Диалоги', st.dialogs }, { 'Оружие', st.weapons },
                        { 'Круг. меню', st.pie }, { 'Заметки', st.notes },
                    }
                    local px, py = x + 18, y + CH - 32
                    for _, it in ipairs(items) do
                        local txt = it[1] .. ': ' .. it[2]
                        if px + SM.tw(txt) + 16 > x + sw - 12 then break end
                        px = chipL(dl, px, py, txt, P.chip, it[2] > 0 and P.accentSoft or P.muted)
                    end
                else
                    if isAct and animOn then
                        local ph = (now * 0.8) % 1
                        dl:AddCircle(V(x + 26, y + CH / 2), 15 + 5 * ph, U(cc, 0.55 * (1 - ph)), 32, 1.5)
                    end
                    dl:AddCircleFilled(V(x + 26, y + CH / 2), 14, U(cc, 0.92), 32)
                    centerText(dl, x + 12, y + CH / 2 - 14, 28, 28, ch, U(C(255, 255, 255)))
                    local nameAvail = sw - 48 - (isAct and 26 or 8)
                    dl:PushClipRect(V(x + 48, y), V(x + 48 + nameAvail, y + CH), true)
                    dl:AddText(V(x + 48, y + 6), U(P.text), fitText(m.name, nameAvail, 1))
                    dl:AddText(V(x + 48, y + 25), U(P.muted), 'Бинды ' .. st.binds .. ' / Оружие ' .. st.weapons)
                    dl:PopClipRect()
                    if isAct then
                        local ck = ico('CHECK')
                        if ck ~= '' then dl:AddText(V(x + sw - 22, y + 6), U(P.accentSoft), ck) end
                    end
                end
                if showTooltips and hovered then SM.tip(isAct and 'Активный профиль' or 'Переключить профиль') end

            elseif sl.new then
                if clicked then SM.goTab(8); SM.pfNew() end
                card(dl, x, y, sw, CH, 12, lerpC(P.chip, P.cardHover, t), lerpC(P.line, P.accent, 0.3 + 0.6 * t))
                if rich then
                    dl:AddCircleFilled(V(x + 42, y + 38), 24, U(P.active, 0.55 + 0.45 * t), 40)
                    centerText(dl, x + 18, y + 14, 48, 48, ico('PLUS'), U(lerpC(P.accentSoft, P.text, t)))
                    dl:PushClipRect(V(x + 78, y), V(x + sw - 10, y + CH), true)
                    dl:AddTextFontPtr(font, 18, V(x + 78, y + 14), U(lerpC(P.muted, P.text, t)), 'Новый профиль')
                    dl:AddText(V(x + 78, y + 40), U(P.muted), 'С нуля или копия существующего')
                    dl:PopClipRect()
                else
                    centerText(dl, x, y, sw, CH, ico('PLUS') .. ' Новый профиль', U(lerpC(P.muted, P.accentSoft, t)))
                end

            else
                if clicked then SM.goTab(8) end
                card(dl, x, y, sw, CH, 12, lerpC(P.chip, P.cardHover, t), lerpC(P.line, P.accent, 0.3 + 0.6 * t))
                centerText(dl, x, y, sw, CH, 'Ещё профилей: ' .. sl.more, U(lerpC(P.muted, P.accentSoft, t)))
            end
            GA = gaSaved
        end
    end

    local qy = sy + 2 * STH + 10 + 16
    dl:AddText(V(cx, qy), U(P.muted), 'Открытие меню')
    local ry1 = qy + 24
    local hw = math.floor((cw - 12) / 2)

    card(dl, cx, ry1, hw, KH, 12, P.card)
    rrf(dl, V(cx + 1, ry1 + 16), V(cx + 5, ry1 + KH - 16), U(P.accent), 2)
    local kbw = clamp(math.floor(hw * 0.4), 92, 150)
    local kbx, kby = cx + hw - 14 - kbw, ry1 + 19
    dl:PushClipRect(V(cx + 10, ry1), V(kbx - 8, ry1 + KH), true)
    dl:AddText(V(cx + 18, ry1 + 14), U(P.text), 'Клавиша открытия')
    dl:AddText(V(cx + 18, ry1 + 36), U(P.muted), 'Нажмите, чтобы сменить')
    dl:PopClipRect()
    imgui.SetCursorScreenPos(V(kbx, kby))
    if imgui.InvisibleButton('##mainopenkey', V(kbw, 28)) then
        hotCap = (hotCap == 1) and 0 or 1
        binder.pie.cap = false
    end
    local kt = hot('mainopenkey', imgui.IsItemHovered())
    local kcap = (hotCap == 1)
    card(dl, kbx, kby, kbw, 28, 8, kcap and P.active or lerpC(P.chip, P.cardHover, kt),
        kcap and P.accent or lerpC(P.line, P.accent, kt * 0.7))
    local khk = hotkeys[1][2]
    local klabel = khk
    if kcap then
        klabel = binder.capText('Нажмите сочетание...')
        if SM.tw(klabel) + 14 > kbw then klabel = 'Нажмите...' end
    end
    dl:PushClipRect(V(kbx + 4, kby), V(kbx + kbw - 4, kby + 28), true)
    centerText(dl, kbx, kby, kbw, 28, klabel,
        U(kcap and P.text or (khk == 'Не задана' and P.muted or P.accentSoft)))
    dl:PopClipRect()

    local cx2 = cx + hw + 12
    card(dl, cx2, ry1, hw, KH, 12, P.card)
    rrf(dl, V(cx2 + 1, ry1 + 16), V(cx2 + 5, ry1 + KH - 16), U(P.accent), 2)
    local fw = kbw
    local fx, fy = cx2 + hw - 14 - fw, ry1 + 18
    local showMsg = SM.cmdMsg and (os.clock() - SM.cmdMsgT) < 3
    dl:PushClipRect(V(cx2 + 10, ry1), V(fx - 22, ry1 + KH), true)
    dl:AddText(V(cx2 + 18, ry1 + 14), U(P.text), 'Команда в чате')
    dl:AddText(V(cx2 + 18, ry1 + 36),
        showMsg and U(C(240, 110, 110)) or U(P.muted), showMsg and SM.cmdMsg or 'Нажмите, чтобы изменить')
    dl:PopClipRect()
    dl:AddText(V(fx - 14, fy + 7), U(P.accentSoft), '/')
    imgui.SetCursorScreenPos(V(fx, fy))
    pushInput()
    imgui.PushStyleColor(imgui.Col.FrameBg, P.chip)
    imgui.PushStyleColor(imgui.Col.Text, P.accentSoft)
    imgui.PushItemWidth(fw)
    imgui.InputText('##maincmd', SM.cmdBuf, ffi.sizeof(SM.cmdBuf), imgui.InputTextFlags.EnterReturnsTrue)
    imgui.PopItemWidth()
    local cmdActive = imgui.IsItemActive()
    local cmdHover = imgui.IsItemHovered()
    local rmin, rmax = imgui.GetItemRectMin(), imgui.GetItemRectMax()
    imgui.PopStyleColor(2)
    popInput()

    do
        local ct = hot('maincmd_ring', cmdActive or cmdHover)
        if cmdActive and not SM.low then
            rr(dl, V(rmin.x - 2, rmin.y - 2), V(rmax.x + 2, rmax.y + 2), U(P.accent, 0.25), 11, 15, 2)
        end
        rr(dl, V(rmin.x + 0.5, rmin.y + 0.5), V(rmax.x - 0.5, rmax.y - 0.5),
            U(P.accent, cmdActive and 1 or (0.55 + 0.35 * ct)), 9, 15, 1.3)
    end

    if SM.cmdWas and not cmdActive then
        local name = (ffi.string(SM.cmdBuf):gsub('^/', '')):match('^%s*(.-)%s*$') or ''
        local err
        if name == SM.cmd then

        elseif #name < 1 or #name > 24 or not name:match('^[%w_]+$') or name:find('[^%w_]') then
            err = 'Только латиница, цифры и _'
        elseif binder.cmdTaken(name:lower(), nil, 'open') then
            err = 'Такая команда уже занята'
        else
            SM.setCmd(name); cfgDirty = true
        end
        if err then SM.cmdMsg, SM.cmdMsgT = err, os.clock() end
        imgui.StrCopy(SM.cmdBuf, SM.cmd)
    end
    SM.cmdWas = cmdActive

    local ry2 = ry1 + KH + 10
    local toggles = {
        { 'toggle', 'Закрывать той же клавишей', 'Повторное нажатие закрывает меню',
          function() return SM.toggleKey end, function(v) SM.toggleKey = v end },
        { 'greet',  'Подсказка при запуске',     'Клавиша и команда в чате при входе',
          function() return SM.greet end,     function(v) SM.greet = v end },
    }
    for i, o in ipairs(toggles) do
        local x = cx + (i - 1) * (hw + 12)
        card(dl, x, ry2, hw, TH, 12, P.card)
        dl:AddText(V(x + 18, ry2 + 9), U(P.text), o[2])
        dl:AddText(V(x + 18, ry2 + 28), U(P.muted), o[3])
        local tx, ty = x + hw - 14 - 36, ry2 + 17
        imgui.SetCursorScreenPos(V(tx - 4, ty - 4))
        if imgui.InvisibleButton('##mt_' .. o[1], V(44, 26)) then o[5](not o[4]()); cfgDirty = true end
        switchDraw(dl, 'mt_' .. o[1] .. 'sw', tx, ty, o[4]())
    end

end

function binder.featRow(dl, id, x, y, w, h, icon, title, desc, on, locked, lockText)
    local HR = 56
    local tg = anim('feat_' .. id, on and 1 or 0, 14)
    local dim = locked and 0.5 or 1
    local saved = GA
    card(dl, x, y, w, h, 14, lerpC(P.card, P.cardHover, tg * 0.35), lerpC(P.line, P.accent, tg * 0.7), 0.9)
    if on and not locked then rrf(dl, V(x + 5, y + 14), V(x + 8, y + 42), U(P.accent), 2) end
    iconBadge(dl, x + 22, y + 8, 40, icon, (on and not locked) and P.active or P.chip)
    local bx, by = x + w - 20 - 46, y + (HR - 26) / 2
    local st = locked and (lockText or 'Недоступно') or (on and 'Включено' or 'Выключено')
    local stw = SM.tw(st)
    local font = imgui.GetFont()
    dl:PushClipRect(V(x + 74, y), V(bx - 22 - stw, y + HR), true)
    dl:AddTextFontPtr(font, 16, V(x + 74, y + 8), U(P.text, dim), title)
    dl:AddText(V(x + 74, y + 32), U(P.muted, dim), desc)
    dl:PopClipRect()
    dl:AddText(V(bx - 14 - stw, y + (HR - imgui.GetTextLineHeight()) / 2),
        U((on and not locked) and P.accentSoft or P.muted, dim), st)
    local clicked = false
    if not locked then
        imgui.SetCursorScreenPos(V(bx - 4, by - 4))
        clicked = imgui.InvisibleButton('##feat_' .. id, V(54, 34))
    end
    GA = saved * dim
    switchDraw(dl, 'feat_' .. id .. '_sw', bx, by, on and not locked, 46, 26)
    GA = saved
    return clicked
end

function binder.hkPill(dl, id, x, y, w, h, k, label)
    local hk = hotkeys[k]
    if not hk then return end
    imgui.SetCursorScreenPos(V(x, y))
    if imgui.InvisibleButton(id, V(w, h)) then
        hotCap = (hotCap == k) and 0 or k
        binder.pie.cap, binder.note.cap = false, false
        if binder.wanted then binder.wanted.keyCap = false end
        binder.ccReset()
    end
    local hov = imgui.IsItemHovered()
    local t = hot(id, hov)
    local cap = (hotCap == k)
    card(dl, x, y, w, h, 10, cap and P.active or lerpC(P.card, P.cardHover, t),
        cap and P.accent or lerpC(P.line, P.accent, t * 0.7))
    local unset = (hk[2] == 'Не задана')
    local val = cap and binder.capText('Нажмите...') or (unset and 'Нет' or hk[2])
    local cwid = math.min(SM.tw(val) + 16, w * 0.6)
    local cxp, cyp = x + w - 8 - cwid, y + (h - 22) / 2
    rrf(dl, V(cxp, cyp), V(cxp + cwid, cyp + 22), U(P.chip), 7)
    dl:PushClipRect(V(cxp + 4, cyp), V(cxp + cwid - 4, cyp + 22), true)
    dl:AddText(V(cxp + 8, cyp + 4), U(cap and P.text or (unset and P.muted or P.accentSoft)), val)
    dl:PopClipRect()
    dl:PushClipRect(V(x + 8, y), V(cxp - 4, y + h), true)
    dl:AddText(V(x + 12, y + (h - imgui.GetTextLineHeight()) / 2), U(cap and P.text or lerpC(P.muted, P.text, 0.5 + 0.5 * t)), label)
    dl:PopClipRect()
    if showTooltips and hov then
        SM.tip(hk[1] .. '\nНажмите, чтобы изменить. Delete - сбросить, Esc - отмена')
    end
end

local LIST_MODES = {
    bind   = { si = 1, title = 'Биндер',            sub = 'Свои отыгровки (порядок - перетаскиванием)',          hint = 'Поиск отыгровки' },
    weapon = { si = 2, title = 'Отыгровка оружий',  sub = 'Отыгровки при использовании оружия',  hint = 'Поиск оружия' },
    dialog = { si = 3, title = 'Диалоги',           sub = 'Диалоговые меню (порядок меняется перетаскиванием)',       hint = 'Поиск диалога' },
}

local function bindListPage(dl, pos, cx, cw, mode)
    local cfg  = LIST_MODES[mode]
    local list = (mode == 'weapon') and weapons or (mode == 'dialog') and dialogs or binds
    local si   = cfg.si
    local oy, cs = 0, nil
    if mode == 'bind' then
        oy = 44
        cs = binder.catCur()
        local items = { 'Системные' }
        for _, c in ipairs(binder.cats) do items[#items + 1] = binder.cut(c.name, 14) end
        local canAdd = #binder.cats < binder.MAX_CATS
        if canAdd then items[#items + 1] = '+' end
        local cur = 1
        if cs ~= 'sys' then local _, ci = binder.catFind(cs); cur = 1 + (ci or 1) end
        local r = segTabs(dl, '##bindsub', cx, pos.y + 64, items, cur, nil, canAdd and #items or nil)
        if r and r ~= cur then
            if r == 1 then binder.catSel = 'sys'
            elseif r <= #binder.cats + 1 then binder.catSel = binder.cats[r - 1].uid
            else
                local nc = binder.catAdd()
                if nc then binder.catSel = nc.uid end
            end
            binder.catDelAsk = nil
            scrollReset = 2; pageStart = os.clock()
            cs = binder.catCur()
        end
        if cs == 'sys' then
            heading(dl, cx, pos.y + 18, cfg.title, 'Системные отыгровки хелпера')
            binder.sysPage(dl, pos, cx, cw)
            return
        end
        list = {}
        for _, b in ipairs(binds) do if binder.catOf(b) == cs then list[#list + 1] = b end end
    end
    heading(dl, cx, pos.y + 18, cfg.title, cfg.sub)
    if mode == 'bind' then

        local cat = binder.catFind(cs)
        local many = #binder.cats > 1
        local mw, bw = 190, 96
        local mx = cx + cw - 10 - mw - (many and (bw + 8) or 0)
        binder.catBuf = binder.catBuf or new.char[64]()
        if binder.catBufUid ~= cs then imgui.StrCopy(binder.catBuf, cat.name); binder.catBufUid = cs end
        imgui.SetCursorScreenPos(V(mx, pos.y + 18))
        pushInput()
        imgui.PushItemWidth(mw)
        if imgui.InputTextWithHint('##catname', 'Название категории', binder.catBuf, ffi.sizeof(binder.catBuf)) then
            local nm = binder.trim(ffi.string(binder.catBuf))
            if nm ~= '' then cat.name = nm; binder.needSave = true end
        end
        imgui.PopItemWidth()
        popInput()
        if many then
            local asked = (binder.catDelAsk == cs)
            if button(dl, '##catdel', mx + mw + 8, pos.y + 18, bw, 30, asked and 'Точно?' or 'Удалить', asked) then
                if asked then
                    binder.catSel = binder.catDelete(cs)
                    binder.catDelAsk = nil
                    scrollReset = 2; pageStart = os.clock()
                    return
                end
                binder.catDelAsk = cs
            end
            if showTooltips and imgui.IsItemHovered() then SM.tip('Отыгровки категории перейдут в соседнюю') end
        end
    end

    imgui.SetCursorScreenPos(V(cx, pos.y + 66 + oy))
    pushInput()
    imgui.PushItemWidth(cw - (mode == 'weapon' and 10 or 128))
    imgui.InputTextWithHint('##search' .. si, cfg.hint, searchBuf[si], ffi.sizeof(searchBuf[si]))
    imgui.PopItemWidth()
    popInput()
    if mode ~= 'weapon' and button(dl, '##add' .. si, cx + cw - 116, pos.y + 66 + oy, 116, 30, '+ Добавить', true) then
        openEditor(0, mode)
    end

    local ly = pos.y + 112
    if mode == 'weapon' then

        local lbl1, lbl2 = 'Автоотыгровка оружия', 'Только по ПКМ'
        local w1, w2 = 30 + SM.tw(lbl1), 30 + SM.tw(lbl2)
        local gap = 26

        local okF, fs = pcall(imgui.GetFontSize)
        local titleW = SM.tw(cfg.title) * 20 / ((okF and fs and fs > 0) and fs or 14)
        local x1 = cx + cw - 24 - (w1 + gap + w2)
        x1 = math.max(x1, cx + 52 + titleW + 44)
        local x2 = x1 + w1 + gap
        local cy = pos.y + 16

        local bx0, bw0 = x1 - 14, (w1 + gap + w2) + 28
        local anyOn = weaponRP and 1 or 0
        card(dl, bx0, cy - 6, bw0, 36, 12, lerpC(P.card, P.cardHover, 0.4 * anyOn),
            lerpC(P.line, P.accent, 0.55 + 0.25 * anyOn), 0.95)
        rrf(dl, V(bx0 + 5, cy + 3), V(bx0 + 8, cy + 21), U(P.accent, weaponRP and 1 or 0.5), 2)
        dl:AddLine(V(x2 - gap / 2, cy), V(x2 - gap / 2, cy + 24), U(P.line, 0.9), 1)
        if checkDraw(dl, '##wrp_chk', x1, cy, weaponRP, lbl1) then
            weaponRP = not weaponRP; cfgDirty = true
        end
        if showTooltips and imgui.IsItemHovered() then SM.tip('Отыгровка при доставании и убирании оружия') end
        local saved = GA
        if not weaponRP then GA = saved * 0.5 end
        if checkDraw(dl, '##wrmb_chk', x2, cy, weaponOnRmb, lbl2) and weaponRP then
            weaponOnRmb = not weaponOnRmb; cfgDirty = true
        end
        if showTooltips and imgui.IsItemHovered() then
            SM.tip(weaponRP and 'Срабатывает, только когда зажата ПКМ с оружием в руках' or 'Нужна включённая автоотыгровка')
        end
        GA = saved
    end
    if mode == 'bind' then

        local gap = 8
        local pw = (cw - 10 - gap * 2) / 3
        local pills = {
            { 4, (ico('PAUSE') ~= '' and (ico('PAUSE') .. ' ') or '') .. 'Пауза' },
            { 3, (ico('PLAY') ~= '' and (ico('PLAY') .. ' ') or '') .. 'Продолжить' },
            { 2, (ico('STOP') ~= '' and (ico('STOP') .. ' ') or '') .. 'Стоп' },
        }
        for i, pl in ipairs(pills) do
            binder.hkPill(dl, '##hkp' .. pl[1], cx + (i - 1) * (pw + gap), pos.y + 104 + oy, pw, 32, pl[1], pl[2])
        end
        ly = pos.y + 148 + oy
    end
    local base, cdl = beginList('##blist' .. si, cx, ly, cw, pos.y + WIN_H - MARGIN - ly)
    local vwy, vwh = imgui.GetWindowPos().y, imgui.GetWindowSize().y
    local iw = cw - 10
    local query = ffi.string(searchBuf[si]):match('^%s*(.-)%s*$') or ''

    local rd = rowDrag
    local canDrag = (mode == 'bind' or mode == 'dialog') and query == '' and #list > 1 and not editor[0]
    local wasDrag = rd.on
    if rd.on and (not canDrag or not imgui.IsMouseDown(0)) then
        rd.on = false
        if canDrag and rd.tgt ~= rd.idx and list[rd.idx] then
            if mode == 'bind' then
                binder.reorder(list, rd.idx, rd.tgt)
            else
                local moved = table.remove(list, rd.idx)
                table.insert(list, rd.tgt, moved)
            end
            if mode == 'dialog' then binder.saveDialogs() else binder.save() end
        end
    end
    if rd.on then
        local my = imgui.GetMousePos().y
        rd.tgt = clamp(math.floor((my - base.y) / 52) + 1, 1, #list)

        if my < ly + 28 then imgui.SetScrollY(imgui.GetScrollY() - 10)
        elseif my > pos.y + WIN_H - MARGIN - 28 then imgui.SetScrollY(imgui.GetScrollY() + 10) end
    end
    local order = {}
    for i = 1, #list do order[i] = i end
    if rd.on then
        table.remove(order, rd.idx)
        table.insert(order, rd.tgt, rd.idx)
    end

    local shown = 0
    for p, i in ipairs(order) do
        local b = list[i]
        if query == '' or containsText(b.title, query) or containsText(b.cmd, query)
            or containsText(b.key, query) or containsText(b.preview, query) then
            local sel = editor[0] and editIdx == (mode == 'bind' and binder.bindIdx(b) or i) and editMode == mode

            local ta = 1
            if smoothAnimations and not SM.low then
                ta = ease(clamp((os.clock() - pageStart - 0.05 - 0.04 * math.min(shown, 8)) / 0.22, 0, 1))
            end
            local saved = GA
            GA = saved * ta
            local badge = (mode == 'weapon') and tostring(i) or (mode == 'dialog') and tostring(b.uid) or tostring(p)
            local slot = rd.on and (p - 1) or shown
            local ryv = base.y + slot * 52
            if not (rd.on and i == rd.idx) and (rd.on or (ryv + 54 >= vwy and ryv <= vwy + vwh + 2)) then
                local clicked, active = rollRow(cdl, '##row' .. si .. '_' .. i, base.x, base.y + slot * 52 + (1 - ta) * 8, iw, b, badge, sel)
                if clicked and not wasDrag and not rd.on then openEditor(mode == 'bind' and binder.bindIdx(b) or i, mode) end
                if canDrag and active and not rd.on and imgui.IsMouseDragging(0, 5) then
                    rd.on, rd.idx, rd.tgt = true, i, i
                    rd.grab = imgui.GetMousePos().y - (base.y + slot * 52)
                end
            end
            GA = saved
            shown = shown + 1
        end
    end
    if rd.on and list[rd.idx] then
        local gy = clamp(imgui.GetMousePos().y - rd.grab, base.y, base.y + (#list - 1) * 52)
        rollRow(cdl, '##ghost', base.x, gy, iw, list[rd.idx], (mode == 'bind') and tostring(rd.tgt) or nil, true, true)
    end
    if shown == 0 then
        local msg = (#list == 0) and 'Пока пусто. Нажмите «+ Добавить», чтобы создать первую запись.' or 'Ничего не найдено'
        cdl:AddText(V(base.x + 16, base.y + 14), U(P.muted), msg)
    end
    endList(base, math.max(shown, 1) * 52)
end

function binder.sysOpen(e)
    local S = binder.sysEd
    S.e, S.on, S.justOpened = e, e.on, true
    imgui.StrCopy(ed.content, binder.sysText(e))
    ed.curS, ed.curE, ed.setCursor, ed.refocus = nil, nil, nil, nil
    editMode, editIdx = 'sys', 0
    ed.capture = false
    edOpenAt = os.clock()
    editor[0] = true
end

function binder.sysCommit()
    local S = binder.sysEd
    local e = S.e
    if not e then editor[0] = false; return end
    binder.sysSetText(e, ffi.string(ed.content))
    e.on, e._was = S.on, S.on
    if e.kind == 'bind' then binder.needSync = true end
    binder.save()
    editor[0] = false
end

local function sysIcon(e)
    local name, fb = 'DESKTOP', 'K'
    if e.kind == 'afind' then name, fb = 'MAGNIFYING_GLASS', 'F'
    elseif e.kind == 'wanted' then name, fb = 'TABLE_LIST', 'W'
    elseif e.kind == 'pursuit' then name, fb = 'PERSON_RUNNING', 'P'
    elseif e.kind == 'bind' then name, fb = 'USER_LOCK', 'B' end
    local g = ico(name)
    return g ~= '' and g or fb
end

function binder.sysPage(dl, pos, cx, cw)
    dl:AddText(V(cx + 4, pos.y + 70 + 44), U(P.muted), 'Фиксированный список: можно менять текст и отключать. Клик по строке - редактирование.')

    local ly = pos.y + 98 + 44
    local base, cdl = beginList('##syslist', cx, ly, cw, pos.y + WIN_H - MARGIN - ly)
    local vwy, vwh = imgui.GetWindowPos().y, imgui.GetWindowSize().y
    local iw = cw - 10
    local y, shown, lastGroup = base.y, 0, nil
    local S = binder.sysEd

    for i, e in ipairs(binder.sys) do
        if e.group ~= lastGroup then
            lastGroup = e.group
            if y + 22 >= vwy and y <= vwy + vwh then cdl:AddText(V(base.x + 4, y + 4), U(P.muted), e.group) end
            y = y + 26
        end

        local ta = 1
        if smoothAnimations and not SM.low then
            ta = ease(clamp((os.clock() - pageStart - 0.05 - 0.04 * math.min(shown, 8)) / 0.22, 0, 1))
        end
        local saved = GA
        GA = saved * ta
        if y + 54 >= vwy and y <= vwy + vwh + 2 then
            if e.kind == 'kpk' then e.cmd = kpkSecs[e.si].cmd or ''
            elseif e.kind == 'afind' then e.cmd = (binder.afind and binder.afind.cmd) or ''
            elseif e.kind == 'wanted' then e.cmd = kpkSecs[1].cmd or 'asu'
            elseif e.kind == 'bind' then e.cmd = e.bcmd
            else e.cmd = 'pursuit' end
            local t = binder.sysText(e)
            if e._pt ~= t then
                e._pt = t
                e._pv = (binder.trim(t) == '')
                    and (e.kind == 'kpk' and 'Текст не задан - отправляется только команда' or 'Текст не задан - отыгровка не проигрывается')
                    or binder.preview(t)
            end
            e.preview = e._pv
            if e._was == nil then e._was = e.on end
            local sel = editor[0] and editMode == 'sys' and S.e == e
            local clicked = rollRow(cdl, '##sysrow' .. i, base.x, y + (1 - ta) * 8, iw, e, sysIcon(e), sel)
            if e.on ~= e._was then
                e._was = e.on; binder.save()
                if e.kind == 'bind' then binder.needSync = true end
            end
            if clicked then binder.sysOpen(e) end
        end
        GA = saved
        y = y + 52
        shown = shown + 1
    end
    endList(base, math.max(y - base.y, 1))
end

pages[2] = function(dl, pos, cx, cw) bindListPage(dl, pos, cx, cw, 'bind') end
pages[4] = function(dl, pos, cx, cw) bindListPage(dl, pos, cx, cw, 'weapon') end
pages[5] = function(dl, pos, cx, cw) bindListPage(dl, pos, cx, cw, 'dialog') end

local ked = {
    kind = 'chapter', ch = 0, ii = 0,
    title = new.char[512](), text = new.char[1536](), reason = new.char[128](), sum = new.char[16](),
    val = 1, minutes = new.int(15), carcOn = true, err = nil, delAsk = nil, justOpened = false,
}

function binder.groupDigits(str)
    local d = tostring(str):gsub('%D', ''):sub(1, 7)
    if (tonumber(d) or 0) > 3000000 then d = '3000000' end
    return (d:reverse():gsub('(%d%d%d)', '%1 '):reverse():gsub('^%s+', ''))
end
ked.sumCb = nil
do
    local ok, cb = pcall(function()
        return ffi.cast('int (*)(ImGuiInputTextCallbackData*)', function(data)
            pcall(function()
                local cur = ffi.string(data.Buf, data.BufTextLen)
                local f = binder.groupDigits(cur)
                if f ~= cur then

                    local before = select(2, cur:sub(1, data.CursorPos):gsub('%d', ''))
                    local pos, seen = #f, 0
                    if before == 0 then pos = 0 else
                        for i = 1, #f do
                            if f:sub(i, i):match('%d') then seen = seen + 1 end
                            if seen >= before then pos = i; break end
                        end
                    end
                    data:DeleteChars(0, data.BufTextLen)
                    data:InsertChars(0, f)
                    data.CursorPos, data.SelectionStart, data.SelectionEnd = pos, pos, pos
                end
            end)
            return 0
        end)
    end)
    if ok then ked.sumCb = cb end
end

local function openKpkEditor(kind, ch, ii)
    local sec = kpkSecs[kpkSec]
    ked.kind, ked.ch, ked.ii, ked.err, ked.delAsk = kind, ch, ii, nil, nil
    local chapter = sec.chapters[ch]
    if kind == 'chapter' then
        imgui.StrCopy(ked.title, chapter and chapter.title or '')
    else
        local it = chapter and chapter.items[ii]
        imgui.StrCopy(ked.text, it and it.text or '')
        imgui.StrCopy(ked.reason, it and it.reason or '')
        imgui.StrCopy(ked.sum, (it and sec.mode == 'money') and binder.groupDigits(tostring(math.floor(it.value))) or '')
        ked.minutes[0] = (it and sec.mode == 'minutes') and it.value or 15
        ked.val = (it and sec.mode == 'pips') and it.value or 1
    end
    editMode, editIdx = 'kpk', 0
    ed.capture = false
    edOpenAt = os.clock()
    editor[0] = true
    ked.justOpened = true
end

local function fmtMoney(n)
    local r = (tostring(math.floor(n)):reverse():gsub('(%d%d%d)', '%1 ')):reverse()
    return (r:gsub('^%s+', ''))
end

local function kpkPipColor(sec, n)
    if sec.max == 6 then return LV[n] or P.accent end
    return lerpC(LV[1], LV[6], (clamp(n, 1, 10) - 1) / 9)
end

local function kpkLayout(sec, x, w)
    local lay = {}
    lay.act = x + w - 30
    local right = lay.act - 6
    if sec.reason then
        lay.reason = right - 120
        right = lay.reason - 6
    end
    local valW = (sec.mode == 'pips') and (sec.max == 10 and (sec.kind == 'punish' and 156 or 134) or 100) or (sec.mode == 'money' and 118 or 72)
    lay.val = right - valW
    lay.descLimit = lay.val - 8
    return lay
end

local function miniAct(dl, id, x, y, glyph, fallback)
    imgui.SetCursorScreenPos(V(x, y))
    local clicked = imgui.InvisibleButton(id, V(24, 24))
    local t = hot(id, imgui.IsItemHovered())
    local g = ico(glyph); if g == '' then g = fallback end
    centerText(dl, x, y, 24, 24, g, U(lerpC(P.muted, P.accentSoft, t)))
    return clicked
end

local ellCache, ellN = {}, 0
local function ellipsize(text, maxW)
    if SM.tw(text) <= maxW then return text end
    local wi = math.floor(maxW + 0.5)
    local bucket = ellCache[wi]
    if not bucket then bucket = {}; ellCache[wi] = bucket end
    local hit = bucket[text]
    if hit then return hit end
    local chars = {}
    for ch in text:gmatch('[%z\1-\127\194-\244][\128-\191]*') do chars[#chars + 1] = ch end
    local lo, hi = 1, #chars
    while lo < hi do
        local mid = math.ceil((lo + hi) / 2)
        if imgui.CalcTextSize(table.concat(chars, '', 1, mid) .. '...').x > wi then hi = mid - 1 else lo = mid end
    end
    local res = table.concat(chars, '', 1, lo) .. '...'
    if ellN > 3000 then ellCache, ellN = {}, 0; bucket = {}; ellCache[wi] = bucket end
    ellN = ellN + 1
    bucket[text] = res
    return res
end

function binder.kpkDragFrame(kd, sec, R, base, cdl, iw, ly, pos)
    local my = imgui.GetMousePos().y

    if my < ly + 28 then imgui.SetScrollY(imgui.GetScrollY() - 10)
    elseif my > pos.y + WIN_H - MARGIN - 28 then imgui.SetScrollY(imgui.GetScrollY() + 10) end

    local n = #sec.chapters
    local lineY, hiC
    if kd.kind == 'chapter' then
        kd.tgtC = n + 1
        for c = 1, n do
            local r = R.ch[c]
            if r and my < (r.y0 + r.y1) / 2 then kd.tgtC = c; break end
        end
        local r = R.ch[kd.tgtC]
        lineY = r and (r.y0 - 4) or ((R.ch[n] and R.ch[n].y2 or base.y) + 4)
    else
        local found = false
        for c = 1, n do
            local r = R.ch[c]
            if r then
                if my >= r.y0 and my < r.y1 then kd.tgtC, kd.tgtI, hiC, found = c, 1, c, true; break end
                local rows = R.it[c] or {}
                if (r.b1 or r.y1) > r.y1 + 1 then
                    local items = #sec.chapters[c].items
                    for k = 1, items do
                        local rw = rows[k]
                        if rw and my < (rw.y0 + rw.y1) / 2 then
                            kd.tgtC, kd.tgtI, lineY, found = c, k, rw.y0 - 3, true; break
                        end
                    end
                    if found then break end
                    if my < r.b1 + 4 then
                        kd.tgtC, kd.tgtI, found = c, items + 1, true
                        lineY = (items > 0 and rows[items]) and (rows[items].y1 + 3) or (r.y1 + 3)
                        break
                    end
                end
            end
        end
        if not found then
            kd.tgtC = n
            kd.tgtI = #sec.chapters[n].items + 1
            local rows, r = R.it[n] or {}, R.ch[n]
            if r and (r.b1 or r.y1) > r.y1 + 1 and rows[kd.tgtI - 1] then lineY = rows[kd.tgtI - 1].y1 + 3
            else hiC = n end
        end
    end

    local saved = GA
    GA = 1
    if lineY then rrf(cdl, V(base.x, lineY - 1), V(base.x + iw, lineY + 1), U(P.accent), 1) end
    if hiC and R.ch[hiC] then
        local r = R.ch[hiC]
        rr(cdl, V(base.x + 0.5, r.y0 + 0.5), V(base.x + iw - 0.5, r.y1 - 0.5), U(P.accent, 0.9), 10, 15, 1.6)
    end

    local gy = my - kd.grab
    if kd.kind == 'chapter' then
        local ch = sec.chapters[kd.ci]
        if ch then
            rrf(cdl, V(base.x - 2, gy + 2), V(base.x + iw + 2, gy + 40), U(C(0, 0, 0, 90)), 12)
            card(cdl, base.x, gy, iw, 38, 10, P.active, P.accent)
            cdl:AddTextFontPtr(imgui.GetFont(), 15, V(base.x + 38, gy + 10), U(P.text), ellipsize(ch.title, iw - 160))
            chipR(cdl, base.x + iw - 70, gy + 8, 'Пунктов: ' .. #ch.items, P.chip, P.muted)
        end
    else
        local chp = sec.chapters[kd.ci]
        local it = chp and chp.items[kd.ii]
        if it then
            local gx, gw = base.x + 16, iw - 16
            rrf(cdl, V(gx - 2, gy + 2), V(gx + gw + 2, gy + 42), U(C(0, 0, 0, 90)), 12)
            card(cdl, gx, gy, gw, 40, 9, P.active, P.accent)
            cdl:AddText(V(gx + 18, gy + 12), U(P.text), ellipsize(it.text, gw - 34))
        end
    end
    GA = saved

    if not imgui.IsMouseDown(0) then
        kd.on = false
        local moved = false
        if kd.kind == 'chapter' then
            local src, dst = kd.ci, kd.tgtC
            if dst ~= src and dst ~= src + 1 then
                local oldOpen, oldP = {}, {}
                for i = 1, n do
                    local k = kpkSec .. ':1:' .. i
                    oldOpen[i], oldP[i] = kpkOpen[k], hv['p' .. k]
                end
                local perm = {}
                for i = 1, n do perm[i] = i end
                local ch = table.remove(sec.chapters, src)
                table.remove(perm, src)
                if dst > src then dst = dst - 1 end
                table.insert(sec.chapters, dst, ch)
                table.insert(perm, dst, src)
                for i = 1, n do
                    local k = kpkSec .. ':1:' .. i
                    kpkOpen[k], hv['p' .. k] = oldOpen[perm[i]], oldP[perm[i]]
                end
                moved = true
            end
        else
            local sc, dc = kd.ci, kd.tgtC
            local srcList, dstCh = sec.chapters[sc] and sec.chapters[sc].items, sec.chapters[dc]
            if srcList and dstCh and srcList[kd.ii] then
                local si, di = kd.ii, kd.tgtI
                if not (sc == dc and (di == si or di == si + 1)) then
                    local it = table.remove(srcList, si)
                    if sc == dc and di > si then di = di - 1 end
                    table.insert(dstCh.items, clamp(di, 1, #dstCh.items + 1), it)
                    kpkOpen[kpkSec .. ':1:' .. dc] = true
                    moved = true
                end
            end
        end
        if moved then binder.saveKpk() end
    end
end

pages[7] = function(dl, pos, cx, cw)
    heading(dl, cx, pos.y + 18, 'КПК', 'Розыск, штрафы, сроки и карцер' .. (binder.pf.kpkSub and binder.pf.kpkSub() or ''))
    local secNames = {}
    for i = 1, KPK_TABS do secNames[i] = kpkSecs[i].tabName or kpkSecs[i].name end
    local r = segTabs(dl, '##ksec', cx, pos.y + 64, secNames, kpkSec, 2)
    if r and r ~= kpkSec then kpkSec = r; scrollReset = 2 end
    local sec = kpkSecs[kpkSec]

    if button(dl, '##kaddch', cx + cw - 116, pos.y + 64, 116, 32, '+ Глава', true) then
        openKpkEditor('chapter', 0, 0)
    end
    if binder.isArizona() then
        local rm = binder.remote
        local g = ico('CLOUD_ARROW_DOWN'); if g == '' then g = 'v' end
        if button(dl, '##kcloud', cx + cw - 116 - 8 - 36, pos.y + 64, 36, 32, g, false) then
            rm.runSections({ kpkSec })
        end
        if showTooltips and imgui.IsItemHovered() then
            SM.tip(rm.busy and 'Загрузка...' or ('Загрузить / обновить статьи: ' .. kpkSecs[kpkSec].name))
        end
    end

    do
        local cmdSecs = { kpkSec }
        local fw = (#cmdSecs == 2) and 84 or 108
        local ix = cx + cw - 116 - 10 - (binder.isArizona() and 44 or 0) - fw
        for n = #cmdSecs, 1, -1 do
            local si = cmdSecs[n]
            local csec = kpkSecs[si]
            dl:AddText(V(ix - 11, pos.y + 64 + 8), U(P.accentSoft), '/')
            pushInput()
            imgui.PushStyleColor(imgui.Col.FrameBg, P.chip)
            imgui.PushStyleColor(imgui.Col.FrameBgHovered, P.item)
            imgui.PushStyleColor(imgui.Col.FrameBgActive, P.active)
            local buf = binder.kpkBuf(si)
            imgui.SetCursorScreenPos(V(ix, pos.y + 65))
            imgui.PushItemWidth(fw)
            imgui.InputTextWithHint('##kcmd' .. si, csec.defCmd, buf, ffi.sizeof(buf), imgui.InputTextFlags.CharsNoBlank)
            imgui.PopItemWidth()
            if imgui.IsItemActive() then
                local mn, mx = imgui.GetItemRectMin(), imgui.GetItemRectMax()
                rr(dl, V(mn.x + 0.5, mn.y + 0.5), V(mx.x - 0.5, mx.y - 0.5), U(P.accent, 0.9), 9, 15, 1.2)
            else
                local txt = ffi.string(buf)
                if txt ~= csec.cmd then binder.kpkSetCmd(si, txt) end
            end
            imgui.PopStyleColor(3)
            popInput()
            if showTooltips and imgui.IsItemHovered() then SM.tip('Команда: ' .. binder.kpkUsage(csec)) end
            ix = ix - fw - 24
        end
    end

    local iw = cw - 10
    local lay = kpkLayout(sec, cx + 16, iw - 16)
    dl:AddText(V(cx + 16 + 18, pos.y + 108), U(P.muted), 'Описание')
    dl:AddText(V(lay.val,      pos.y + 108), U(P.muted), sec.head)
    if sec.reason then dl:AddText(V(lay.reason, pos.y + 108), U(P.muted), 'Причина') end

    if #sec.chapters == 0 then
        dl:AddText(V(cx + 4, pos.y + 140), U(P.muted), 'Пока пусто. Нажмите «+ Глава», чтобы создать первую главу.')
        return
    end

    local ly = pos.y + 130
    local base, cdl = beginList('##kpklist', cx, ly, cw, pos.y + WIN_H - MARGIN - ly)
    local font = imgui.GetFont()
    local vwy, vwh = imgui.GetWindowPos().y, imgui.GetWindowSize().y
    local y = base.y
    local kd = binder.kdrag
    if kd.on and (editor[0] or not imgui.IsMouseDown(0) and not sec.chapters[kd.ci]) then kd.on = false end
    local R = { ch = {}, it = {} }
    local descW = lay.descLimit - (base.x + 16 + 18)

    for ci, ch in ipairs(sec.chapters) do
        local key = kpkSec .. ':1:' .. ci
        local hid = '##ch' .. key
        local gaChap = GA
        if kd.on and kd.kind == 'chapter' and kd.ci == ci then GA = GA * 0.35 end
        R.ch[ci] = { y0 = y }

        local cntText = 'Пунктов: ' .. #ch.items
        local cntW = SM.tw(cntText) + 16
        local editX = base.x + iw - 64
        local titleW = (editX - cntW - 14) - (base.x + 38)
        local tLines = binder.wrap(ch.title, titleW * 14 / 15)
        local tExtra = (#tLines > 1) and (#tLines - 1) * 17 or 0
        local he = hv[hid .. 'x'] or 0
        local hdrH = 38 + tExtra * he

        imgui.SetCursorScreenPos(V(base.x, y))
        if imgui.InvisibleButton(hid, V(iw - 70, hdrH)) and not kd.on then kpkOpen[key] = not kpkOpen[key] end
        if imgui.IsItemActive() and not kd.on and not editor[0] and imgui.IsMouseDragging(0, 5) then
            kd.on, kd.kind, kd.ci, kd.ii, kd.tgtC, kd.tgtI = true, 'chapter', ci, 0, ci, 0
            kd.grab = imgui.GetMousePos().y - y
        end
        local hov = imgui.IsItemHovered()
        local ht = hot(hid, hov)
        he = anim(hid .. 'x', (hov and tExtra > 0 and not kd.on) and 1 or 0, 14)
        hdrH = 38 + tExtra * he
        local p  = anim('p' .. key, kpkOpen[key] and 1 or 0, 12)

        card(cdl, base.x, y, iw, hdrH, 10, lerpC(P.card, P.cardHover, ht),
            lerpC(P.line, P.accent, math.max(ht * 0.7, p * 0.6)))
        chevron(cdl, base.x + 20, y + 19, p, U(lerpC(P.muted, P.accentSoft, p)))

        cdl:PushClipRect(V(base.x + 38, y), V(base.x + 38 + titleW, y + hdrH - 2), true)
        if tExtra > 0 then

            cdl:AddTextFontPtr(font, 15, V(base.x + 38, y + 10), U(P.text, 1 - he), ellipsize(ch.title, titleW * 14 / 15))
            for li, ln in ipairs(tLines) do
                local a = (li == 1) and he or clamp((tExtra * he - (li - 2) * 17) / 17, 0, 1)
                if a > 0.01 then
                    cdl:AddTextFontPtr(font, 15, V(base.x + 38, y + 10 + (li - 1) * 17), U(P.text, a), ln)
                end
            end
        else
            cdl:AddTextFontPtr(font, 15, V(base.x + 38, y + 10), U(P.text), ch.title)
        end
        cdl:PopClipRect()
        chipR(cdl, editX - 6, y + 8, cntText, P.chip, P.muted)
        if miniAct(cdl, '##chadd' .. key, base.x + iw - 36, y + 7, 'PLUS', '+') then openKpkEditor('item', ci, 0) end
        if miniAct(cdl, '##chedit' .. key, editX, y + 7, 'PEN', 'E') then openKpkEditor('chapter', ci, 0) end
        y = y + hdrH
        R.ch[ci].y1 = y

        local rowsH, lineSets, bodyH = {}, {}, 0
        for k, it in ipairs(p > 0 and ch.items or {}) do
            local rid = '##it' .. key .. '_' .. k
            local lines = binder.wrap(it.text, descW)
            local extra = (#lines > 1) and (#lines - 1) * 15 or 0
            lineSets[k] = lines
            rowsH[k] = 40 + extra * (hv[rid .. 'x'] or 0)
            bodyH = bodyH + rowsH[k] + 4
        end
        if #ch.items == 0 then bodyH = 36 end

        if p > 0 then
            local vis = (bodyH + 4) * p
            imgui.PushClipRect(V(base.x, y), V(base.x + iw, y + vis), true)
            local saved = GA
            GA = saved * p
            if #ch.items == 0 then
                cdl:AddText(V(base.x + 20, y + 14 - (1 - p) * 8), U(P.muted), 'Пунктов нет. Нажмите + в заголовке главы.')
            end
            local off = 0
            for k, it in ipairs(ch.items) do
                local lines = lineSets[k]
                local multi = #lines > 1
                local extra = multi and (#lines - 1) * 15 or 0
                local ry  = y + 4 + off - (1 - p) * 8
                local ix  = base.x + 16
                local iw2 = iw - 16
                local rid = '##it' .. key .. '_' .. k

                local rowHot, e = 0, hv[rid .. 'x'] or 0
                if ry + rowsH[k] < vwy - 4 or ry > vwy + vwh + 4 then
                    R.it[ci] = R.it[ci] or {}
                    R.it[ci][k] = { y0 = ry, y1 = ry + rowsH[k] }
                    off = off + rowsH[k] + 4
                    goto nextItem
                end
                if p > 0.9 then
                    imgui.SetCursorScreenPos(V(ix, ry))
                    if imgui.InvisibleButton(rid, V(iw2, rowsH[k])) and not kd.on then openKpkEditor('item', ci, k) end
                    if imgui.IsItemActive() and not kd.on and not editor[0] and imgui.IsMouseDragging(0, 5) then
                        kd.on, kd.kind, kd.ci, kd.ii, kd.tgtC, kd.tgtI = true, 'item', ci, k, ci, k
                        kd.grab = imgui.GetMousePos().y - ry
                    end
                    local rh = imgui.IsItemHovered()
                    rowHot = hot(rid, rh)
                    e = anim(rid .. 'x', (rh and multi and not kd.on) and 1 or 0, 14)
                end
                local rowH = 40 + extra * e
                off = off + rowH + 4
                R.it[ci] = R.it[ci] or {}
                R.it[ci][k] = { y0 = ry, y1 = ry + rowH }
                local gaRow = GA
                if kd.on and kd.kind == 'item' and kd.ci == ci and kd.ii == k then GA = GA * 0.35 end

                card(cdl, ix, ry, iw2, rowH, 9, lerpC(P.item, P.cardHover, rowHot),
                    lerpC(P.line, P.accent, rowHot * 0.6), 0.8)
                local stripe = (sec.mode == 'pips' and it.value > 0) and kpkPipColor(sec, it.value) or P.accent
                rrf(cdl, V(ix + 3, ry + 10), V(ix + 5.5, ry + rowH - 10), U(stripe), 2)
                cdl:PushClipRect(V(ix + 18, ry), V(lay.descLimit, ry + rowH - 2), true)
                if multi then

                    cdl:AddText(V(ix + 18, ry + 12), U(P.text, 1 - e), ellipsize(it.text, descW))
                    for li, ln in ipairs(lines) do
                        local a = (li == 1) and e or clamp((extra * e - (li - 2) * 15) / 15, 0, 1)
                        if a > 0.01 then cdl:AddText(V(ix + 18, ry + 12 + (li - 1) * 15), U(P.text, a), ln) end
                    end
                else
                    cdl:AddText(V(ix + 18, ry + 12), U(P.text), it.text)
                end
                cdl:PopClipRect()

                if sec.mode == 'pips' and it.value <= 0 then
                    cdl:AddText(V(lay.val, ry + 12), U(P.muted, 0.7), 'Нет')
                elseif sec.mode == 'pips' then
                    local lc = kpkPipColor(sec, it.value)
                    local pw, step = (sec.max == 6) and 10 or 9, (sec.max == 6) and 14 or 12
                    for n = 1, sec.max do
                        local px = lay.val + (n - 1) * step
                        rrf(cdl, V(px, ry + 13), V(px + pw, ry + 27),
                            U(n <= it.value and lc or P.off, n <= it.value and 1 or 0.55), 3)
                    end
                    cdl:AddText(V(lay.val + sec.max * step + 6, ry + 12), U(P.text), tostring(it.value))
                elseif sec.mode == 'money' then
                    chipL(cdl, lay.val, ry + 9, fmtMoney(it.value) .. ' $', P.chip, P.text)
                else
                    chipL(cdl, lay.val, ry + 9, it.value .. ' мин', P.chip, P.text)
                end

                if sec.reason and it.reason ~= '' then
                    cdl:PushClipRect(V(lay.reason, ry), V(lay.reason + 120, ry + 40), true)
                    chipL(cdl, lay.reason, ry + 9, ellipsize(it.reason, 104), P.chip, P.accentSoft)
                    cdl:PopClipRect()
                end

                local g = ico('PEN'); if g == '' then g = 'E' end
                centerText(cdl, lay.act, ry + 8, 24, 24, g, U(lerpC(P.off, P.text, rowHot)))
                GA = gaRow
                ::nextItem::
            end
            GA = saved
            imgui.PopClipRect()
        end
        R.ch[ci].b1 = y + (bodyH + 4) * p
        y = y + (bodyH + 4) * p + 8
        R.ch[ci].y2 = y - 8
        GA = gaChap
    end

    if kd.on then binder.kpkDragFrame(kd, sec, R, base, cdl, iw, ly, pos) end
    endList(base, (y - base.y) + 4)
end

function binder.pieOpenEditor(list, idx, kind, parent)
    local it = list[idx]
    binder.pie.ed = {
        list = list, idx = idx, kind = kind, parent = parent,
        on = (it == nil) or (it.on ~= false), err = nil, delAsk = nil,
    }
    local defName = (kind == 'cat') and 'Новая категория' or 'Новая отыгровка'
    imgui.StrCopy(ed.name, it and it.title or defName)
    imgui.StrCopy(ed.content, (it and it.text) or '')
    ed.curS, ed.curE, ed.setCursor, ed.refocus = nil, nil, nil, nil
    ed.capture, ed.err = false, nil
    btnDrag.on = false
    editMode, editIdx = 'pie', idx
    edOpenAt   = os.clock()
    editor[0]  = true
    justOpened = true
end

function binder.pieCommit()
    local p = binder.pie
    local e = p.ed
    local name = binder.trim(ffi.string(ed.name))
    if name == '' then return false, 'Введите название пункта' end
    local text = ffi.string(ed.content)
    if e.kind == 'item' and binder.trim(text) == '' then return false, 'Введите текст отыгровки' end
    local it = e.list[e.idx]
    if not it then
        local lim = e.parent and p.MAX_KIDS or p.MAX
        if #e.list >= lim then return false, 'Достигнут лимит: ' .. lim .. ((e.parent and ' отыгровок в разделе') or ' разделов') end
        it = (e.kind == 'cat') and { children = {} } or {}
        e.list[#e.list + 1] = it
    end
    it.title, it.on = name, e.on
    if e.kind == 'item' then
        it.text = text
        it.preview = binder.preview(text)
    end
    binder.pieSave()
    editor[0] = false
    return true
end

pages[3] = function(dl, pos, cx, cw)
    local p = binder.pie
    heading(dl, cx, pos.y + 18, 'Круговое меню', 'Быстрые отыгровки поверх экрана')
    do

        local lbl = 'Включено'
        local w1 = 30 + SM.tw(lbl)
        local okF, fs = pcall(imgui.GetFontSize)
        local titleW = SM.tw('Круговое меню') * 20 / ((okF and fs and fs > 0) and fs or 14)
        local x1 = cx + cw - 24 - w1
        x1 = math.max(x1, cx + 52 + titleW + 44)
        local cy = pos.y + 16
        local on = p.enabled
        card(dl, x1 - 14, cy - 6, w1 + 28, 36, 12, lerpC(P.card, P.cardHover, on and 0.4 or 0),
            lerpC(P.line, P.accent, on and 0.8 or 0.55), 0.95)
        rrf(dl, V(x1 - 9, cy + 3), V(x1 - 6, cy + 21), U(P.accent, on and 1 or 0.5), 2)
        if checkDraw(dl, '##pie_chk', x1, cy, on, lbl) then
            p.enabled = not p.enabled; binder.pieSave()
        end
    end
    local ly = pos.y + 70
    local base, cdl = beginList('##radiallist', cx, ly, cw, pos.y + WIN_H - MARGIN - ly)
    local iw, x, ty = cw - 10, base.x, base.y
    local font = imgui.GetFont()
    local vwy, vwh = imgui.GetWindowPos().y, imgui.GetWindowSize().y

    local hy = ty + 2
    local pk = hotkeys[6][2]
    local how = (p.mode == 1) and ('ПКМ + ' .. ((pk ~= 'Не задана') and pk or '(клавиша не задана)')) or 'СКМ'
    cdl:AddText(V(x + 4, hy), U(P.muted), 'Зажмите ' .. how .. ', наведите на пункт и отпустите. У категории вложенные пункты')
    cdl:AddText(V(x + 4, hy + 18), U(P.muted), 'раскрываются кольцом. Теги - как в биндере. Способ вызова: Настройки - Функционал.')

    local hdrY = hy + 46
    cdl:AddTextFontPtr(font, 16, V(x + 4, hdrY + 6), U(P.text), 'Пункты меню')
    chipL(cdl, x + 124, hdrY + 4, #p.items .. ' / ' .. p.MAX, P.chip, P.accentSoft)
    if button(cdl, '##pie_add_item', x + iw - 268, hdrY, 130, 30, '+ Отыгровка', true) then
        if #p.items >= p.MAX then
            binder.say('Достигнут лимит в {aaaaaa}' .. p.MAX .. '{ffffff} разделов, добавление невозможно.')
        else
            binder.pieOpenEditor(p.items, 0, 'item')
        end
    end
    if button(cdl, '##pie_add_cat', x + iw - 130, hdrY, 130, 30, '+ Категория', false) then
        if #p.items >= p.MAX then
            binder.say('Достигнут лимит в {aaaaaa}' .. p.MAX .. '{ffffff} разделов, добавление невозможно.')
        else
            binder.pieOpenEditor(p.items, 0, 'cat')
        end
    end

    local rows = {}
    for i, it in ipairs(p.items) do
        rows[#rows + 1] = { it = it, list = p.items, idx = i, depth = 0 }
        if it.children then
            for j, c in ipairs(it.children) do
                rows[#rows + 1] = { it = c, list = it.children, idx = j, depth = 1, parent = it }
            end
        end
    end

    local y = hdrY + 42
    local act
    for n, row in ipairs(rows) do
        local it, d = row.it, row.depth
        local rx, rw = x + d * 26, iw - d * 26
        local isCat = it.children ~= nil
        local id = '##pr' .. n
        local ctrlW = isCat and 132 or 106
        if y + 50 < vwy or y > vwy + vwh then y = y + 50; goto nextRow end

        imgui.SetCursorScreenPos(V(rx, y))
        local clicked = imgui.InvisibleButton(id, V(rw - ctrlW, 44))
        local t = hot(id, imgui.IsItemHovered())
        card(cdl, rx, y, rw, 44, 10, lerpC(P.card, P.cardHover, t), lerpC(P.line, P.accent, t * 0.7))
        local a = it.on and 1 or 0.5
        if it.on then rrf(cdl, V(rx + 4, y + 11), V(rx + 7, y + 33), U(P.accent), 2) end
        local g = ico(isCat and 'BARS' or 'COMMENTS')
        if g == '' then g = isCat and '=' or '*' end
        card(cdl, rx + 16, y + 7, 30, 30, 8, P.chip, P.line, a)
        centerText(cdl, rx + 16, y + 7, 30, 30, g, U(P.accentSoft, a))

        local tx = rx + 58
        cdl:PushClipRect(V(tx, y), V(rx + rw - ctrlW - 6, y + 44), true)
        cdl:AddText(V(tx, y + 7), U(P.text, a), it.title)
        local sub
        if isCat then
            local cnt = #it.children
            sub = 'Категория: ' .. cnt .. ((cnt == 1) and ' пункт' or (cnt >= 2 and cnt <= 4) and ' пункта' or ' пунктов')
        else
            sub = it.preview or ''
        end
        cdl:AddText(V(tx, y + 25), U(P.muted, a), sub)
        cdl:PopClipRect()

        local sx = rx + rw - 48
        imgui.SetCursorScreenPos(V(sx, y + 13))
        if imgui.InvisibleButton(id .. 'tg', V(36, 18)) then act = { 'toggle', row } end
        switchDraw(cdl, id .. 'sw', sx, y + 13, it.on)
        local bx = sx - 28
        if miniAct(cdl, id .. 'del', bx, y + 10, 'TRASH', 'x') then act = { 'del', row } end
        bx = bx - 26
        if miniAct(cdl, id .. 'ed', bx, y + 10, 'PEN_TO_SQUARE', 'E') then act = { 'edit', row } end
        if isCat then
            bx = bx - 26
            if miniAct(cdl, id .. 'add', bx, y + 10, 'PLUS', '+') then act = { 'add', row } end
        end
        if clicked then act = { 'edit', row } end
        y = y + 50
        ::nextRow::
    end

    if #rows == 0 then
        local s = 'Здесь ничего нет. Добавьте отыгровку или категорию.'
        cdl:AddText(V(x + (iw - imgui.CalcTextSize(s).x) / 2, y + 16), U(P.muted), s)
        y = y + 50
    end

    if act then
        local row = act[2]
        if act[1] == 'toggle' then
            row.it.on = not row.it.on
            binder.pieSave()
        elseif act[1] == 'del' then
            table.remove(row.list, row.idx)
            binder.pieSave()
        elseif act[1] == 'edit' then
            binder.pieOpenEditor(row.list, row.idx, row.it.children and 'cat' or 'item', row.parent)
        elseif act[1] == 'add' then
            if #row.it.children >= p.MAX_KIDS then
                binder.say('Достигнут лимит в {aaaaaa}' .. p.MAX_KIDS .. '{ffffff} отыгровок внутри раздела.')
            else
                binder.pieOpenEditor(row.it.children, 0, 'item', row.it)
            end
        end
    end

    endList(base, (y - base.y) + 8)
end

pages[6] = function(dl, pos, cx, cw)
    heading(dl, cx, pos.y + 18, 'Заметки', 'Окно с вашим текстом открывается командой или клавишей')
    local N, notes = binder.note, binder.notes
    binder.noteTick()
    local ly = pos.y + 70
    local bottom = pos.y + WIN_H - MARGIN
    local lw = 206
    local rx, rw = cx + lw + 12, cw - lw - 12
    if N.sel > #notes then N.sel = #notes end
    if N.sel < 1 then N.sel = 1 end

    if button(dl, '##note_add', cx, ly, lw, 34, '+ Добавить заметку', true) then binder.noteAdd() end
    local base, cdl = beginList('##nlist', cx, ly + 44, lw, bottom - ly - 44)
    local iw = lw - 8
    for i, n in ipairs(notes) do
        local y = base.y + (i - 1) * 50
        imgui.SetCursorScreenPos(V(base.x, y))
        if imgui.InvisibleButton('##nrow' .. i, V(iw, 44)) then N.sel = i; N.cap = false; N.delAsk = nil end
        local t = hot('nrow' .. i, imgui.IsItemHovered())
        local sel = (N.sel == i)
        card(cdl, base.x, y, iw, 44, 10, sel and P.active or lerpC(P.card, P.cardHover, t),
            sel and P.accent or lerpC(P.line, P.accent, t * 0.7))
        if sel then rrf(cdl, V(base.x + 4, y + 12), V(base.x + 7, y + 32), U(P.accent), 2) end
        cdl:AddText(V(base.x + 14, y + 6), U(n.on and P.text or P.muted), binder.cut(n.title ~= '' and n.title or 'Без названия', 20))
        local sub = (n.cmd ~= '') and ('/' .. n.cmd) or 'без команды'
        if n.key ~= 'Нет' then sub = sub .. '  |  ' .. n.key end
        cdl:AddText(V(base.x + 14, y + 24), U(P.muted, 0.9), binder.cut(sub, 26))
    end
    endList(base, #notes * 50 + 4)

    card(dl, rx, ly, rw, bottom - ly, 14, P.card)
    local n = notes[N.sel]
    if not n then
        centerText(dl, rx, ly, rw, bottom - ly, 'Заметок пока нет. Нажмите «Добавить заметку».', U(P.muted))
        return
    end
    if N.loaded ~= n then
        imgui.StrCopy(N.tb, n.title); imgui.StrCopy(N.cb, n.cmd); imgui.StrCopy(N.xb, n.text)
        N.loaded, N.delAsk, N.selS, N.selE = n, nil, nil, nil
    end

    local fx, fw = rx + 14, rw - 28
    local y0 = ly + 12
    dl:AddText(V(fx, y0), U(P.muted), 'Название (нажмите, чтобы изменить)')
    local bwShow, bwDel = 96, 84
    local titleW = fw - bwShow - bwDel - 16
    pushInput()
    binder.fieldBegin()
    imgui.SetCursorScreenPos(V(fx, y0 + 18))
    imgui.PushItemWidth(titleW)
    if imgui.InputTextWithHint('##ntitle' .. N.sel, 'Введите название', N.tb, ffi.sizeof(N.tb)) then
        n.title = ffi.string(N.tb); binder.noteDirty()
    end
    imgui.PopItemWidth()
    binder.fieldEnd(dl, true)
    popInput()
    if button(dl, '##note_show', fx + titleW + 8, y0 + 18, bwShow, 30, 'Показать', false) then binder.noteOpen(n) end
    local asked = (N.delAsk == n)
    if button(dl, '##note_del', fx + titleW + 8 + bwShow + 8, y0 + 18, bwDel, 30, asked and 'Точно?' or 'Удалить', asked) then
        if asked then binder.noteDelete(N.sel); return end
        N.delAsk = n
    end

    local y1 = y0 + 58
    dl:AddText(V(fx, y1), U(P.muted), 'Команда')
    dl:AddText(V(fx, y1 + 18 + 7), U(P.accentSoft), '/')
    pushInput()
    binder.fieldBegin()
    imgui.SetCursorScreenPos(V(fx + 12, y1 + 18))
    imgui.PushItemWidth(110)
    imgui.InputTextWithHint('##ncmd' .. N.sel, 'команда', N.cb, ffi.sizeof(N.cb), imgui.InputTextFlags.CharsNoBlank)
    imgui.PopItemWidth()
    local cmdActive = imgui.IsItemActive()
    binder.fieldEnd(dl, false)
    popInput()
    if not cmdActive then
        local c = ffi.string(N.cb)
        if c ~= n.cmd then binder.noteSetCmd(n, c) end
    end

    local kx = fx + 134
    dl:AddText(V(kx, y1), U(P.muted), 'Клавиша')
    imgui.SetCursorScreenPos(V(kx, y1 + 18))
    if imgui.InvisibleButton('##nkey', V(140, 30)) then N.cap = not N.cap; hotCap = 0; binder.pie.cap = false end
    local kt = hot('nkey', imgui.IsItemHovered())
    card(dl, kx, y1 + 18, 140, 30, 8, N.cap and P.active or lerpC(P.chip, P.cardHover, kt),
        N.cap and P.accent or lerpC(P.line, P.accent, kt * 0.7))
    local none = (n.key == 'Нет')
    centerText(dl, kx, y1 + 18, 140, 30, N.cap and binder.capText('Нажмите сочетание...') or (none and 'Не задана' or n.key),
        U(N.cap and P.text or (none and P.muted or P.accentSoft)))
    if showTooltips and imgui.IsItemHovered() then SM.tip('Esc - отмена, Backspace или Delete - сбросить клавишу') end

    if checkDraw(dl, '##nenabled', kx + 152, y1 + 18 + 5, n.on, 'Включена') then
        n.on = not n.on; binder.noteDirty(); binder.needSync = true
    end

    local y2 = y1 + 58
    dl:AddText(V(fx, y2), U(P.muted), 'Текст заметки')
    local hint = 'Сначала выделите текст'
    dl:AddText(V(rx + rw - 14 - SM.tw(hint), y2), U(P.muted, 0.8), hint)

    local bx0 = fx + SM.tw('Текст заметки') + 14
    for k, f in ipairs({ { 'b', 'B', 'Жирный' }, { 'i', 'I', 'Курсив' }, { 'u', 'U', 'Подчёркнутый' } }) do
        local bx, by = bx0 + (k - 1) * 30, y2 - 3
        imgui.SetCursorScreenPos(V(bx, by))
        if imgui.InvisibleButton('##nfmt' .. f[1], V(26, 20)) then binder.noteFormat(n, f[1]) end
        local ft = hot('nfmt' .. f[1], imgui.IsItemHovered())
        if showTooltips and imgui.IsItemHovered() then SM.tip(f[3] .. ': выделите текст и нажмите кнопку') end
        card(dl, bx, by, 26, 20, 7, lerpC(P.chip, P.cardHover, ft), lerpC(P.line, P.accent, ft * 0.8))
        local font = (f[1] == 'b' and binder.nf.b) or (f[1] == 'i' and binder.nf.i) or imgui.GetFont()
        local tx = SM.tw(f[2])
        dl:AddTextFontPtr(font, 14, V(bx + 13 - tx / 2, by + 3), U(P.text), f[2])
        if f[1] == 'b' and font == imgui.GetFont() then
            dl:AddTextFontPtr(font, 14, V(bx + 13 - tx / 2 + 0.7, by + 3), U(P.text), f[2])
        end
        if f[1] == 'u' then dl:AddLine(V(bx + 13 - tx / 2, by + 17), V(bx + 13 + tx / 2, by + 17), U(P.text), 1) end
    end
    pushInput()
    binder.fieldBegin()
    imgui.SetCursorScreenPos(V(fx, y2 + 18))
    if N.refocus then imgui.SetKeyboardFocusHere(); N.refocus = false end
    local sz = V(fw, bottom - (y2 + 18) - 12)
    local changed
    if binder.noteCb then
        changed = imgui.InputTextMultiline('##ntext' .. N.sel, N.xb, ffi.sizeof(N.xb), sz,
            imgui.InputTextFlags.CallbackAlways, binder.noteCb)
    else
        changed = imgui.InputTextMultiline('##ntext' .. N.sel, N.xb, ffi.sizeof(N.xb), sz)
    end
    if changed then n.text = ffi.string(N.xb); binder.noteDirty() end
    binder.fieldEnd(dl, false)
    popInput()
end

binder.fn = { bufs = {}, was = {} }

function binder.fnCmdField(dl, id, x, y, w, get, apply, hint)
    local st = binder.fn
    local buf = st.bufs[id]
    if not buf then buf = new.char[32](); st.bufs[id] = buf; imgui.StrCopy(buf, get()) end
    dl:AddText(V(x - 12, y + 7), U(P.accentSoft), '/')
    imgui.SetCursorScreenPos(V(x, y))
    pushInput()
    imgui.PushStyleColor(imgui.Col.FrameBg, P.chip)
    imgui.PushStyleColor(imgui.Col.FrameBgHovered, P.item)
    imgui.PushStyleColor(imgui.Col.FrameBgActive, P.active)
    imgui.PushItemWidth(w)
    imgui.InputTextWithHint('##fn_' .. id, hint or '', buf, ffi.sizeof(buf), imgui.InputTextFlags.CharsNoBlank)
    imgui.PopItemWidth()
    local act, hov = imgui.IsItemActive(), imgui.IsItemHovered()
    local mn, mx = imgui.GetItemRectMin(), imgui.GetItemRectMax()
    imgui.PopStyleColor(3)
    popInput()
    local ht = hot('fn_ring_' .. id, act or hov)
    if act and not SM.low then
        rr(dl, V(mn.x - 2, mn.y - 2), V(mx.x + 2, mx.y + 2), U(P.accent, 0.25), 11, 15, 2)
    end
    rr(dl, V(mn.x + 0.5, mn.y + 0.5), V(mx.x - 0.5, mx.y - 0.5), U(P.accent, act and 1 or (0.45 + 0.4 * ht)), 9, 15, 1.2)
    local cur = get()
    if act then
        st.was[id] = true
    else
        if st.was[id] then
            st.was[id] = false
            local txt = binder.trim((ffi.string(buf):gsub('^/+', '')))
            if txt ~= cur then apply(txt); cur = get() end
        end
        if ffi.string(buf) ~= cur then imgui.StrCopy(buf, cur) end
    end
end

function binder.fnDelayField(dl, id, x, y, w, get, apply, hint)
    local st = binder.fn
    local buf = st.bufs[id]
    local function fmt() return string.format('%g', get()) end
    if not buf then buf = new.char[16](); st.bufs[id] = buf; imgui.StrCopy(buf, fmt()) end
    imgui.SetCursorScreenPos(V(x, y))
    pushInput()
    imgui.PushStyleColor(imgui.Col.FrameBg, P.chip)
    imgui.PushStyleColor(imgui.Col.FrameBgHovered, P.item)
    imgui.PushStyleColor(imgui.Col.FrameBgActive, P.active)
    imgui.PushItemWidth(w)
    imgui.InputTextWithHint('##fn_' .. id, hint or '2', buf, ffi.sizeof(buf), imgui.InputTextFlags.CharsDecimal)
    imgui.PopItemWidth()
    local act, hov = imgui.IsItemActive(), imgui.IsItemHovered()
    local mn, mx = imgui.GetItemRectMin(), imgui.GetItemRectMax()
    imgui.PopStyleColor(3)
    popInput()
    local ht = hot('fn_ring_' .. id, act or hov)
    if act and not SM.low then
        rr(dl, V(mn.x - 2, mn.y - 2), V(mx.x + 2, mx.y + 2), U(P.accent, 0.25), 11, 15, 2)
    end
    rr(dl, V(mn.x + 0.5, mn.y + 0.5), V(mx.x - 0.5, mx.y - 0.5), U(P.accent, act and 1 or (0.45 + 0.4 * ht)), 9, 15, 1.2)
    dl:AddText(V(mx.x + 8, y + 7), U(P.muted), 'сек')
    if act then
        st.was[id] = true
    else
        if st.was[id] then
            st.was[id] = false
            local txt = binder.trim(ffi.string(buf))
            if txt ~= fmt() then apply(txt) end
        end
        if ffi.string(buf) ~= fmt() then imgui.StrCopy(buf, fmt()) end
    end
end

function binder.fnPage(dl, x, ty, iw, font)
    local p = binder.pie
    local mk = binder.mark
    local lh = imgui.GetTextLineHeight()

    local function section(sy, h, title, sub)
        card(dl, x, sy, iw, h, 14, P.card)
        rrf(dl, V(x + 14, sy + 15), V(x + 18, sy + 37), U(P.accent), 2)
        dl:AddTextFontPtr(font, 16, V(x + 28, sy + 14), U(P.text), title)
        dl:AddText(V(x + 28, sy + 36), U(P.muted), sub)
        dl:AddLine(V(x + 16, sy + 62), V(x + iw - 16, sy + 62), U(P.line, 0.8), 1)
    end

    local function rowText(ry, rightX, title, desc, dim)
        local saved = GA
        if dim then GA = saved * 0.5 end
        dl:PushClipRect(V(x + 10, ry), V(rightX - 10, ry + 48), true)
        dl:AddText(V(x + 18, ry + 6), U(P.text), title)
        dl:AddText(V(x + 18, ry + 26), U(P.muted), desc)
        dl:PopClipRect()
        GA = saved
    end
    local pw, fw = 150, 110

    local function toggle(id, tx, ry, on)
        imgui.SetCursorScreenPos(V(tx - 4, ry - 4))
        local clicked = imgui.InvisibleButton('##' .. id, V(54, 34))
        switchDraw(dl, id .. 'sw', tx, ry, on, 46, 26)
        return clicked
    end

    local rowsA = {
        { 'Открыть хелпер', key = 1, cmd = { 'open', function() return SM.cmd end, binder.openSetCmd, 'rhelp' } },
        { 'Рация департамента', key = 7, cmd = { 'dep', function() return binder.dep.cmd end, binder.depSetCmd, 'dep' } },
        { 'Завершить отыгровку', key = 2 },
        { 'Продолжить отыгровку', key = 3 },
        { 'Приостановить отыгровку', key = 4 },
    }
    for i, sec in ipairs(kpkSecs) do
        rowsA[#rowsA + 1] = { 'КПК: ' .. sec.name, cmd = { 'kpk' .. i, function() return sec.cmd end,
            function(txt) return binder.kpkSetCmd(i, txt) end, sec.defCmd } }
    end
    local sy = ty
    local hA = 90 + #rowsA * 40 + 38
    section(sy, hA, 'Команды и клавиши', 'Команда в чате и горячая клавиша каждой функции')
    local px = x + iw - 16 - pw
    local fx = px - 26 - fw
    dl:AddText(V(fx, sy + 68), U(P.muted), 'Команда')
    dl:AddText(V(px + 4, sy + 68), U(P.muted), 'Клавиша')
    for i, r in ipairs(rowsA) do
        local ry = sy + 90 + (i - 1) * 40
        if i > 1 then dl:AddLine(V(x + 16, ry - 4), V(x + iw - 16, ry - 4), U(P.line, 0.5), 1) end
        dl:PushClipRect(V(x + 10, ry), V(fx - 22, ry + 36), true)
        dl:AddText(V(x + 18, ry + (36 - lh) / 2), U(P.text), r[1])
        dl:PopClipRect()
        if r.cmd then binder.fnCmdField(dl, r.cmd[1], fx, ry + 3, fw, r.cmd[2], r.cmd[3], r.cmd[4]) end
        if r.key then binder.hkPill(dl, '##fnhk' .. r.key, px, ry + 3, pw, 30, r.key, '') end
    end
    dl:PushClipRect(V(x + 10, sy + hA - 30), V(x + iw - 10, sy + hA), true)
    dl:AddText(V(x + 18, sy + hA - 28), U(P.muted), 'Команды и клавиши биндов, диалогов, заметок и оружия - в самих записях.')
    dl:PopClipRect()

    local by = sy + hA + 10
    local hB = 62 + 3 * 48 + 10
    section(by, hB, 'Круговое меню', 'Быстрые отыгровки поверх экрана')
    local cbx = x + iw - 16 - 46
    local r1 = by + 62
    rowText(r1, cbx, 'Включено', 'Пункты меню настраиваются на вкладке «Круговое меню»')
    if toggle('fn_pie_on', cbx, r1 + 11, p.enabled) then p.enabled = not p.enabled; binder.pieSave() end
    local r2 = r1 + 48
    local items = { 'СКМ', 'ПКМ + клавиша' }
    local sw = segWidth(items)
    rowText(r2, x + iw - 16 - sw, 'Способ вызова', 'Зажмите кнопку (или ПКМ и клавишу), наведите на пункт, отпустите')
    local res = segTabs(dl, '##fn_piemode', x + iw - 16 - sw, r2 + 8, items, p.mode + 1)
    if res and res - 1 ~= p.mode then
        p.mode = res - 1
        p.btn = (p.mode == 1) and 0x02 or 0x04
        if p.mode == 1 and not binder.parseKey(hotkeys[6][2]) then hotkeys[6][2] = 'R' end
        cfgDirty = true
        binder.pieSave()
    end
    local r3 = r2 + 48
    local pieKeyOn = (p.mode == 1)
    rowText(r3, px - 10, 'Клавиша вместе с ПКМ', pieKeyOn and 'По умолчанию R. Delete - вернуть R' or 'Доступна в режиме «ПКМ + клавиша»', not pieKeyOn)
    if pieKeyOn then
        binder.hkPill(dl, '##fnhk6', px, r3 + 9, pw, 30, 6, 'ПКМ +')
    else
        local saved = GA; GA = saved * 0.5
        dl:AddText(V(px + 8, r3 + 17), U(P.muted), 'Не используется')
        GA = saved
    end

    local cy = by + hB + 10
    local hC = 62 + 3 * 48 + 10
    section(cy, hC, 'Захват цели', 'Выбор игрока для тега {target}')
    local c1 = cy + 62
    local cfx = x + iw - 16 - fw
    rowText(c1, cfx - 20, 'Команда', 'Захват по ID, повторный ввод снимает цель')
    binder.fnCmdField(dl, 'mark', cfx, c1 + 9, fw, function() return mk.cmd end, binder.markSetCmd, 'mark')
    local c2 = c1 + 48
    rowText(c2, px - 10, 'Комбинация захвата', 'Прицельтесь ПКМ в игрока и нажмите клавишу. Delete - отключить')
    binder.hkPill(dl, '##fnhk5', px, c2 + 9, pw, 30, 5, 'ПКМ +')
    local c3 = c2 + 48
    rowText(c3, cbx, 'Отображать метку на цели', 'Треугольник над головой и метка на карте. Отключите, если сервер запрещает')
    if toggle('fn_mark_blip', cbx, c3 + 11, mk.blip) then
        mk.blip = not mk.blip
        cfgDirty = true
        binder.mark.tickAt = 0
        if not mk.blip then binder.markBlipRemove() elseif binder.target.id ~= -1 then binder.markBlipSet(binder.target.id) end
    end

    local af = binder.afind
    local ay = cy + hC + 10
    local hAf = 62 + 2 * 48 + 10
    section(ay, hAf, 'Автопоиск', 'Автоматический /find по ID: повторная команда останавливает поиск')
    local a1 = ay + 62
    rowText(a1, cfx - 20, 'Команда', 'Запуск по ID: /' .. af.cmd .. ' ID, остановка: /' .. af.cmd)
    binder.fnCmdField(dl, 'afind', cfx, a1 + 9, fw, function() return af.cmd end, binder.afindSetCmd, 'afind')
    local a2 = a1 + 48
    rowText(a2, cfx - 20, 'Задержка', 'Пауза между отправками /find, от 0.5 до 30 секунд')
    binder.fnDelayField(dl, 'afind_delay', cfx, a2 + 9, fw - 34, function() return af.delay end, binder.afindSetDelay)

    local wd = binder.wanted
    local wy = ay + hAf + 10
    local hW = 62 + 4 * 48 + 10
    section(wy, hW, 'Розыск /wanteds', 'Окно общего списка розыска: открывается командой /wanteds')
    local w1 = wy + 62
    rowText(w1, cbx, 'Автообновление', 'Список обновляется сам, пока окно открыто')
    if toggle('fn_wn_auto', cbx, w1 + 11, wd.auto) then binder.wantedSetAuto(not wd.auto) end
    local w2 = w1 + 48
    rowText(w2, cfx - 20, 'Время автообновления', 'Пауза между сканированиями, от 5 до 300 секунд', not wd.auto)
    local savedW = GA
    if not wd.auto then GA = savedW * 0.5 end
    binder.fnDelayField(dl, 'wanted_int', cfx, w2 + 9, fw - 34, function() return wd.interval end, binder.wantedSetInterval, '30')
    GA = savedW
    local w3 = w2 + 48
    rowText(w3, cbx, 'Запоминать позицию окна', 'Окно открывается там, где вы его оставили')
    if toggle('fn_wn_rem', cbx, w3 + 11, wd.remember) then wd.remember = not wd.remember; cfgDirty = true end
    local w4 = w3 + 48
    rowText(w4, px - 10, 'Курсор в окне розыска', 'Удерживайте клавишу (до 2 клавиш). По умолчанию Alt')
    binder.wantedKeyPill(dl, '##fnwnkey', px, w4 + 9, pw, 30, 'Зажать')

    local dp = binder.dep
    local ey = wy + hW + 10
    local hE = 62 + 3 * 48 + 10
    section(ey, hE, 'Рация департамента', 'Теги и волна в сообщениях /d. Окно рации: команда и клавиша выше')
    local e1 = ey + 62
    rowText(e1, cbx, 'Автоподстановка тегов', 'Сообщение /d уходит с префиксом из выбранных тегов и волны')
    if toggle('fn_dep_auto', cbx, e1 + 11, dp.auto) then dp.auto = not dp.auto; binder.depSave() end
    local e2 = e1 + 48
    rowText(e2, cbx, 'Перенос длинных сообщений', 'Текст, не помещающийся в чат, делится на несколько /d', not dp.auto)
    local savedE = GA
    if not dp.auto then GA = savedE * 0.5 end
    if toggle('fn_dep_wrap', cbx, e2 + 11, dp.wrap) and dp.auto then dp.wrap = not dp.wrap; binder.depSave() end
    GA = savedE
    local e3 = e2 + 48
    local ffw = 200
    rowText(e3, x + iw - 16 - ffw - 10, 'Форма префикса', '#1 - первый тег, $ - волна, #2 - второй тег')
    binder.depFormField(dl, x + iw - 16 - ffw, e3 + 9, ffw)

    local ch = binder.chat
    local cy2 = ey + hE + 10
    local hCh = 62 + 3 * 48 + 10
    section(cy2, hCh, 'Обработка чата', 'Правка /me, /do и обычных сообщений. Отыгровки биндера не затрагиваются')
    local h1 = cy2 + 62
    rowText(h1, cbx, 'Правка /me и /do', '/me - с маленькой, /do - с большой буквы, в конце точка')
    if toggle('fn_chat_me', cbx, h1 + 11, ch.me) then ch.me = not ch.me; binder.chatSave() end
    local h2 = h1 + 48
    rowText(h2, cbx, 'Правка обычных сообщений', 'С большой буквы и точкой в конце. После «...» - с маленькой')
    if toggle('fn_chat_plain', cbx, h2 + 11, ch.plain) then ch.plain = not ch.plain; binder.chatSave() end
    local h3 = h2 + 48
    rowText(h3, cbx, 'Перенос длинных строк', 'Текст, не помещающийся в строку, делится на несколько сообщений')
    if toggle('fn_chat_wrap', cbx, h3 + 11, ch.wrap) then ch.wrap = not ch.wrap; binder.chatSave() end

    local dy = cy2 + hCh + 10
    local hD = 62 + 2 * 48 + 10
    section(dy, hD, 'Отыгровка оружий', 'Копия настроек раздела «Отыгровка оружий»')
    local d1 = dy + 62
    rowText(d1, cbx, 'Автоотыгровка оружия', 'Отыгровка при доставании и убирании оружия')
    if toggle('fn_wrp', cbx, d1 + 11, weaponRP) then weaponRP = not weaponRP; cfgDirty = true end
    local d2 = d1 + 48
    rowText(d2, cbx, 'Только по ПКМ', 'Срабатывает, только когда зажата ПКМ с оружием в руках', not weaponRP)
    local saved = GA
    if not weaponRP then GA = saved * 0.5 end
    if toggle('fn_wrmb', cbx, d2 + 11, weaponOnRmb) and weaponRP then weaponOnRmb = not weaponOnRmb; cfgDirty = true end
    GA = saved

    return (dy + hD) - ty
end

pages[9] = function(dl, pos, cx, cw)
    heading(dl, cx, pos.y + 18, 'Настройки', 'Персонализация интерфейса Ranger Helper')

    local ly = pos.y + 70
    local base, cdl = beginList('##slist', cx, ly, cw, pos.y + WIN_H - MARGIN - ly)
    local iw, x = cw - 10, base.x
    local font = imgui.GetFont()

    local tabs = { 'Визуальные', 'Панели', 'Функционал', 'Персонаж' }
    local gap = 6
    local tw = (iw - gap * (#tabs - 1)) / #tabs
    for i, name in ipairs(tabs) do
        local tx = x + (i - 1) * (tw + gap)
        imgui.SetCursorScreenPos(V(tx, base.y))
        if imgui.InvisibleButton('##settingsTab' .. i, V(tw, 36)) then settingsTab = i; hotCap = 0; binder.pie.cap = false end
        local hovered = imgui.IsItemHovered()
        local t = hot('settingsTab' .. i, hovered)
        local active = settingsTab == i
        card(cdl, tx, base.y, tw, 36, 9, active and P.active or lerpC(P.card, P.cardHover, t),
            active and P.accent or lerpC(P.line, P.accent, t * 0.6), active and 0.9 or 0.9)
        if active then
            rrf(cdl, V(tx + tw / 2 - 12, base.y + 32), V(tx + tw / 2 + 12, base.y + 35), U(P.accent), 2)
        end
        centerText(cdl, tx, base.y, tw, 36, name, U(active and P.text or lerpC(P.muted, P.text, t * 0.6)))
    end

    local ty = base.y + 48
    if settingsTab == 1 then

        local themeH = 164
        card(cdl, x, ty, iw, themeH, 12, P.card)
        rrf(cdl, V(x + 14, ty + 15), V(x + 18, ty + 37), U(P.accent), 2)
        cdl:AddTextFontPtr(font, 16, V(x + 28, ty + 14), U(P.text), 'Цветовая тема')
        cdl:AddText(V(x + 28, ty + 36), U(P.muted), 'Выбери цвет акцента интерфейса')

        local pc = PAL[palIdx]
        local right = chipR(cdl, x + iw - 16, ty + 14,
            string.format('#%02X%02X%02X', pc[1], pc[2], pc[3]), P.chip, P.accentSoft)
        chipR(cdl, right, ty + 14, PAL_NAMES[palIdx], P.chip, P.text)

        local swGap = 8
        local swW = (iw - 32 - swGap * (#PAL - 1)) / #PAL
        for i, color in ipairs(PAL) do
            local sx = x + 16 + (i - 1) * (swW + swGap)
            local sy = ty + 70
            imgui.SetCursorScreenPos(V(sx, sy))
            if imgui.InvisibleButton('##pal' .. i, V(swW, 52)) then applyPalette(i); cfgDirty = true end
            local t = hot('pal' .. i, imgui.IsItemHovered())
            local chosen = (palIdx == i)
            local cc = C(color[1], color[2], color[3])
            card(cdl, sx, sy, swW, 52, 10, lerpC(P.item, P.cardHover, t),
                chosen and cc or lerpC(P.line, cc, t * 0.8))
            local lift = t * 2
            rrf(cdl, V(sx + 5, sy + 5 - lift), V(sx + swW - 5, sy + 47 - lift), U(cc), 7)
            cdl:AddLine(V(sx + 9, sy + 6.5 - lift), V(sx + swW - 9, sy + 6.5 - lift), U(C(255, 255, 255, 70)), 1)
            if chosen then
                rr(cdl, V(sx, sy), V(sx + swW, sy + 52), U(cc), 10, 15, 2.0)
                local ccx, ccy = sx + swW / 2, sy + 26
                cdl:AddCircleFilled(V(ccx, ccy), 9, U(C(255, 255, 255)), 28)
                cdl:AddLine(V(ccx - 4, ccy), V(ccx - 1, ccy + 3.5), U(C(30, 34, 50)), 2)
                cdl:AddLine(V(ccx - 1, ccy + 3.5), V(ccx + 4.5, ccy - 3.5), U(C(30, 34, 50)), 2)
            end
        end
        cdl:AddText(V(x + 16, ty + 134), U(P.muted), 'Цвет применяется к активным вкладкам, кнопкам и акцентам.')

        local options = {
            { id = 'tips', title = 'Подсказки при наведении', desc = 'Показывать названия вкладок в свернутом меню', get = function() return showTooltips end,
              set = function(v) showTooltips = v end },
            { id = 'anim', title = 'Плавные анимации', desc = 'Переходы, наведение и раскрытие списков', get = function() return smoothAnimations end,
              set = function(v) smoothAnimations = v end },
            { id = 'lowpc', title = 'Слабый ПК', desc = 'Упрощённый интерфейс: без свечений, плавных переходов и сглаженных углов', get = function() return SM.low end,
              set = function(v) SM.low = v end },
        }
        local oy = ty + themeH + 8
        for i, opt in ipairs(options) do
            local ry = oy + (i - 1) * 54

            local locked = (opt.id == 'anim' and SM.low)
            local saved = GA
            if locked then GA = saved * 0.45 end
            card(cdl, x, ry, iw, 48, 10, P.card)
            cdl:AddText(V(x + 16, ry + 7), U(P.text), opt.title)
            cdl:AddText(V(x + 16, ry + 26), U(P.muted), locked and 'Недоступно в режиме «Слабый ПК»' or opt.desc)
            local bx, by, bw, bh = x + iw - 66, ry + 11, 46, 26
            if not locked then
                imgui.SetCursorScreenPos(V(bx - 4, by - 4))
                if imgui.InvisibleButton('##visual_' .. opt.id, V(bw + 8, bh + 8)) then opt.set(not opt.get()); cfgDirty = true end
            end
            switchDraw(cdl, 'visual_' .. opt.id .. 'sw', bx, by, (not locked) and opt.get(), bw, bh)
            GA = saved
        end
        endList(base, 48 + themeH + 8 + #options * 54 + 4)

    elseif settingsTab == 2 then
        local lw = math.floor(iw * 0.62)
        local rx, rw = x + lw + 12, iw - lw - 12
        local hdrH, optH = 84, 164

        card(cdl, x, ty, lw, hdrH, 12, P.card)
        iconBadge(cdl, x + 14, ty + 14, 40, 'GAUGE_HIGH', P.active)
        cdl:AddTextFontPtr(font, 16, V(x + 66, ty + 13), U(P.text), 'Информационная панель')
        cdl:AddText(V(x + 66, ty + 36), U(P.muted), 'Данные игрока поверх экрана')
        if checkDraw(cdl, '##pc_enabled', x + 66, ty + 54, PANEL.enabled, 'Включить') then
            PANEL.enabled = not PANEL.enabled; cfgDirty = true
        end
        local mg = ico('UP_DOWN_LEFT_RIGHT')
        if button(cdl, '##pan_move', x + lw - 14 - 126, ty + 48, 126, 28, (mg ~= '' and (mg .. ' ') or '') .. 'Переместить', false) then
            panelStartMove()
        end

        local oy = ty + hdrH + 10
        card(cdl, x, oy, lw, optH, 12, P.card)
        rrf(cdl, V(x + 14, oy + 14), V(x + 17, oy + 32), U(P.accent), 2)
        cdl:AddTextFontPtr(font, 16, V(x + 26, oy + 12), U(P.text), 'Отображать')
        local groups = {
            { 'Местоположение', { { 'city', 'Город' }, { 'area', 'Район' }, { 'square', 'Квадрат' } } },
            { 'Прочее',         { { 'dir', 'Направление' }, { 'ping', 'Пинг' }, { 'fps', 'FPS' } } },
            { 'Время (МСК)',    { { 'time', 'Часы' }, { 'secs', 'Секунды' }, { 'date', 'Дата' } } },
        }
        local colW = (lw - 32) / 3
        for gi, g in ipairs(groups) do
            local gx = x + 16 + (gi - 1) * colW
            cdl:AddText(V(gx, oy + 42), U(P.accentSoft), g[1])
            if gi > 1 then cdl:AddLine(V(gx - 8, oy + 44), V(gx - 8, oy + optH - 16), U(P.line, 0.8), 1) end
            for ri, o in ipairs(g[2]) do
                if checkDraw(cdl, '##pc_' .. o[1], gx, oy + 66 + (ri - 1) * 29, PANEL[o[1]], o[2]) then
                    PANEL[o[1]] = not PANEL[o[1]]; cfgDirty = true
                end
            end
        end

        local ph = hdrH + 10 + optH
        card(cdl, rx, ty, rw, ph, 12, P.card)
        cdl:AddText(V(rx + 14, ty + 12), U(P.muted), 'Предпросмотр')
        panelPreview(cdl, rx, ty + 30, rw, ph - 36)

        local T = binder.tab
        local ty2 = ty + hdrH + 10 + optH + 10
        local tabH = 140
        card(cdl, x, ty2, iw, tabH, 12, P.card)
        iconBadge(cdl, x + 14, ty2 + 14, 40, 'USERS', P.active)
        cdl:AddTextFontPtr(font, 16, V(x + 66, ty2 + 13), U(P.text), 'Кастомный TAB')
        cdl:AddText(V(x + 66, ty2 + 36), U(P.muted), 'Список игроков вместо стандартного: открывается по TAB, Esc закрывает, при наведении на ник - копировать и позвонить')
        if checkDraw(cdl, '##tab_on', x + 66, ty2 + 62, T.enabled, 'Включить кастомный TAB') then
            T.enabled = not T.enabled; if not T.enabled then T.open = false end; binder.tabSave(); binder.tabApply()
        end
        if checkDraw(cdl, '##tab_hov', x + 66, ty2 + 92, T.hoverColor, 'Белый ник при наведении и выборе') then
            T.hoverColor = not T.hoverColor; binder.tabSave()
        end
        cdl:AddText(V(x + 66, ty2 + tabH - 22), U(P.muted), 'Если стандартный TAB не вернулся после отключения, перезайдите на сервер.')
        endList(base, 48 + hdrH + 10 + optH + 10 + tabH + 8)

    elseif settingsTab == 4 then

        local colW = (iw - 32 - 16) / 2
        local c2x  = x + 32 + colW
        local heroH, secH = 92, 198

        local nm, sn = ffi.string(profile.name), ffi.string(profile.surname)
        local full = (nm .. ' ' .. sn):match('^%s*(.-)%s*$')
        local fr, rk, ph = ffi.string(profile.fraction), ffi.string(profile.rank), ffi.string(profile.phone)
        local cs = ffi.string(profile.callsign)
        card(cdl, x, ty, iw, heroH, 14, P.card)
        iconBadge(cdl, x + 18, ty + 20, 52, 'CIRCLE_USER', P.active, 0.6)
        local right = x + iw - 16
        right = chipR(cdl, right, ty + 14, profile.sex == 0 and 'Мужской' or 'Женский', P.chip, P.accentSoft)
        if ph ~= '' then right = chipR(cdl, right, ty + 14, ph, P.chip, P.text) end
        if cs ~= '' then right = chipR(cdl, right, ty + 14, cs, P.chip, P.text) end
        cdl:PushClipRect(V(x + 84, ty), V(math.max(x + 90, right), ty + heroH), true)
        cdl:AddTextFontPtr(font, 20, V(x + 84, ty + 22), U(full ~= '' and P.text or P.muted), full ~= '' and full or 'Имя Фамилия')
        local sub = {}
        if fr ~= '' then sub[#sub + 1] = fr end
        if rk ~= '' then sub[#sub + 1] = rk end
        cdl:AddText(V(x + 84, ty + 52), U(P.muted), #sub > 0 and table.concat(sub, '  -  ') or 'Фракция и звание не указаны')
        cdl:PopClipRect()

        local function field(id, caption, tag, hint, buf, fx, fy)
            cdl:AddText(V(fx + 2, fy + 1), U(P.muted), caption)
            chipR(cdl, fx + colW, fy - 3, tag, P.chip, P.accentSoft)
            imgui.SetCursorScreenPos(V(fx, fy + 22))
            imgui.PushItemWidth(colW)
            if imgui.InputTextWithHint('##prof_' .. id, hint, buf, ffi.sizeof(buf)) then cfgDirty = true end
            imgui.PopItemWidth()
            if imgui.IsItemActive() then
                local mn, mx = imgui.GetItemRectMin(), imgui.GetItemRectMax()
                rr(cdl, V(mn.x + 0.5, mn.y + 0.5), V(mx.x - 0.5, mx.y - 0.5), U(P.accent, 0.9), 9, 15, 1.2)
            end
        end
        local function section(sy, title, sub2)
            card(cdl, x, sy, iw, secH, 14, P.card)
            rrf(cdl, V(x + 14, sy + 15), V(x + 18, sy + 37), U(P.accent), 2)
            cdl:AddTextFontPtr(font, 16, V(x + 28, sy + 14), U(P.text), title)
            cdl:AddText(V(x + 28, sy + 36), U(P.muted), sub2)
            cdl:AddLine(V(x + 16, sy + 62), V(x + iw - 16, sy + 62), U(P.line, 0.8), 1)
        end
        local function note(nx, ny, nw, text)
            rrf(cdl, V(nx, ny), V(nx + nw, ny + 32), U(P.chip), 10)
            rr(cdl, V(nx + 0.5, ny + 0.5), V(nx + nw - 0.5, ny + 31.5), U(P.line, 0.8), 10, 15, 1)
            local ic = ico('CIRCLE_INFO')
            if ic ~= '' then cdl:AddText(V(nx + 12, ny + 8), U(P.accentSoft), ic) end
            cdl:PushClipRect(V(nx + 30, ny), V(nx + nw - 6, ny + 32), true)
            cdl:AddText(V(nx + 32, ny + 8), U(P.muted), text)
            cdl:PopClipRect()
        end

        pushInput()
        imgui.PushStyleColor(imgui.Col.FrameBg, P.chip)
        imgui.PushStyleColor(imgui.Col.FrameBgHovered, P.item)
        imgui.PushStyleColor(imgui.Col.FrameBgActive, P.active)

        local s1 = ty + heroH + 10
        section(s1, 'Личные данные', 'Имя и пол персонажа для отыгровок')
        field('name',    'Имя',     '<name()>',    '',   profile.name,    x + 16, s1 + 74)
        field('surname', 'Фамилия', '<surname()>', '', profile.surname, c2x,    s1 + 74)
        cdl:AddText(V(x + 18, s1 + 135), U(P.muted), 'Пол персонажа')
        chipR(cdl, x + 16 + colW, s1 + 131, '{?}', P.chip, P.accentSoft)
        local r = segTabs(cdl, '##sex', x + 16, s1 + 154, { 'Мужской', 'Женский' }, profile.sex + 1)
        if r and r - 1 ~= profile.sex then profile.sex = r - 1; cfgDirty = true end
        note(c2x, s1 + 154, colW, 'Пустые имя и фамилия берутся из ника')

        local s2 = s1 + secH + 10
        section(s2, 'Служба', 'Фракция, звание, позывной и телефон; теги подставятся в текст отыгровки')
        field('fraction', 'Фракция', '{fraction}', '', profile.fraction, x + 16, s2 + 74)
        field('rank',     'Звание',  '{rank}',     '',   profile.rank,     c2x,    s2 + 74)
        field('phone',    'Номер телефона', '{phone}', '', profile.phone,   x + 16, s2 + 134)
        field('callsign', 'Позывной', '{callsign}', '', profile.callsign, c2x, s2 + 134)

        imgui.PopStyleColor(3)
        popInput()

        local s3, prevH = s2 + secH + 10, 138
        card(cdl, x, s3, iw, prevH, 14, P.card)
        rrf(cdl, V(x + 14, s3 + 15), V(x + 18, s3 + 37), U(P.accent), 2)
        cdl:AddTextFontPtr(font, 16, V(x + 28, s3 + 14), U(P.text), 'Так это выглядит в отыгровке')
        cdl:AddText(V(x + 28, s3 + 36), U(P.muted), 'Заполненные поля подставляются, пустые показаны тегом')
        cdl:AddLine(V(x + 16, s3 + 62), V(x + iw - 16, s3 + 62), U(P.line, 0.8), 1)
        local function pline(ly, parts)
            local px = x + 28
            cdl:PushClipRect(V(x + 16, ly), V(x + iw - 16, ly + 20), true)
            for _, pt in ipairs(parts) do
                local txt, col
                if pt.v ~= nil then
                    if pt.v ~= '' then txt, col = pt.v, P.accentSoft else txt, col = pt.t, P.muted end
                else
                    txt, col = pt.s, P.text
                end
                cdl:AddText(V(px, ly), U(col), txt)
                px = px + SM.tw(txt)
            end
            cdl:PopClipRect()
        end
        pline(s3 + 74, { { s = 'Меня зовут ' }, { v = nm, t = '<name()>' }, { s = ' ' }, { v = sn, t = '<surname()>' } })
        pline(s3 + 96, { { s = 'Позывной ' }, { v = cs, t = '{callsign}' }, { s = ', ' }, { v = rk, t = '{rank}' },
                         { s = ' - ' }, { v = fr, t = '{fraction}' } })
        pline(s3 + 118, { { s = 'Мой номер телефона - ' }, { v = ph, t = '{phone}' } })

        local cardH = heroH + 10 + secH + 10 + secH + 10 + prevH
        endList(base, 48 + cardH + 8)

    elseif settingsTab == 3 then

        local total = binder.fnPage(cdl, x, ty, iw, font)
        endList(base, 48 + total + 8)
    end
end

local mainFocused = false
local mainPos = nil
local mainDragging = false
local mainDragOffset = { x = 0, y = 0 }

local SCRIPT_DIR = (thisScript().path:match('^(.*)[\\/]') or getWorkingDirectory())
local CFG_DIR    = SCRIPT_DIR .. '\\Ranger Helper'
local CFG_FILE   = CFG_DIR .. '\\settings.ini'

local WEAPON_FILE = CFG_DIR .. '\\weaponBinds.json'
local weaponLastJson = nil
binder.pf = { dir = CFG_DIR }

local function jsonStr(s)
    s = tostring(s):gsub('[%c"\\]', function(c)
        if c == '"' then return '\\"' elseif c == '\\' then return '\\\\'
        elseif c == '\n' then return '\\n' elseif c == '\r' then return '\\r'
        elseif c == '\t' then return '\\t' end
        return string.format('\\u%04x', c:byte())
    end)
    return '"' .. s .. '"'
end

local function saveWeapons()
    local out = { '{', '  "enabled": ' .. tostring(weaponRP) .. ',', '  "rmbOnly": ' .. tostring(weaponOnRmb) .. ',', '  "weapons": [' }
    for i, w in ipairs(weapons) do
        out[#out + 1] = string.format('    {"id": %d, "title": %s, "on": %s, "take": %s, "put": %s}%s',
            w.id, jsonStr(w.title), tostring(w.on), jsonStr(w.take), jsonStr(w.put), i < #weapons and ',' or '')
    end
    out[#out + 1] = '  ]'
    out[#out + 1] = '}'
    local text = table.concat(out, '\n') .. '\n'
    if text == weaponLastJson then return true end
    if not doesDirectoryExist(CFG_DIR) then createDirectory(CFG_DIR) end
    local f = io.open(WEAPON_FILE, 'wb')
    if not f then return false end
    f:write(text); f:close()
    weaponLastJson = text
    return true
end

local function loadWeapons()
    local f = io.open(WEAPON_FILE, 'rb')
    if not f then return false end
    local text = f:read('*a'); f:close()
    text = text:gsub('^\239\187\191', '')
    local ok, data = pcall(decodeJson, text)
    if not ok or type(data) ~= 'table' then
        print('[RangerHelper] weaponBinds.json повреждён, используются значения по умолчанию')
        return false
    end
    if type(data.enabled) == 'boolean' then weaponRP = data.enabled end
    if type(data.rmbOnly) == 'boolean' then weaponOnRmb = data.rmbOnly end
    local byId = {}
    for _, w in ipairs(weapons) do byId[w.id] = w end
    for _, e in ipairs(type(data.weapons) == 'table' and data.weapons or {}) do
        local w = type(e) == 'table' and byId[tonumber(e.id)]
        if w then
            if type(e.on) == 'boolean' then w.on = e.on end
            if type(e.title) == 'string' and e.title ~= '' then w.title = e.title end
            if type(e.take) == 'string' and e.take ~= '' then w.take = e.take end
            if type(e.put)  == 'string' and e.put  ~= '' then w.put  = e.put end
            w.preview, w.text = weaponPreview(w.take), w.take
        end
    end
    return true
end

function binder.pieSerialize(list, pad)
    local out = {}
    for _, it in ipairs(list) do
        local head = pad .. '{"title": ' .. jsonStr(it.title) .. ', "on": ' .. tostring(it.on ~= false)
        if it.children then
            out[#out + 1] = head .. ', "children": [\n' .. binder.pieSerialize(it.children, pad .. '    ') .. '\n' .. pad .. ']}'
        else
            out[#out + 1] = head .. ', "text": ' .. jsonStr(it.text or '') .. '}'
        end
    end
    return table.concat(out, ',\n')
end

function binder.pieSave()
    if not doesDirectoryExist(CFG_DIR) then createDirectory(CFG_DIR) end
    local p = binder.pie
    local text = table.concat({
        '{',
        '  "enabled": ' .. tostring(p.enabled) .. ',',
        '  "ver": 2,',
        '  "mode": ' .. tostring(p.mode) .. ',',
        '  "btn": ' .. tostring(p.mode == 1 and 0x02 or 0x04) .. ',',
        '  "key": ' .. jsonStr(p.mode == 1 and hotkeys[6][2] or '') .. ',',
        '  "items": [',
        binder.pieSerialize(p.items, '    '),
        '  ]',
        '}',
    }, '\n') .. '\n'
    local f = io.open(binder.pf.dir .. '\\pie.json', 'wb')
    if not f then return false end
    f:write(text); f:close()
    return true
end

function binder.pieClean(list, depth)
    local out = {}
    for _, e in ipairs(type(list) == 'table' and list or {}) do
        if type(e) == 'table' and type(e.title) == 'string' and e.title ~= '' and #out < ((depth == 1) and binder.pie.MAX or binder.pie.MAX_KIDS) then
            local it = { title = e.title, on = (e.on ~= false) }
            if depth == 1 and type(e.children) == 'table' then
                it.children = binder.pieClean(e.children, 2)
            else
                it.text = type(e.text) == 'string' and e.text or ''
                it.preview = binder.preview(it.text)
            end
            out[#out + 1] = it
        end
    end
    return out
end

function binder.pieLoad()
    local p = binder.pie
    local f = io.open(binder.pf.dir .. '\\pie.json', 'rb')
    if not f then return false end
    local text = f:read('*a'); f:close()
    text = text:gsub('^\239\187\191', '')
    local ok, data = pcall(decodeJson, text)
    if not ok or type(data) ~= 'table' then
        print('[RangerHelper] pie.json повреждён, используются значения по умолчанию')
        return true
    end
    if type(data.enabled) == 'boolean' then p.enabled = data.enabled end

    if tonumber(data.ver) and tonumber(data.ver) >= 2 then
        if tonumber(data.mode) then p.mode = (tonumber(data.mode) == 1) and 1 or 0 end
        p.btn = (p.mode == 1) and 0x02 or 0x04
    end
    p.items = binder.pieClean(data.items, 1)
    return true
end

binder.notes = {}
binder.note = {
    sel = 1, cur = nil, open = false, pin = false, apply = false, focusNext = false,
    cap = false, loaded = nil, delAsk = nil, dirty = false, dirtyAt = 0, curOn = false,
    tb = new.char[128](), cb = new.char[32](), xb = new.char[16384](),
    nq = new.char[64](), search = false, hi = 1, lastQ = '', jump = false, nfocus = false,
}
binder.NOTE_MAX = 60
binder.NOTE_W, binder.NOTE_H = 480, 380
binder.note.rect, binder.note.rectOn = { x = 0, y = 0, w = 0, h = 0 }, false

function binder.noteHit(mp)
    local N = binder.note
    if not (N.open and N.rectOn) then return false end
    local r = N.rect
    return mp.x >= r.x and mp.x <= r.x + r.w and mp.y >= r.y and mp.y <= r.y + r.h
end

function binder.fieldBegin()
    imgui.PushStyleColor(imgui.Col.FrameBg, P.chip)
    imgui.PushStyleColor(imgui.Col.FrameBgHovered, P.item)
    imgui.PushStyleColor(imgui.Col.FrameBgActive, P.active)
end
function binder.fieldEnd(dl, pencil)
    local act, hov = imgui.IsItemActive(), imgui.IsItemHovered()
    local mn, mx = imgui.GetItemRectMin(), imgui.GetItemRectMax()
    rr(dl, V(mn.x + 0.5, mn.y + 0.5), V(mx.x - 0.5, mx.y - 0.5),
        U(act and P.accent or (hov and P.accentSoft or P.line), act and 0.95 or (hov and 0.8 or 0.9)), 9, 15, act and 1.4 or 1)
    if pencil and not act then
        local g = ico('PEN')
        if g ~= '' then
            local tx, ty = SM.tsz(g)
            dl:AddText(V(mx.x - 12 - tx, (mn.y + mx.y) / 2 - ty / 2), U(hov and P.accentSoft or P.muted, 0.9), g)
        end
    end
    imgui.PopStyleColor(3)
end

function binder.noteDirty()
    binder.note.dirty, binder.note.dirtyAt = true, os.clock()
end

function binder.noteTick()
    local N = binder.note
    if N.dirty and os.clock() - N.dirtyAt > 1.2 then binder.noteSave() end
end

function binder.noteSave()
    binder.note.dirty = false
    if not doesDirectoryExist(CFG_DIR) then createDirectory(CFG_DIR) end
    local out = {}
    for _, n in ipairs(binder.notes) do
        out[#out + 1] = string.format('    {"title": %s, "cmd": %s, "key": %s, "on": %s, "w": %d, "h": %d, "x": %d, "y": %d, "text": %s}',
            jsonStr(n.title), jsonStr(n.cmd), jsonStr(n.key), tostring(n.on),
            math.floor(n.w or 380), math.floor(n.h or 300), math.floor(n.x or -1), math.floor(n.y or -1), jsonStr(n.text))
    end
    local f = io.open(binder.pf.dir .. '\\notes.json', 'wb')
    if not f then return false end
    f:write('{\n  "notes": [\n', table.concat(out, ',\n'), '\n  ]\n}\n'); f:close()
    return true
end

function binder.noteLoad()
    local f = io.open(binder.pf.dir .. '\\notes.json', 'rb')
    if not f then return false end
    local text = f:read('*a'); f:close()
    text = text:gsub('^\239\187\191', '')
    local ok, data = pcall(decodeJson, text)
    binder.notes = {}
    if not ok or type(data) ~= 'table' then
        print('[RangerHelper] notes.json повреждён, заметки не загружены')
        return true
    end
    for _, e in ipairs(type(data.notes) == 'table' and data.notes or {}) do
        if type(e) == 'table' and #binder.notes < binder.NOTE_MAX then
            local n = {
                title = type(e.title) == 'string' and e.title or '',
                cmd   = type(e.cmd) == 'string' and e.cmd:gsub('^/+', '') or '',
                key   = (type(e.key) == 'string' and e.key ~= '') and e.key or 'Нет',
                on    = (e.on ~= false),
                text  = type(e.text) == 'string' and e.text or '',
                w = math.max(220, tonumber(e.w) or binder.NOTE_W), h = math.max(120, tonumber(e.h) or binder.NOTE_H),
            }
            if not n.cmd:match('^[A-Za-z0-9_]*$') then n.cmd = '' end
            if tonumber(e.w) == 380 and tonumber(e.h) == 300 then n.w, n.h = binder.NOTE_W, binder.NOTE_H end
            if (tonumber(e.x) or -1) >= 0 then n.x = tonumber(e.x) end
            if (tonumber(e.y) or -1) >= 0 then n.y = tonumber(e.y) end
            binder.notes[#binder.notes + 1] = n
        end
    end
    return true
end

function binder.noteAdd()
    local N = binder.note
    if #binder.notes >= binder.NOTE_MAX then binder.say('Достигнут лимит заметок: ' .. binder.NOTE_MAX); return end
    binder.notes[#binder.notes + 1] = {
        title = 'Заметка ' .. (#binder.notes + 1), cmd = '', key = 'Нет', on = true, text = '', w = binder.NOTE_W, h = binder.NOTE_H,
    }
    N.sel, N.cap, N.delAsk = #binder.notes, false, nil
    binder.noteSave()
    binder.needSync = true
end

function binder.noteDelete(i)
    local N = binder.note
    if N.cur == binder.notes[i] then N.open = false end
    table.remove(binder.notes, i)
    N.cap, N.delAsk, N.loaded = false, nil, nil
    binder.noteSave()
    binder.needSync = true
end

function binder.noteSetCmd(n, raw)
    local c = binder.trim(raw):gsub('^/+', '')
    local function revert(msg)
        imgui.StrCopy(binder.note.cb, n.cmd)
        if msg then binder.say(msg) end
    end
    if c == n.cmd then return end
    if c ~= '' then
        if not c:match('^[A-Za-z0-9_]+$') then return revert('Команда: только латиница, цифры и _') end
        local who = binder.cmdTaken(c:lower())
        if who then return revert('Команда {aaaaaa}/' .. c .. '{ffffff} уже занята: ' .. who) end
    end
    n.cmd = c
    binder.noteSave()
    binder.needSync = true
end

function binder.noteOpen(n)
    local N = binder.note
    N.cur, N.open, N.pin, N.apply, N.focusNext = n, true, false, true, true
end

function binder.noteClose()
    local N = binder.note
    N.open = false
    N.search = false
    imgui.StrCopy(N.nq, '')
    if N.dirty then binder.noteSave() end
end

function binder.noteToggle(n)
    local N = binder.note
    if N.open and N.cur == n then binder.noteClose() else binder.noteOpen(n) end
end

function binder.noteCursor(on)
    local N = binder.note
    if on == N.curOn then return end
    N.curOn = on
    pcall(sampToggleCursor, on)
end

binder.nf = binder.nf or {}
binder.nwc, binder.nwcN = {}, 0

function binder.noteTokens(text)
    text = text:gsub('\r', ''):gsub('\t', '    ')
    local toks, b, i, u, pos = {}, false, false, false, 1
    local function plain(str)
        local first = true
        for piece in (str .. '\n'):gmatch('([^\n]*)\n') do
            if not first then toks[#toks + 1] = { nl = true } end
            first = false
            local k = 1
            while k <= #piece do
                local sp = piece:match('^ +', k)
                if sp then
                    toks[#toks + 1] = { sp = true, s = sp, b = b, i = i, u = u }
                    k = k + #sp
                else
                    local wd = piece:match('^[^ ]+', k)
                    toks[#toks + 1] = { s = wd, b = b, i = i, u = u }
                    k = k + #wd
                end
            end
        end
    end
    while true do
        local a, e, slash, tag = text:find('%[(/?)([biuBIU])%]', pos)
        if not a then plain(text:sub(pos)); break end
        plain(text:sub(pos, a - 1))
        local on = (slash == '')
        tag = tag:lower()
        if tag == 'b' then b = on elseif tag == 'i' then i = on else u = on end
        pos = e + 1
    end
    return toks
end

function binder.noteLayout(toks, maxW)
    local nf, font0 = binder.nf, imgui.GetFont()
    local function width(font, key, str)
        local ck = key .. '|' .. str
        local w = binder.nwc[ck]
        if not w then
            imgui.PushFont(font); w = imgui.CalcTextSize(str).x; imgui.PopFont()
            binder.nwcN = binder.nwcN + 1
            if binder.nwcN > 6000 then binder.nwc, binder.nwcN = {}, 0 end
            binder.nwc[ck] = w
        end
        return w
    end
    local lines, cur = {}, { segs = {}, w = 0, wrapped = false }
    local function newline(wrapped)
        lines[#lines + 1] = cur
        cur = { segs = {}, w = 0, wrapped = wrapped }
    end
    local function addSeg(str, key, tk, font, w)
        local last = cur.segs[#cur.segs]
        if last and last.key == key and last.u == tk.u then
            last.s, last.w = last.s .. str, last.w + w
        else
            cur.segs[#cur.segs + 1] = {
                s = str, key = key, u = tk.u, font = font, x = cur.w, w = w,
                fake = tk.b and font == font0, tint = tk.i and font == font0 and not tk.b,
            }
        end
        cur.w = cur.w + w
    end
    for _, tk in ipairs(toks) do
        if tk.nl then
            newline(false)
        else
            local key = (tk.b and 'b' or '') .. (tk.i and 'i' or '')
            local font = (tk.b and tk.i) and (nf.bi or nf.b or nf.i or font0) or tk.b and (nf.b or font0) or tk.i and (nf.i or font0) or font0
            local w = width(font, key, tk.s)
            if tk.sp then
                if not (cur.w == 0 and cur.wrapped) then
                    if cur.w + w <= maxW then addSeg(tk.s, key, tk, font, w) else newline(true) end
                end
            else
                if cur.w + w > maxW and cur.w > 0 then newline(true) end
                if w <= maxW then
                    addSeg(tk.s, key, tk, font, w)
                else
                    for ch in tk.s:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
                        local cw = width(font, key, ch)
                        if cur.w + cw > maxW and cur.w > 0 then newline(true) end
                        addSeg(ch, key, tk, font, cw)
                    end
                end
            end
        end
    end
    lines[#lines + 1] = cur
    return lines
end

function binder.noteLay(n, maxW)
    local text = (n.text ~= '') and n.text or '(пусто)'
    local w = math.floor(maxW)
    local c = n._lay
    if c and c.text == text and c.w == w then return c.lines end
    if n._tokText ~= text then n._tok, n._tokText = binder.noteTokens(text), text end
    n._lay = { text = text, w = w, lines = binder.noteLayout(n._tok, w) }
    return n._lay.lines
end

function binder.noteDrawText(cdl, base, lines, vwy, vwh, col)
    local fs, lh = imgui.GetFontSize(), 18
    local tintCol = U(P.accentSoft)
    for li, ln in ipairs(lines) do
        local y = base.y + (li - 1) * lh
        if y + lh >= vwy and y <= vwy + vwh then
            for _, sg in ipairs(ln.segs) do
                local x = base.x + sg.x
                local c = sg.tint and tintCol or col
                cdl:AddTextFontPtr(sg.font, fs, V(x, y), c, sg.s)
                if sg.fake then cdl:AddTextFontPtr(sg.font, fs, V(x + 0.7, y), c, sg.s) end
                if sg.u then cdl:AddLine(V(x, y + fs + 0.5), V(x + sg.w, y + fs + 0.5), c, 1) end
            end
        end
    end
    return #lines * lh + 4
end

function binder.noteFormat(n, tag)
    local N = binder.note
    local cur = ffi.string(N.xb)
    local lo, hi = #cur, #cur
    if N.selS and N.selE then lo, hi = math.min(N.selS, N.selE), math.max(N.selS, N.selE) end
    lo, hi = clamp(lo, 0, #cur), clamp(hi, 0, #cur)
    local open, close = '[' .. tag .. ']', '[/' .. tag .. ']'
    local new_text, cpos
    if lo == hi then
        new_text, cpos = cur:sub(1, lo) .. open .. close .. cur:sub(hi + 1), lo + #open
    else
        new_text, cpos = cur:sub(1, lo) .. open .. cur:sub(lo + 1, hi) .. close .. cur:sub(hi + 1), hi + #open + #close
    end
    if #new_text >= ffi.sizeof(N.xb) - 1 then return end
    imgui.StrCopy(N.xb, new_text)
    n.text = new_text
    N.selS, N.selE, N.setCursor, N.refocus = cpos, cpos, cpos, true
    binder.noteDirty()
end

do
    local ok, cb = pcall(function()
        return ffi.cast('int (*)(ImGuiInputTextCallbackData*)', function(data)
            pcall(function()
                local N = binder.note
                if N.setCursor then
                    local c = N.setCursor
                    N.setCursor = nil
                    data.CursorPos, data.SelectionStart, data.SelectionEnd = c, c, c
                end
                if data.SelectionStart == data.SelectionEnd then
                    N.selS, N.selE = data.CursorPos, data.CursorPos
                else
                    N.selS, N.selE = data.SelectionStart, data.SelectionEnd
                end
            end)
            return 0
        end)
    end)
    if ok then binder.noteCb = cb end
end

function binder.noteSearchBuild(n, lines, q)
    local c = n._hl
    if c and c.lines == lines and c.q == q then return c.list end
    local list = {}
    if q ~= '' then
        for li, ln in ipairs(lines) do
            local parts, offs, o = {}, {}, 0
            for si, sg in ipairs(ln.segs) do parts[si] = sg.s; offs[si] = o; o = o + #sg.s end
            local low = binder.lowerU8(table.concat(parts))
            local init = 1
            while true do
                local a, b = low:find(q, init, true)
                if not a then break end
                local x0, x1
                for si, sg in ipairs(ln.segs) do
                    local s0, s1 = offs[si] + 1, offs[si] + #sg.s
                    local lo, hi = math.max(a, s0), math.min(b, s1)
                    if lo <= hi then
                        imgui.PushFont(sg.font)
                        local pre = (lo > s0) and imgui.CalcTextSize(sg.s:sub(1, lo - s0)).x or 0
                        local mw = imgui.CalcTextSize(sg.s:sub(lo - s0 + 1, hi - s0 + 1)).x
                        imgui.PopFont()
                        if not x0 then x0 = sg.x + pre end
                        x1 = sg.x + pre + mw
                    end
                end
                if x0 then list[#list + 1] = { li = li, x = x0, w = math.max(x1 - x0, 3) } end
                init = b + 1
            end
        end
    end
    n._hl = { lines = lines, q = q, list = list }
    return list
end

function binder.noteFrame(player)
    local N = binder.note
    local okP, paused = pcall(isPauseMenuActive)
    if N.open and okP and paused then N.open = false end
    local n = N.cur
    if not N.open or not n then
        N.rectOn = false
        binder.noteCursor(false)
        player.HideCursor, player.LockPlayer = true, false
        return
    end
    DT = clamp(imgui.GetIO().DeltaTime, 0.001, 0.1)
    UI_ALPHA, GA = 1.0, 1
    local pin = N.pin
    binder.noteCursor(not pin)
    player.HideCursor = pin

    local sw, sh = getScreenResolution()
    if N.apply then
        imgui.SetNextWindowSize(V(n.w or binder.NOTE_W, n.h or binder.NOTE_H), imgui.Cond.Always)
        imgui.SetNextWindowPos(V(n.x or (sw - (n.w or binder.NOTE_W) - 24), n.y or 140), imgui.Cond.Always)
        N.apply = false
    end
    imgui.SetNextWindowSizeConstraints(V(220, 120), V(sw, sh))
    if N.focusNext then imgui.SetNextWindowFocus(); N.focusNext = false end
    local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoSavedSettings + imgui.WindowFlags.NoBackground +
        imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse
    if pin then flags = flags + imgui.WindowFlags.NoInputs end
    imgui.PushStyleColor(imgui.Col.ResizeGrip, P.accentSoft)
    imgui.PushStyleColor(imgui.Col.ResizeGripHovered, P.accent)
    imgui.PushStyleColor(imgui.Col.ResizeGripActive, P.accentHov)
    imgui.Begin('RangerHelper Note', nil, flags)

    local dl = imgui.GetWindowDrawList()
    local pos, size = imgui.GetWindowPos(), imgui.GetWindowSize()
    local p2 = V(pos.x + size.x, pos.y + size.y)
    local R = N.rect
    R.x, R.y, R.w, R.h, N.rectOn = pos.x, pos.y, size.x, size.y, not pin
    local _fc = SM.clipOff(dl)
    rrf(dl, pos, p2, U(imgui.ImVec4(P.bg.x, P.bg.y, P.bg.z, pin and 0.84 or 0.97)), 14)
    rr(dl, V(pos.x + 0.5, pos.y + 0.5), V(p2.x - 0.5, p2.y - 0.5), U(P.outline, 0.8), 14, 15, 1.2)
    SM.clipOn(dl, _fc)
    hairline(dl, pos.x + 18, p2.x - 18, pos.y + 1, P.accentSoft, 0.5)

    local right = size.x - 16
    if pin then
        local t = 'закреплено'
        dl:AddText(V(p2.x - 16 - SM.tw(t), pos.y + 14), U(P.muted, 0.8), t)
        right = right - SM.tw(t) - 10
    else
        local ic = ico('XMARK')
        if button(dl, '##note_x', p2.x - 16 - 26, pos.y + 10, 26, 26, ic ~= '' and ic or 'X', false) then
            binder.noteClose()
        end
        local pi = ico('THUMBTACK')
        if button(dl, '##note_pin', p2.x - 16 - 26 - 6 - 26, pos.y + 10, 26, 26, pi ~= '' and pi or 'P', false) then
            N.pin = true
        end
        if showTooltips and imgui.IsItemHovered() then SM.tip('Закрепить: окно остаётся поверх игры без курсора') end
        local si = ico('MAGNIFYING_GLASS')
        if button(dl, '##note_find', p2.x - 16 - 3 * 26 - 2 * 6, pos.y + 10, 26, 26, si ~= '' and si or 'F', N.search) then
            N.search = not N.search
            if N.search then N.nfocus = true else imgui.StrCopy(N.nq, '') end
        end
        if showTooltips and imgui.IsItemHovered() then SM.tip('Поиск по заметке') end
        right = right - 96
    end
    local title = (n.title ~= '') and n.title or 'Заметка'
    dl:AddTextFontPtr(imgui.GetFont(), 16, V(pos.x + 16, pos.y + 12), U(P.text),
        binder.cut(title, math.max(4, math.floor((right - 8) / 8.5))))
    dl:AddLine(V(pos.x + 14, pos.y + 44), V(p2.x - 14, pos.y + 44), U(P.line), 1)

    local lay = binder.noteLay(n, size.x - 28 - 14)
    local sr, hl, top, typing = N.search and not pin, {}, 52, false
    if sr then
        local ry, bw, cw = pos.y + 52, 26, 52
        local iw = size.x - 28 - 2 * (bw + 6) - cw
        imgui.SetCursorScreenPos(V(pos.x + 14, ry))
        pushInput()
        if N.nfocus then imgui.SetKeyboardFocusHere(); N.nfocus = false end
        imgui.PushItemWidth(iw)
        local entered = imgui.InputTextWithHint('##notesearch', 'Поиск по заметке', N.nq, ffi.sizeof(N.nq),
            imgui.InputTextFlags.EnterReturnsTrue)
        imgui.PopItemWidth()
        typing = imgui.IsItemActive()
        popInput()
        local q = binder.lowerU8(binder.trim(ffi.string(N.nq)))
        if q ~= N.lastQ then N.lastQ, N.hi, N.jump = q, 1, true end
        hl = binder.noteSearchBuild(n, lay, q)
        if N.hi > #hl or N.hi < 1 then N.hi = 1 end
        local function step(d)
            if #hl > 0 then N.hi = (N.hi - 1 + d) % #hl + 1; N.jump = true end
        end
        if entered then step(1); N.nfocus = true end
        local cnt = (q == '') and '' or ((#hl > 0) and (N.hi .. '/' .. #hl) or '0')
        centerText(dl, pos.x + 14 + iw + 4, ry, cw - 4, bw, cnt, U(P.muted))
        local up, dn = ico('CHEVRON_UP'), ico('CHEVRON_DOWN')
        if button(dl, '##note_sprev', pos.x + 14 + iw + cw, ry, bw, bw, up ~= '' and up or '^', false) then step(-1) end
        if button(dl, '##note_snext', pos.x + 14 + iw + cw + bw + 6, ry, bw, bw, dn ~= '' and dn or 'v', false) then step(1) end
        top = 52 + 34
    end

    local base, cdl = beginList('##notebody', pos.x + 14, pos.y + top, size.x - 28, size.y - top - 14)
    local vwy, vwh = imgui.GetWindowPos().y, imgui.GetWindowSize().y
    if #hl > 0 then
        for k, h in ipairs(hl) do
            local hy = base.y + (h.li - 1) * 18
            if hy + 18 >= vwy and hy <= vwy + vwh then
                local cur = (k == N.hi)
                rrf(cdl, V(base.x + h.x - 1, hy), V(base.x + h.x + h.w + 1, hy + 17),
                    U(cur and P.accentHov or P.accent, cur and 0.8 or 0.38), 3)
            end
        end
        if N.jump then
            imgui.SetScrollY(math.max(0, (hl[N.hi].li - 1) * 18 - (size.y - top - 14) / 2))
        end
    end
    N.jump = false
    endList(base, binder.noteDrawText(cdl, base, lay, vwy, vwh, U(P.text)))

    if not pin and not imgui.IsMouseDown(0) then
        if math.abs((n.w or 0) - size.x) > 0.5 or math.abs((n.h or 0) - size.y) > 0.5
            or math.abs((n.x or -1) - pos.x) > 0.5 or math.abs((n.y or -1) - pos.y) > 0.5 then
            n.w, n.h, n.x, n.y = size.x, size.y, pos.x, pos.y
            binder.noteDirty()
            N.dirtyAt = 0
        end
    end
    player.LockPlayer = typing
    imgui.End()
    imgui.PopStyleColor(3)
    binder.noteTick()
end

function SM.writeSettings()
    cfgDirty = false
    if not doesDirectoryExist(CFG_DIR) then createDirectory(CFG_DIR) end
    local cdir = CFG_FILE:match('^(.*)[\\/][^\\/]*$')
    if cdir and not doesDirectoryExist(cdir) then createDirectory(cdir) end

    local out = {}
    local function add(s) out[#out + 1] = s end
    local function section(name) if #out > 0 then add('') end add('[' .. name .. ']') end

    section('main')
    add('theme=' .. palIdx)
    add('tooltips=' .. tostring(showTooltips))
    add('animations=' .. tostring(smoothAnimations))
    add('lowpc=' .. tostring(SM.low))
    add('toggleKey=' .. tostring(SM.toggleKey))
    add('greeting=' .. tostring(SM.greet))
    add('command=' .. SM.cmd)
    if mainPos then
        add('windowX=' .. math.floor(mainPos.x + 0.5))
        add('windowY=' .. math.floor(mainPos.y + 0.5))
    end

    section('hotkeys')
    for _, h in ipairs(hotkeys) do add(h[1] .. '=' .. h[2]) end

    section('panels')
    for _, k in ipairs({ 'enabled', 'city', 'area', 'square', 'dir', 'ping', 'fps', 'date', 'time', 'secs' }) do
        add(k .. '=' .. tostring(PANEL[k]))
    end
    if PANEL.x and PANEL.y then
        add('x=' .. math.floor(PANEL.x + 0.5))
        add('y=' .. math.floor(PANEL.y + 0.5))
    end

    section('mark')
    add('cmd=' .. binder.mark.cmd)
    add('blip=' .. tostring(binder.mark.blip))

    section('wanted')
    add('auto=' .. tostring(binder.wanted.auto))
    add('interval=' .. binder.wanted.interval)
    add('remember=' .. tostring(binder.wanted.remember))
    add('curkeys=' .. table.concat(binder.wanted.curKeys, ','))
    if binder.wanted.remember and binder.wanted.x and binder.wanted.y then
        add('x=' .. math.floor(binder.wanted.x + 0.5))
        add('y=' .. math.floor(binder.wanted.y + 0.5))
    end

    section('afind')
    add('cmd=' .. binder.afind.cmd)
    add('delay=' .. string.format('%g', binder.afind.delay))

    local f = io.open(CFG_FILE, 'w')
    if not f then return false end
    f:write(table.concat(out, '\n'))
    f:write('\n')
    f:close()
    return true
end

local function saveConfig()
    if not SM.writeSettings() then return false end
    saveWeapons()
    binder.pf.saveChar()
    if binder.needSave then binder.needSave = false; binder.save(); binder.saveDialogs() end
    return true
end

local function readIni(path)
    local f = io.open(path, 'r')
    if not f then return nil end
    local data, cur = {}, nil
    for raw in f:lines() do
        local line = raw:gsub('\r', '')
        line = line:gsub('^\239\187\191', '')
        line = line:match('^%s*(.-)%s*$')
        if line ~= '' and line:sub(1, 1) ~= ';' and line:sub(1, 1) ~= '#' then
            local sec = line:match('^%[(.-)%]$')
            if sec then
                cur = sec
                data[cur] = data[cur] or {}
            elseif cur then
                local k, v = line:match('^(.-)%s*=%s*(.*)$')
                if k and k ~= '' then data[cur][k] = v end
            end
        end
    end
    f:close()
    return data
end

local function loadConfig(keepWin)
    local ini = readIni(CFG_FILE)
    if not ini then return false end
    local function bool(v) if v == 'true' then return true elseif v == 'false' then return false end end

    local m = ini.main or {}
    if tonumber(m.theme) then applyPalette(math.floor(tonumber(m.theme))) end
    if bool(m.tooltips) ~= nil then showTooltips = bool(m.tooltips) end
    if bool(m.animations) ~= nil then smoothAnimations = bool(m.animations) end
    if bool(m.lowpc) ~= nil then SM.low = bool(m.lowpc) end
    if bool(m.weaponRP) ~= nil then weaponRP = bool(m.weaponRP) end
    if bool(m.toggleKey) ~= nil then SM.toggleKey = bool(m.toggleKey) end
    if bool(m.greeting) ~= nil then SM.greet = bool(m.greeting) end
    if m.command and #m.command >= 1 and #m.command <= 24 and m.command:match('^[%w_]+$') then
        SM.cmd = m.command; imgui.StrCopy(SM.cmdBuf, SM.cmd)
    end

    for _, h in ipairs(hotkeys) do
        local v = ini.hotkeys and ini.hotkeys[h[1]]
        if v and v ~= '' then h[2] = v end
    end

    if hotkeys[1][2] == 'F10' then hotkeys[1][2] = 'F2' end
    local pn = ini.panels or {}
    for _, k in ipairs({ 'enabled', 'city', 'area', 'square', 'dir', 'ping', 'fps', 'date', 'time', 'secs' }) do
        local v = bool(pn[k])
        if v ~= nil then PANEL[k] = v end
    end
    if tonumber(pn.x) and tonumber(pn.y) then PANEL.x, PANEL.y = tonumber(pn.x), tonumber(pn.y) end
    local mk = ini.mark or {}
    if mk.cmd and #mk.cmd >= 1 and #mk.cmd <= 24 and mk.cmd:match('^[%w_]+$') then binder.mark.cmd = mk.cmd end
    if bool(mk.blip) ~= nil then binder.mark.blip = bool(mk.blip) end
    local wn = ini.wanted or {}
    if tonumber(wn.x) and tonumber(wn.y) then binder.wanted.x, binder.wanted.y = tonumber(wn.x), tonumber(wn.y) end
    if bool(wn.auto) ~= nil then binder.wanted.auto = bool(wn.auto) end
    if bool(wn.remember) ~= nil then binder.wanted.remember = bool(wn.remember) end
    if tonumber(wn.interval) then binder.wanted.interval = math.floor(clamp(tonumber(wn.interval), 5, 300) + 0.5) end
    if type(wn.curkeys) == 'string' then
        local ks, seenVk = {}, {}
        for n in wn.curkeys:gmatch('%d+') do
            local vk = tonumber(n)
            if vk and binder.wantedKeyOk(vk) and not seenVk[vk] and #ks < 2 then
                seenVk[vk] = true
                ks[#ks + 1] = vk
            end
        end
        if #ks > 0 then binder.wanted.curKeys = ks end
    end
    local af = ini.afind or {}
    if af.cmd and #af.cmd >= 1 and #af.cmd <= 24 and af.cmd:match('^[%w_]+$') then binder.afind.cmd = af.cmd end
    if tonumber(af.delay) then binder.afind.delay = math.max(0.5, math.min(30, tonumber(af.delay))) end
    local pr = ini.profile or {}
    if tonumber(pr.sex) then profile.sex = (tonumber(pr.sex) == 1) and 1 or 0 end
    for _, k in ipairs({ 'name', 'surname', 'fraction', 'rank', 'phone', 'callsign' }) do
        if pr[k] then imgui.StrCopy(profile[k], pr[k]) end
    end
    for _, w in ipairs(weapons) do
        local k = tostring(w.id)
        local v = ini.weapons and bool(ini.weapons[k])
        if v ~= nil then w.on = v end
        local nm = ini.weapon_names and ini.weapon_names[k]
        if nm and nm ~= '' then w.title = nm end
        local tk = ini.weapon_take and ini.weapon_take[k]
        if tk and tk ~= '' then w.take = iniUnesc(tk) end
        local pt = ini.weapon_put and ini.weapon_put[k]
        if pt and pt ~= '' then w.put = iniUnesc(pt) end
        w.preview, w.text = weaponPreview(w.take), w.take
    end

    if not keepWin and tonumber(m.windowX) and tonumber(m.windowY) then
        local sw, sh = getScreenResolution()
        mainPos = {
            x = clamp(tonumber(m.windowX), 0, math.max(0, sw - WIN_W)),
            y = clamp(tonumber(m.windowY), 0, math.max(0, sh - WIN_H)),
        }
    end
    return true
end

binder.file        = CFG_DIR .. '\\binder.ini'
binder.dialogsFile = CFG_DIR .. '\\dialogs.ini'
binder.threads     = {}
binder.resume      = false
binder.paused      = false
binder.target      = { id = -1 }
binder.dlg = {
    stack = {}, selected = 1, params = '', args = {}, keepOnce = false,
    scrollTo = nil, focusNext = false, focused = false, click = { id = 0, t = 0 }, aimId = nil,
}

local HK_STOP   = 'Принудительно завершить отыгровку'
local HK_RESUME = 'Продолжить приостановленную отыгровку'
local HK_PAUSE  = 'Приостановить отыгровку'

function binder.trim(v) return (tostring(v or ''):match('^%s*(.-)%s*$')) end

function binder.split(str)
    local t = {}
    for w in tostring(str or ''):gmatch('%S+') do t[#t + 1] = w end
    return t
end

function binder.cut(str, n)
    local out, c = {}, 0
    for ch in str:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
        c = c + 1
        if c > n then out[#out + 1] = '...'; break end
        out[#out + 1] = ch
    end
    return table.concat(out)
end

function binder.preview(text)
    for line in (text .. '\n'):gmatch('(.-)\r?\n') do
        line = binder.trim(line)
        if line ~= '' and not line:match('^<%s*%d+%s*>$') then return binder.cut(prettyTags(line), 70) end
    end
    return ''
end

function binder.dlgPreview(d)
    local names = {}
    for _, b in ipairs(d.buttons) do names[#names + 1] = b.title end
    if #names == 0 then return 'Нет кнопок' end
    return binder.cut(table.concat(names, ', '), 70)
end

function binder.hotkeyOf(label)
    for _, h in ipairs(hotkeys) do if h[1] == label then return h[2] end end
end

binder.vkNames, binder.nameVk = {}, {}
do
    local N = binder.vkNames
    for c = 0x41, 0x5A do N[c] = string.char(c) end
    for c = 0x30, 0x39 do N[c] = string.char(c) end
    for i = 1, 12 do N[0x6F + i] = 'F' .. i end
    for i = 0, 9 do N[0x60 + i] = 'Num' .. i end
    N[0x20] = 'Space';  N[0x09] = 'Tab';    N[0x0D] = 'Enter';  N[0x2D] = 'Insert'
    N[0x2E] = 'Delete'; N[0x24] = 'Home';   N[0x23] = 'End';    N[0x21] = 'PageUp'
    N[0x22] = 'PageDown'; N[0x25] = 'Left'; N[0x26] = 'Up';     N[0x27] = 'Right'
    N[0x28] = 'Down';   N[0x13] = 'Pause';  N[0x08] = 'Backspace'
    N[0x6A] = 'Num*';   N[0x6B] = 'Num+';   N[0x6D] = 'Num-';   N[0x6E] = 'Num.'; N[0x6F] = 'Num/'
    N[0xC0] = '~';  N[0xBD] = '-'; N[0xBB] = '='; N[0xDB] = '['; N[0xDD] = ']'
    N[0xBA] = ';';  N[0xDE] = "'"; N[0xBC] = ','; N[0xBE] = '.'; N[0xBF] = '/'; N[0xDC] = '\\'
    for vk, name in pairs(N) do binder.nameVk[name:lower()] = vk end
end

local function vkDown(vk) return bit.band(ffi.C.GetAsyncKeyState(vk), 0x8000) ~= 0 end
function binder.mods() return vkDown(0x11), vkDown(0x12), vkDown(0x10) end

function binder.splitKeys(rest, out, depth)
    out, depth = out or {}, depth or 0
    if depth > 2 then return nil end
    local whole = binder.nameVk[rest:lower()]
    if whole then out[#out + 1] = whole; return out end
    local from = 2
    while true do
        local i = rest:find('+', from, true)
        if not i then return nil end
        local vk = binder.nameVk[rest:sub(1, i - 1):lower()]
        if vk then
            out[#out + 1] = vk
            local r = binder.splitKeys(rest:sub(i + 1), out, depth + 1)
            if r then return r end
            out[#out] = nil
        end
        from = i + 1
    end
end

function binder.parseKey(str)
    if type(str) ~= 'string' then return nil end
    local k = { ctrl = false, alt = false, shift = false }
    local rest = str
    while true do
        local m, r = rest:match('^(%a+)%+(.+)$')
        local lm = m and m:lower()
        if lm == 'ctrl' or lm == 'alt' or lm == 'shift' then k[lm] = true; rest = r else break end
    end
    local keys = binder.splitKeys(rest)
    if not keys or #keys == 0 then return nil end
    local seen = {}
    for _, vk in ipairs(keys) do
        if seen[vk] then return nil end
        seen[vk] = true
    end
    k.keys, k.vk = keys, keys[#keys]
    local sorted = {}
    for i, vk in ipairs(keys) do sorted[i] = vk end
    table.sort(sorted)
    k.sig = table.concat(sorted, ',')
    return k
end

function binder.comboName(vk)
    local ctrl, alt, shift = binder.mods()
    return (ctrl and 'Ctrl+' or '') .. (alt and 'Alt+' or '') .. (shift and 'Shift+' or '') .. binder.vkNames[vk]
end

function binder.sameKey(a, b)
    return a and b and a.sig == b.sig and a.ctrl == b.ctrl and a.alt == b.alt and a.shift == b.shift
end

function binder.keyHit(k, vk, ctrl, alt, shift)
    if not k or not k.keys or k.ctrl ~= ctrl or k.alt ~= alt or k.shift ~= shift then return false end
    local inCombo = false
    for _, kv in ipairs(k.keys) do
        if kv == vk then inCombo = true elseif not vkDown(kv) then return false end
    end
    return inCombo
end

function binder.keysHeld(k)
    if not k or not k.keys then return false end
    for _, kv in ipairs(k.keys) do
        if not vkDown(kv) then return false end
    end
    return true
end

binder.cc = { keys = {}, ctrl = false, alt = false, shift = false, commit = nil }
function binder.ccReset()
    local c = binder.cc
    c.keys, c.ctrl, c.alt, c.shift, c.commit = {}, false, false, false, nil
end
function binder.ccName()
    local c = binder.cc
    if #c.keys == 0 then return nil end
    local parts = {}
    if c.ctrl then parts[#parts + 1] = 'Ctrl' end
    if c.alt then parts[#parts + 1] = 'Alt' end
    if c.shift then parts[#parts + 1] = 'Shift' end
    for _, vk in ipairs(c.keys) do parts[#parts + 1] = binder.vkNames[vk] end
    return table.concat(parts, '+')
end

function binder.capText(default)
    return binder.ccName() or default
end

function binder.capDown(wparam, spec)
    local c = binder.cc
    local MODS = { [0x10] = true, [0x11] = true, [0x12] = true,
                   [0xA0] = true, [0xA1] = true, [0xA2] = true, [0xA3] = true, [0xA4] = true, [0xA5] = true }
    if MODS[wparam] then return end

    local alive = {}
    for _, vk in ipairs(c.keys) do if vkDown(vk) then alive[#alive + 1] = vk end end
    c.keys = alive
    if wparam == 0x1B then
        binder.ccReset(); spec.cancel(); return
    end
    if #c.keys == 0 and spec.clearVk and spec.clearVk[wparam] then
        binder.ccReset(); spec.clear(); return
    end
    if not binder.vkNames[wparam] then return end
    for _, vk in ipairs(c.keys) do if vk == wparam then return end end
    if #c.keys >= 3 then return end
    c.keys[#c.keys + 1] = wparam
    local ctrl, alt, shift = binder.mods()
    c.ctrl, c.alt, c.shift = c.ctrl or ctrl, c.alt or alt, c.shift or shift
    c.commit = spec.commit
end

function binder.capUp()
    local c = binder.cc
    if #c.keys == 0 then return end
    for _, vk in ipairs(c.keys) do if vkDown(vk) then return end end
    local name, commit = binder.ccName(), c.commit
    binder.ccReset()
    if name and commit then commit(name) end
end

local function escVal(v)
    return (tostring(v or ''):gsub('\\', '\\\\'):gsub('\r', ''):gsub('\n', '\\n'))
end
local function unescVal(v)
    return (tostring(v or ''):gsub('\\(.)', function(c)
        if c == 'n' then return '\n' elseif c == '\\' then return '\\' end
        return '\\' .. c
    end))
end

function binder.normalize()
    for _, b in ipairs(binds) do
        b.title = b.title or ''
        b.cmd   = b.cmd or ''
        b.key   = b.key or 'Нет'
        b.text  = b.text or ''
        if b.on == nil then b.on = true end
    end
    for _, d in ipairs(dialogs) do
        d.title   = d.title or ''
        d.cmd     = d.cmd or ''
        d.key     = d.key or 'Нет'
        d.buttons = d.buttons or {}
        if d.on == nil then d.on = true end
    end
end

function binder.save()
    binder.needSave = false
    binder.normalize()
    if not doesDirectoryExist(CFG_DIR) then createDirectory(CFG_DIR) end
    local out = { '; Ranger Helper - биндер. Файл можно править вручную (перенос строки в тексте = \\n).',
                  '[meta]', 'count=' .. #binds, 'moved=1' }
    for i, b in ipairs(binds) do
        out[#out + 1] = ''
        out[#out + 1] = '[bind' .. i .. ']'
        out[#out + 1] = 'title=' .. escVal(b.title)
        out[#out + 1] = 'cmd='   .. escVal(b.cmd)
        out[#out + 1] = 'key='   .. escVal(b.key)
        out[#out + 1] = 'cat='   .. tostring(binder.catOf(b))
        out[#out + 1] = 'on='    .. tostring(b.on)
        out[#out + 1] = 'text='  .. escVal(b.text)
    end
    out[#out + 1] = ''
    out[#out + 1] = '[cats]'
    out[#out + 1] = 'count=' .. #binder.cats
    out[#out + 1] = 'next='  .. binder.catNext
    for i, c in ipairs(binder.cats) do
        out[#out + 1] = 'c' .. i .. '_uid='  .. c.uid
        out[#out + 1] = 'c' .. i .. '_name=' .. escVal(c.name)
    end
    out[#out + 1] = ''
    out[#out + 1] = '[sys]'
    for _, e in ipairs(binder.sys) do
        out[#out + 1] = e.id .. '_on='   .. tostring(e.on == true)
        out[#out + 1] = e.id .. '_text=' .. escVal(binder.sysText(e))
    end
    binder.sysInIni = true
    local f = io.open(binder.file, 'w')
    if not f then return false end
    f:write(table.concat(out, '\n'), '\n')
    f:close()
    return true
end

function binder.sysLoadIni(ini)
    local sx = ini.sys
    binder.sysInIni = (sx ~= nil)
    if sx then
        for _, e in ipairs(binder.sys) do
            if sx[e.id .. '_on'] ~= nil then e.on = (sx[e.id .. '_on'] == 'true') end
            local t = sx[e.id .. '_text']
            if t ~= nil then binder.sysSetText(e, unescVal(t)) end
        end
    end
    for _, e in ipairs(binder.sys) do e._was = e.on end
end

function binder.load()
    binder.sysReset()
    binder.sysInIni = false
    binder.catResetDefault()
    local ini = readIni(binder.file)
    if not ini then
        for i = #binds, 1, -1 do binds[i] = nil end
        for _, b in ipairs(binder.defaultBinds()) do binds[#binds + 1] = b end
        return 'missing'
    end
    if not ini.meta then return 'invalid' end
    binder.sysLoadIni(ini)
    if ini.cats then
        local cs, seen, maxUid = {}, {}, 0
        for i = 1, tonumber(ini.cats.count) or 0 do
            local uid, nm = tonumber(ini.cats['c' .. i .. '_uid']), binder.trim(unescVal(ini.cats['c' .. i .. '_name']))
            if uid and nm ~= '' and not seen[uid] and #cs < binder.MAX_CATS then
                seen[uid] = true; maxUid = math.max(maxUid, uid)
                cs[#cs + 1] = { uid = uid, name = nm }
            end
        end
        if #cs > 0 then
            binder.cats = cs
            binder.catNext = math.max(tonumber(ini.cats.next) or 0, maxUid + 1)
        end
    end
    for i = #binds, 1, -1 do binds[i] = nil end
    local i = 1
    while ini['bind' .. i] do
        local t = ini['bind' .. i]
        local b = {
            title = unescVal(t.title), cmd = unescVal(t.cmd), key = unescVal(t.key),
            on = (t.on ~= 'false'), text = unescVal(t.text), cat = tonumber(t.cat),
        }
        if not ini.cats and not b.cat then b.cat = binder.DEF_CAT_OF[b.cmd] end
        b.cat = binder.catOf(b)
        if b.key == '' or b.key == 'Чат' then b.key = 'Нет' end
        b.preview = binder.preview(b.text)
        binds[#binds + 1] = b
        i = i + 1
    end

    if ini.meta.moved ~= '1' then
        local sx = ini.sys
        for _, d in ipairs(binder.defaultBinds()) do
            if binder.MOVED[d.cmd] then
                local have = false
                for _, o in ipairs(binds) do if o.cmd:lower() == d.cmd then have = true; break end end
                if not have then
                    if sx then
                        local t, o = sx['b_' .. d.cmd .. '_text'], sx['b_' .. d.cmd .. '_on']
                        if t ~= nil then d.text = unescVal(t); d.preview = binder.preview(d.text) end
                        if o ~= nil then d.on = (o == 'true') end
                    end
                    d._mig = true
                    if ini.cats then d.cat = binder.cats[1].uid end
                    binds[#binds + 1] = d
                end
            end
        end
        binder.needSave = true
    end
    return 'ok'
end

function binder.saveDialogs()
    binder.normalize()
    if not doesDirectoryExist(CFG_DIR) then createDirectory(CFG_DIR) end
    local out = { '; Ranger Helper - диалоги. Файл можно править вручную (перенос строки в тексте = \\n).',
                  '[meta]', 'count=' .. #dialogs }
    for i, d in ipairs(dialogs) do
        out[#out + 1] = ''
        out[#out + 1] = '[dialog' .. i .. ']'
        out[#out + 1] = 'uid='     .. tostring(d.uid)
        out[#out + 1] = 'title='   .. escVal(d.title)
        out[#out + 1] = 'cmd='     .. escVal(d.cmd)
        out[#out + 1] = 'key='     .. escVal(d.key)
        out[#out + 1] = 'on='      .. tostring(d.on)
        out[#out + 1] = 'buttons=' .. #d.buttons
        for j, b in ipairs(d.buttons) do
            out[#out + 1] = 'b' .. j .. '_title=' .. escVal(b.title)
            out[#out + 1] = 'b' .. j .. '_text='  .. escVal(b.text)
        end
    end
    local f = io.open(binder.dialogsFile, 'w')
    if not f then return false end
    f:write(table.concat(out, '\n'), '\n')
    f:close()
    return true
end

function binder.loadDialogs()
    local ini = readIni(binder.dialogsFile)
    if not ini then return 'missing' end
    if not ini.meta then return 'invalid' end
    for i = #dialogs, 1, -1 do dialogs[i] = nil end
    local used = {}
    local i = 1
    while ini['dialog' .. i] do
        local t = ini['dialog' .. i]
        local d = {
            uid = tonumber(t.uid), title = unescVal(t.title), cmd = unescVal(t.cmd), key = unescVal(t.key),
            on = (t.on ~= 'false'), buttons = {},
        }
        if d.key == '' then d.key = 'Нет' end
        local n = 1
        while t['b' .. n .. '_title'] ~= nil or t['b' .. n .. '_text'] ~= nil do
            d.buttons[#d.buttons + 1] = { title = unescVal(t['b' .. n .. '_title']), text = unescVal(t['b' .. n .. '_text']) }
            n = n + 1
        end
        if not d.uid or used[d.uid] then d.uid = binder.freeUid(used) end
        used[d.uid] = true
        d.preview = binder.dlgPreview(d)
        dialogs[#dialogs + 1] = d
        i = i + 1
    end
    return 'ok'
end

function binder.freeUid(used)
    if not used then
        used = {}
        for _, d in ipairs(dialogs) do used[d.uid] = true end
    end
    local n = 1
    while used[n] do n = n + 1 end
    return n
end

function binder.findDialog(uid)
    for _, d in ipairs(dialogs) do if d.uid == uid then return d end end
    return nil
end

binder.KPK_FILES = { 'asu', 'aticket', 'apun', 'acarc' }
binder.kpkDir    = nil
binder.kpkLegacy = nil

function binder.kpkPath(si)
    if not binder.kpkDir then return nil end
    return binder.kpkDir .. '\\' .. binder.KPK_FILES[si] .. '.json'
end

function binder.kpkClamp(sec, v)
    v = math.floor(tonumber(v) or 1)
    if sec.mode == 'money' then return clamp(v, 100000, 3000000) end
    local hi = (sec.mode == 'minutes') and 30 or sec.max
    return clamp(v, 1, hi)
end

function binder.kpkVal(sec, it)
    return it.value or 0
end

function binder.kpkSecJson(si)
    local sec = kpkSecs[si]
    local out = { '{',
        '  "name": '  .. jsonStr(sec.name) .. ',',
        '  "cmd": '   .. jsonStr(sec.cmd) .. ',' }
    if si == 1 then
        out[#out + 1] = '  "enabled": ' .. tostring(binder.kpk.enabled ~= false) .. ','
    end
    out[#out + 1] = '  "chapters": ['
    for ci, ch in ipairs(sec.chapters) do
        out[#out + 1] = '    {"title": ' .. jsonStr(ch.title) .. ', "items": ['
        for ii, it in ipairs(ch.items) do
            out[#out + 1] = string.format('      {"text": %s, "value": %d, "reason": %s}%s',
                jsonStr(it.text), math.floor(tonumber(it.value) or 0), jsonStr(it.reason or ''),
                ii < #ch.items and ',' or '')
        end
        out[#out + 1] = '    ]}' .. (ci < #sec.chapters and ',' or '')
    end
    out[#out + 1] = '  ]'
    out[#out + 1] = '}'
    return table.concat(out, '\n') .. '\n'
end

function binder.saveKpk()
    local dir = binder.kpkDir
    if not dir then return false end
    local parent = dir:match('^(.*)\\[^\\]+$')
    if parent and not doesDirectoryExist(parent) then createDirectory(parent) end
    if not doesDirectoryExist(dir) then createDirectory(dir) end
    local ok = true
    for si = 1, #kpkSecs do
        local f = io.open(binder.kpkPath(si), 'wb')
        if f then
            f:write(binder.kpkSecJson(si))
            f:close()
        else
            ok = false
        end
    end
    return ok
end

function binder.sysLoad(ini)
    for si = 1, #kpkSecs do
        local sc = ini['s' .. si]
        local eU = binder.sysKpk(si)
        if sc then
            if eU and sc.rp_on ~= nil then eU.on = (sc.rp_on ~= 'false') end
        end
    end
    local s = ini.sys
    if s then
        for _, e in ipairs(binder.sys) do
            if e.kind ~= 'kpk' then
                if s[e.id .. '_on'] ~= nil then e.on = (s[e.id .. '_on'] == 'true') end
                local t = s[e.id .. '_text']
                if t ~= nil then e.text = unescVal(t) end
            end
        end
    end
    for _, e in ipairs(binder.sys) do e._was = e.on end
end

function binder.loadKpkIni(file)
    binder.sysReset()
    local ini = readIni(file)
    if not ini then return 'missing' end
    if not ini.meta then return 'invalid' end
    binder.sysLoad(ini)
    if ini.meta.enabled == 'false' then binder.kpk.enabled = false
    elseif ini.meta.enabled == 'true' then binder.kpk.enabled = true end
    binder.kpk.bufs = {}
    local ver = tonumber(ini.meta.version) or 1

    local legacy = ver < 3
    for si, sec in ipairs(kpkSecs) do
        sec.chapters = {}
        local sc = ini['s' .. si]
        sec.rp = unescVal((sc and sc.rp) or '')
        local c = sc and binder.trim(unescVal(sc.cmd)) or ''
        sec.cmd = c:match('^[A-Za-z0-9_]+$') and c or sec.defCmd
        if not (legacy and sec.kind == 'carcer') then
            local ci = 1
            while ini['s' .. si .. 'c' .. ci] do
                local t = ini['s' .. si .. 'c' .. ci]
                local ch = { title = unescVal(t.title), items = {} }
                local n = 1
                while t['i' .. n .. '_text'] ~= nil do
                    local it = {
                        text   = unescVal(t['i' .. n .. '_text']),
                        value  = binder.kpkClamp(sec, t['i' .. n .. '_value']),
                        reason = unescVal(t['i' .. n .. '_reason']),
                        rp     = unescVal(t['i' .. n .. '_rp']),
                    }
                    if legacy and sec.kind == 'punish' then
                        if ver < 2 then
                            it.carc = 0
                        else
                            local v = math.floor(tonumber(t['i' .. n .. '_value']) or 0)
                            it.value = clamp(v, 0, sec.max)
                            it.carc  = clamp(math.floor(tonumber(t['i' .. n .. '_carc']) or 0), 0, 30)
                            local rawCr = t['i' .. n .. '_carcreason']
                            it.carcReason = (rawCr ~= nil) and unescVal(rawCr) or it.reason
                        end
                    end
                    if t['i' .. n .. '_lower'] ~= 'true' then ch.items[#ch.items + 1] = it end
                    n = n + 1
                end
                sec.chapters[#sec.chapters + 1] = ch
                ci = ci + 1
            end
        end
    end

    if legacy then
        local term, carcSec = kpkSecs[3], kpkSecs[4]

        if ver < 2 then
            local ci = 1
            while ini['s4c' .. ci] do
                local t = ini['s4c' .. ci]
                local title = unescVal(t.title)
                local target
                for _, ch in ipairs(term.chapters) do if ch.title == title then target = ch; break end end
                if not target then
                    target = { title = title, items = {} }
                    term.chapters[#term.chapters + 1] = target
                end
                local n = 1
                while t['i' .. n .. '_text'] ~= nil do
                    local text = unescVal(t['i' .. n .. '_text'])
                    local minutes = clamp(math.floor(tonumber(t['i' .. n .. '_value']) or 1), 1, 30)
                    local reason, rp = unescVal(t['i' .. n .. '_reason']), unescVal(t['i' .. n .. '_rp'])
                    local same
                    for _, it in ipairs(target.items) do
                        if it.text == text and it.carc == 0 then same = it; break end
                    end
                    if same then
                        same.carc = minutes
                        if same.reason == '' then same.reason = reason end
                        same.carcReason = reason
                    else
                        target.items[#target.items + 1] = { text = text, value = 0, carc = minutes, reason = reason, carcReason = reason, rp = rp }
                    end
                    n = n + 1
                end
                ci = ci + 1
            end
        end

        carcSec.chapters = {}
        local termChapters = {}
        for _, ch in ipairs(term.chapters) do
            local keep, cItems = {}, {}
            for _, it in ipairs(ch.items) do
                if (it.carc or 0) > 0 then
                    cItems[#cItems + 1] = {
                        text = it.text, value = binder.kpkClamp(carcSec, it.carc), rp = it.rp or '',
                        reason = (it.carcReason ~= nil) and it.carcReason or it.reason,
                    }
                end
                if (it.value or 0) > 0 then
                    it.carc, it.carcReason = nil, nil
                    keep[#keep + 1] = it
                end
            end
            if #keep > 0 or #ch.items == 0 then
                termChapters[#termChapters + 1] = { title = ch.title, items = keep }
            end
            if #cItems > 0 then
                carcSec.chapters[#carcSec.chapters + 1] = { title = ch.title, items = cItems }
            end
        end
        term.chapters = termChapters

        local src = io.open(file, 'rb')
        if src then
            local data = src:read('*a'); src:close()
            local bak = io.open(file .. '.v' .. ver .. '.bak', 'wb')
            if bak then bak:write(data); bak:close() end
        end
        binder.saveKpk()
    end
    return 'ok'
end

function binder.kpkReadJson(path)
    if not path then return nil end
    local f = io.open(path, 'rb')
    if not f then return nil end
    local text = f:read('*a'); f:close()
    text = text:gsub('^\239\187\191', '')
    local ok, data = pcall(decodeJson, text)
    if ok and type(data) == 'table' then return data end
    print('[RangerHelper] ' .. path .. ' повреждён, файл переименован в .bad')
    os.remove(path .. '.bad')
    os.rename(path, path .. '.bad')
    return nil
end

function binder.kpkHasRp(t, depth)
    if type(t) ~= 'table' or (depth or 0) > 6 then return false end
    if t.rp ~= nil or t.rp_on ~= nil or t.sys ~= nil then return true end
    for _, v in pairs(t) do
        if type(v) == 'table' and binder.kpkHasRp(v, (depth or 0) + 1) then return true end
    end
    return false
end

function binder.loadKpk()
    binder.kpk.enabled, binder.kpk.bufs = true, {}
    for _, sec in ipairs(kpkSecs) do
        sec.chapters, sec.cmd = {}, sec.defCmd
    end

    local datas, found = {}, false
    for si = 1, #kpkSecs do
        datas[si] = binder.kpkReadJson(binder.kpkPath(si))
        if datas[si] then found = true end
    end

    if not found then

        local old = binder.kpkLegacy
        if old and doesFileExist(old) then
            local r = binder.loadKpkIni(old)
            if r == 'ok' then
                binder.saveKpk()
                pcall(binder.save)
                os.remove(old .. '.old')
                os.rename(old, old .. '.old')
            end
            return r
        end
        return 'missing'
    end

    local R = binder.remote
    local dirty = false
    for si, sec in ipairs(kpkSecs) do
        local data = datas[si]
        if data then
            local c = binder.trim(type(data.cmd) == 'string' and data.cmd or '')
            sec.cmd = c:match('^[A-Za-z0-9_]+$') and c or sec.defCmd

            if binder.kpkHasRp(data) then dirty = true end
            if not binder.sysInIni then
                local eU = binder.sysKpk(si)
                if type(data.rp) == 'string' then sec.rp = data.rp end
                if eU and type(data.rp_on) == 'boolean' then eU.on = data.rp_on end
            end

            sec.chapters = R.chapters(data, si, sec)
        end
    end

    local d1 = datas[1]
    if d1 then
        if type(d1.enabled) == 'boolean' then binder.kpk.enabled = d1.enabled end
        if not binder.sysInIni and type(d1.sys) == 'table' then
            for _, e in ipairs(binder.sys) do
                local s = d1.sys[e.id]
                if e.kind ~= 'kpk' and type(s) == 'table' then
                    if type(s.on) == 'boolean' then e.on = s.on end
                    if type(s.text) == 'string' then e.text = s.text end
                end
            end
        end
    end
    if d1 and type(d1.sys) == 'table' then
        for _, b in ipairs(binds) do
            local ls = b._mig and d1.sys['b_' .. b.cmd]
            if type(ls) == 'table' then
                if type(ls.text) == 'string' and ls.text ~= '' then b.text = ls.text; b.preview = binder.preview(b.text) end
                if type(ls.on) == 'boolean' then b.on = ls.on end
                b._mig = nil; binder.needSave = true
            end
        end
    end
    for _, e in ipairs(binder.sys) do e._was = e.on end
    if dirty then
        if not binder.sysInIni then binder.sysInIni = true; pcall(binder.save) end
        pcall(binder.saveKpk)
    end
    return 'ok'
end

function binder.kpkCommit()
    local sec = kpkSecs[kpkSec]
    if ked.kind == 'chapter' then
        local title = binder.trim(ffi.string(ked.title))
        if title == '' then return false, 'Введите название главы' end
        local ch = sec.chapters[ked.ch]
        if ch then
            ch.title = title
        else
            sec.chapters[#sec.chapters + 1] = { title = title, items = {} }
            kpkOpen[kpkSec .. ':1:' .. #sec.chapters] = true
        end
    else
        local chapter = sec.chapters[ked.ch]
        if not chapter then return false, 'Глава не найдена' end
        local text = binder.trim(ffi.string(ked.text))
        if text == '' then return false, 'Введите описание пункта' end
        local value
        if sec.mode == 'money' then
            local n = tonumber((ffi.string(ked.sum):gsub('%s', '')))
            if not n or n ~= math.floor(n) or n < 100000 or n > 3000000 then
                return false, 'Сумма штрафа: целое число от 100 000 до 3 000 000'
            end
            value = n
        elseif sec.mode == 'minutes' then
            value = binder.kpkClamp(sec, ked.minutes[0])
        else
            value = binder.kpkClamp(sec, ked.val)
        end
        local it = chapter.items[ked.ii]
        if not it then
            it = {}
            chapter.items[#chapter.items + 1] = it
        end
        it.text, it.value = text, value
        it.reason = sec.reason and binder.trim(ffi.string(ked.reason)) or ''
        kpkOpen[kpkSec .. ':1:' .. ked.ch] = true
    end
    binder.saveKpk()
    editor[0] = false
    return true
end

function binder.kpkRemove()
    local sec = kpkSecs[kpkSec]
    if ked.kind == 'chapter' then
        table.remove(sec.chapters, ked.ch)
        for k in pairs(kpkOpen) do kpkOpen[k] = nil end
    else
        local chapter = sec.chapters[ked.ch]
        if chapter then table.remove(chapter.items, ked.ii) end
    end
    binder.saveKpk()
    editor[0] = false
end

local PH_ZONES = {
    {"Avispa Country Club",-2667.81,-302.135,-28.831,-2646.4,-262.32,71.169},
    {"Easter Bay Airport",-1315.42,-405.388,15.406,-1264.4,-209.543,25.406},
    {"Avispa Country Club",-2550.04,-355.493,0,-2470.04,-318.493,39.7},
    {"Easter Bay Airport",-1490.33,-209.543,15.406,-1264.4,-148.388,25.406},
    {"Garcia",-2395.14,-222.589,-5.3,-2354.09,-204.792,200},
    {"Shady Cabin",-1632.83,-2263.44,-3,-1601.33,-2231.79,200},
    {"East Los Santos",2381.68,-1494.03,-89.084,2421.03,-1454.35,110.916},
    {"LVA Freight Depot",1236.63,1163.41,-89.084,1277.05,1203.28,110.916},
    {"Blackfield Intersection",1277.05,1044.69,-89.084,1315.35,1087.63,110.916},
    {"Avispa Country Club",-2470.04,-355.493,0,-2270.04,-318.493,46.1},
    {"Temple",1252.33,-926.999,-89.084,1357,-910.17,110.916},
    {"Unity Station",1692.62,-1971.8,-20.492,1812.62,-1932.8,79.508},
    {"LVA Freight Depot",1315.35,1044.69,-89.084,1375.6,1087.63,110.916},
    {"Los Flores",2581.73,-1454.35,-89.084,2632.83,-1393.42,110.916},
    {"Starfish Casino",2437.39,1858.1,-39.084,2495.09,1970.85,60.916},
    {"Easter Bay Chemicals",-1132.82,-787.391,0,-956.476,-768.027,200},
    {"Downtown Los Santos",1370.85,-1170.87,-89.084,1463.9,-1130.85,110.916},
    {"Esplanade East",-1620.3,1176.52,-4.5,-1580.01,1274.26,200},
    {"Market Station",787.461,-1410.93,-34.126,866.009,-1310.21,65.874},
    {"Linden Station",2811.25,1229.59,-39.594,2861.25,1407.59,60.406},
    {"Montgomery Intersection",1582.44,347.457,0,1664.62,401.75,200},
    {"Frederick Bridge",2759.25,296.501,0,2774.25,594.757,200},
    {"Yellow Bell Station",1377.48,2600.43,-21.926,1492.45,2687.36,78.074},
    {"Downtown Los Santos",1507.51,-1385.21,110.916,1582.55,-1325.31,335.916},
    {"Jefferson",2185.33,-1210.74,-89.084,2281.45,-1154.59,110.916},
    {"Mulholland",1318.13,-910.17,-89.084,1357,-768.027,110.916},
    {"Avispa Country Club",-2361.51,-417.199,0,-2270.04,-355.493,200},
    {"Jefferson",1996.91,-1449.67,-89.084,2056.86,-1350.72,110.916},
    {"Julius Thruway West",1236.63,2142.86,-89.084,1297.47,2243.23,110.916},
    {"Jefferson",2124.66,-1494.03,-89.084,2266.21,-1449.67,110.916},
    {"Julius Thruway North",1848.4,2478.49,-89.084,1938.8,2553.49,110.916},
    {"Rodeo",422.68,-1570.2,-89.084,466.223,-1406.05,110.916},
    {"Cranberry Station",-2007.83,56.306,0,-1922,224.782,100},
    {"Downtown Los Santos",1391.05,-1026.33,-89.084,1463.9,-926.999,110.916},
    {"Redsands West",1704.59,2243.23,-89.084,1777.39,2342.83,110.916},
    {"Little Mexico",1758.9,-1722.26,-89.084,1812.62,-1577.59,110.916},
    {"Blackfield Intersection",1375.6,823.228,-89.084,1457.39,919.447,110.916},
    {"Los Santos International",1974.63,-2394.33,-39.084,2089,-2256.59,60.916},
    {"Beacon Hill",-399.633,-1075.52,-1.489,-319.033,-977.516,198.511},
    {"Rodeo",334.503,-1501.95,-89.084,422.68,-1406.05,110.916},
    {"Richman",225.165,-1369.62,-89.084,334.503,-1292.07,110.916},
    {"Downtown Los Santos",1724.76,-1250.9,-89.084,1812.62,-1150.87,110.916},
    {"The Strip",2027.4,1703.23,-89.084,2137.4,1783.23,110.916},
    {"Downtown Los Santos",1378.33,-1130.85,-89.084,1463.9,-1026.33,110.916},
    {"Blackfield Intersection",1197.39,1044.69,-89.084,1277.05,1163.39,110.916},
    {"Conference Center",1073.22,-1842.27,-89.084,1323.9,-1804.21,110.916},
    {"Montgomery",1451.4,347.457,-6.1,1582.44,420.802,200},
    {"Foster Valley",-2270.04,-430.276,-1.2,-2178.69,-324.114,200},
    {"Blackfield Chapel",1325.6,596.349,-89.084,1375.6,795.01,110.916},
    {"Los Santos International",2051.63,-2597.26,-39.084,2152.45,-2394.33,60.916},
    {"Mulholland",1096.47,-910.17,-89.084,1169.13,-768.027,110.916},
    {"Yellow Bell Gol Course",1457.46,2723.23,-89.084,1534.56,2863.23,110.916},
    {"The Strip",2027.4,1783.23,-89.084,2162.39,1863.23,110.916},
    {"Jefferson",2056.86,-1210.74,-89.084,2185.33,-1126.32,110.916},
    {"Mulholland",952.604,-937.184,-89.084,1096.47,-860.619,110.916},
    {"Aldea Malvada",-1372.14,2498.52,0,-1277.59,2615.35,200},
    {"Las Colinas",2126.86,-1126.32,-89.084,2185.33,-934.489,110.916},
    {"Las Colinas",1994.33,-1100.82,-89.084,2056.86,-920.815,110.916},
    {"Richman",647.557,-954.662,-89.084,768.694,-860.619,110.916},
    {"LVA Freight Depot",1277.05,1087.63,-89.084,1375.6,1203.28,110.916},
    {"Julius Thruway North",1377.39,2433.23,-89.084,1534.56,2507.23,110.916},
    {"Willowfield",2201.82,-2095,-89.084,2324,-1989.9,110.916},
    {"Julius Thruway North",1704.59,2342.83,-89.084,1848.4,2433.23,110.916},
    {"Temple",1252.33,-1130.85,-89.084,1378.33,-1026.33,110.916},
    {"Little Mexico",1701.9,-1842.27,-89.084,1812.62,-1722.26,110.916},
    {"Queens",-2411.22,373.539,0,-2253.54,458.411,200},
    {"Las Venturas Airport",1515.81,1586.4,-12.5,1729.95,1714.56,87.5},
    {"Richman",225.165,-1292.07,-89.084,466.223,-1235.07,110.916},
    {"Temple",1252.33,-1026.33,-89.084,1391.05,-926.999,110.916},
    {"East Los Santos",2266.26,-1494.03,-89.084,2381.68,-1372.04,110.916},
    {"Julius Thruway East",2623.18,943.235,-89.084,2749.9,1055.96,110.916},
    {"Willowfield",2541.7,-1941.4,-89.084,2703.58,-1852.87,110.916},
    {"Las Colinas",2056.86,-1126.32,-89.084,2126.86,-920.815,110.916},
    {"Julius Thruway East",2625.16,2202.76,-89.084,2685.16,2442.55,110.916},
    {"Rodeo",225.165,-1501.95,-89.084,334.503,-1369.62,110.916},
    {"Las Brujas",-365.167,2123.01,-3,-208.57,2217.68,200},
    {"Julius Thruway East",2536.43,2442.55,-89.084,2685.16,2542.55,110.916},
    {"Rodeo",334.503,-1406.05,-89.084,466.223,-1292.07,110.916},
    {"Vinewood",647.557,-1227.28,-89.084,787.461,-1118.28,110.916},
    {"Rodeo",422.68,-1684.65,-89.084,558.099,-1570.2,110.916},
    {"Julius Thruway North",2498.21,2542.55,-89.084,2685.16,2626.55,110.916},
    {"Downtown Los Santos",1724.76,-1430.87,-89.084,1812.62,-1250.9,110.916},
    {"Rodeo",225.165,-1684.65,-89.084,312.803,-1501.95,110.916},
    {"Jefferson",2056.86,-1449.67,-89.084,2266.21,-1372.04,110.916},
    {"Hampton Barns",603.035,264.312,0,761.994,366.572,200},
    {"Temple",1096.47,-1130.84,-89.084,1252.33,-1026.33,110.916},
    {"Kincaid Bridge",-1087.93,855.37,-89.084,-961.95,986.281,110.916},
    {"Verona Beach",1046.15,-1722.26,-89.084,1161.52,-1577.59,110.916},
    {"Commerce",1323.9,-1722.26,-89.084,1440.9,-1577.59,110.916},
    {"Mulholland",1357,-926.999,-89.084,1463.9,-768.027,110.916},
    {"Rodeo",466.223,-1570.2,-89.084,558.099,-1385.07,110.916},
    {"Mulholland",911.802,-860.619,-89.084,1096.47,-768.027,110.916},
    {"Mulholland",768.694,-954.662,-89.084,952.604,-860.619,110.916},
    {"Julius Thruway South",2377.39,788.894,-89.084,2537.39,897.901,110.916},
    {"Idlewood",1812.62,-1852.87,-89.084,1971.66,-1742.31,110.916},
    {"Ocean Docks",2089,-2394.33,-89.084,2201.82,-2235.84,110.916},
    {"Commerce",1370.85,-1577.59,-89.084,1463.9,-1384.95,110.916},
    {"Julius Thruway North",2121.4,2508.23,-89.084,2237.4,2663.17,110.916},
    {"Temple",1096.47,-1026.33,-89.084,1252.33,-910.17,110.916},
    {"Glen Park",1812.62,-1449.67,-89.084,1996.91,-1350.72,110.916},
    {"Easter Bay Airport",-1242.98,-50.096,0,-1213.91,578.396,200},
    {"Martin Bridge",-222.179,293.324,0,-122.126,476.465,200},
    {"The Strip",2106.7,1863.23,-89.084,2162.39,2202.76,110.916},
    {"Willowfield",2541.7,-2059.23,-89.084,2703.58,-1941.4,110.916},
    {"Marina",807.922,-1577.59,-89.084,926.922,-1416.25,110.916},
    {"Las Venturas Airport",1457.37,1143.21,-89.084,1777.4,1203.28,110.916},
    {"Idlewood",1812.62,-1742.31,-89.084,1951.66,-1602.31,110.916},
    {"Esplanade East",-1580.01,1025.98,-6.1,-1499.89,1274.26,200},
    {"Downtown Los Santos",1370.85,-1384.95,-89.084,1463.9,-1170.87,110.916},
    {"The Mako Span",1664.62,401.75,0,1785.14,567.203,200},
    {"Rodeo",312.803,-1684.65,-89.084,422.68,-1501.95,110.916},
    {"Pershing Square",1440.9,-1722.26,-89.084,1583.5,-1577.59,110.916},
    {"Mulholland",687.802,-860.619,-89.084,911.802,-768.027,110.916},
    {"Gant Bridge",-2741.07,1490.47,-6.1,-2616.4,1659.68,200},
    {"Las Colinas",2185.33,-1154.59,-89.084,2281.45,-934.489,110.916},
    {"Mulholland",1169.13,-910.17,-89.084,1318.13,-768.027,110.916},
    {"Julius Thruway North",1938.8,2508.23,-89.084,2121.4,2624.23,110.916},
    {"Commerce",1667.96,-1577.59,-89.084,1812.62,-1430.87,110.916},
    {"Rodeo",72.648,-1544.17,-89.084,225.165,-1404.97,110.916},
    {"Roca Escalante",2536.43,2202.76,-89.084,2625.16,2442.55,110.916},
    {"Rodeo",72.648,-1684.65,-89.084,225.165,-1544.17,110.916},
    {"Market",952.663,-1310.21,-89.084,1072.66,-1130.85,110.916},
    {"Las Colinas",2632.74,-1135.04,-89.084,2747.74,-945.035,110.916},
    {"Mulholland",861.085,-674.885,-89.084,1156.55,-600.896,110.916},
    {"King's",-2253.54,373.539,-9.1,-1993.28,458.411,200},
    {"Redsands East",1848.4,2342.83,-89.084,2011.94,2478.49,110.916},
    {"Downtown",-1580.01,744.267,-6.1,-1499.89,1025.98,200},
    {"Conference Center",1046.15,-1804.21,-89.084,1323.9,-1722.26,110.916},
    {"Richman",647.557,-1118.28,-89.084,787.461,-954.662,110.916},
    {"Ocean Flats",-2994.49,277.411,-9.1,-2867.85,458.411,200},
    {"Greenglass College",964.391,930.89,-89.084,1166.53,1044.69,110.916},
    {"Glen Park",1812.62,-1100.82,-89.084,1994.33,-973.38,110.916},
    {"LVA Freight Depot",1375.6,919.447,-89.084,1457.37,1203.28,110.916},
    {"Regular Tom",-405.77,1712.86,-3,-276.719,1892.75,200},
    {"Verona Beach",1161.52,-1722.26,-89.084,1323.9,-1577.59,110.916},
    {"East Los Santos",2281.45,-1372.04,-89.084,2381.68,-1135.04,110.916},
    {"Caligula's Palace",2137.4,1703.23,-89.084,2437.39,1783.23,110.916},
    {"Idlewood",1951.66,-1742.31,-89.084,2124.66,-1602.31,110.916},
    {"Pilgrim",2624.4,1383.23,-89.084,2685.16,1783.23,110.916},
    {"Idlewood",2124.66,-1742.31,-89.084,2222.56,-1494.03,110.916},
    {"Queens",-2533.04,458.411,0,-2329.31,578.396,200},
    {"Downtown",-1871.72,1176.42,-4.5,-1620.3,1274.26,200},
    {"Commerce",1583.5,-1722.26,-89.084,1758.9,-1577.59,110.916},
    {"East Los Santos",2381.68,-1454.35,-89.084,2462.13,-1135.04,110.916},
    {"Marina",647.712,-1577.59,-89.084,807.922,-1416.25,110.916},
    {"Richman",72.648,-1404.97,-89.084,225.165,-1235.07,110.916},
    {"Vinewood",647.712,-1416.25,-89.084,787.461,-1227.28,110.916},
    {"East Los Santos",2222.56,-1628.53,-89.084,2421.03,-1494.03,110.916},
    {"Rodeo",558.099,-1684.65,-89.084,647.522,-1384.93,110.916},
    {"Easter Tunnel",-1709.71,-833.034,-1.5,-1446.01,-730.118,200},
    {"Rodeo",466.223,-1385.07,-89.084,647.522,-1235.07,110.916},
    {"Redsands East",1817.39,2202.76,-89.084,2011.94,2342.83,110.916},
    {"The Clown's Pocket",2162.39,1783.23,-89.084,2437.39,1883.23,110.916},
    {"Idlewood",1971.66,-1852.87,-89.084,2222.56,-1742.31,110.916},
    {"Montgomery Intersection",1546.65,208.164,0,1745.83,347.457,200},
    {"Willowfield",2089,-2235.84,-89.084,2201.82,-1989.9,110.916},
    {"Temple",952.663,-1130.84,-89.084,1096.47,-937.184,110.916},
    {"Prickle Pine",1848.4,2553.49,-89.084,1938.8,2863.23,110.916},
    {"Los Santos International",1400.97,-2669.26,-39.084,2189.82,-2597.26,60.916},
    {"Garver Bridge",-1213.91,950.022,-89.084,-1087.93,1178.93,110.916},
    {"Garver Bridge",-1339.89,828.129,-89.084,-1213.91,1057.04,110.916},
    {"Kincaid Bridge",-1339.89,599.218,-89.084,-1213.91,828.129,110.916},
    {"Kincaid Bridge",-1213.91,721.111,-89.084,-1087.93,950.022,110.916},
    {"Verona Beach",930.221,-2006.78,-89.084,1073.22,-1804.21,110.916},
    {"Verdant Bluffs",1073.22,-2006.78,-89.084,1249.62,-1842.27,110.916},
    {"Vinewood",787.461,-1130.84,-89.084,952.604,-954.662,110.916},
    {"Vinewood",787.461,-1310.21,-89.084,952.663,-1130.84,110.916},
    {"Commerce",1463.9,-1577.59,-89.084,1667.96,-1430.87,110.916},
    {"Market",787.461,-1416.25,-89.084,1072.66,-1310.21,110.916},
    {"Rockshore West",2377.39,596.349,-89.084,2537.39,788.894,110.916},
    {"Julius Thruway North",2237.4,2542.55,-89.084,2498.21,2663.17,110.916},
    {"East Beach",2632.83,-1668.13,-89.084,2747.74,-1393.42,110.916},
    {"Fallow Bridge",434.341,366.572,0,603.035,555.68,200},
    {"Willowfield",2089,-1989.9,-89.084,2324,-1852.87,110.916},
    {"Chinatown",-2274.17,578.396,-7.6,-2078.67,744.17,200},
    {"El Castillo del Diablo",-208.57,2337.18,0,8.43,2487.18,200},
    {"Ocean Docks",2324,-2145.1,-89.084,2703.58,-2059.23,110.916},
    {"Easter Bay Chemicals",-1132.82,-768.027,0,-956.476,-578.118,200},
    {"The Visage",1817.39,1703.23,-89.084,2027.4,1863.23,110.916},
    {"Ocean Flats",-2994.49,-430.276,-1.2,-2831.89,-222.589,200},
    {"Richman",321.356,-860.619,-89.084,687.802,-768.027,110.916},
    {"Green Palms",176.581,1305.45,-3,338.658,1520.72,200},
    {"Richman",321.356,-768.027,-89.084,700.794,-674.885,110.916},
    {"Starfish Casino",2162.39,1883.23,-89.084,2437.39,2012.18,110.916},
    {"East Beach",2747.74,-1668.13,-89.084,2959.35,-1498.62,110.916},
    {"Jefferson",2056.86,-1372.04,-89.084,2281.45,-1210.74,110.916},
    {"Downtown Los Santos",1463.9,-1290.87,-89.084,1724.76,-1150.87,110.916},
    {"Downtown Los Santos",1463.9,-1430.87,-89.084,1724.76,-1290.87,110.916},
    {"Garver Bridge",-1499.89,696.442,-179.615,-1339.89,925.353,20.385},
    {"Julius Thruway South",1457.39,823.228,-89.084,2377.39,863.229,110.916},
    {"East Los Santos",2421.03,-1628.53,-89.084,2632.83,-1454.35,110.916},
    {"Greenglass College",964.391,1044.69,-89.084,1197.39,1203.22,110.916},
    {"Las Colinas",2747.74,-1120.04,-89.084,2959.35,-945.035,110.916},
    {"Mulholland",737.573,-768.027,-89.084,1142.29,-674.885,110.916},
    {"Ocean Docks",2201.82,-2730.88,-89.084,2324,-2418.33,110.916},
    {"East Los Santos",2462.13,-1454.35,-89.084,2581.73,-1135.04,110.916},
    {"Ganton",2222.56,-1722.33,-89.084,2632.83,-1628.53,110.916},
    {"Avispa Country Club",-2831.89,-430.276,-6.1,-2646.4,-222.589,200},
    {"Willowfield",1970.62,-2179.25,-89.084,2089,-1852.87,110.916},
    {"Esplanade North",-1982.32,1274.26,-4.5,-1524.24,1358.9,200},
    {"The High Roller",1817.39,1283.23,-89.084,2027.39,1469.23,110.916},
    {"Ocean Docks",2201.82,-2418.33,-89.084,2324,-2095,110.916},
    {"Last Dime Motel",1823.08,596.349,-89.084,1997.22,823.228,110.916},
    {"Bayside Marina",-2353.17,2275.79,0,-2153.17,2475.79,200},
    {"King's",-2329.31,458.411,-7.6,-1993.28,578.396,200},
    {"El Corona",1692.62,-2179.25,-89.084,1812.62,-1842.27,110.916},
    {"Blackfield Chapel",1375.6,596.349,-89.084,1558.09,823.228,110.916},
    {"The Pink Swan",1817.39,1083.23,-89.084,2027.39,1283.23,110.916},
    {"Julius Thruway West",1197.39,1163.39,-89.084,1236.63,2243.23,110.916},
    {"Los Flores",2581.73,-1393.42,-89.084,2747.74,-1135.04,110.916},
    {"The Visage",1817.39,1863.23,-89.084,2106.7,2011.83,110.916},
    {"Prickle Pine",1938.8,2624.23,-89.084,2121.4,2861.55,110.916},
    {"Verona Beach",851.449,-1804.21,-89.084,1046.15,-1577.59,110.916},
    {"Robada Intersection",-1119.01,1178.93,-89.084,-862.025,1351.45,110.916},
    {"Linden Side",2749.9,943.235,-89.084,2923.39,1198.99,110.916},
    {"Ocean Docks",2703.58,-2302.33,-89.084,2959.35,-2126.9,110.916},
    {"Willowfield",2324,-2059.23,-89.084,2541.7,-1852.87,110.916},
    {"King's",-2411.22,265.243,-9.1,-1993.28,373.539,200},
    {"Commerce",1323.9,-1842.27,-89.084,1701.9,-1722.26,110.916},
    {"Mulholland",1269.13,-768.027,-89.084,1414.07,-452.425,110.916},
    {"Marina",647.712,-1804.21,-89.084,851.449,-1577.59,110.916},
    {"Battery Point",-2741.07,1268.41,-4.5,-2533.04,1490.47,200},
    {"The Four Dragons Casino",1817.39,863.232,-89.084,2027.39,1083.23,110.916},
    {"Blackfield",964.391,1203.22,-89.084,1197.39,1403.22,110.916},
    {"Julius Thruway North",1534.56,2433.23,-89.084,1848.4,2583.23,110.916},
    {"Yellow Bell Gol Course",1117.4,2723.23,-89.084,1457.46,2863.23,110.916},
    {"Idlewood",1812.62,-1602.31,-89.084,2124.66,-1449.67,110.916},
    {"Redsands West",1297.47,2142.86,-89.084,1777.39,2243.23,110.916},
    {"Doherty",-2270.04,-324.114,-1.2,-1794.92,-222.589,200},
    {"Hilltop Farm",967.383,-450.39,-3,1176.78,-217.9,200},
    {"Las Barrancas",-926.13,1398.73,-3,-719.234,1634.69,200},
    {"Pirates in Men's Pants",1817.39,1469.23,-89.084,2027.4,1703.23,110.916},
    {"City Hall",-2867.85,277.411,-9.1,-2593.44,458.411,200},
    {"Avispa Country Club",-2646.4,-355.493,0,-2270.04,-222.589,200},
    {"The Strip",2027.4,863.229,-89.084,2087.39,1703.23,110.916},
    {"Hashbury",-2593.44,-222.589,-1,-2411.22,54.722,200},
    {"Los Santos International",1852,-2394.33,-89.084,2089,-2179.25,110.916},
    {"Whitewood Estates",1098.31,1726.22,-89.084,1197.39,2243.23,110.916},
    {"Sherman Reservoir",-789.737,1659.68,-89.084,-599.505,1929.41,110.916},
    {"El Corona",1812.62,-2179.25,-89.084,1970.62,-1852.87,110.916},
    {"Downtown",-1700.01,744.267,-6.1,-1580.01,1176.52,200},
    {"Foster Valley",-2178.69,-1250.97,0,-1794.92,-1115.58,200},
    {"Las Payasadas",-354.332,2580.36,2,-133.625,2816.82,200},
    {"Valle Ocultado",-936.668,2611.44,2,-715.961,2847.9,200},
    {"Blackfield Intersection",1166.53,795.01,-89.084,1375.6,1044.69,110.916},
    {"Ganton",2222.56,-1852.87,-89.084,2632.83,-1722.33,110.916},
    {"Easter Bay Airport",-1213.91,-730.118,0,-1132.82,-50.096,200},
    {"Redsands East",1817.39,2011.83,-89.084,2106.7,2202.76,110.916},
    {"Esplanade East",-1499.89,578.396,-79.615,-1339.89,1274.26,20.385},
    {"Caligula's Palace",2087.39,1543.23,-89.084,2437.39,1703.23,110.916},
    {"Royal Casino",2087.39,1383.23,-89.084,2437.39,1543.23,110.916},
    {"Richman",72.648,-1235.07,-89.084,321.356,-1008.15,110.916},
    {"Starfish Casino",2437.39,1783.23,-89.084,2685.16,2012.18,110.916},
    {"Mulholland",1281.13,-452.425,-89.084,1641.13,-290.913,110.916},
    {"Downtown",-1982.32,744.17,-6.1,-1871.72,1274.26,200},
    {"Hankypanky Point",2576.92,62.158,0,2759.25,385.503,200},
    {"K.A.C.C. Military Fuels",2498.21,2626.55,-89.084,2749.9,2861.55,110.916},
    {"Harry Gold Parkway",1777.39,863.232,-89.084,1817.39,2342.83,110.916},
    {"Bayside Tunnel",-2290.19,2548.29,-89.084,-1950.19,2723.29,110.916},
    {"Ocean Docks",2324,-2302.33,-89.084,2703.58,-2145.1,110.916},
    {"Richman",321.356,-1044.07,-89.084,647.557,-860.619,110.916},
    {"Randolph Industrial Estate",1558.09,596.349,-89.084,1823.08,823.235,110.916},
    {"East Beach",2632.83,-1852.87,-89.084,2959.35,-1668.13,110.916},
    {"Flint Water",-314.426,-753.874,-89.084,-106.339,-463.073,110.916},
    {"Blueberry",19.607,-404.136,3.8,349.607,-220.137,200},
    {"Linden Station",2749.9,1198.99,-89.084,2923.39,1548.99,110.916},
    {"Glen Park",1812.62,-1350.72,-89.084,2056.86,-1100.82,110.916},
    {"Downtown",-1993.28,265.243,-9.1,-1794.92,578.396,200},
    {"Redsands West",1377.39,2243.23,-89.084,1704.59,2433.23,110.916},
    {"Richman",321.356,-1235.07,-89.084,647.522,-1044.07,110.916},
    {"Gant Bridge",-2741.45,1659.68,-6.1,-2616.4,2175.15,200},
    {"Lil' Probe Inn",-90.218,1286.85,-3,153.859,1554.12,200},
    {"Flint Intersection",-187.7,-1596.76,-89.084,17.063,-1276.6,110.916},
    {"Las Colinas",2281.45,-1135.04,-89.084,2632.74,-945.035,110.916},
    {"Sobell Rail Yards",2749.9,1548.99,-89.084,2923.39,1937.25,110.916},
    {"The Emerald Isle",2011.94,2202.76,-89.084,2237.4,2508.23,110.916},
    {"El Castillo del Diablo",-208.57,2123.01,-7.6,114.033,2337.18,200},
    {"Santa Flora",-2741.07,458.411,-7.6,-2533.04,793.411,200},
    {"Playa del Seville",2703.58,-2126.9,-89.084,2959.35,-1852.87,110.916},
    {"Market",926.922,-1577.59,-89.084,1370.85,-1416.25,110.916},
    {"Queens",-2593.44,54.722,0,-2411.22,458.411,200},
    {"Pilson Intersection",1098.39,2243.23,-89.084,1377.39,2507.23,110.916},
    {"Spinybed",2121.4,2663.17,-89.084,2498.21,2861.55,110.916},
    {"Pilgrim",2437.39,1383.23,-89.084,2624.4,1783.23,110.916},
    {"Blackfield",964.391,1403.22,-89.084,1197.39,1726.22,110.916},
    {"'The Big Ear'",-410.02,1403.34,-3,-137.969,1681.23,200},
    {"Dillimore",580.794,-674.885,-9.5,861.085,-404.79,200},
    {"El Quebrados",-1645.23,2498.52,0,-1372.14,2777.85,200},
    {"Esplanade North",-2533.04,1358.9,-4.5,-1996.66,1501.21,200},
    {"Easter Bay Airport",-1499.89,-50.096,-1,-1242.98,249.904,200},
    {"Fisher's Lagoon",1916.99,-233.323,-100,2131.72,13.8,200},
    {"Mulholland",1414.07,-768.027,-89.084,1667.61,-452.425,110.916},
    {"East Beach",2747.74,-1498.62,-89.084,2959.35,-1120.04,110.916},
    {"San Andreas Sound",2450.39,385.503,-100,2759.25,562.349,200},
    {"Shady Creeks",-2030.12,-2174.89,-6.1,-1820.64,-1771.66,200},
    {"Market",1072.66,-1416.25,-89.084,1370.85,-1130.85,110.916},
    {"Rockshore West",1997.22,596.349,-89.084,2377.39,823.228,110.916},
    {"Prickle Pine",1534.56,2583.23,-89.084,1848.4,2863.23,110.916},
    {"Easter Basin",-1794.92,-50.096,-1.04,-1499.89,249.904,200},
    {"Leafy Hollow",-1166.97,-1856.03,0,-815.624,-1602.07,200},
    {"LVA Freight Depot",1457.39,863.229,-89.084,1777.4,1143.21,110.916},
    {"Prickle Pine",1117.4,2507.23,-89.084,1534.56,2723.23,110.916},
    {"Blueberry",104.534,-220.137,2.3,349.607,152.236,200},
    {"El Castillo del Diablo",-464.515,2217.68,0,-208.57,2580.36,200},
    {"Downtown",-2078.67,578.396,-7.6,-1499.89,744.267,200},
    {"Rockshore East",2537.39,676.549,-89.084,2902.35,943.235,110.916},
    {"San Fierro Bay",-2616.4,1501.21,-3,-1996.66,1659.68,200},
    {"Paradiso",-2741.07,793.411,-6.1,-2533.04,1268.41,200},
    {"The Camel's Toe",2087.39,1203.23,-89.084,2640.4,1383.23,110.916},
    {"Old Venturas Strip",2162.39,2012.18,-89.084,2685.16,2202.76,110.916},
    {"Juniper Hill",-2533.04,578.396,-7.6,-2274.17,968.369,200},
    {"Juniper Hollow",-2533.04,968.369,-6.1,-2274.17,1358.9,200},
    {"Roca Escalante",2237.4,2202.76,-89.084,2536.43,2542.55,110.916},
    {"Julius Thruway East",2685.16,1055.96,-89.084,2749.9,2626.55,110.916},
    {"Verona Beach",647.712,-2173.29,-89.084,930.221,-1804.21,110.916},
    {"Foster Valley",-2178.69,-599.884,-1.2,-1794.92,-324.114,200},
    {"Arco del Oeste",-901.129,2221.86,0,-592.09,2571.97,200},
    {"Fallen Tree",-792.254,-698.555,-5.3,-452.404,-380.043,200},
    {"The Farm",-1209.67,-1317.1,114.981,-908.161,-787.391,251.981},
    {"The Sherman Dam",-968.772,1929.41,-3,-481.126,2155.26,200},
    {"Esplanade North",-1996.66,1358.9,-4.5,-1524.24,1592.51,200},
    {"Financial",-1871.72,744.17,-6.1,-1701.3,1176.42,300},
    {"Garcia",-2411.22,-222.589,-1.14,-2173.04,265.243,200},
    {"Montgomery",1119.51,119.526,-3,1451.4,493.323,200},
    {"Creek",2749.9,1937.25,-89.084,2921.62,2669.79,110.916},
    {"Los Santos International",1249.62,-2394.33,-89.084,1852,-2179.25,110.916},
    {"Santa Maria Beach",72.648,-2173.29,-89.084,342.648,-1684.65,110.916},
    {"Mulholland Intersection",1463.9,-1150.87,-89.084,1812.62,-768.027,110.916},
    {"Angel Pine",-2324.94,-2584.29,-6.1,-1964.22,-2212.11,200},
    {"Verdant Meadows",37.032,2337.18,-3,435.988,2677.9,200},
    {"Octane Springs",338.658,1228.51,0,664.308,1655.05,200},
    {"Come-A-Lot",2087.39,943.235,-89.084,2623.18,1203.23,110.916},
    {"Redsands West",1236.63,1883.11,-89.084,1777.39,2142.86,110.916},
    {"Santa Maria Beach",342.648,-2173.29,-89.084,647.712,-1684.65,110.916},
    {"Verdant Bluffs",1249.62,-2179.25,-89.084,1692.62,-1842.27,110.916},
    {"Las Venturas Airport",1236.63,1203.28,-89.084,1457.37,1883.11,110.916},
    {"Flint Range",-594.191,-1648.55,0,-187.7,-1276.6,200},
    {"Verdant Bluffs",930.221,-2488.42,-89.084,1249.62,-2006.78,110.916},
    {"Palomino Creek",2160.22,-149.004,0,2576.92,228.322,200},
    {"Ocean Docks",2373.77,-2697.09,-89.084,2809.22,-2330.46,110.916},
    {"Easter Bay Airport",-1213.91,-50.096,-4.5,-947.98,578.396,200},
    {"Whitewood Estates",883.308,1726.22,-89.084,1098.31,2507.23,110.916},
    {"Calton Heights",-2274.17,744.17,-6.1,-1982.32,1358.9,200},
    {"Easter Basin",-1794.92,249.904,-9.1,-1242.98,578.396,200},
    {"Los Santos Inlet",-321.744,-2224.43,-89.084,44.615,-1724.43,110.916},
    {"Doherty",-2173.04,-222.589,-1,-1794.92,265.243,200},
    {"Mount Chiliad",-2178.69,-2189.91,-47.917,-2030.12,-1771.66,576.083},
    {"Fort Carson",-376.233,826.326,-3,123.717,1220.44,200},
    {"Foster Valley",-2178.69,-1115.58,0,-1794.92,-599.884,200},
    {"Ocean Flats",-2994.49,-222.589,-1,-2593.44,277.411,200},
    {"Fern Ridge",508.189,-139.259,0,1306.66,119.526,200},
    {"Bayside",-2741.07,2175.15,0,-2353.17,2722.79,200},
    {"Las Venturas Airport",1457.37,1203.28,-89.084,1777.39,1883.11,110.916},
    {"Blueberry Acres",-319.676,-220.137,0,104.534,293.324,200},
    {"Palisades",-2994.49,458.411,-6.1,-2741.07,1339.61,200},
    {"North Rock",2285.37,-768.027,0,2770.59,-269.74,200},
    {"Hunter Quarry",337.244,710.84,-115.239,860.554,1031.71,203.761},
    {"Los Santos International",1382.73,-2730.88,-89.084,2201.82,-2394.33,110.916},
    {"Missionary Hill",-2994.49,-811.276,0,-2178.69,-430.276,200},
    {"San Fierro Bay",-2616.4,1659.68,-3,-1996.66,2175.15,200},
    {"Restricted Area",-91.586,1655.05,-50,421.234,2123.01,250},
    {"Mount Chiliad",-2997.47,-1115.58,-47.917,-2178.69,-971.913,576.083},
    {"Mount Chiliad",-2178.69,-1771.66,-47.917,-1936.12,-1250.97,576.083},
    {"Easter Bay Airport",-1794.92,-730.118,-3,-1213.91,-50.096,200},
    {"The Panopticon",-947.98,-304.32,-1.1,-319.676,327.071,200},
    {"Shady Creeks",-1820.64,-2643.68,-8,-1226.78,-1771.66,200},
    {"Back o Beyond",-1166.97,-2641.19,0,-321.744,-1856.03,200},
    {"Mount Chiliad",-2994.49,-2189.91,-47.917,-2178.69,-1115.58,576.083},
    {"Tierra Robada",-1213.91,596.349,-242.99,-480.539,1659.68,900},
    {"Flint County",-1213.91,-2892.97,-242.99,44.615,-768.027,900},
    {"Whetstone",-2997.47,-2892.97,-242.99,-1213.91,-1115.58,900},
    {"Bone County",-480.539,596.349,-242.99,869.461,2993.87,900},
    {"Tierra Robada",-2997.47,1659.68,-242.99,-480.539,2993.87,900},
    {"San Fierro",-2997.47,-1115.58,-242.99,-1213.91,1659.68,900},
    {"Las Venturas",869.461,596.349,-242.99,2997.06,2993.87,900},
    {"Red County",-1213.91,-768.027,-242.99,2997.06,596.349,900},
    {"Los Santos",44.615,-2892.97,-242.99,2997.06,-768.027,900},
}
local PH_COLORS = {
    [0] = 'Чёрный', 'Белый', 'Голубой', 'Красный',
    'Тёмно-зеленый', 'Пурпурный', 'Жёлтый', 'Светло-голубой',
    'Серебристый', 'Серый', 'Сине-серый', 'Серый',
    'Сине-серый', 'Тёмно-серый', 'Белый', 'Серый',
    'Зелёный', 'Красный', 'Тёмно-красный', 'Серебристый',
    'Светло-синий', 'Светло-красный', 'Бордовый', 'Серебристый',
    'Тёмно-серый', 'Тёмно-серый', 'Серебристый', 'Тёмно-серый',
    'Светло-синий', 'Серебристый', 'Тёмно-красный', 'Светло-красный',
    'Светло-серый', 'Серый', 'Тёмно-серый', 'Тёмно-серый',
    'Чёрный', 'Тёмно-зелёный', 'Серебристый', 'Серый',
    'Тёмно-коричневый', 'Тёмно-бежевый', 'Красный', 'Тёмно-красный',
    'Тёмно-зелёный', 'Красный', 'Светло-бежевый', 'Тёмно-бежевый',
    'Бежевый', 'Светло-серебристый', 'Серебристо-серый', 'Тёмно-зелёный',
    'Серый', 'Тёмно-синий', 'Серо-синей', 'Красно-коричневый',
    'Серебристый', 'Серо-коричневый', 'Красный', 'Светло-синий',
    'Серебристый', 'Светло-коричневый', 'Красный', 'Серебристый',
    'Светло-бежевый', 'Золотистый', 'Бордовый', 'Серый',
    'Светло-бежевый', 'Светло-розовый', 'Красный', 'Сине-серый',
    'Тёмно-серый', 'Светло-бежевый', 'Тёмно-красный', 'Тёмно-синий',
    'Серебристый', 'Серо-коричневый', 'Красный', 'Синий',
    'Малиновый', 'Серый', 'Красный', 'Чёрно-зелёный',
    'Шоколадный', 'Вишнёвый', 'Зелёный', 'Светло-синий',
    'Светло-красный', 'Светло-бежевый', 'Белый', 'Тёмно-серый',
    'Серый', 'Бирюзовый', 'Светло-синий', 'Сине-серый',
    'Светло-бежевый', 'Серый', 'Бирюзово-синий', 'Светло-коричневый',
    'Тёмно-голубой', 'Тёмно-синий', 'Светло-коричневый', 'Синий',
    'Светло-коричневый', 'Светло-серый', 'Синий', 'Светло-коричневый',
    'Серо-голубой', 'Серый', 'Светло-коричневый', 'Серебристо-серый',
    'Сине-серый', 'Коричневый', 'Тёмно-зелёный', 'Красный',
    'Тёмно-синий', 'Красный', 'Серебристый', 'Бежево-серый',
    'Светло-бежевый', 'Красный', 'Серебристый', 'Тёмно-коричневый',
    'Красный', 'Синий', 'Розовый', 'Чёрный',
    'Светло-зелёный', 'Черновато-красный', 'Светло-голубой', 'Желтовато-коричневый',
    'Красно-коричневый', 'Чёрный', 'Фиолетовый', 'Бирюзовый',
    'Светло-фиолетовый', 'Светло-зелёный', 'Светло-серый', 'Пурпурно-синий',
    'Серебристый', 'Серый', 'Светло-оливковый', 'Сиреневый',
    'Фиолетовый', 'Светло-зелёный', 'Светло-фиолетовый', 'Фиолетовый',
    'Чёрный', 'Коричнево-чёрный', 'Чёрный', 'Сине-зелёный',
    'Светло-синий', 'Зелёный', 'Светло-зелёный', 'Бирюзовый',
    'Серебристый', 'Сине-серый', 'Тёмно-красный', 'Коричневый',
    'Тёмно-зелёный', 'Светло-розовый', 'Синий', 'Бирюзовый',
    'Чёрно-серый', 'Тёмно-бирюзовый', 'Голубой', 'Фиолетовый',
    'Шоколадный', 'Светло-фиолетовый', 'Светло-фиолетовый', 'Фиолетовый',
    'Тёмно-зелёный', 'Шоколадный', 'Шоколадный', 'Красный',
    'Светло-фиолетовый', 'Светло-фиолетовый', 'Фиолетовый', 'Тёмно-фиолетовый',
    'Морковный', 'Красный', 'Морковный', 'Морковный',
    'Пурпурно-красный', 'Серо-розовый', 'Тёмно-зелёный', 'Тёмно-зелёный',
    'Тёмно-зелёный', 'Тёмно-зелёный', 'Розовый', 'Зелёный',
    'Бежевый', 'Серый', 'Жёлтый', 'Золотистый',
    'Серый', 'Жёлтый', 'Синий', 'Тёмно-оливковый',
    'Тёмно-бежевый', 'Тёмно-синий', 'Тёмно-зелёный', 'Тёмно-синий',
    'Светло-синий', 'Тёмно-фиолетовый', 'Тёмно-синий', 'Тёмно-синий',
    'Светло-синий', 'Синий', 'Тёмно-синий', 'Фиолетовый',
    'Морковный', 'Серебристый', 'Жёлто-зеленый', 'Тёмно-зелёный',
    'Морковный', 'Бирюзовый', 'Светло-розовый', 'Оранжевый',
    'Розовый', 'Оливкого-желтый', 'Морковный', 'Тёмно-синий',
    'Красно-коричневый', 'Тёмно-оливковый', 'Светло-зелёный', 'Тёмно-зелёный',
    'Жёлтый', 'Светло-зелёный', 'Бурый', 'Светло-коричневый',
    'Розовый', 'Розовый', 'Тёмно-зелёный', 'Болотный',
    'Зеленовато-синий', 'Розовый', 'Коричнево-бежевый', 'Морковный',
    'Бирюзовый', 'Салатовый', 'Пурпурный', 'Зелёный',
    'Тёмно-коричневый', 'Тёмно-зелёный', 'Серо-голубой', 'Серо-синей',
    'Красный', 'Пурпурно-фиолетовый', 'Серебряно-бежевый', 'Тёмно-серый',
    'Серый', 'Серый', 'Кофейный', 'Тёмно-синий',
}
local PH_CITIES = { "Los Santos", "San Fierro", "Las Venturas" }

local okWL, weaponLib = pcall(require, 'game.weapons')
local H = {}

function H.myId()
    local ok, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if ok then return id end
    return sampGetLocalPlayerId()
end

function H.rpId(v)
    local id = tonumber(v)
    if not id or id < 0 then id = H.myId() end
    local d = tostring(math.floor(id))
    if #d < 3 then d = string.rep('0', 3 - #d) .. d end
    local r = d:gsub('(%d)', '%1-')
    return r:sub(1, -2)
end
function H.valid(id)
    return id ~= nil and id >= 0 and id < 1004 and sampIsPlayerConnected(id) and not sampIsPlayerNpc(id)
end
function H.pid(arg)
    local id = tonumber(arg)
    if not H.valid(id) then id = H.myId() end
    return id
end
function H.nick(id) return u8:encode(sampGetPlayerNickname(id) or '') end
function H.charStrict(id)
    if id == H.myId() then return PLAYER_PED end
    local ok, h = sampGetCharHandleBySampPlayerId(id)
    if ok then return h end
    return nil
end
function H.char(arg)
    local id = tonumber(arg)
    if H.valid(id) then
        local h = H.charStrict(id)
        if h then return h end
    end
    return PLAYER_PED
end
function H.vehicle(arg)
    local id = tonumber(arg)
    if id and id >= 50000 and doesVehicleExist(id - 50000) then return id - 50000 end
    return nil
end
function H.weaponName(id)
    local ok, name = pcall(function()
        if okWL and weaponLib.get_name then return weaponLib.get_name(id) end
        return okWL and weaponLib.names and weaponLib.names[id] or nil
    end)
    return (ok and name) or ''
end
function H.chatColor(id)
    return string.format('%06X', bit.band(sampGetPlayerColor(id), 0xFFFFFF))
end
function H.where(arg)
    local veh = H.vehicle(arg)
    if veh then return getCarCoordinates(veh) end
    return getCharCoordinates(H.char(arg))
end
function H.city(x, y, z)
    local c = getCityFromCoords(x, y, z)
    if c > 0 and PH_CITIES[c] then return PH_CITIES[c] end
    return 'Нет'
end
local SQ = { 'А', 'Б', 'В', 'Г', 'Д', 'Ж', 'З', 'И', 'К', 'Л', 'М', 'Н', 'О', 'П', 'Р', 'С', 'Т', 'У', 'Ф', 'Х', 'Ц', 'Ч', 'Ш', 'Я' }
function H.square(x, y)
    local cx = math.ceil((x + 3000) / 250)
    local cy = SQ[math.ceil((y * -1 + 3000) / 250)]
    if cy ~= nil then return cy .. '-' .. cx end
    return 'Неизвестно'
end
function H.area(x, y, z)
    for _, zn in ipairs(PH_ZONES) do
        if x >= zn[2] and y >= zn[3] and z >= zn[4] and x <= zn[5] and y <= zn[6] and z <= zn[7] then return zn[1] end
    end
    return 'Неизвестно'
end
function H.direction(handle, isCar)
    if isCar then
        if not doesVehicleExist(handle) then return 'Неизвестно' end
    elseif not doesCharExist(handle) then
        return 'Неизвестно'
    end
    local a = math.floor(isCar and getCarHeading(handle) or getCharHeading(handle))
    if (a >= 0 and a <= 30) or (a <= 360 and a >= 330) then return 'Север'
    elseif a > 80 and a < 100 then return 'Запад'
    elseif a > 260 and a < 280 then return 'Восток'
    elseif a >= 170 and a <= 190 then return 'Юг'
    elseif a >= 31 and a <= 79 then return 'Северо-запад'
    elseif a >= 191 and a <= 259 then return 'Юго-восток'
    elseif a >= 81 and a <= 169 then return 'Юго-запад'
    elseif a >= 259 and a <= 329 then return 'Северо-восток' end
    return a .. ' град.'
end

function H.msk() return os.time() + 3 * 3600 end
function H.pf(s) return binder.trim(ffi.string(profile[s])) end

binder.tagList, binder.tags, binder.funcList, binder.funcs = {}, {}, {}, {}
binder.alsoFunc = { name = true, surname = true, namesurname = true, posx = true, posy = true,
                    posz = true, city = true, square = true, area = true, direction = true, gun = true }

local function defTag(name, desc, ex, exec)
    local t = { name = name, desc = desc, ex = ex, exec = exec }
    binder.tagList[#binder.tagList + 1] = t
    binder.tags[name] = t
end
local function defFunc(name, desc, ex, exec)
    local t = { name = name, desc = desc, ex = ex, exec = exec }
    binder.funcList[#binder.funcList + 1] = t
    binder.funcs[name] = t
end

defFunc('namesurname', 'Возвращает имя и фамилию по ID, либо ваши, если игрока нет в сети',
    'Доброго времени суток, <namesurname({nearplayer})>, предъявите документы.\nДоброго времени суток, <namesurname({param1})>, предъявите документы.',
    function(arg) return binder.funcs.name.exec(arg) .. ' ' .. binder.funcs.surname.exec(arg) end)
defFunc('name', 'Возвращает имя по ID, либо ваше, если игрока нет в сети',
    'Мистер <name({nearplayer})>, вы прекрасно выглядите!\nМистер <name({param1})>, вы прекрасно выглядите!',
    function(arg)
        local id = tonumber(arg)
        local pn = H.pf('name')
        if not id and pn ~= '' then return pn end
        local nick = H.nick(H.pid(arg))
        return nick:match('^(.+)[_ ]') or nick
    end)
defFunc('surname', 'Возвращает фамилию по ID, либо вашу, если игрока нет в сети',
    'Мистер <surname({nearplayer})>, вы имеете право хранить молчание.\nМистер <surname({param1})>, вы имеете право хранить молчание.',
    function(arg)
        local id = tonumber(arg)
        local ps = H.pf('surname')
        if not id and ps ~= '' then return ps end
        local nick = H.nick(H.pid(arg))
        return nick:match('[_ ](.+)$') or nick
    end)
defFunc('score', 'Возвращает уровень по ID, либо ваш, если игрока нет в сети',
    '/b У тебя <score({nearplayer})> уровень.\n/b У него <score({param1})> уровень.',
    function(arg) return sampGetPlayerScore(H.pid(arg)) end)
defFunc('ping', 'Возвращает пинг по ID, либо ваш, если игрока нет в сети',
    '/b У тебя <ping({nearplayer})> пинг.\n/b У него <ping({param1})> пинг.',
    function(arg) return sampGetPlayerPing(H.pid(arg)) end)
defFunc('color', 'Возвращает цвет в формате HEX по ID, либо ваш, если игрока нет в сети',
    '#Начинаю арестовывать {<color({param1})>}<namesurname({param1})>',
    function(arg) return H.chatColor(H.pid(arg)) end)
defFunc('gun', 'Возвращает название оружия игрока по ID, либо ваше, если игрока нет в сети',
    '/me взял <gun({nearplayer})> у <namesurname({nearplayer})>',
    function(arg) return H.weaponName(getCurrentCharWeapon(H.char(arg))) end)
defFunc('carid', 'Возвращает идентификатор транспорта по ID игрока, либо -1, если игрока нет в сети или он не в машине',
    '/r Преследую машину марки <carname(carid({param1}))>, его водитель: <namesurname({param1})>.',
    function(arg)
        local h = H.charStrict(H.pid(arg))
        if not h or not isCharInAnyCar(h) then return -1 end
        return storeCarCharIsInNoSave(h) + 50000
    end)
defFunc('carname', 'Возвращает название транспорта по идентификатору транспорта',
    '/r Преследую машину марки <carname({nearcar})>.',
    function(arg)
        local veh = H.vehicle(arg)
        if not veh then return 'Нет' end
        return u8:encode(getGxtText(getNameOfVehicleModel(getCarModel(veh))) or 'Нет')
    end)
defFunc('carplate', 'Возвращает номерные знаки транспорта по идентификатору транспорта',
    '/r Преследую машину марки <carname({nearcar})>, номерные знаки: <carplate({nearcar})>.',
    function(arg)
        local veh = H.vehicle(arg)
        if not veh then return 'Нет' end
        local ok, vid = sampGetVehicleIdByCarHandle(veh)
        if not ok then return 'Нет' end
        local okP, plate = pcall(sampGetLicensePlateText, vid)
        if not okP or not plate then return 'Нет' end
        plate = plate:gsub('{......}', '')
        if binder.trim(plate) == '' then return 'Нет номеров' end
        return u8:encode(plate)
    end)
defFunc('cardriver', 'Возвращает ID водителя транспорта по идентификатору транспорта',
    '/r Преследую машину марки <carname({nearcar})>, ID водителя: <cardriver({nearcar})>.',
    function(arg)
        local me = H.myId()
        local veh = H.vehicle(arg)
        if not veh then return me end
        local drv = getDriverOfCar(veh)
        if drv and doesCharExist(drv) then
            local ok, id = sampGetPlayerIdByCharHandle(drv)
            if ok and H.valid(id) then return id end
        end
        return me
    end)
defFunc('carcolor', 'Возвращает цвет транспорта по идентификатору транспорта',
    '/r Преследую <carcolor({nearcar})> <carname({nearcar})>.',
    function(arg)
        local veh = H.vehicle(arg)
        if not veh then return 'Нет' end
        local c1 = getCarColours(veh)
        return PH_COLORS[c1] or ''
    end)
local posEx = '/r Он находится на X: <posx({param1})>; Y: <posy({param1})>; Z: <posz({param1})>.\nЯ нашёл ту машину, она на X: <posx({nearcar})>; Y: <posy({nearcar})>; Z: <posz({nearcar})>.'
defFunc('posx', 'Возвращает позицию по X транспорта по идентификатору транспорта, либо игрока по ID', posEx,
    function(arg) return string.format('%.2f', (H.where(arg))) end)
defFunc('posy', 'Возвращает позицию по Y транспорта по идентификатору транспорта, либо игрока по ID', posEx,
    function(arg) return string.format('%.2f', select(2, H.where(arg))) end)
defFunc('posz', 'Возвращает позицию по Z транспорта по идентификатору транспорта, либо игрока по ID', posEx,
    function(arg) return string.format('%.2f', select(3, H.where(arg))) end)
defFunc('city', 'Возвращает город по позиции транспорта или игрока',
    '/r Он находится в городе <city({param1})>\nЯ нашёл ту машину в городе <city({nearcar})>',
    function(arg) return H.city(H.where(arg)) end)
defFunc('square', 'Возвращает квадрат по позиции транспорта или игрока',
    '/r Он находится в квадрате <square({param1})>\nЯ нашёл ту машину в квадрате <square({nearcar})>',
    function(arg) local x, y = H.where(arg); return H.square(x, y) end)
defFunc('area', 'Возвращает район по позиции транспорта или игрока',
    '/r Он находится в районе <area({param1})>\nЯ нашёл ту машину в районе <area({nearcar})>',
    function(arg) return H.area(H.where(arg)) end)
defFunc('direction', 'Возвращает направление движения транспорта или игрока',
    '/r Он направляется на <direction({param1})>\nМашина направляется на <direction({nearcar})>',
    function(arg)
        local veh = H.vehicle(arg)
        if veh then return H.direction(veh, true) end
        return H.direction(H.char(arg), false)
    end)
defFunc('dialog', 'Запускает диалоговое окно по его UID',
    '#Начинаю арест игрока <name({param1})>.\n<dialog(12)>',
    function(arg)
        local uid = tonumber(arg)
        if uid then
            if not binder.findDialog(uid) then
                binder.say('Диалог с UID {aaaaaa}' .. uid .. '{ffffff} не найден. Запуск диалогового окна невозможен.')
            else
                binder.dlgFlush()
                binder.dlgPush(uid)
            end
        end
        return ''
    end)
defFunc('random', 'Возвращает случайное число в диапазоне',
    '#Я загадал число от 1 до 100000 и получилось: <random(1, 100000)>',
    function(arg)
        local a = tonumber(arg:match('^(%d+)'))
        local b = tonumber(arg:match('(%d+)$'))
        if b == nil or b == a then b = a; a = 1 end
        if a == nil or b == nil then return '' end
        if a > b then a, b = b, a end
        return tostring(math.random(a, b))
    end)

defTag('greeting', 'Возвращает приветствие в зависимости от времени суток по московскому времени',
    '{greeting}, вас беспокоит {rank} {fraction} {namesurname}.\nПредъявите документы, удостоверяющие вашу личность.',
    function()
        local h = tonumber(os.date('!%H', H.msk()))
        if h <= 4 then return 'Доброй ночи'
        elseif h <= 12 then return 'Доброе утро'
        elseif h <= 16 then return 'Добрый день' end
        return 'Добрый вечер'
    end)
defTag('id', 'Возвращает ваш ID', 'Мой ID - {id}', function() return H.myId() end)
defTag('?', 'Возвращает окончание -а, если выбран женский пол, либо ничего, если мужской',
    '/me взял{?} стакан со стола', function() return profile.sex == 0 and '' or 'а' end)
defTag('??', 'Возвращает окончание -ась, если выбран женский пол, либо -ся, если мужской',
    '/me ухватил{??} за канат', function() return profile.sex == 0 and 'ся' or 'ась' end)
defTag('???', 'Возвращает окончание -ла, если выбран женский пол, либо -ел, если мужской',
    '/me выш{???} из машины\n/me пош{???} за рацией.', function() return profile.sex == 0 and 'ел' or 'ла' end)
defTag('nearplayer', 'Возвращает ID ближайшего игрока', 'Рядом со мной игрок с ID {nearplayer}',
    function()
        local best = 99999
        local res = H.myId()
        local px, py, pz = getCharCoordinates(PLAYER_PED)
        local myCar = isCharInAnyCar(PLAYER_PED) and storeCarCharIsInNoSave(PLAYER_PED) or false
        for _, ch in ipairs(getAllChars()) do
            local ok, id = sampGetPlayerIdByCharHandle(ch)
            if ok and id ~= -1 and H.valid(id) then
                local x, y, z = getCharCoordinates(ch)
                local d = getDistanceBetweenCoords3d(px, py, pz, x, y, z)
                if d < sampGetNametagRenderDistance() and d < best then
                    if myCar and isCharInAnyCar(ch) then
                        if storeCarCharIsInNoSave(ch) ~= myCar then best, res = d, id end
                    else
                        best, res = d, id
                    end
                end
            end
        end
        return res
    end)
local function nearCar(needDriver)
    local best, found = 99999, nil
    local px, py, pz = getCharCoordinates(PLAYER_PED)
    local myCar = isCharInAnyCar(PLAYER_PED) and storeCarCharIsInNoSave(PLAYER_PED) or false
    for _, v in ipairs(getAllVehicles()) do
        local x, y, z = getCarCoordinates(v)
        local d = getDistanceBetweenCoords3d(px, py, pz, x, y, z)
        if d < best and (not needDriver or doesCharExist(getDriverOfCar(v))) then
            if not myCar or v ~= myCar then best, found = d, v end
        end
    end
    return found and found + 50000 or myCar and myCar + 50000 or -1
end
defTag('nearcar', 'Возвращает идентификатор ближайшего транспорта, либо ваш, если рядом нет машин',
    'Марка этой машины - <carname({nearcar})>', function() return nearCar(false) end)
defTag('nearcarwithdriver', 'Возвращает идентификатор ближайшего транспорта с водителем, либо ваш, если поблизости нет таковых',
    '/m Водитель <carname({nearcarwithdriver})> под ID <cardriver({nearcarwithdriver})> с номерными знаками <carplate({nearcarwithdriver})>, приказываю прижаться к обочине!',
    function() return nearCar(true) end)

binder.CAR_COLORS_GEN = {
    [0] = "чёрного", [1] = "белого", [2] = "бирюзового", [3] = "бордового", [4] = "хвойного", [5] = "пурпурного", [6] = "жёлтого", [7] = "голубого", [8] = "серого",
    [9] = "оливкового", [10] = "синего", [11] = "серого", [12] = "голубого", [13] = "графитового", [14] = "светлого", [15] = "светлого", [16] = "хвойного", [17] = "бордового",
    [18] = "бордового", [19] = "серого", [20] = "синего", [21] = "бордового", [22] = "бордового", [23] = "серого", [24] = "графитового", [25] = "серого", [26] = "светлого",
    [27] = "тусклого", [28] = "синего", [29] = "светлого", [30] = "бордового", [31] = "бордового", [32] = "голубоватого", [33] = "серого", [34] = "тусклого",
    [35] = "коричневого", [36] = "синего", [37] = "хвойного", [38] = "серого", [39] = "синего", [40] = "тёмного", [41] = "коричневого", [42] = "коричневого",
    [43] = "бордового", [44] = "хвойного", [45] = "бордового", [46] = "бежевого", [47] = "оливкового", [48] = "оливкового", [49] = "серого", [50] = "серебристого",
    [51] = "хвойного", [52] = "синего", [53] = "синего", [54] = "синего", [55] = "коричневого", [56] = "голубого", [57] = "оливкового", [58] = "тёмнокрасного",
    [59] = "синего", [60] = "светлого", [61] = "оранжевого", [62] = "тёмнокрасного", [63] = "серебристого", [64] = "светлого", [65] = "оливкового", [66] = "коричневого",
    [67] = "асфальтового", [68] = "оливкового", [69] = "кварцевого", [70] = "тёмнокрасного", [71] = "светлого", [72] = "тёмносерого", [73] = "оливкового", [74] = "бордового",
    [75] = "синего", [76] = "оливкового", [77] = "оранжевого", [78] = "бордового", [79] = "синего", [80] = "розового", [81] = "оливкового", [82] = "тёмнокрасного",
    [83] = "бирюзового", [84] = "коричневого", [85] = "розового", [86] = "хвойного", [87] = "синего", [88] = "винного", [89] = "оливкового", [90] = "светлого",
    [91] = "тёмносинего", [92] = "тёмносерого", [93] = "голубоватого", [94] = "синего", [95] = "синего", [96] = "светлого", [97] = "асфальтового", [98] = "голубоватого",
    [99] = "коричневого", [100] = "бриллиантового", [101] = "кобальтового", [102] = "коричневого", [103] = "синего", [104] = "коричневого", [105] = "серого", [106] = "синего",
    [107] = "оливкового", [108] = "бриллиантового", [109] = "серого", [110] = "оливкового", [111] = "серого", [112] = "серого", [113] = "коричневого", [114] = "зелёного",
    [115] = "тёмнокрасного", [116] = "синего", [117] = "бордового", [118] = "голубого", [119] = "коричневого", [120] = "оливкового", [121] = "бордового", [122] = "тёмносерого",
    [123] = "коричневого", [124] = "тёмнокрасного", [125] = "синего", [126] = "розового", [127] = "чёрного", [128] = "зелёного", [129] = "бордового", [130] = "синего",
    [131] = "коричневого", [132] = "тёмнокрасного", [133] = "чёрного", [134] = "фиолетового", [135] = "яркосинего", [136] = "аметистового", [137] = "зелёного", [138] = "серого",
    [139] = "пурпурного", [140] = "светлого", [141] = "тёмносерого", [142] = "оливкового", [143] = "фиолетового", [144] = "фиолетового", [145] = "зелёного", [146] = "пурпурного",
    [147] = "фиолетового", [148] = "оливкового", [149] = "тёмного", [150] = "тёмнозелёного", [151] = "зеленого", [152] = "синего", [153] = "зелёного", [154] = "салатового",
    [155] = "бирюзового", [156] = "коричневого", [157] = "светлого", [158] = "оранжевого", [159] = "коричневого", [160] = "тёмнозелёного", [161] = "винного", [162] = "синего",
    [163] = "графитового", [164] = "чёрного", [165] = "бирюзового", [166] = "бирюзового", [167] = "фиолетового", [168] = "бордового", [169] = "фиолетового", [170] = "фиолетового",
    [171] = "фиолетового", [172] = "хвойного", [173] = "коричневого", [174] = "коричневого", [175] = "коричневого", [176] = "пурпурного", [177] = "пурпурного", [178] = "пурпурного",
    [179] = "фиолетового", [180] = "коричневого", [181] = "красного", [182] = "оранжевого", [183] = "оливкового", [184] = "голубого", [185] = "чёрного", [186] = "чёрного",
    [187] = "зелёного", [188] = "зелёного", [189] = "зелёного", [190] = "пурпурного", [191] = "салатового", [192] = "светлого", [193] = "светлого", [194] = "оливкового",
    [195] = "оливкового", [196] = "серого", [197] = "оливкового", [198] = "синего", [199] = "оливкового", [200] = "странного", [201] = "синего", [202] = "зелёного", [203] = "синего",
    [204] = "голубого", [205] = "синего", [206] = "тёмносинего", [207] = "голубого", [208] = "синего", [209] = "синего", [210] = "синего", [211] = "фиолетового",
    [212] = "оранжевого", [213] = "светлого", [214] = "оливкового", [215] = "чёрного", [216] = "оранжевого", [217] = "бирюзового", [218] = "бледно-розового", [219] = "оранжевого",
    [220] = "розового", [221] = "оливкового", [222] = "оранжевого", [223] = "синего", [224] = "бордового", [225] = "хвойного", [226] = "салатового", [227] = "зелёного",
    [228] = "бледного", [229] = "салатового", [230] = "бордового", [231] = "коричневого", [232] = "розового", [233] = "пурпурного", [234] = "тёмнозелёного", [235] = "оливкового",
    [236] = "хвойного", [237] = "пурпурного", [238] = "оранжевого", [239] = "коричневого", [240] = "голубого", [241] = "зеленого", [242] = "фиолетового", [243] = "зелёного",
    [244] = "коричневого", [245] = "хвойного", [246] = "голубого", [247] = "синего", [248] = "бордового", [249] = "бордового", [250] = "серого", [251] = "серого", [252] = "чёрного",
    [253] = "серого", [254] = "коричневого", [255] = "синего"
}

defFunc('carinfo', 'Возвращает готовое описание транспорта: марка, цвет и номера. Если транспорта нет - «транспортного средства»',
    '/me осматривает <carinfo({nearcar})>\n/r Преследую <carinfo({nearcarwithdriver})>.',
    function(arg)
        local veh = H.vehicle(arg)
        if not veh then return 'транспортного средства' end
        local out = binder.funcs.carname.exec(arg)
        local okC, c1 = pcall(getCarColours, veh)
        local cn = okC and binder.CAR_COLORS_GEN[c1]
        if cn then out = out .. ' ' .. cn .. ' цвета' end
        local plate = binder.funcs.carplate.exec(arg)
        if plate ~= 'Нет' and plate ~= 'Нет номеров' then out = out .. ' с номерами ' .. plate end
        return out
    end)
defTag('nearcarinfo', 'Возвращает описание ближайшего транспорта: марка, цвет и номера (например «Infernus чёрного цвета с номерами A123BC»)',
    '/me осматривает {nearcarinfo}', function() return binder.funcs.carinfo.exec(nearCar(false)) end)
defTag('nearcarwithdriverinfo', 'Возвращает описание ближайшего транспорта с водителем: марка, цвет и номера',
    '/m Водитель {nearcarwithdriverinfo}, прижмитесь к обочине!', function() return binder.funcs.carinfo.exec(nearCar(true)) end)
defTag('fraction', 'Возвращает вашу фракцию, вписанную в профиле', 'Я состою в {fraction}', function() return H.pf('fraction') end)
defTag('rank', 'Возвращает ваш ранг, вписанный в профиле', 'Моё звание - {rank}', function() return H.pf('rank') end)
defTag('phone', 'Возвращает ваш номер телефона, вписанный в профиле', 'Звоните на мой номер телефона - {phone}', function() return H.pf('phone') end)
defTag('callsign', 'Возвращает ваш позывной, вписанный в профиле', 'Мой позывной - {callsign}', function() return H.pf('callsign') end)
defTag('target', 'Возвращает ID вашей цели (цель задаётся командой /mark ID). Если диалог открыт по клавише с ПКМ-прицелом на игрока - его ID, только на одну отыгровку',
    'Моя цель - {target}\nЯ вижу <namesurname({target})>. Его позиция: <posx({target})>',
    function()
        local t = binder.runTarget
        if t and H.valid(t) then return t end
        if binder.target.id ~= -1 and not H.valid(binder.target.id) then binder.target.id = -1 end
        return binder.target.id
    end)
defTag('time', 'Возвращает текущее время по МСК', '/do Текущее время на часах: {time}',
    function() return os.date('!%H:%M:%S', H.msk()) end)
defTag('date', 'Возвращает текущую дату по МСК', '/do Текущая дата на календаре: {date}',
    function() return os.date('!%d.%m.%Y', H.msk()) end)

binder.help = {
    { head = 'Возможности', items = {
        { tok = '<X>', ins = '<1500>', desc = 'Задержка отыгровки, время указывается в миллисекундах. 1 секунда = 1000 миллисекунд',
          ex = '/me ухватил{??} за дробовик\n<2000>\n/me нажал на курок' },
        { tok = '#', ins = '#', desc = 'Отправляет сообщение в ваш чат, а не серверу.',
          ex = '#Начинаю арестовывать {<color({param1})>}<namesurname({param1})>' },
        { tok = '*', ins = '*', desc = 'Делает скриншот экрана',
          ex = '/time\n<300>\n*' },
        { tok = '<!>', ins = '<!>', desc = 'Приостанавливает отыгровку, пока вы не нажмёте клавишу продолжения (вкладка Биндер, плашка «Продолжить»).',
          ex = '{greeting}, я ваш лечащий врач {namesurname}. Что вас беспокоит?\n<!>\nХорошо, я вас понял.' },
        { tok = '>>X', ins = '>>', desc = 'Вписывает в поле ввода чата указанный текст и открывает чат',
          ex = '>>/cuff ' },
        { tok = '>>>X', ins = '>>>', desc = 'Эмулирует отправку текста в чат. Полезно, чтобы запустить другой бинд, не повторяя его отыгровку',
          ex = '>>>/arrest {param1}' },
    } },
    { head = 'Параметры', items = {
        { tok = '{paramX}', ins = '{param1}', desc = 'Возвращает X-ый параметр, указанный при использовании команды активации',
          ex = '/cuff {param1}\n/pay {param1} {param2}\n/r Арестовываю <name({param1})> ({param1}) на {param2} секунд за {param3full}.' },
        { tok = '{paramXfull}', ins = '{param2full}', desc = 'Возвращает все параметры, начиная с X-го (X от 2 до 5)',
          ex = '/ticket {param1} {param2} {param3full}\n/su {param1} {param2} {param3full}' },
        { tok = '{paramfull}', ins = '{paramfull}', desc = 'Возвращает все параметры команды целиком',
          ex = '/r (( {paramfull} ))' },
    } },
    { head = 'Теги', items = {} },
    { head = 'Функции', items = {} },
}
for _, t in ipairs(binder.tagList) do
    table.insert(binder.help[3].items, { tok = '{' .. t.name .. '}', ins = '{' .. t.name .. '}', desc = t.desc, ex = t.ex })
end
for _, f in ipairs(binder.funcList) do
    table.insert(binder.help[4].items, { tok = '<' .. f.name .. '()>', ins = '<' .. f.name .. '()>', desc = f.desc, ex = f.ex })
end
table.insert(binder.help[3].items, { tok = '{rpId()}', ins = '{rpId()}',
    desc = 'Возвращает ID цифрами через дефис: 1 - 0-0-1, 10 - 0-1-0, 123 - 1-2-3. Без аргумента берётся ваш ID, иначе указанный: {rpId({param1})}',
    ex = '/r Запрос розыска, мой ID {rpId()}\n/r Прошу проверить ID {rpId({param1})}' })

binder.helpKpk = {
    { head = 'КПК', items = {
        { tok = '{kpkID}', ins = '{kpkID}', desc = 'ID игрока, указанный в команде (например, /asu ID)',
          ex = '/me достал{?} КПК и открыл{?} дело на <namesurname({kpkID})>' },
        { tok = '{kpkcell}', ins = '{kpkcell}', desc = 'Номер камеры (только для карцера: /carc ID камера)',
          ex = '/me проводил{?} задержанного в камеру {kpkcell}' },
        { tok = '{kpkcmd}', ins = '{kpkcmd}', desc = 'Команда статьи (/su, /ticket, /carcer, /punish). Если тега нет, команда отправится последней строкой через 1.5 сек',
          ex = '/me заполнил{?} постановление\n<1500>\n{kpkcmd}' },
        { tok = '{kpkarticle}', ins = '{kpkarticle}', desc = 'Описание выбранной статьи',
          ex = '/do На экране КПК: {kpkarticle}.' },
        { tok = '{kpkreason}', ins = '{kpkreason}', desc = 'Причина выбранной статьи',
          ex = '/r Задержан за {kpkreason}' },
        { tok = '{kpkvalue}', ins = '{kpkvalue}', desc = 'Значение статьи: уровень, сумма, минуты или степень',
          ex = '/r Выписан штраф на сумму {kpkvalue}' },
    } },
    binder.help[1], binder.help[3], binder.help[4],
}

binder.helpKpkCache = {}
function binder.helpKpkFor(e)
    local h = binder.helpKpkCache[e.id]
    if h then return h end
    local si = e.si
    local valDesc = ({
        'Уровень розыска (1-6)',
        'Сумма штрафа (100 000 - 3 000 000)',
        'Степень повышения срока (1-10)',
        'Время в карцере, минуты (1-30)',
    })[si]
    local valEx = ({
        '/r Выдан розыск {kpkvalue} ур.',
        '/r Выписан штраф на сумму {kpkvalue}',
        '/r Срок повышен на {kpkvalue} ст.',
        '/r Посажен в карцер на {kpkvalue} мин.',
    })[si]
    local items = {
        { tok = '{kpkID}', ins = '{kpkID}', desc = 'ID игрока, указанный в команде',
          ex = '/me достал{?} КПК и открыл{?} дело на <namesurname({kpkID})>' },
    }
    if si == 4 then
        items[#items + 1] = { tok = '{kpkcell}', ins = '{kpkcell}', desc = 'Номер камеры (/carc ID камера)',
          ex = '/me проводил{?} задержанного в камеру {kpkcell}' }
    end
    local more = {
        { tok = '{kpkcmd}', ins = '{kpkcmd}', desc = 'Команда статьи. Если тега нет, команда отправится последней строкой через 1.5 сек',
          ex = '/me заполнил{?} постановление\n<1500>\n{kpkcmd}' },
        { tok = '{kpkarticle}', ins = '{kpkarticle}', desc = 'Описание выбранной статьи',
          ex = '/do На экране КПК: {kpkarticle}.' },
        { tok = '{kpkreason}', ins = '{kpkreason}', desc = 'Причина выбранной статьи',
          ex = '/r Причина: {kpkreason}' },
        { tok = '{kpkvalue}', ins = '{kpkvalue}', desc = valDesc, ex = valEx },
    }
    for _, it in ipairs(more) do items[#items + 1] = it end
    h = { { head = 'КПК: ' .. e.title, items = items }, binder.help[1], binder.help[3], binder.help[4] }
    binder.helpKpkCache[e.id] = h
    return h
end

binder.helpSys = {
    kpk = binder.helpKpk,
    afind = {
        { head = 'Автопоиск', items = {
            { tok = '{param1}', ins = '{param1}', desc = 'ID игрока, за которым ведётся автопоиск',
              ex = '/me достал{?} КПК и включил{?} слежение за <namesurname({param1})>' },
        } },
        binder.help[1], binder.help[3], binder.help[4],
    },
    wanted = {
        { head = 'КПК', items = {
            { tok = '{kpkID}', ins = '{kpkID}', desc = 'ID игрока из окна статей /asu',
              ex = '/r Прошу проверить ID {kpkID}' },
            { tok = '{kpkarticle}', ins = '{kpkarticle}', desc = 'Описание статьи, рядом с которой нажата кнопка',
              ex = '/do На экране КПК: {kpkarticle}.' },
            { tok = '{kpkreason}', ins = '{kpkreason}', desc = 'Причина статьи, рядом с которой нажата кнопка',
              ex = '/r Запрашиваю розыск, причина: {kpkreason}' },
            { tok = '{kpkvalue}', ins = '{kpkvalue}', desc = 'Уровень розыска статьи, рядом с которой нажата кнопка',
              ex = '/r Статья на {kpkvalue} ур. розыска' },
        } },
        binder.help[1], binder.help[3], binder.help[4],
    },
    pursuit = {
        { head = 'Погоня', items = {
            { tok = '{param1}', ins = '{param1}', desc = 'ID игрока, за которым начинается или заканчивается погоня',
              ex = '/me нажал{?} на КПК кнопку начала погони за <namesurname({param1})>' },
            { tok = '{syscmd}', ins = '{syscmd}', desc = 'Команда погони (/pursuit ID). Если тега нет, команда отправится последней строкой через 1.5 сек',
              ex = '/me включил{?} режим погони\n<1500>\n{syscmd}' },
        } },
        binder.help[1], binder.help[3], binder.help[4],
    },
}

function binder.tagGroups()
    if editMode == 'kpk' then return binder.helpKpk end
    if editMode == 'sys' then
        local e = binder.sysEd.e
        if e and e.kind == 'kpk' then return binder.helpKpkFor(e) end
        return (e and binder.helpSys[e.kind]) or binder.help
    end
    return binder.help
end

binder.wrapCache, binder.wrapN, binder.wrapInfo = {}, 0, {}
function binder.wrap(text, w)
    local info = binder.wrapInfo[text]
    if not info then
        local norm = text:gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', '')
        info = { norm = norm, w = imgui.CalcTextSize(norm).x, one = { norm } }
        if binder.wrapN > 6000 then binder.wrapInfo, binder.wrapCache, binder.wrapN = {}, {}, 0 end
        binder.wrapN = binder.wrapN + 1
        binder.wrapInfo[text] = info
    end
    if info.w <= w then return info.one end
    local wi = math.floor(w + 0.5)
    local bucket = binder.wrapCache[wi]
    if not bucket then bucket = {}; binder.wrapCache[wi] = bucket end
    local cached = bucket[text]
    if cached then return cached end
    local lines, cur = {}, ''
    for word in info.norm:gmatch('%S+') do
        local try = (cur == '') and word or (cur .. ' ' .. word)
        if cur ~= '' and imgui.CalcTextSize(try).x > wi then
            lines[#lines + 1] = cur; cur = word
        else
            cur = try
        end
    end
    if cur ~= '' then lines[#lines + 1] = cur end
    bucket[text] = lines
    return lines
end

function binder.say(msg)
    msg = tostring(msg):gsub('{aaaaaa}', '{AAAAAA}')
    sampAddChatMessage(u8:decode('{5B78EE}[Ranger Helper]{FFFFFF}: ' .. msg), -1)
end

local function plural(n, a, b, c)
    local m10, m100 = n % 10, n % 100
    if m10 == 1 and m100 ~= 11 then return a end
    if m10 >= 2 and m10 <= 4 and (m100 < 10 or m100 >= 20) then return b end
    return c
end

function binder.takeScreen()
    pcall(function()
        local fn = ffi.cast('void (*__stdcall)()', sampGetBase() + (getGameGlobal(707) <= 21 and 462784 or 478896))
        fn()
    end)
end

function binder.applyParams(text, args, params)
    for i, v in ipairs(args) do
        if v ~= '' then text = text:gsub('{param' .. i .. '}', function() return v end) end
    end
    local pat = '(.+)$'
    for n = 2, 5 do
        pat = '.-%s+' .. pat
        local full = params:match(pat)
        if full ~= nil then text = text:gsub('{param' .. n .. 'full}', function() return full end) end
    end
    text = text:gsub('{paramfull}', function() return params end)
    text = text:gsub('{param1full}', function() return params end)
    return text
end

function binder.callFunc(name, arg)
    local f = binder.funcs[name:lower()]
    if not f then return nil end
    arg = binder.trim(arg)
    local inner, iarg = arg:match('^(%a+)%s*%((.*)%)$')
    if inner and binder.funcs[inner:lower()] then
        local r = binder.callFunc(inner, iarg)
        if r ~= nil then arg = r end
    end
    local ok, res = pcall(f.exec, arg)
    if not ok then return '' end
    return tostring(res)
end

function binder.expandLine(line)
    line = line:gsub('{%s*([A-Za-z?]+)%s*}', function(t)
        local tl = t:lower()
        local tag = binder.tags[tl]
        if tag then
            local ok, r = pcall(tag.exec)
            return ok and tostring(r) or ''
        end
        if binder.alsoFunc[tl] then
            local ok, r = pcall(binder.funcs[tl].exec, '')
            return ok and tostring(r) or ''
        end
        return nil
    end)
    line = line:gsub('{%s*[Rr][Pp][Ii][Dd]%s*%(%s*(.-)%s*%)%s*}', function(arg)
        return H.rpId(arg)
    end)
    line = line:gsub('<%s*(%a+)%s*%((.-)%)%s*>', function(name, arg)
        return binder.callFunc(name, arg)
    end)
    return line
end

function binder.asScript(fn, ...)
    binder.fromScript = (binder.fromScript or 0) + 1
    local ok, err = pcall(fn, ...)
    binder.fromScript = math.max(0, (binder.fromScript or 1) - 1)
    if not ok then error(err, 0) end
end

function binder.sendLine(line)
    return binder.asScript(binder.sendLineRaw, line)
end

function binder.sendLineRaw(line)
    local s = u8:decode(line)
    if s:sub(1, 1) == '/' then
        local cmd = s:match('^/(%S+)')
        local own = false
        if cmd then
            for name in pairs(binder.cmds) do
                if name:lower() == cmd:lower() then own = true; break end
            end
        end
        if cmd and not own and sampIsChatCommandDefined(cmd:lower()) then
            sampProcessChatInput(s)
        else
            sampSendChat(s)
        end
    else
        sampSendChat(s)
    end
end

function binder.play(text, args, params)
    args, params = args or {}, params or ''
    text = binder.applyParams(text, args, params)

    local seen, missing = {}, 0
    for n, rest in text:gmatch('{param(%d+)(.-)}') do
        if not seen[n] then
            binder.say('Параметр {aaaaaa}№' .. n .. '{ffffff} не указан, тег {aaaaaa}{param' .. n .. rest .. '}{ffffff} остался неизменным.')
            seen[n] = true
            missing = missing + 1
        end
    end
    if missing > 0 then
        binder.say('Пожалуйста, укажите {aaaaaa}' .. missing .. '{ffffff} ' ..
            plural(missing, 'недостающий аргумент', 'недостающих аргумента', 'недостающих аргументов') ..
            ', чтобы воспроизвести отыгровку.')
        return false
    end

    local ctx = binder.dlgTarget
    if ctx and not H.valid(ctx) then ctx = nil end
    if text:lower():find('{%s*target%s*}') then
        local tid = ctx or binder.target.id
        if tid ~= -1 and not H.valid(tid) then binder.target.id = -1; tid = -1 end
        if tid == -1 then
            binder.say('Цель не выбрана, тег {aaaaaa}{target}{ffffff} использовать нельзя.')
            binder.say('Выберите цель командой {aaaaaa}/' .. binder.mark.cmd .. ' ID{ffffff}, затем повторите отыгровку.')
            return false
        end
    end

    for i = #binder.threads, 1, -1 do
        local st = binder.threads[i]:status()
        if st == 'dead' or st == 'error' then table.remove(binder.threads, i) end
    end
    if #binder.threads == 0 then binder.paused = false end

    local th = lua_thread.create(function()
        local ok, err = pcall(function()
            local last = -100
            for raw in text:gmatch('[^\r\n]+') do
                while binder.paused do wait(50) end
                local line = binder.trim(raw)
                if line == '*' then
                    binder.takeScreen()
                elseif line == '<!>' then
                    local key = binder.parseKey(binder.hotkeyOf(HK_RESUME))
                    if not key then
                        binder.say('Не удалось поставить отыгровку на паузу.')
                        binder.say('Не задана клавиша продолжения (вкладка Биндер, плашка «Продолжить»).')
                    else
                        binder.say('Отыгровка приостановлена. Нажмите {aaaaaa}[ ' .. binder.hotkeyOf(HK_RESUME) .. ' ]{ffffff}, чтобы продолжить.')
                        binder.resume = false
                        while not binder.resume do wait(50) end
                        binder.resume = false
                    end
                else
                    local ms = line:match('^<%s*(%d+)%s*>$')
                    if ms then

                        local left = tonumber(ms)
                        while left > 0 do
                            if binder.paused then
                                wait(50)
                            else
                                local d = math.min(50, left)
                                wait(d); left = left - d
                            end
                        end
                    else
                        binder.runTarget = ctx
                        line = binder.trim(binder.expandLine(line))
                        binder.runTarget = nil
                        if line ~= '' then
                            local note = line:match('^#%s?(.+)')
                            if note then
                                binder.say(note)
                            else
                                if os.clock() - last < 1.2 and not binder.noDelayWarned then
                                    binder.say('По всей видимости, вы не поставили задержку между строками, либо поставили её менее 1.2 сек.')
                                    binder.say('Из-за этого отыгровка может быть заблокирована анти-флуд системой сервера. Добавьте задержку, например: {aaaaaa}<1500>')
                                    binder.noDelayWarned = true
                                end
                                last = os.clock()
                                local x3 = line:match('^>>>%s?(.+)')
                                local x2 = line:match('^>>%s?(.+)')
                                if x3 then
                                    wait(20)
                                    binder.asScript(sampProcessChatInput, u8:decode(x3))
                                elseif x2 then
                                    wait(20)
                                    sampSetChatInputText(u8:decode(x2))
                                    sampSetChatInputEnabled(true)
                                    while sampIsChatInputActive() do wait(0) end
                                else
                                    if line:sub(1, 1) == '\1' then

                                        binder.asScript(sampSendChat, u8:decode(line:sub(2)))
                                    else
                                        binder.sendLine(line)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end)
        if not ok then print('[RangerHelper] ошибка отыгровки: ' .. tostring(err)) end
    end)
    binder.threads[#binder.threads + 1] = th
    return true
end

local weaponById = {}
for _, w in ipairs(weapons) do weaponById[w.id] = w end
local weaponThread = nil

local function oneMe(s)
    s = binder.trim(s)
    if s:find('[\r\n]') then return nil end
    return s:match('^/[mM][eE]%s+(.+)$')
end

function binder.weaponText(old, new)
    local o = weaponById[old]; if o and not o.on then o = nil end
    local n = weaponById[new]; if n and not n.on then n = nil end
    if o and n then
        local a, b = oneMe(o.put), oneMe(n.take)
        if a and b then return '/me ' .. a .. ', после чего ' .. b end
        return o.put .. '\n<1500>\n' .. n.take
    elseif n then
        return n.take
    elseif o then
        return o.put
    end
end

function binder.weaponLoop()
    local drawn, synced, pend, since, wasDead = nil, nil, nil, 0, false

    local function step()
            if not (binder.ready and sampIsLocalPlayerSpawned()) then drawn, synced, pend = nil, nil, nil; return end
            local cur  = getCurrentCharWeapon(PLAYER_PED)
            local dead = isCharDead(PLAYER_PED)
            if synced == nil or dead or wasDead then
                wasDead = dead
                drawn, synced, pend = nil, cur, cur
                return
            end
            if cur ~= pend then pend, since = cur, os.clock(); return end
            if os.clock() - since < 0.35 then return end

            if weaponThread then
                local st = weaponThread:status()
                if not (st == 'dead' or st == 'error') then return end
            end
            if not weaponRP then drawn, synced = nil, cur; return end

            local w = weaponById[cur]
            local curOn = (w ~= nil) and w.on
            local wantTake
            if weaponOnRmb then
                local okR, rmb = pcall(function()
                    return vkDown(0x02) and not (window[0] or editor[0] or sampIsChatInputActive() or sampIsDialogActive())
                end)
                wantTake = curOn and cur ~= drawn and okR and rmb
            else
                wantTake = curOn and cur ~= synced
            end
            local needPut = drawn ~= nil and cur ~= drawn

            local text
            if wantTake and needPut then text = binder.weaponText(drawn, cur)
            elseif wantTake then text = binder.weaponText(0, cur)
            elseif needPut then text = binder.weaponText(drawn, 0) end

            if wantTake then drawn = cur elseif needPut then drawn = nil end
            synced = cur
            if text and binder.play(text) then weaponThread = binder.threads[#binder.threads] end
    end
    while true do
        wait(0)
        local ok, err = pcall(step)
        if not ok then print('[RangerHelper] ошибка отслеживания оружия: ' .. tostring(err)) end
    end
end

function binder.stopAll()
    local n = 0
    for _, th in ipairs(binder.threads) do
        local st = th:status()
        if st ~= 'dead' and st ~= 'error' then th:terminate(); n = n + 1 end
    end
    binder.threads = {}
    binder.paused = false
    if n > 0 then binder.say('Все запущенные отыгровки принудительно завершены.') end
end

function binder.pauseToggle()
    if binder.paused then
        binder.paused = false
        binder.say('Отыгровка продолжена.')
        return
    end
    local n = 0
    for _, th in ipairs(binder.threads) do
        local st = th:status()
        if st ~= 'dead' and st ~= 'error' then n = n + 1 end
    end
    if n == 0 then return end
    binder.paused = true
    local rk = binder.parseKey(binder.hotkeyOf(HK_RESUME)) and binder.hotkeyOf(HK_RESUME)
        or binder.hotkeyOf(HK_PAUSE)
    binder.say('Отыгровка приостановлена. Нажмите {aaaaaa}[ ' .. tostring(rk) .. ' ]{ffffff}, чтобы продолжить.')
end

function binder.dlgCurrent() local s = binder.dlg.stack; return s[#s] end

function binder.dlgPush(uid)
    local d = binder.findDialog(uid)
    if not d then return end
    local dlg = binder.dlg
    dlg.stack[#dlg.stack + 1] = d
    dlg.selected = 1
    dlg.focusNext = true
end

function binder.dlgPop()
    local dlg = binder.dlg
    table.remove(dlg.stack)
    dlg.selected = 1
end

function binder.dlgFlush()
    local dlg = binder.dlg
    dlg.selected = 1
    if dlg.keepOnce then dlg.keepOnce = false; return end
    dlg.stack, dlg.params, dlg.args, dlg.focused, dlg.aimId = {}, '', {}, false, nil
    binder.dlgTarget = nil
end

function binder.dlgOpen(d, args, params)
    binder.dlgFlush()
    binder.dlgPush(d.uid)
    binder.dlg.args, binder.dlg.params = args or {}, params or ''
end

function binder.aimTargetId()
    local ok, has, ped = pcall(getCharPlayerIsTargeting, PLAYER_HANDLE)
    if ok and has and ped then
        local okI, pid = sampGetPlayerIdByCharHandle(ped)
        if okI and H.valid(pid) then return pid end
    end
end

function binder.dlgContext()
    local okR, rmb = pcall(vkDown, 0x02)
    if okR and rmb then
        local id = binder.aimTargetId()
        if id then return id, 'aim' end
    end
    local t = binder.target.id
    if t ~= -1 and H.valid(t) then return t, 'mark' end
end

function binder.dlgOpenCtx(d, args, params)
    local id, src
    if not params or params == '' then id, src = binder.dlgContext() end
    if id then args, params = { tostring(id) }, tostring(id) end
    binder.dlgOpen(d, args or {}, params or '')
    binder.dlg.aimId = id

    binder.dlgTarget = (src == 'aim') and id or nil
end

function binder.dlgSelect()
    local dlg = binder.dlg
    local d = binder.dlgCurrent()
    local btn = d and d.buttons[dlg.selected]
    if not btn then return end
    local text, args, params = btn.text, dlg.args, dlg.params
    local filled = binder.applyParams(text, args, params)
    local ctx = binder.dlgTarget
    if filled:find('^%s-<dialog%(%d+%)>%s-$') then
        dlg.keepOnce = true
    else
        binder.dlgFlush()
    end
    binder.dlgTarget = ctx
    binder.play(text, args, params)
    if not dlg.keepOnce then binder.dlgTarget = nil end
end

function binder.dlgMove(delta)
    local dlg = binder.dlg
    local d = binder.dlgCurrent()
    local n = dlg.selected + delta
    if d and d.buttons[n] then dlg.selected = n; dlg.scrollTo = n end
end

function binder.lowerU8(s)
    s = tostring(s or ''):lower()
    s = s:gsub('\208([\144-\159])', function(c) return '\208' .. string.char(c:byte() + 32) end)
    s = s:gsub('\208([\160-\175])', function(c) return '\209' .. string.char(c:byte() - 32) end)
    s = s:gsub('\208\129', '\209\145')
    return s
end

function binder.kpkMatch(value, q)
    if q == '' then return true end
    return binder.lowerU8(value):find(q, 1, true) ~= nil
end

function binder.kpkUsage(sec)
    return '/' .. sec.cmd .. ' ID' .. ((sec.kind == 'carcer') and ' камера' or '')
end

function binder.kpkFormat(sec)
    if sec.kind == 'su' then return '/su ID уровень причина'
    elseif sec.kind == 'ticket' then return '/ticket ID сумма причина'
    elseif sec.kind == 'carcer' then return '/carcer ID камера минуты причина' end
    return '/punish ID уровень 1|2 причина'
end

function binder.cmdTaken(lc, skipKpk, skipSelf)
    if binder.reserved[lc] then return 'хелпер' end
    if skipSelf ~= 'open' and SM.cmd:lower() == lc then return 'хелпер, открытие меню' end
    if skipSelf ~= 'mark' and binder.mark.cmd:lower() == lc then return 'хелпер, захват цели' end
    if skipSelf ~= 'dep' and binder.dep.cmd:lower() == lc then return 'хелпер, рация департамента' end
    if skipSelf ~= 'afind' and binder.afind.cmd:lower() == lc then return 'хелпер, автопоиск' end
    for j, s in ipairs(kpkSecs) do
        if j ~= skipKpk and s.cmd:lower() == lc then return 'КПК, ' .. s.name end
    end
    for _, e in ipairs(binder.sys) do
        if e.kind == 'bind' and e.bcmd:lower() == lc then return 'системная отыгровка, ' .. e.title end
    end
    for _, o in ipairs(binds) do if o.cmd:lower() == lc then return o.title end end
    for _, o in ipairs(dialogs) do if o.cmd:lower() == lc then return o.title end end
    for _, w in ipairs(weapons) do if w.cmd ~= '' and w.cmd:lower() == lc then return w.title end end
    for _, o in ipairs(binder.notes) do if o.cmd ~= '' and o.cmd:lower() == lc then return o.title end end
    return nil
end

function binder.kpkBuf(si)
    local b = binder.kpk.bufs
    if not b[si] then
        b[si] = new.char[32]()
        imgui.StrCopy(b[si], kpkSecs[si].cmd)
    end
    return b[si]
end

function binder.kpkSetCmd(si, raw)
    local sec = kpkSecs[si]
    local c = binder.trim(raw):gsub('^/+', '')
    local buf = binder.kpkBuf(si)
    local function revert(msg)
        imgui.StrCopy(buf, sec.cmd)
        if msg then binder.say(msg) end
        return false
    end
    if c == sec.cmd then imgui.StrCopy(buf, c); return true end
    if c == '' then return revert('Команда КПК не может быть пустой.') end
    if not c:match('^[A-Za-z0-9_]+$') then return revert('Команда: только латиница, цифры и _') end
    local who = binder.cmdTaken(c:lower(), si)
    if who then return revert('Команда {aaaaaa}/' .. c .. '{ffffff} уже занята: ' .. who) end
    sec.cmd = c
    binder.saveKpk()
    binder.needSync = true
    return true
end

function binder.kpkValText(sec, it)
    if sec.kind == 'ticket' then return fmtMoney(it.value) .. ' $'
    elseif sec.kind == 'carcer' then return it.value .. ' мин'
    elseif sec.kind == 'punish' then return 'Ст. ' .. it.value end
    return 'Ур. ' .. it.value
end

function binder.kpkReason(sec, it)
    return it.reason or ''
end

function binder.kpkText(sec, it, id, cell)
    local reason = binder.trim(binder.kpkReason(sec, it))
    local tail = (reason ~= '') and (' ' .. reason) or ''
    local v = math.floor(tonumber(binder.kpkVal(sec, it)) or 1)
    if sec.kind == 'su' then return string.format('/su %d %d%s', id, v, tail)
    elseif sec.kind == 'ticket' then return string.format('/ticket %d %d%s', id, v, tail)
    elseif sec.kind == 'carcer' then return string.format('/carcer %d %d %d%s', id, cell or 1, v, tail) end
    return string.format('/punish %d %d 2%s', id, v, tail)
end

function binder.kpkOpenPop(si, id, cell)
    local pop = binder.kpk.pop
    pop.open, pop.sec, pop.id, pop.cell = true, si, id, cell or 0
    pop.exp, pop.first, pop.focusNext, pop.focusInput, pop.typing = {}, nil, true, false, false
    for k in pairs(hv) do if type(k) == 'string' and k:find('^##kpi') then hv[k] = nil end end
    imgui.StrCopy(pop.q, '')
end

function binder.kpkWantedRequest(sec, it)
    local k = binder.kpk
    if k.reqBusy then return end
    local ctx
    if sec and it then
        local shown = binder.kpkVal(sec, it)
        ctx = {
            kpkarticle = it.text or '',
            kpkreason  = binder.kpkReason(sec, it),
            kpkvalue   = (sec.kind == 'ticket') and fmtMoney(shown) or tostring(shown),
            kpkID      = tostring(binder.kpk.pop.id),
        }
    end
    local th = binder.sysPlay('wantedreq', H.myId(), ctx)
    if not th then
        binder.say('Отыгровка {aaaaaa}«Запрос розыска»{ffffff} отключена или пуста (Биндер - Системные).')
        return
    end
    k.reqBusy = true
    lua_thread.create(function()
        binder.sysWait(th)
        k.reqBusy = false
    end)
end

function binder.kpkCmd(si, arg)
    local sec = kpkSecs[si]
    local a = binder.split(arg)
    local usage = '{aaaaaa}' .. binder.kpkUsage(sec):gsub('ID', '[ID]'):gsub('камера', '[камера 1-10]')
    local id = tonumber(a[1])
    if not id or not H.valid(id) then
        binder.say('Укажите ID игрока: ' .. usage)
        return
    end
    local cell
    if sec.kind == 'carcer' then
        cell = tonumber(a[2])
        if not cell or cell < 1 or cell > 10 or cell ~= math.floor(cell) then
            binder.say('Укажите номер камеры от 1 до 10: ' .. usage)
            return
        end
    end
    binder.kpkOpenPop(si, id, cell)
end

function binder.kpkPick(it)
    local pop = binder.kpk.pop
    local sec = kpkSecs[pop.sec]
    if not sec or not it then return end
    if not H.valid(pop.id) then
        binder.say('Игрок с ID {aaaaaa}' .. pop.id .. '{ffffff} вышел из сети.')
        pop.open = false
        return
    end
    local cmdPlain = binder.kpkText(sec, it, pop.id, pop.cell)
    local cmdDirect = '\1' .. cmdPlain
    local rp = binder.sysKpkText(pop.sec)
    local text = cmdDirect
    if binder.trim(rp) ~= '' then
        local function put(tag, val) rp = rp:gsub('{' .. tag .. '}', function() return val end) end
        put('kpkarticle', it.text or '')
        put('kpkID', tostring(pop.id))
        put('kpkcell', (pop.cell and pop.cell > 0) and tostring(pop.cell) or '')
        put('kpkreason', binder.kpkReason(sec, it))
        local shown = binder.kpkVal(sec, it)
        put('kpkvalue', (sec.kind == 'ticket') and fmtMoney(shown) or tostring(shown))
        local out, found = {}, false
        for ln in (rp .. '\n'):gmatch('(.-)\r?\n') do
            if binder.trim(ln) == '{kpkcmd}' then
                out[#out + 1], found = cmdDirect, true
            elseif ln:find('{kpkcmd}', 1, true) then
                out[#out + 1], found = (ln:gsub('{kpkcmd}', function() return cmdPlain end)), true
            else
                out[#out + 1] = ln
            end
        end
        text = table.concat(out, '\n')
        if not found then text = text .. '\n<1500>\n' .. cmdDirect end
    end
    pop.open = false

    local args = { tostring(pop.id), pop.cell and pop.cell > 0 and tostring(pop.cell) or '' }
    binder.play(text, args, tostring(pop.id) .. ((args[2] ~= '') and (' ' .. args[2]) or ''))
end

function binder.kpkExpText(dl, x, y0, text, lines, extra, ex, col, tw)
    if extra <= 0 then
        dl:AddText(V(x, y0), U(col), text)
        return
    end
    dl:AddText(V(x, y0), U(col, 1 - ex), ellipsize(text, tw))
    for li, ln in ipairs(lines) do
        local a = (li == 1) and ex or clamp((extra * ex - (li - 2) * 15) / 15, 0, 1)
        if a > 0.01 then dl:AddText(V(x, y0 + (li - 1) * 15), U(col, a), ln) end
    end
end

function binder.drawKpkPop(player)
    DT = clamp(imgui.GetIO().DeltaTime, 0.001, 0.1)
    UI_ALPHA, GA = 1.0, 1
    local pop = binder.kpk.pop
    local sec = kpkSecs[pop.sec]
    if not sec then pop.open = false; return end
    if not H.valid(pop.id) then
        binder.say('Игрок с ID {aaaaaa}' .. pop.id .. '{ffffff} вышел из сети.')
        pop.open = false
        return
    end

    local PW, PH = 600, 540
    local sw, sh = getScreenResolution()
    imgui.SetNextWindowPos(V(sw / 2, sh / 2), imgui.Cond.Appearing, V(0.5, 0.5))
    imgui.SetNextWindowSize(V(PW, PH), imgui.Cond.Always)
    if pop.focusNext then imgui.SetNextWindowFocus(); pop.focusNext = false end
    imgui.Begin('RangerHelper KPK Pick', nil,
        imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoSavedSettings +
        imgui.WindowFlags.NoBackground + imgui.WindowFlags.NoResize +
        imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)

    local dl  = imgui.GetWindowDrawList()
    local pos = imgui.GetWindowPos()
    local p2  = V(pos.x + PW, pos.y + PH)
    local font = imgui.GetFont()

    local _fc = SM.clipOff(dl)
    rrf(dl, pos, p2, U(imgui.ImVec4(P.bg.x, P.bg.y, P.bg.z, 0.99)), 18)
    rr(dl, V(pos.x + 0.5, pos.y + 0.5), V(p2.x - 0.5, p2.y - 0.5), U(P.outline, 0.8), 18, 15, 1.5)
    SM.clipOn(dl, _fc)
    hairline(dl, pos.x + 24, p2.x - 24, pos.y + 1, P.accentSoft, 0.55)

    local nick = (H.nick(pop.id):gsub('_', ' '))
    local sub = ((sec.kind == 'carcer') and ('Камера ' .. pop.cell .. '. ') or '') .. 'Выберите статью - команда отправится сразу'
    rrf(dl, V(pos.x + 24, pos.y + 16), V(pos.x + 64, pos.y + 56), U(P.active), 12)
    rr(dl, V(pos.x + 24.5, pos.y + 16.5), V(pos.x + 63.5, pos.y + 55.5), U(P.accent, 0.45), 12, 15, 1)
    centerText(dl, pos.x + 24, pos.y + 16, 40, 40, ico('DESKTOP'), U(P.accentSoft))
    dl:AddTextFontPtr(font, 18, V(pos.x + 76, pos.y + 18), U(P.text),
        binder.cut(sec.name .. ': ' .. nick .. ' [' .. pop.id .. ']', 42))
    dl:AddText(V(pos.x + 76, pos.y + 44), U(P.muted), sub)
    dl:AddLine(V(pos.x + 24, pos.y + 72), V(p2.x - 24, pos.y + 72), U(P.line), 1)

    local cx0, cy0 = pos.x + PW - 40, pos.y + 16
    imgui.SetCursorScreenPos(V(cx0, cy0))
    if imgui.InvisibleButton('##kpclosex', V(24, 24)) then pop.open = false end
    local ect = hot('kpclosex', imgui.IsItemHovered())
    if ect > 0.01 then dl:AddCircleFilled(V(cx0 + 12, cy0 + 12), 14, U(P.danger, 0.22 * ect), 32) end
    local xc = U(lerpC(P.muted, P.danger, ect))
    dl:AddLine(V(cx0 + 7, cy0 + 7), V(cx0 + 17, cy0 + 17), xc, 1.6)
    dl:AddLine(V(cx0 + 17, cy0 + 7), V(cx0 + 7, cy0 + 17), xc, 1.6)

    local q = binder.lowerU8(binder.trim(ffi.string(pop.q)))
    local base, cdl = beginList('##kpkpick', pos.x + 24, pos.y + 84, PW - 48, PH - 84 - 84)
    local iw = PW - 48 - 10
    local y, shown, picked = base.y, 0, nil
    local byVal = false
    pop.first = nil

    for ci, ch in ipairs(sec.chapters) do
        local titleHit = binder.kpkMatch(ch.title, q)
        local list = {}
        for k, it in ipairs(ch.items) do

            local has = (not byVal) or binder.kpkVal(sec, it) > 0
            if has and (titleHit or binder.kpkMatch(it.text, q) or binder.kpkMatch(binder.kpkReason(sec, it), q)) then
                list[#list + 1] = { k, it }
            end
        end
        if #list > 0 or (q == '' and not byVal) then
            shown = shown + 1
            local hid = '##kph' .. ci
            local open = (q ~= '') or pop.exp[ci]
            imgui.SetCursorScreenPos(V(base.x, y))
            if imgui.InvisibleButton(hid, V(iw, 34)) and q == '' then pop.exp[ci] = not pop.exp[ci] end
            local ht = hot(hid, imgui.IsItemHovered())
            local pp = anim('kpp' .. ci, open and 1 or 0, 12)
            card(cdl, base.x, y, iw, 34, 10, lerpC(P.card, P.cardHover, ht),
                lerpC(P.line, P.accent, math.max(ht * 0.7, pp * 0.6)))
            chevron(cdl, base.x + 20, y + 17, pp, U(lerpC(P.muted, P.accentSoft, pp)))
            local cr = chipR(cdl, base.x + iw - 10, y + 6, 'Пунктов: ' .. #list, P.chip, P.muted)
            cdl:PushClipRect(V(base.x + 38, y), V(cr - 4, y + 34), true)
            cdl:AddTextFontPtr(font, 15, V(base.x + 38, y + 9), U(P.text), ch.title)
            cdl:PopClipRect()
            y = y + 38

            if open then
                for _, e in ipairs(list) do
                    local k, it = e[1], e[2]
                    local rid = '##kpi' .. ci .. '_' .. k
                    local rx, rw = base.x + 14, iw - 14
                    local valText = binder.kpkValText(sec, it)
                    local wb = (sec.kind == 'su') and 32 or 0
                    local tw = (rx + rw - 8) - (SM.tw(valText) + 16) - 6 - (rx + 18) - 4 - wb
                    local tLines = binder.wrap(it.text, tw)
                    local rsn = binder.kpkReason(sec, it)
                    local rLines = (rsn ~= '') and binder.wrap(rsn, tw) or {}
                    local ext1 = (#tLines > 1) and (#tLines - 1) * 15 or 0
                    local ext2 = (#rLines > 1) and (#rLines - 1) * 15 or 0
                    local multi = (ext1 + ext2) > 0
                    local ex = hv[rid .. 'x'] or 0
                    imgui.SetCursorScreenPos(V(rx, y))
                    local clicked = imgui.InvisibleButton(rid, V(rw, 46 + (ext1 + ext2) * ex))
                    local hov = imgui.IsItemHovered()
                    local t = hot(rid, hov)
                    ex = anim(rid .. 'x', (hov and multi) and 1 or 0, 14)
                    local rowH = 46 + (ext1 + ext2) * ex
                    card(cdl, rx, y, rw, rowH, 9, lerpC(P.item, P.cardHover, t), lerpC(P.line, P.accent, t * 0.7), 0.9)
                    rrf(cdl, V(rx + 3, y + 10), V(rx + 5.5, y + rowH - 10), U(P.accent), 2)
                    chipR(cdl, rx + rw - 8, y + 12, valText, P.chip, P.text)
                    binder.kpkExpText(cdl, rx + 18, y + 6, it.text, tLines, ext1, ex, P.text, tw)
                    if rsn ~= '' then
                        binder.kpkExpText(cdl, rx + 18, y + 25 + ext1 * ex, rsn, rLines, ext2, ex, P.muted, tw)
                    end
                    local overBtn = false
                    if sec.kind == 'su' then
                        local bw = 26
                        local bx = rx + rw - 8 - (SM.tw(valText) + 16) - 6 - bw
                        local by = y + 10
                        local bt = hot(rid .. 'w', hov)
                        overBtn = bt > 0.3 and imgui.IsMouseHoveringRect(V(bx, by), V(bx + bw, by + bw))
                        if bt > 0.01 then
                            local bh = hot(rid .. 'wb', overBtn)
                            local busy = binder.kpk.reqBusy
                            rrf(cdl, V(bx, by), V(bx + bw, by + bw),
                                U(lerpC(P.item, P.accentHov, bh), (busy and 0.45 or 1) * bt), 7)
                            local g = ico('TABLE_LIST'); if g == '' then g = 'W' end
                            centerText(cdl, bx, by, bw, bw, g, U(P.text, (busy and 0.4 or 1) * bt))
                            if overBtn and showTooltips then SM.tip('Запросить розыск') end
                        end
                        if overBtn and imgui.IsMouseClicked(0) then binder.kpkWantedRequest(sec, it) end
                    end
                    if clicked and not overBtn then picked = it end
                    if not pop.first then pop.first = it end
                    y = y + rowH - 46
                    y = y + 50
                end
            end
            y = y + 4
        end
    end

    if shown == 0 then
        local msg = 'Ничего не найдено'
        if #sec.chapters == 0 then
            msg = 'В КПК пока нет статей. Добавьте главы и пункты на вкладке КПК.'
        elseif q == '' and byVal then
            msg = (sec.kind == 'carcer') and 'Нет статей с карцером. Укажите время карцера в статье на вкладке КПК.'
                or 'Нет статей со сроком. Укажите степень срока в статье на вкладке КПК.'
        end
        cdl:AddText(V(base.x + 12, base.y + 14), U(P.muted), msg)
        y = y + 40
    end
    endList(base, (y - base.y) + 4)

    local fy = pos.y + PH - 60
    hairline(dl, pos.x + 24, p2.x - 24, fy - 12, P.accent, 0.35)
    imgui.SetCursorScreenPos(V(pos.x + 24, fy + 5))
    pushInput()
    imgui.PushItemWidth(PW - 48 - 122)
    imgui.InputTextWithHint('##kpksearch', 'Поиск статьи или причины', pop.q, ffi.sizeof(pop.q))
    local searchActive = imgui.IsItemActive()
    imgui.PopItemWidth()
    popInput()
    if button(dl, '##kpclose', p2.x - 24 - 110, fy, 110, 38, 'Закрыть', false) then pop.open = false end

    pop.focused = imgui.IsWindowFocused(imgui.FocusedFlags.RootAndChildWindows)

    pop.typing = searchActive and true or false
    player.HideCursor, player.LockPlayer = false, pop.typing
    imgui.End()

    if picked then binder.kpkPick(picked) end
end

function binder.kpkCursor(on)
    local k = binder.kpk
    if on == k.curOn then return end
    k.curOn = on
    pcall(sampToggleCursor, on)
end

function binder.kpkFrame(player)
    local pop = binder.kpk.pop
    local okP, paused = pcall(isPauseMenuActive)
    if pop.open and okP and paused then pop.open = false end
    if not pop.open then
        binder.kpkCursor(false)
        pop.typing = false
        player.HideCursor, player.LockPlayer = true, false
        return
    end
    binder.kpkCursor(true)
    binder.drawKpkPop(player)
end

binder.reserved = { ph = true, target = true, wanteds = true }

function binder.sync()
    binder.normalize()
    for _, b in ipairs(binds) do b.pk = binder.parseKey(b.key) end
    for _, d in ipairs(dialogs) do d.pk = binder.parseKey(d.key) end
    for _, n in ipairs(binder.notes) do n.pk = binder.parseKey(n.key) end
    if not binder.ready then return end

    for name in pairs(binder.cmds) do pcall(sampUnregisterChatCommand, name) end
    binder.cmds = {}
    local seen = {}
    for name in pairs(binder.reserved) do seen[name] = true end
    seen[SM.cmd:lower()] = true
    seen[binder.mark.cmd:lower()] = true
    seen[binder.dep.cmd:lower()] = true
    seen[binder.afind.cmd:lower()] = true

    local function reg(name, fn)
        if name ~= '' and not seen[name:lower()] then
            seen[name:lower()] = true
            local ok, res = pcall(sampRegisterChatCommand, name, fn)
            if ok and res ~= false then binder.cmds[name] = true end
        end
    end
    if binder.kpk.enabled then
        for si, sec in ipairs(kpkSecs) do
            reg(sec.cmd, function(arg) binder.kpkCmd(si, u8:encode(arg or '')) end)
        end
    end
    for _, e in ipairs(binder.sys) do
        if e.kind == 'bind' and e.on then
            reg(e.bcmd, function(arg)
                local params = binder.trim(u8:encode(arg or ''))
                binder.play(binder.sysText(e), binder.split(params), params)
            end)
        end
    end
    for _, n in ipairs(binder.notes) do
        if n.on and n.cmd ~= '' then reg(n.cmd, function() binder.noteToggle(n) end) end
    end
    for _, b in ipairs(binds) do
        if b.on then
            reg(b.cmd, function(arg)
                local params = binder.trim(u8:encode(arg or ''))
                binder.play(b.text, binder.split(params), params)
            end)
        end
    end
    for _, d in ipairs(dialogs) do
        if d.on then
            reg(d.cmd, function(arg)
                local params = binder.trim(u8:encode(arg or ''))
                binder.dlgOpenCtx(d, binder.split(params), params)
            end)
        end
    end
end

function binder.markBlipRemove()
    local m = binder.mark
    if m.blipH then
        local ok, ex = pcall(doesBlipExist, m.blipH)
        if ok and ex then pcall(removeBlip, m.blipH) end
    end
    m.blipH, m.blipFor = nil, -1
end

function binder.markBlipSet(id)
    local m = binder.mark
    binder.markBlipRemove()
    if not m.blip or id == nil or id == -1 or not H.valid(id) then return end
    local ok, h = sampGetCharHandleBySampPlayerId(id)
    if ok and h then
        local okB, b = pcall(addBlipForChar, h)
        if okB and b then m.blipH, m.blipFor = b, id end
    end
end

function binder.markTick()
    local m, id = binder.mark, binder.target.id
    if os.clock() - m.tickAt < 0.3 then return end
    m.tickAt = os.clock()
    if id == -1 then
        if m.blipH then binder.markBlipRemove() end
        return
    end
    if not H.valid(id) then
        binder.target.id = -1
        binder.markBlipRemove()
        return
    end
    if not m.blip then
        if m.blipH then binder.markBlipRemove() end
        return
    end
    local alive = false
    if m.blipH and m.blipFor == id then
        local ok, ex = pcall(doesBlipExist, m.blipH)
        alive = ok and ex
    end
    if not alive then binder.markBlipSet(id) end
end

function binder.targetCmd(arg)
    if binder.target.id ~= -1 then
        local id = binder.target.id
        binder.target.id = -1
        binder.markBlipRemove()
        if H.valid(id) then binder.say('{' .. H.chatColor(id) .. '}' .. H.nick(id):gsub('_', ' ') .. ' {aaaaaa}[' .. id .. ']{ffffff} более не является целью.') end
        return
    end
    local id = tonumber(arg)
    if id and H.valid(id) then
        binder.target.id = id
        binder.markBlipSet(id)
        binder.say('Новая цель: {' .. H.chatColor(id) .. '}' .. H.nick(id):gsub('_', ' ') .. ' {aaaaaa}[' .. id .. ']{ffffff}. Уровень: {aaaaaa}' .. sampGetPlayerScore(id))
    elseif id == H.myId() then
        binder.say('Вы ввели свой ID.')
    else
        binder.say('Захват цели {aaaaaa}[ /' .. binder.mark.cmd .. ' ID ]')
    end
end

function binder.markKey()
    if binder.target.id ~= -1 then binder.targetCmd(''); return end
    local ok, has, ped = pcall(getCharPlayerIsTargeting, PLAYER_HANDLE)
    local id
    if ok and has and ped then
        local okI, pid = sampGetPlayerIdByCharHandle(ped)
        if okI and H.valid(pid) then id = pid end
    end
    if not id then
        binder.say('Прицельтесь (ПКМ) в игрока и нажмите клавишу захвата ещё раз.')
        return
    end
    local okD, d = pcall(function()
        local x1, y1, z1 = getCharCoordinates(ped)
        local x2, y2, z2 = getCharCoordinates(PLAYER_PED)
        return getDistanceBetweenCoords3d(x1, y1, z1, x2, y2, z2)
    end)
    local okL, lim = pcall(sampGetNametagRenderDistance)
    if okD and okL and lim and lim > 0 and d > lim then
        binder.say('Игрок слишком далеко для захвата цели.')
        return
    end
    binder.targetCmd(tostring(id))
end

function binder.markSetCmd(raw)
    local c = binder.trim((tostring(raw or ''):gsub('^/+', '')))
    local m = binder.mark
    if c == m.cmd then return true end
    if c == '' or #c > 24 or not c:match('^[A-Za-z0-9_]+$') then
        binder.say('Команда: только латиница, цифры и _')
        return false
    end
    local who = binder.cmdTaken(c:lower(), nil, 'mark')
    if who then binder.say('Команда {aaaaaa}/' .. c .. '{ffffff} уже занята: ' .. who); return false end
    pcall(sampUnregisterChatCommand, m.cmd)
    m.cmd = c
    if binder.ready then pcall(sampRegisterChatCommand, c, function(arg) binder.targetCmd(arg) end) end
    cfgDirty = true
    return true
end

function binder.openSetCmd(raw)
    local c = binder.trim((tostring(raw or ''):gsub('^/+', '')))
    if c == SM.cmd then return true end
    if c == '' or #c > 24 or not c:match('^[A-Za-z0-9_]+$') then
        binder.say('Команда: только латиница, цифры и _')
        return false
    end
    local who = binder.cmdTaken(c:lower(), nil, 'open')
    if who then binder.say('Команда {aaaaaa}/' .. c .. '{ffffff} уже занята: ' .. who); return false end
    SM.setCmd(c); cfgDirty = true
    return true
end

function binder.validate(kind, idx, cmd, key)
    if cmd ~= '' then
        if not cmd:match('^[A-Za-z0-9_]+$') then return 'Команда: только латиница, цифры и _' end
        local lc = cmd:lower()
        if binder.reserved[lc] or lc == SM.cmd:lower() or lc == binder.mark.cmd:lower() or lc == binder.dep.cmd:lower() or lc == binder.afind.cmd:lower() then
            return 'Команда /' .. cmd .. ' зарезервирована хелпером'
        end
        for _, ks in ipairs(kpkSecs) do
            if ks.cmd:lower() == lc then return 'Команда /' .. cmd .. ' уже занята: КПК, ' .. ks.name end
        end
        for i, o in ipairs(binds) do
            if not (kind == 'bind' and i == idx) and o.cmd:lower() == lc then
                return 'Команда /' .. cmd .. ' уже занята: ' .. o.title
            end
        end
        for i, o in ipairs(dialogs) do
            if not (kind == 'dialog' and i == idx) and o.cmd:lower() == lc then
                return 'Команда /' .. cmd .. ' уже занята: ' .. o.title
            end
        end
        for _, w in ipairs(weapons) do
            if w.cmd ~= '' and w.cmd:lower() == lc then
                return 'Команда /' .. cmd .. ' уже занята: ' .. w.title
            end
        end
    end
    local pk = binder.parseKey(key)
    if pk then
        for i, o in ipairs(binds) do
            if not (kind == 'bind' and i == idx) and binder.sameKey(binder.parseKey(o.key), pk) then
                return 'Клавиша ' .. key .. ' уже занята: ' .. o.title
            end
        end
        for i, o in ipairs(dialogs) do
            if not (kind == 'dialog' and i == idx) and binder.sameKey(binder.parseKey(o.key), pk) then
                return 'Клавиша ' .. key .. ' уже занята: ' .. o.title
            end
        end
        return nil, key
    end
    return nil, 'Нет'
end

function binder.edStore()
    local b = ed.btns[ed.sel]
    if b then b.title, b.text = ffi.string(ed.btnTitle), ffi.string(ed.content) end
end
function binder.edLoad(i)
    ed.sel = i
    ed.curS, ed.curE, ed.setCursor, ed.refocus = nil, nil, nil, nil
    local b = ed.btns[i]
    imgui.StrCopy(ed.btnTitle, b and b.title or '')
    imgui.StrCopy(ed.content, b and b.text or '')
end

function binder.commit()
    if editMode == 'dialog' then return binder.commitDialog() end

    local name = binder.trim(ffi.string(ed.name))
    local cmd  = binder.trim(ffi.string(ed.cmd)):gsub('^/+', '')
    local text = ffi.string(ed.content)

    if name == '' then return false, 'Введите название отыгровки' end
    if binder.trim(text) == '' then return false, 'Введите текст отыгровки' end
    local err, key = binder.validate('bind', editIdx, cmd, ed.key)
    if err then return false, err end
    if cmd == '' and key == 'Нет' then return false, 'Задайте команду или клавишу' end

    local b = binds[editIdx]
    if not b then
        b = { on = true }
        binds[#binds + 1] = b
    end
    b.title, b.cmd, b.key, b.text = name, cmd, key, text
    b.cat = binder.catFind(ed.catSel) and ed.catSel or binder.cats[1].uid
    b.preview = binder.preview(text)

    binder.sync()
    binder.save()
    editor[0] = false
    return true
end

function binder.weaponEdSwitch(i)
    local w = weapons[i]
    if not w then return end
    editIdx, ed.weaponIdx, ed.phase, ed.err, ed.capture = i, i, 1, nil, false
    ed.curS, ed.curE, ed.setCursor, ed.refocus = nil, nil, nil, nil
    imgui.StrCopy(ed.name, w.title)
    ed.texts = { w.take, w.put }
    imgui.StrCopy(ed.content, ed.texts[1])
end

function binder.commitWeapon()
    local w = weapons[editIdx]
    if not w then return false, 'Оружие не выбрано' end
    ed.texts[ed.phase] = ffi.string(ed.content)
    local name = binder.trim(ffi.string(ed.name))
    local take, put = binder.trim(ed.texts[1]), binder.trim(ed.texts[2])
    if name == '' then return false, 'Введите название' end
    if take == '' or put == '' then return false, 'Заполните оба текста: «Достать» и «Убрать»' end
    w.title, w.take, w.put = name, take, put
    w.preview, w.text = weaponPreview(take), take
    cfgDirty = true
    editor[0] = false
    return true
end

function binder.commitDialog()
    binder.edStore()
    local name = binder.trim(ffi.string(ed.name))
    local cmd  = binder.trim(ffi.string(ed.cmd)):gsub('^/+', '')

    if name == '' then return false, 'Введите название диалога' end
    if #ed.btns == 0 then return false, 'Добавьте хотя бы одну кнопку' end
    for i, b in ipairs(ed.btns) do
        if binder.trim(b.title) == '' or binder.trim(b.text) == '' then
            return false, 'Заполните название и текст у кнопки #' .. i
        end
    end
    local err, key = binder.validate('dialog', editIdx, cmd, ed.key)
    if err then return false, err end

    local d = dialogs[editIdx]
    if not d then
        d = { on = true, uid = binder.freeUid() }
        dialogs[#dialogs + 1] = d
    end
    d.title, d.cmd, d.key = name, cmd, key
    d.buttons = {}
    for _, b in ipairs(ed.btns) do d.buttons[#d.buttons + 1] = { title = binder.trim(b.title), text = b.text } end
    d.preview = binder.dlgPreview(d)

    binder.sync()
    binder.saveDialogs()
    editor[0] = false
    return true
end

function binder.remove(i)
    if editMode == 'dialog' then
        if not dialogs[i] then return end
        table.remove(dialogs, i)
        binder.dlgFlush()
        binder.sync()
        binder.saveDialogs()
    else
        if not binds[i] then return end
        table.remove(binds, i)
        binder.sync()
        binder.save()
    end
    editor[0] = false
end

function binder.onKeyDown(vk, lparam)
    if not binder.ready then return end
    if bit.band(bit.rshift(lparam, 30), 1) == 1 then return end
    local okA, blocked = pcall(function()
        return sampIsChatInputActive() or sampIsDialogActive() or isSampfuncsConsoleActive()
    end)
    if not okA or blocked then return end

    if SM.imReady then
        local okT, typing = pcall(function() return imgui.GetIO().WantTextInput end)
        if okT and typing then return end
    end

    local ctrl, alt, shift = binder.mods()
    local function hit(k) return binder.keyHit(k, vk, ctrl, alt, shift) end

    if hit(binder.parseKey(binder.hotkeyOf('Открыть хелпер'))) then
        if window[0] then
            if SM.toggleKey and not editor[0] then setOpen(false) end
            return
        elseif not binder.pie.open and not binder.kpk.pop.open then
            setOpen(true)
            return
        end
    end

    if hit(binder.parseKey(binder.hotkeyOf(HK_STOP))) then binder.stopAll() end
    local hitResume = hit(binder.parseKey(binder.hotkeyOf(HK_RESUME)))
    if hitResume then
        binder.resume = true
        if binder.paused then binder.paused = false; binder.say('Отыгровка продолжена.') end
    end
    if not hitResume and hit(binder.parseKey(binder.hotkeyOf(HK_PAUSE))) then binder.pauseToggle() end
    if hit(binder.parseKey(binder.hotkeyOf(binder.HK_DEP))) then
        if binder.dep.open then binder.dep.open = false; return end
        if not (window[0] or editor[0] or binder.pie.open or binder.kpk.pop.open) then binder.depToggle(); return end
    end
    if window[0] or editor[0] or binder.pie.open or binder.kpk.pop.open then return end

    if vkDown(0x02) then
        local mk = binder.parseKey(binder.hotkeyOf(binder.HK_MARK))
        if mk and hit(mk) then binder.markKey(); return end

        if binder.pie.mode == 1 and hit(binder.parseKey(binder.hotkeyOf(binder.HK_PIE))) then return end
    end

    for _, b in ipairs(binds) do
        if b.on and hit(b.pk) then binder.play(b.text, {}, ''); return end
    end
    for _, d in ipairs(dialogs) do
        if d.on and hit(d.pk) then
            if binder.dlg.stack[1] == d then binder.dlgFlush(); return end
            binder.dlgOpenCtx(d)
            return
        end
    end
    for _, n in ipairs(binder.notes) do
        if n.on and hit(n.pk) then binder.noteToggle(n); return end
    end
end

local function drawMain()
    if SM.edOn and editor[0] and edT >= 1 and mainPos then
        local er = SM.edR
        if mainPos.x >= er.x + 24 and mainPos.y >= er.y + 24
            and mainPos.x + WIN_W <= er.x + er.w - 24 and mainPos.y + WIN_H <= er.y + er.h - 24 then
            mainFocused = false
            return
        end
    end
    local sw, sh = getScreenResolution()
    local mp = imgui.GetMousePos()

    if not mainPos then
        mainPos = { x = (sw - WIN_W) / 2, y = (sh - WIN_H) / 2 }
    end
    if not editor[0] then
        local insideMain = mp.x >= mainPos.x and mp.x <= mainPos.x + WIN_W and
            mp.y >= mainPos.y and mp.y <= mainPos.y + WIN_H
        local overItem = imgui.IsAnyItemHovered and imgui.IsAnyItemHovered() or false
        local activeItem = imgui.IsAnyItemActive and imgui.IsAnyItemActive() or false

        if imgui.IsMouseClicked(0) and insideMain and not overItem and not activeItem and not binder.noteHit(mp) then
            mainDragging = true
            mainDragOffset.x = mp.x - mainPos.x
            mainDragOffset.y = mp.y - mainPos.y
        end
        if not imgui.IsMouseDown(0) then
            if mainDragging then cfgDirty = true end
            mainDragging = false
        end
        if mainDragging and imgui.IsMouseDown(0) then
            mainPos.x = clamp(mp.x - mainDragOffset.x, 0, math.max(0, sw - WIN_W))
            mainPos.y = clamp(mp.y - mainDragOffset.y, 0, math.max(0, sh - WIN_H))
        end
    else
        mainDragging = false
    end

    imgui.SetNextWindowPos(V(math.floor(mainPos.x + 0.5), math.floor(mainPos.y + 0.5)), imgui.Cond.Always)
    imgui.SetNextWindowSize(V(WIN_W, WIN_H), imgui.Cond.Always)
    local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoSavedSettings +
        imgui.WindowFlags.NoBackground + imgui.WindowFlags.NoResize +
        imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse +
        imgui.WindowFlags.NoBringToFrontOnFocus
    if editor[0] then flags = flags + imgui.WindowFlags.NoInputs end
    imgui.Begin('RangerHelper Main', nil, flags)

    local dl  = imgui.GetWindowDrawList()
    local pos = imgui.GetWindowPos()
    local p1  = V(pos.x, pos.y)
    local p2  = V(pos.x + WIN_W, pos.y + WIN_H)
    mainCenter.x, mainCenter.y = pos.x + WIN_W / 2, pos.y + WIN_H / 2

    local inside = mp.x >= pos.x and mp.x <= p2.x and mp.y >= pos.y and mp.y <= p2.y
    local canReact = not editor[0] and (os.clock() - openedAt > 0.25)
    if canReact then
        if sideTarget == 0 then
            if inside and mp.x > pos.x + SB_FULL + 8 then
                collapseTimer = collapseTimer + DT
                if collapseTimer > 0.12 then sideTarget = 1 end
            else
                collapseTimer = 0
            end
        else
            if inside and mp.x < pos.x + SB_MIN then sideTarget = 0; collapseTimer = 0 end
        end
    end
    if smoothAnimations and not SM.low then
        sideT = sideT + (sideTarget - sideT) * clamp(DT * ANIM_SPEED, 0, 1)
        if math.abs(sideTarget - sideT) < 0.002 then sideT = sideTarget end
    else
        sideT = sideTarget
    end
    local sbW = SB_FULL + (SB_MIN - SB_FULL) * ease(sideT)
    local la  = clamp(1 - sideT * 2.5, 0, 1)

    local _fc = SM.clipOff(dl)
    rrf(dl, p1, p2, U(P.bg), ROUNDING)
    SM.clipOn(dl, _fc)

    hairline(dl, p1.x + ROUNDING, p2.x - ROUNDING, p1.y + 1, P.accentSoft, 0.55)

    drawSidebar(dl, pos, sbW, la)

    local cx = pos.x + sbW + 18
    local cw = WIN_W - sbW - 36
    GA = SM.low and 1 or ease(clamp((os.clock() - pageStart) / 0.18, 0, 1))
    pages[tab](dl, pos, cx, cw)
    GA = 1

    if edT > 0 then local _f2 = SM.clipOff(dl); rrf(dl, p1, p2, U(C(0, 0, 0, 80), edT), ROUNDING); SM.clipOn(dl, _f2) end

    mainFocused = imgui.IsWindowFocused(imgui.FocusedFlags.RootAndChildWindows)
    imgui.End()
end

local function drawOverlay()
    local sw, sh = getScreenResolution()

    pcall(function()
        local ds = imgui.GetIO().DisplaySize
        if ds.x > 1 and ds.y > 1 then sw, sh = ds.x, ds.y end
    end)
    local k = ease(clamp(edT, 0, 1))
    imgui.SetNextWindowPos(V(0, 0), imgui.Cond.Always)
    imgui.SetNextWindowSize(V(sw, sh), imgui.Cond.Always)
    imgui.Begin('RangerHelper Overlay', nil,
        imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoSavedSettings +
        imgui.WindowFlags.NoBackground + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove +
        imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse +
        imgui.WindowFlags.NoFocusOnAppearing + imgui.WindowFlags.NoBringToFrontOnFocus)
    local dl = imgui.GetWindowDrawList()
    local fc = SM.clipOff(dl)
    dl:AddRectFilled(V(-64, -64), V(sw + 64, sh + 64), U(C(6, 8, 16, 120), k))
    SM.clipOn(dl, fc)
    imgui.End()
end

local editorFocused = false

local function label(text) imgui.TextColored(P.muted, text) end

local contentCb, contentInput = nil, nil
do

local hist = { id = nil, text = '', undo = {}, redo = {}, t = 0, seen = 0, grace = 0, active = false }
local HIST_MAX = 300

local function histReset(id, text)
    hist.id, hist.text, hist.undo, hist.redo = id, text, {}, {}
    hist.t, hist.grace = 0, 0
end

local function histRecord(newText, force)
    if newText == hist.text then return end
    local now = os.clock()
    if force or math.abs(#newText - #hist.text) > 1 or now - hist.t > 0.7 then
        hist.undo[#hist.undo + 1] = hist.text
        if #hist.undo > HIST_MAX then table.remove(hist.undo, 1) end
    end
    hist.redo = {}
    hist.text, hist.t = newText, force and 0 or now
end

local function histCursor(a, b)
    local la, lb = #a, #b
    local p = 0
    local m = math.min(la, lb)
    while p < m and a:byte(p + 1) == b:byte(p + 1) do p = p + 1 end
    local sfx = 0
    while sfx < m - p and a:byte(la - sfx) == b:byte(lb - sfx) do sfx = sfx + 1 end
    local pos = lb - sfx
    while pos < lb do
        local c = b:byte(pos + 1)
        if c >= 0x80 and c < 0xC0 then pos = pos + 1 else break end
    end
    return pos
end

local function histApply(newText)
    local old = hist.text
    local cpos = histCursor(old, newText)
    hist.text, hist.t, hist.grace = newText, 0, 3
    ed.apply = { text = newText, cur = cpos }
    ed.curS, ed.curE = cpos, cpos
end

local function histUndo()
    local prev = table.remove(hist.undo)
    if not prev then return end
    hist.redo[#hist.redo + 1] = hist.text
    histApply(prev)
end

local function histRedo()
    local nxt = table.remove(hist.redo)
    if not nxt then return end
    hist.undo[#hist.undo + 1] = hist.text
    histApply(nxt)
end

local function histCutLine()
    local cur = ffi.string(ed.content)
    local lo, hi = #cur, #cur
    if ed.curS and ed.curE then lo, hi = math.min(ed.curS, ed.curE), math.max(ed.curS, ed.curE) end
    lo, hi = clamp(lo, 0, #cur), clamp(hi, 0, #cur)
    if #cur == 0 then return end
    local ls = 0
    for i = lo, 1, -1 do
        if cur:byte(i) == 10 then ls = i; break end
    end
    local scan = hi
    if hi > lo and cur:byte(hi) == 10 then scan = hi - 1 end
    local nl = cur:find('\n', scan + 1, true)
    local new_text, cpos
    if nl then
        new_text, cpos = cur:sub(1, ls) .. cur:sub(nl + 1), ls
    elseif ls > 0 then
        new_text, cpos = cur:sub(1, ls - 1), ls - 1
    else
        new_text, cpos = '', 0
    end
    histRecord(new_text, true)
    hist.grace = 3
    ed.apply = { text = new_text, cur = cpos }
    ed.curS, ed.curE = cpos, cpos
end

function binder.histCommit(oldText, newText)
    if hist.id and hist.text == oldText then histRecord(newText, true) end
end

do
    local ok, cb = pcall(function()
        return ffi.cast('int (*)(ImGuiInputTextCallbackData*)', function(data)
            pcall(function()
                if ed.apply then
                    local a = ed.apply
                    ed.apply = nil
                    data:DeleteChars(0, data.BufTextLen)
                    data:InsertChars(0, a.text)
                    data.CursorPos, data.SelectionStart, data.SelectionEnd = a.cur, a.cur, a.cur
                end
                if ed.setCursor then
                    local n = ed.setCursor
                    ed.setCursor = nil
                    data.CursorPos, data.SelectionStart, data.SelectionEnd = n, n, n
                end
                if data.SelectionStart == data.SelectionEnd then
                    ed.curS, ed.curE = data.CursorPos, data.CursorPos
                else
                    ed.curS, ed.curE = data.SelectionStart, data.SelectionEnd
                end
            end)
            return 0
        end)
    end)
    if ok then contentCb = cb end
end

local function keyPressed(vk)
    local ok, r = pcall(imgui.IsKeyPressed, vk)
    return ok and r
end

contentInput = function(id, size)
    if ed.refocus then imgui.SetKeyboardFocusHere(); ed.refocus = false end
    if not contentCb then
        return imgui.InputTextMultiline(id, ed.content, ffi.sizeof(ed.content), size)
    end

    local imio = imgui.GetIO()
    local now = os.clock()
    local text0 = ffi.string(ed.content)
    if hist.id ~= id or now - hist.seen > 0.5 then histReset(id, text0) end
    hist.seen = now

    local mute = false
    if hist.active and imio.KeyCtrl and not imio.KeyAlt then
        if keyPressed(0x5A) then
            if imio.KeyShift then histRedo() else histUndo() end
            mute = true
        elseif keyPressed(0x59) then
            histRedo()
            mute = true
        elseif keyPressed(0x58) then
            histCutLine()
            mute = true
        end
    end
    if mute then imio.KeyCtrl = false end

    local changed = imgui.InputTextMultiline(id, ed.content, ffi.sizeof(ed.content), size,
        imgui.InputTextFlags.CallbackAlways, contentCb)

    if mute then imio.KeyCtrl = true end
    hist.active = imgui.IsItemActive()

    local cur = ffi.string(ed.content)
    if hist.grace > 0 then
        hist.grace = (cur == hist.text) and 0 or (hist.grace - 1)
    elseif cur ~= hist.text then
        if changed then histRecord(cur, false) else histReset(id, cur) end
    end
    return changed
end
end

local function drawTagPanel(dl, pos, canInsert)
    local sx, sy = pos.x + 712, pos.y + 12
    local sw2, sh2 = ED_W - 712 - 12, ED_H - 24
    local panelCol = lerpC(P.chip, C(0, 0, 0), 0.30)
    card(dl, sx, sy, sw2, sh2, 14, panelCol, P.line, 0.9)
    rrf(dl, V(sx + 14, sy + 16), V(sx + 17, sy + 34), U(P.accent), 2)
    dl:AddTextFontPtr(imgui.GetFont(), 16, V(sx + 26, sy + 14), U(P.text), 'Теги и функции')
    dl:AddText(V(sx + 14, sy + 38), U(P.muted), 'Нажмите, чтобы вставить в текст')

    local base, cdl = beginList('##tagpanel', sx + 8, sy + 62, sw2 - 16, sh2 - 72)
    local vwy, vwh = imgui.GetWindowPos().y, imgui.GetWindowSize().y
    local w = sw2 - 16 - 8
    local y = base.y
    for gi, grp in ipairs(binder.tagGroups()) do
        if y + 22 >= vwy and y <= vwy + vwh then cdl:AddText(V(base.x + 4, y), U(P.muted), grp.head) end
        y = y + 22
        for ii, it in ipairs(grp.items) do
            local lines = it._wl
            if not lines or it._ww ~= w then lines = binder.wrap(it.desc, w - 20); it._wl, it._ww = lines, w end
            local h = 44 + #lines * 15
            if y + h >= vwy - 4 and y <= vwy + vwh + 4 then
            imgui.SetCursorScreenPos(V(base.x, y))
            local clicked = imgui.InvisibleButton('##help' .. gi .. '_' .. ii, V(w, h))
            local hovered = imgui.IsItemHovered()
            local t = hot('help' .. gi .. '_' .. ii, hovered)
            if clicked and canInsert then
                local cur = ffi.string(ed.content)
                if #cur + #it.ins < 4000 then
                    local lo, hi = #cur, #cur
                    if ed.curS and ed.curE then lo, hi = math.min(ed.curS, ed.curE), math.max(ed.curS, ed.curE) end
                    lo, hi = clamp(lo, 0, #cur), clamp(hi, 0, #cur)
                    local newText = cur:sub(1, lo) .. it.ins .. cur:sub(hi + 1)
                    binder.histCommit(cur, newText)
                    imgui.StrCopy(ed.content, newText)
                    ed.curS, ed.curE = lo + #it.ins, lo + #it.ins
                    ed.setCursor, ed.refocus = lo + #it.ins, true
                end
            end
            card(cdl, base.x, y, w, h, 10, lerpC(P.item, P.cardHover, t), lerpC(P.line, P.accent, t * 0.8))
            chipL(cdl, base.x + 8, y + 8, it.tok, P.chip, P.accentSoft)
            for li, ln in ipairs(lines) do
                cdl:AddText(V(base.x + 10, y + 36 + (li - 1) * 15), U(P.muted), ln)
            end
            if showTooltips and hovered and it.ex then SM.tip(it.ex) end
            end
            y = y + h + 6
        end
        y = y + 8
    end
    endList(base, (y - base.y) + 4)
end

local function drawDialogEditor(dl, pos)
    local lx, ly, lw, lh = pos.x + 24, pos.y + 252, 216, 232
    imgui.SetCursorPos(V(24, 226)); label('Кнопки диалога')
    card(dl, lx, ly, lw, lh, 10, P.card, P.line, 0.9)

    local bd = btnDrag
    local wasDrag = bd.on
    if bd.on and not imgui.IsMouseDown(0) then
        bd.on = false
        if bd.tgt ~= bd.idx and ed.btns[bd.idx] and bd.tgt >= 1 and bd.tgt <= #ed.btns then
            binder.edStore()
            local cur = ed.btns[ed.sel]
            table.insert(ed.btns, bd.tgt, (table.remove(ed.btns, bd.idx)))
            local newSel = 0
            for n, b in ipairs(ed.btns) do if b == cur then newSel = n end end
            binder.edLoad(newSel)
        end
    end

    local base, cdl = beginList('##dlgbtns', lx + 4, ly + 4, lw - 8, lh - 8)
    local rowW = lw - 16
    local selW = rowW - 66
    local y = base.y
    local action
    local order = {}
    for i = 1, #ed.btns do order[i] = i end
    if bd.on then
        local my = imgui.GetMousePos().y
        bd.tgt = clamp(math.floor((my - base.y) / 34) + 1, 1, math.max(#ed.btns, 1))
        if my < ly + 22 then imgui.SetScrollY(imgui.GetScrollY() - 8)
        elseif my > ly + lh - 22 then imgui.SetScrollY(imgui.GetScrollY() + 8) end
        if ed.btns[bd.idx] then
            table.remove(order, bd.idx)
            table.insert(order, bd.tgt, bd.idx)
        else
            bd.on = false
        end
    end
    local MINI = { { 'ARROW_UP', '^', 'up' }, { 'ARROW_DOWN', 'v', 'down' }, { 'XMARK', 'x', 'del' } }

    local function btnTitleOf(i)
        local title = (ed.sel == i) and ffi.string(ed.btnTitle) or ed.btns[i].title
        if title == '' then title = '(без названия)' end
        return title
    end

    for p, i in ipairs(order) do
      if not (bd.on and i == bd.idx) then
        local b = ed.btns[i]
        local selected = (ed.sel == i)
        local title = btnTitleOf(i)
        y = base.y + (p - 1) * 34

        imgui.SetCursorScreenPos(V(base.x, y))
        if imgui.InvisibleButton('##dsel' .. i, V(selW, 30)) then action = { 'sel', i } end
        if not bd.on and imgui.IsItemActive() and imgui.IsMouseDragging(0, 5) then
            bd.on, bd.idx, bd.tgt, bd.grab = true, i, i, imgui.GetMousePos().y - y
        end
        local t = hot('dsel' .. i, imgui.IsItemHovered())
        card(cdl, base.x, y, rowW, 30, 8, selected and P.active or lerpC(P.item, P.cardHover, t),
            selected and P.accent or lerpC(P.line, P.accent, t * 0.7))
        cdl:PushClipRect(V(base.x + 6, y), V(base.x + selW - 2, y + 30), true)
        cdl:AddText(V(base.x + 10, y + 7), U(P.text), title)
        cdl:PopClipRect()

        for k, m in ipairs(MINI) do
            local bx = base.x + selW + (k - 1) * 22
            imgui.SetCursorScreenPos(V(bx, y + 4))
            if imgui.InvisibleButton('##d' .. m[3] .. i, V(22, 22)) then action = { m[3], i } end
            local th = hot('d' .. m[3] .. i, imgui.IsItemHovered())
            local g = ico(m[1]); if g == '' then g = m[2] end
            centerText(cdl, bx, y + 4, 22, 22, g, U(lerpC(P.muted, m[3] == 'del' and P.danger or P.accentSoft, th)))
        end
      end
    end
    y = base.y + #ed.btns * 34

    if bd.on and ed.btns[bd.idx] then
        local gy = clamp(imgui.GetMousePos().y - bd.grab, base.y, base.y + math.max(#ed.btns - 1, 0) * 34)
        rrf(cdl, V(base.x - 1, gy + 2), V(base.x + rowW + 1, gy + 33), U(C(0, 0, 0, 90)), 9)
        card(cdl, base.x, gy, rowW, 30, 8, P.active, P.accent)
        cdl:PushClipRect(V(base.x + 6, gy), V(base.x + rowW - 6, gy + 30), true)
        cdl:AddText(V(base.x + 10, gy + 7), U(P.text), btnTitleOf(bd.idx))
        cdl:PopClipRect()
    end

    imgui.SetCursorScreenPos(V(base.x, y))
    if imgui.InvisibleButton('##dadd', V(rowW, 30)) then action = { 'add' } end
    local ta = hot('dadd', imgui.IsItemHovered())
    card(cdl, base.x, y, rowW, 30, 8, lerpC(P.chip, P.cardHover, ta), lerpC(P.line, P.accent, ta))
    centerText(cdl, base.x, y, rowW, 30, '+ Добавить кнопку', U(lerpC(P.accentSoft, P.text, ta)))
    y = y + 34
    endList(base, y - base.y)

    if bd.on or wasDrag then action = nil end
    if action then
        binder.edStore()
        local cur = ed.btns[ed.sel]
        local k, i = action[1], action[2]
        if k == 'sel' then
            binder.edLoad(i)
        else
            if k == 'add' then
                ed.btns[#ed.btns + 1] = { title = 'Новая кнопка', text = '' }
                cur = ed.btns[#ed.btns]
            elseif k == 'up' and i > 1 then
                ed.btns[i], ed.btns[i - 1] = ed.btns[i - 1], ed.btns[i]
            elseif k == 'down' and i < #ed.btns then
                ed.btns[i], ed.btns[i + 1] = ed.btns[i + 1], ed.btns[i]
            elseif k == 'del' then
                local removed = table.remove(ed.btns, i)
                if removed == cur then cur = ed.btns[math.min(i, #ed.btns)] end
            end
            local newSel = 0
            for n, b in ipairs(ed.btns) do if b == cur then newSel = n end end
            binder.edLoad(newSel)
        end
    end

    if ed.btns[ed.sel] then
        imgui.SetCursorPos(V(252, 226)); label('Название кнопки')
        imgui.SetCursorPos(V(252, 252)); imgui.PushItemWidth(424)
        imgui.InputText('##dbtitle', ed.btnTitle, ffi.sizeof(ed.btnTitle))
        imgui.PopItemWidth()
        imgui.SetCursorPos(V(252, 294)); label('Текст кнопки (отыгровка)')
        imgui.SetCursorPos(V(252, 314))
        contentInput('##dbtext', V(424, 170))
    else
        imgui.SetCursorPos(V(252, 252))
        imgui.TextColored(P.muted, 'Добавьте кнопку слева, чтобы задать её название и текст.')
    end
end

local function drawEditor()
    local ea = ease(clamp(edT, 0, 1))
    local LW = 652
    local isW = (editMode == 'weapon')
    local isD = (editMode == 'dialog')
    local dy = isW and -72 or 0

    local screenW, screenH = getScreenResolution()
    imgui.SetNextWindowPos(V(screenW / 2, screenH / 2), imgui.Cond.Appearing, V(0.5, 0.5))
    imgui.SetNextWindowSize(V(ED_W, ED_H), imgui.Cond.Always)
    if justOpened then imgui.SetNextWindowFocus(); justOpened = false end
    imgui.Begin('RangerHelper Editor', nil,
        imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoSavedSettings +
        imgui.WindowFlags.NoBackground + imgui.WindowFlags.NoResize +
        imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)

    GA = ea
    local dl  = imgui.GetWindowDrawList()
    local pos = imgui.GetWindowPos()
    SM.edBox(pos, ED_W, ED_H)
    local p1, p2 = V(pos.x, pos.y), V(pos.x + ED_W, pos.y + ED_H)

    local edBg = imgui.ImVec4(P.bg.x, P.bg.y, P.bg.z, 0.99)
    local _fc = SM.clipOff(dl)
    rrf(dl, p1, p2, U(edBg), 18)
    rr(dl, V(p1.x + 0.5, p1.y + 0.5), V(p2.x - 0.5, p2.y - 0.5), U(P.outline, 0.8), 18, 15, 1.5)
    SM.clipOn(dl, _fc)
    hairline(dl, p1.x + 24, p2.x - 24, p1.y + 1, P.accentSoft, 0.55)

    local title
    if isW then
        title = (editIdx == 0) and 'Новая отыгровка оружия' or ('Отыгровка оружия: ' .. weapons[editIdx].title)
    elseif isD then
        title = (editIdx == 0) and 'Новый диалог' or ('Диалог #' .. tostring(dialogs[editIdx] and dialogs[editIdx].uid or ''))
    else
        title = (editIdx == 0) and 'Новая отыгровка' or 'Редактирование отыгровки'
    end
    rrf(dl, V(pos.x + 24, pos.y + 16), V(pos.x + 64, pos.y + 56), U(P.active), 12)
    rr(dl, V(pos.x + 24.5, pos.y + 16.5), V(pos.x + 63.5, pos.y + 55.5), U(P.accent, 0.45), 12, 15, 1)
    centerText(dl, pos.x + 24, pos.y + 16, 40, 40, ico(isW and 'GUN' or isD and 'LIST' or 'KEYBOARD'), U(P.accentSoft))
    dl:AddTextFontPtr(imgui.GetFont(), 18, V(pos.x + 76, pos.y + 18), U(P.text), title)
    dl:AddText(V(pos.x + 76, pos.y + 44), U(P.muted), isD and 'Название, активация и кнопки диалога' or 'Название, активация и текст отыгровки')
    dl:AddLine(V(pos.x + 24, pos.y + 72), V(pos.x + 24 + LW, pos.y + 72), U(P.line), 1)

    local cx0, cy0 = pos.x + ED_W - 40, pos.y + 16
    imgui.SetCursorScreenPos(V(cx0, cy0))
    if imgui.InvisibleButton('##eclose', V(24, 24)) then editor[0] = false end
    local ect = hot('eclose', imgui.IsItemHovered())
    if ect > 0.01 then dl:AddCircleFilled(V(cx0 + 12, cy0 + 12), 14, U(P.danger, 0.22 * ect), 32) end
    local xc = U(lerpC(P.muted, P.danger, ect))
    dl:AddLine(V(cx0 + 7, cy0 + 7), V(cx0 + 17, cy0 + 17), xc, 1.6)
    dl:AddLine(V(cx0 + 17, cy0 + 7), V(cx0 + 7, cy0 + 17), xc, 1.6)

    pushInput()

    local isB = (editMode == 'bind')
    local nameW = ((isW and #weapons > 0) or (isB and #binder.cats > 1)) and 320 or LW
    imgui.SetCursorPos(V(24, 86));  label('Название')
    imgui.SetCursorPos(V(24, 106)); imgui.PushItemWidth(nameW)
    imgui.InputText('##ename', ed.name, ffi.sizeof(ed.name))
    imgui.PopItemWidth()

    if isW and #weapons > 0 then
        imgui.SetCursorPos(V(356, 86)); label('Оружие')
        local bx, by, bw = pos.x + 356, pos.y + 106, 320
        card(dl, bx, by, bw, 34, 9, P.card, P.line)
        local n = #weapons
        imgui.SetCursorScreenPos(V(bx, by))
        if imgui.InvisibleButton('##wprev', V(36, 34)) then binder.weaponEdSwitch((ed.weaponIdx - 2) % n + 1) end
        local t1 = hot('wprev', imgui.IsItemHovered())
        imgui.SetCursorScreenPos(V(bx + bw - 36, by))
        if imgui.InvisibleButton('##wnext', V(36, 34)) then binder.weaponEdSwitch(ed.weaponIdx % n + 1) end
        local t2 = hot('wnext', imgui.IsItemHovered())
        local c1, c2 = U(lerpC(P.muted, P.accentSoft, t1)), U(lerpC(P.muted, P.accentSoft, t2))
        dl:AddLine(V(bx + 21, by + 11), V(bx + 15, by + 17), c1, 1.8)
        dl:AddLine(V(bx + 15, by + 17), V(bx + 21, by + 23), c1, 1.8)
        dl:AddLine(V(bx + bw - 21, by + 11), V(bx + bw - 15, by + 17), c2, 1.8)
        dl:AddLine(V(bx + bw - 15, by + 17), V(bx + bw - 21, by + 23), c2, 1.8)
        centerText(dl, bx, by, bw, 34, weapons[ed.weaponIdx].title, U(P.text))
    end

    if isB and #binder.cats > 1 then
        imgui.SetCursorPos(V(356, 86)); label('Категория')
        local bx, by, bw = pos.x + 356, pos.y + 106, 320
        card(dl, bx, by, bw, 34, 9, P.card, P.line)
        local n = #binder.cats
        local _, ci = binder.catFind(ed.catSel)
        ci = ci or 1
        imgui.SetCursorScreenPos(V(bx, by))
        if imgui.InvisibleButton('##cprev', V(36, 34)) then ed.catSel = binder.cats[(ci - 2) % n + 1].uid end
        local t1 = hot('cprev', imgui.IsItemHovered())
        imgui.SetCursorScreenPos(V(bx + bw - 36, by))
        if imgui.InvisibleButton('##cnext', V(36, 34)) then ed.catSel = binder.cats[ci % n + 1].uid end
        local t2 = hot('cnext', imgui.IsItemHovered())
        local c1, c2 = U(lerpC(P.muted, P.accentSoft, t1)), U(lerpC(P.muted, P.accentSoft, t2))
        dl:AddLine(V(bx + 21, by + 11), V(bx + 15, by + 17), c1, 1.8)
        dl:AddLine(V(bx + 15, by + 17), V(bx + 21, by + 23), c1, 1.8)
        dl:AddLine(V(bx + bw - 21, by + 11), V(bx + bw - 15, by + 17), c2, 1.8)
        dl:AddLine(V(bx + bw - 15, by + 17), V(bx + bw - 21, by + 23), c2, 1.8)
        centerText(dl, bx, by, bw, 34, binder.cut(binder.cats[ci].name, 28), U(P.text))
    end

    if not isW then
        imgui.SetCursorPos(V(24, 154));  label('Команда')
        imgui.SetCursorPos(V(356, 154)); label('Клавиша')

        imgui.SetCursorPos(V(24, 174));  imgui.PushItemWidth(320)
        imgui.InputText('##ecmd', ed.cmd, ffi.sizeof(ed.cmd), imgui.InputTextFlags.CharsNoBlank)
        imgui.PopItemWidth()

        imgui.SetCursorPos(V(356, 174))
        if imgui.Button((ed.capture and binder.capText('Нажмите сочетание...') or ed.key) .. '##ekey', V(320, 0)) then
            ed.capture = not ed.capture
        end
    end

    if isD then
        drawDialogEditor(dl, pos)
    else
        imgui.SetCursorPos(V(24, 226 + dy)); label('Содержимое отыгровки')
        if isW then
            local items = { 'Достать', 'Убрать' }
            local r = segTabs(dl, '##wph', pos.x + 24 + LW - segWidth(items), pos.y + 214 + dy, items, ed.phase)
            if r and r ~= ed.phase then
                ed.texts[ed.phase] = ffi.string(ed.content)
                ed.phase = r
                ed.curS, ed.curE, ed.setCursor, ed.refocus = nil, nil, nil, nil
                imgui.StrCopy(ed.content, ed.texts[r])
            end
        end
        imgui.SetCursorPos(V(24, 252 + dy))
        contentInput('##econtent', V(LW, 232 - dy))

    end

    imgui.SetCursorPos(V(24, 492))
    if ed.err then
        imgui.TextColored(P.danger, ed.err)
    elseif ed.capture then
        imgui.TextColored(P.accentSoft, 'Нажмите клавишу или сочетание (до 3 клавиш + Ctrl/Alt/Shift). Esc - отмена, Backspace - сбросить.')
    elseif isW then
        imgui.TextColored(P.muted, 'При смене оружия «Убрать» и «Достать» объединяются в одну /me. {?} - окончание по полу.')
    elseif isD then
        imgui.TextColored(P.muted, 'Двойной клик по кнопке запускает её отыгровку. Вложенный диалог: <dialog(UID)>.')
    else
        imgui.TextColored(P.muted, 'Каждая строка отправляется отдельно. Теги справа подставятся при отыгровке.')
    end

    imgui.SetCursorPos(V(24, 524))
    imgui.PushStyleColor(imgui.Col.Button, P.accent)
    imgui.PushStyleColor(imgui.Col.ButtonHovered, P.accentHov)
    if imgui.Button('Сохранить##esave', V(200, 36)) then
        if isW then
            local ok, err = binder.commitWeapon()
            ed.err = (not ok) and err or nil
        else
            local ok, err = binder.commit()
            ed.err = (not ok) and err or nil
        end
    end
    imgui.PopStyleColor(2)
    imgui.SameLine()
    if imgui.Button('Отмена##ecancel', V(140, 36)) then editor[0] = false end
    if editIdx > 0 and not isW then
        imgui.SameLine(24 + LW - 120)
        local ask = ed.delAsk and (os.clock() - ed.delAsk < 3)
        imgui.PushStyleColor(imgui.Col.Text, P.danger)
        if imgui.Button((ask and 'Точно?' or 'Удалить') .. '##edel', V(120, 36)) then
            if ask then binder.remove(editIdx) else ed.delAsk = os.clock() end
        end
        imgui.PopStyleColor(1)
    end

    if isW then
        imgui.SameLine(24 + LW - 120)
        if imgui.Button('Сбросить##ereset', V(120, 36)) then
            local w = weapons[editIdx]
            if w then
                ed.texts = { w.defTake, w.defPut }
                imgui.StrCopy(ed.content, ed.texts[ed.phase])
                imgui.StrCopy(ed.name, w.defTitle)
            end
        end
    end

    popInput()

    drawTagPanel(dl, pos, (not isD) or ed.sel > 0)

    GA = 1
    editorFocused = imgui.IsWindowFocused(imgui.FocusedFlags.RootAndChildWindows)
    imgui.End()
end

local function drawKpkEditor()
    local ea = ease(clamp(edT, 0, 1))
    local sec = kpkSecs[kpkSec]
    local isItem = (ked.kind == 'item')
    local W = isItem and 700 or 560
    local term = (sec.kind == 'punish')
    local H = isItem and 380 or 236
    local LW = W - 48
    local RX = 24 + LW
    local isNew = (isItem and (ked.ii == 0) or (not isItem and ked.ch == 0))

    local sw, sh = getScreenResolution()
    imgui.SetNextWindowPos(V(sw / 2, sh / 2), imgui.Cond.Appearing, V(0.5, 0.5))
    imgui.SetNextWindowSize(V(W, H), imgui.Cond.Always)
    if ked.justOpened then imgui.SetNextWindowFocus(); ked.justOpened = false end
    imgui.Begin('RangerHelper KPK Editor', nil,
        imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoSavedSettings +
        imgui.WindowFlags.NoBackground + imgui.WindowFlags.NoResize +
        imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)

    GA = ea
    local dl  = imgui.GetWindowDrawList()
    local pos = imgui.GetWindowPos()
    SM.edBox(pos, W, H)
    local p2  = V(pos.x + W, pos.y + H)

    local _fc = SM.clipOff(dl)
    rrf(dl, pos, p2, U(imgui.ImVec4(P.bg.x, P.bg.y, P.bg.z, 0.99)), 18)
    rr(dl, V(pos.x + 0.5, pos.y + 0.5), V(p2.x - 0.5, p2.y - 0.5), U(P.outline, 0.8), 18, 15, 1.5)
    SM.clipOn(dl, _fc)
    hairline(dl, pos.x + 24, p2.x - 24, pos.y + 1, P.accentSoft, 0.55)

    local title = isItem and (isNew and 'Новый пункт' or 'Редактирование пункта')
        or (isNew and 'Новая глава' or 'Редактирование главы')
    local sub = sec.name
    local chapter = sec.chapters[ked.ch]
    if isItem and chapter then sub = sec.name .. ' / ' .. binder.cut(chapter.title, 40) end
    rrf(dl, V(pos.x + 24, pos.y + 16), V(pos.x + 64, pos.y + 56), U(P.active), 12)
    rr(dl, V(pos.x + 24.5, pos.y + 16.5), V(pos.x + 63.5, pos.y + 55.5), U(P.accent, 0.45), 12, 15, 1)
    centerText(dl, pos.x + 24, pos.y + 16, 40, 40, ico('DESKTOP'), U(P.accentSoft))
    dl:AddTextFontPtr(imgui.GetFont(), 18, V(pos.x + 76, pos.y + 18), U(P.text), title)
    dl:AddText(V(pos.x + 76, pos.y + 44), U(P.muted), sub)
    dl:AddLine(V(pos.x + 24, pos.y + 72), V(pos.x + RX, pos.y + 72), U(P.line), 1)

    local cx0, cy0 = pos.x + W - 40, pos.y + 16
    imgui.SetCursorScreenPos(V(cx0, cy0))
    if imgui.InvisibleButton('##kclose', V(24, 24)) then editor[0] = false end
    local ect = hot('kclose', imgui.IsItemHovered())
    if ect > 0.01 then dl:AddCircleFilled(V(cx0 + 12, cy0 + 12), 14, U(P.danger, 0.22 * ect), 32) end
    local xc = U(lerpC(P.muted, P.danger, ect))
    dl:AddLine(V(cx0 + 7, cy0 + 7), V(cx0 + 17, cy0 + 17), xc, 1.6)
    dl:AddLine(V(cx0 + 17, cy0 + 7), V(cx0 + 7, cy0 + 17), xc, 1.6)

    pushInput()
    imgui.PushItemWidth(LW)
    if not isItem then
        imgui.SetCursorPos(V(24, 86));  label('Название главы')
        imgui.SetCursorPos(V(24, 106))
        imgui.InputText('##kted_title', ked.title, ffi.sizeof(ked.title))
    else
        imgui.SetCursorPos(V(24, 86));  label('Описание пункта')
        imgui.SetCursorPos(V(24, 106))
        imgui.InputText('##kted_text', ked.text, ffi.sizeof(ked.text))

        if term then
            imgui.SetCursorPos(V(24, 154)); label('Срок (степень 1-10)')
            local items = {}
            for n = 1, sec.max do items[n] = tostring(n) end
            local r = segTabs(dl, '##kval', pos.x + 24, pos.y + 174, items, ked.val)
            if r then ked.val = r end

            if sec.reason then
                imgui.SetCursorPos(V(24, 222)); label('Причина')
                imgui.SetCursorPos(V(24, 242))
                imgui.InputText('##kted_reason', ked.reason, ffi.sizeof(ked.reason))
            end
        else
            imgui.SetCursorPos(V(24, 154)); label(sec.valueLabel)
            if sec.mode == 'pips' then
                local items = {}
                for n = 1, sec.max do items[n] = tostring(n) end
                local r = segTabs(dl, '##kval', pos.x + 24, pos.y + 174, items, ked.val)
                if r then ked.val = r end
            elseif sec.mode == 'money' then
                imgui.SetCursorPos(V(24, 174))
                imgui.PushItemWidth(260)
                if ked.sumCb then
                    imgui.InputText('##kted_sum', ked.sum, ffi.sizeof(ked.sum), imgui.InputTextFlags.CallbackAlways, ked.sumCb)
                else
                    imgui.InputText('##kted_sum', ked.sum, ffi.sizeof(ked.sum), imgui.InputTextFlags.CharsDecimal)
                end
                imgui.PopItemWidth()
                imgui.SameLine()
                imgui.TextColored(P.accentSoft, '$')
            else
                imgui.SetCursorPos(V(24, 174))
                imgui.SliderInt('##kted_min', ked.minutes, 1, 30, '%d мин')
            end

            if sec.reason then
                imgui.SetCursorPos(V(24, 222)); label('Причина')
                imgui.SetCursorPos(V(24, 242))
                imgui.InputText('##kted_reason', ked.reason, ffi.sizeof(ked.reason))
            end
        end
    end
    imgui.PopItemWidth()

    imgui.SetCursorPos(V(24, H - 92))
    local ask = ked.delAsk and (os.clock() - ked.delAsk < 3)
    if ked.err then
        imgui.TextColored(P.danger, ked.err)
    elseif ask and not isItem then
        imgui.TextColored(P.danger, 'Глава будет удалена вместе со всеми пунктами.')
    else
        imgui.TextColored(P.muted, isItem and ('Команда: ' .. binder.kpkFormat(sec) .. '. Общая отыгровка раздела - вкладка Биндер, Системные.')
            or 'Глава объединяет статьи одной темы.')
    end

    imgui.SetCursorPos(V(24, H - 60))
    imgui.PushStyleColor(imgui.Col.Button, P.accent)
    imgui.PushStyleColor(imgui.Col.ButtonHovered, P.accentHov)
    if imgui.Button('Сохранить##ksave', V(200, 36)) then
        local ok, err = binder.kpkCommit()
        ked.err = (not ok) and err or nil
    end
    imgui.PopStyleColor(2)
    imgui.SameLine()
    if imgui.Button('Отмена##kcancel', V(140, 36)) then editor[0] = false end
    if not isNew then
        imgui.SameLine(RX - 120)
        imgui.PushStyleColor(imgui.Col.Text, P.danger)
        if imgui.Button((ask and 'Точно?' or 'Удалить') .. '##kdel', V(120, 36)) then
            if ask then binder.kpkRemove() else ked.delAsk = os.clock() end
        end
        imgui.PopStyleColor(1)
    end
    popInput()

    GA = 1
    imgui.End()
end

function binder.drawSysEditor()
    local S = binder.sysEd
    local e = S.e
    if not e then editor[0] = false; return end
    local ea = ease(clamp(edT, 0, 1))
    local W, H = ED_W, ED_H
    local LW = 652
    local RX = 24 + LW

    local sw, sh = getScreenResolution()
    imgui.SetNextWindowPos(V(sw / 2, sh / 2), imgui.Cond.Appearing, V(0.5, 0.5))
    imgui.SetNextWindowSize(V(W, H), imgui.Cond.Always)
    if S.justOpened then imgui.SetNextWindowFocus(); S.justOpened = false end
    imgui.Begin('RangerHelper Sys Editor', nil,
        imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoSavedSettings +
        imgui.WindowFlags.NoBackground + imgui.WindowFlags.NoResize +
        imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)

    GA = ea
    local dl  = imgui.GetWindowDrawList()
    local pos = imgui.GetWindowPos()
    SM.edBox(pos, W, H)
    local p2  = V(pos.x + W, pos.y + H)

    local _fc = SM.clipOff(dl)
    rrf(dl, pos, p2, U(imgui.ImVec4(P.bg.x, P.bg.y, P.bg.z, 0.99)), 18)
    rr(dl, V(pos.x + 0.5, pos.y + 0.5), V(p2.x - 0.5, p2.y - 0.5), U(P.outline, 0.8), 18, 15, 1.5)
    SM.clipOn(dl, _fc)
    hairline(dl, pos.x + 24, p2.x - 24, pos.y + 1, P.accentSoft, 0.55)

    rrf(dl, V(pos.x + 24, pos.y + 16), V(pos.x + 64, pos.y + 56), U(P.active), 12)
    rr(dl, V(pos.x + 24.5, pos.y + 16.5), V(pos.x + 63.5, pos.y + 55.5), U(P.accent, 0.45), 12, 15, 1)
    centerText(dl, pos.x + 24, pos.y + 16, 40, 40, sysIcon(e), U(P.accentSoft))
    dl:AddTextFontPtr(imgui.GetFont(), 18, V(pos.x + 76, pos.y + 18), U(P.text), 'Системная отыгровка')
    dl:AddText(V(pos.x + 76, pos.y + 44), U(P.muted), e.group .. ' / ' .. e.title)
    dl:AddLine(V(pos.x + 24, pos.y + 72), V(pos.x + RX, pos.y + 72), U(P.line), 1)

    local cx0, cy0 = pos.x + W - 40, pos.y + 16
    imgui.SetCursorScreenPos(V(cx0, cy0))
    if imgui.InvisibleButton('##sclose', V(24, 24)) then editor[0] = false end
    local ect = hot('sclose', imgui.IsItemHovered())
    if ect > 0.01 then dl:AddCircleFilled(V(cx0 + 12, cy0 + 12), 14, U(P.danger, 0.22 * ect), 32) end
    local xc = U(lerpC(P.muted, P.danger, ect))
    dl:AddLine(V(cx0 + 7, cy0 + 7), V(cx0 + 17, cy0 + 17), xc, 1.6)
    dl:AddLine(V(cx0 + 17, cy0 + 7), V(cx0 + 7, cy0 + 17), xc, 1.6)

    pushInput()
    imgui.PushItemWidth(LW)
    imgui.SetCursorPos(V(24, 86)); label('Текст отыгровки')
    local cl = 'Отыгровка включена'
    local cwid = 20 + 10 + SM.tw(cl) + 4
    if checkDraw(dl, '##sys_on', pos.x + RX - cwid, pos.y + 82, S.on, cl) then S.on = not S.on end
    imgui.SetCursorPos(V(24, 110))
    contentInput('##sysrp', V(LW, H - 100 - 110))
    imgui.PopItemWidth()

    imgui.SetCursorPos(V(24, H - 92))
    imgui.TextColored(P.muted, e.hint or '')

    imgui.SetCursorPos(V(24, H - 60))
    imgui.PushStyleColor(imgui.Col.Button, P.accent)
    imgui.PushStyleColor(imgui.Col.ButtonHovered, P.accentHov)
    if imgui.Button('Сохранить##ssave', V(200, 36)) then binder.sysCommit() end
    imgui.PopStyleColor(2)
    imgui.SameLine()
    if imgui.Button('Отмена##scancel', V(140, 36)) then editor[0] = false end
    imgui.SameLine(RX - 170)
    if imgui.Button('По умолчанию##sdef', V(170, 36)) then
        imgui.StrCopy(ed.content, e.def or '')
        ed.curS, ed.curE, ed.setCursor, ed.refocus = nil, nil, nil, nil
    end
    popInput()

    drawTagPanel(dl, pos, true)

    GA = 1
    imgui.End()
end

function binder.drawPieEditor()
    local p = binder.pie
    local e = p.ed
    local isCat = (e.kind == 'cat')
    local ea = ease(clamp(edT, 0, 1))
    local W, H = isCat and 560 or ED_W, isCat and 292 or ED_H
    local LW = isCat and (W - 48) or 652
    local isNew = (e.idx == 0)

    local sw, sh = getScreenResolution()
    imgui.SetNextWindowPos(V(sw / 2, sh / 2), imgui.Cond.Appearing, V(0.5, 0.5))
    imgui.SetNextWindowSize(V(W, H), imgui.Cond.Always)
    if justOpened then imgui.SetNextWindowFocus(); justOpened = false end
    imgui.Begin('RangerHelper Pie Editor', nil,
        imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoSavedSettings +
        imgui.WindowFlags.NoBackground + imgui.WindowFlags.NoResize +
        imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)

    GA = ea
    local dl  = imgui.GetWindowDrawList()
    local pos = imgui.GetWindowPos()
    SM.edBox(pos, W, H)
    local p2  = V(pos.x + W, pos.y + H)

    local _fc = SM.clipOff(dl)
    rrf(dl, pos, p2, U(imgui.ImVec4(P.bg.x, P.bg.y, P.bg.z, 0.99)), 18)
    rr(dl, V(pos.x + 0.5, pos.y + 0.5), V(p2.x - 0.5, p2.y - 0.5), U(P.outline, 0.8), 18, 15, 1.5)
    SM.clipOn(dl, _fc)
    hairline(dl, pos.x + 24, p2.x - 24, pos.y + 1, P.accentSoft, 0.55)

    local title = (isNew and 'Новая ' or 'Редактирование ') .. (isCat and (isNew and 'категория' or 'категории') or (isNew and 'отыгровка' or 'отыгровки'))
    local sub = e.parent and ('Категория: ' .. binder.cut(e.parent.title, 40)) or 'Круговое меню'
    rrf(dl, V(pos.x + 24, pos.y + 16), V(pos.x + 64, pos.y + 56), U(P.active), 12)
    rr(dl, V(pos.x + 24.5, pos.y + 16.5), V(pos.x + 63.5, pos.y + 55.5), U(P.accent, 0.45), 12, 15, 1)
    centerText(dl, pos.x + 24, pos.y + 16, 40, 40, ico('BULLSEYE'), U(P.accentSoft))
    dl:AddTextFontPtr(imgui.GetFont(), 18, V(pos.x + 76, pos.y + 18), U(P.text), title)
    dl:AddText(V(pos.x + 76, pos.y + 44), U(P.muted), sub)
    dl:AddLine(V(pos.x + 24, pos.y + 72), V(pos.x + 24 + LW, pos.y + 72), U(P.line), 1)

    local cx0, cy0 = pos.x + W - 40, pos.y + 16
    imgui.SetCursorScreenPos(V(cx0, cy0))
    if imgui.InvisibleButton('##peclose', V(24, 24)) then editor[0] = false end
    local ect = hot('peclose', imgui.IsItemHovered())
    if ect > 0.01 then dl:AddCircleFilled(V(cx0 + 12, cy0 + 12), 14, U(P.danger, 0.22 * ect), 32) end
    local xc = U(lerpC(P.muted, P.danger, ect))
    dl:AddLine(V(cx0 + 7, cy0 + 7), V(cx0 + 17, cy0 + 17), xc, 1.6)
    dl:AddLine(V(cx0 + 17, cy0 + 7), V(cx0 + 7, cy0 + 17), xc, 1.6)

    pushInput()

    imgui.SetCursorPos(V(24, 86)); label('Название (отображается в кольце)')
    imgui.SetCursorPos(V(24, 106)); imgui.PushItemWidth(LW - 96)
    imgui.InputText('##pename', ed.name, ffi.sizeof(ed.name))
    imgui.PopItemWidth()
    if checkDraw(dl, '##pe_on', pos.x + 24 + LW - 80, pos.y + 111, e.on, 'Вкл.') then e.on = not e.on end

    if isCat then
        imgui.SetCursorPos(V(24, 154))
        imgui.TextColored(P.muted, 'Категория раскрывается кольцом вложенных пунктов при наведении.')
        imgui.SetCursorPos(V(24, 174))
        imgui.TextColored(P.muted, 'Пункты добавляются кнопкой «+» в строке категории (до ' .. p.MAX_KIDS .. ').')
    else
        imgui.SetCursorPos(V(24, 154)); label('Содержимое отыгровки')
        imgui.SetCursorPos(V(24, 174))
        contentInput('##piecontent', V(LW, 300))
    end

    imgui.SetCursorPos(V(24, H - 88))
    if e.err then
        imgui.TextColored(P.danger, e.err)
    elseif not isCat then
        imgui.TextColored(P.muted, 'Каждая строка отправляется отдельно. {paramX} здесь не работают - запуск без аргументов.')
    else
        local ask = e.delAsk and (os.clock() - e.delAsk < 3)
        if ask then imgui.TextColored(P.danger, 'Категория будет удалена вместе со всеми пунктами.') end
    end

    imgui.SetCursorPos(V(24, H - 56))
    imgui.PushStyleColor(imgui.Col.Button, P.accent)
    imgui.PushStyleColor(imgui.Col.ButtonHovered, P.accentHov)
    if imgui.Button('Сохранить##pesave', V(200, 36)) then
        local ok, err = binder.pieCommit()
        e.err = (not ok) and err or nil
    end
    imgui.PopStyleColor(2)
    imgui.SameLine()
    if imgui.Button('Отмена##pecancel', V(140, 36)) then editor[0] = false end
    if not isNew then
        imgui.SameLine(24 + LW - 120)
        local ask = e.delAsk and (os.clock() - e.delAsk < 3)
        imgui.PushStyleColor(imgui.Col.Text, P.danger)
        if imgui.Button((ask and 'Точно?' or 'Удалить') .. '##pedel', V(120, 36)) then
            if ask then
                table.remove(e.list, e.idx)
                binder.pieSave()
                editor[0] = false
            else
                e.delAsk = os.clock()
            end
        end
        imgui.PopStyleColor(1)
    end

    popInput()

    if not isCat then drawTagPanel(dl, pos, true) end

    GA = 1
    editorFocused = imgui.IsWindowFocused(imgui.FocusedFlags.RootAndChildWindows)
    imgui.End()
end

local PANEL_FONT_SIZE = 14

imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil

    local imio = imgui.GetIO()
    pcall(function() imio.ConfigFlags = bit.bor(imio.ConfigFlags, imgui.ConfigFlags.NoMouseCursorChange) end)

    for _, nm in ipairs({ 'NavEnableKeyboard', 'NavEnableGamepad', 'NavEnableSetMousePos' }) do
        pcall(function() imio.ConfigFlags = bit.band(imio.ConfigFlags, bit.bnot(imgui.ConfigFlags[nm])) end)
    end
    imio.Fonts:Clear()
    local sysFonts = 'C:\\Windows\\Fonts\\'
    local ownFonts = CFG_DIR .. '\\fonts\\'

    local baseFile = doesFileExist(sysFonts .. 'arial.ttf') and (sysFonts .. 'arial.ttf') or (ownFonts .. 'Montserrat-Medium.ttf')
    imio.Fonts:AddFontFromFileTTF(baseFile, 14, nil, imio.Fonts:GetGlyphRangesCyrillic())

    local iconConfig = imgui.ImFontConfig()
    iconConfig.MergeMode = true
    iconConfig.PixelSnapH = true
    iconRanges = imgui.new.ImWchar[3](faicons.min_range, faicons.max_range, 0)
    imio.Fonts:AddFontFromMemoryCompressedBase85TTF(
        faicons.get_font_data_base85('solid'), 14, iconConfig, iconRanges
    )

    do
        local logoFile = doesFileExist(sysFonts .. 'impact.ttf') and (sysFonts .. 'impact.ttf') or (ownFonts .. 'Montserrat-SemiBold.ttf')
        if doesFileExist(logoFile) then
            logoFont = imio.Fonts:AddFontFromFileTTF(logoFile, 24, nil, imio.Fonts:GetGlyphRangesCyrillic())
        end
    end

    binder.nf = {}
    for key, file in pairs({ b = 'arialbd.ttf', i = 'ariali.ttf', bi = 'arialbi.ttf' }) do
        local path = 'C:\\Windows\\Fonts\\' .. file
        if doesFileExist(path) then
            local ok, f = pcall(function()
                return imio.Fonts:AddFontFromFileTTF(path, 14, nil, imio.Fonts:GetGlyphRangesCyrillic())
            end)
            if ok and f then binder.nf[key] = f end
        end
    end

    local function addFontAt(path, noIcons)
        if not doesFileExist(path) then return nil end

        local okV, why = false, 'не удалось прочитать файл'
        pcall(function()
            local fh = io.open(path, 'rb')
            if fh then
                local head = fh:read(4)
                local size = fh:seek('end')
                fh:close()
                if head == nil or size == nil then why = 'пустой файл'
                elseif size < 10000 then why = 'файл слишком маленький (' .. tostring(size) .. ' байт)'
                elseif not (head == '\0\1\0\0' or head == 'true' or head == 'OTTO' or head == 'ttcf') then
                    why = 'не TTF/OTF (заголовок ' .. (head:gsub('[^%w]', '?')) .. ')'
                else okV = true end
            end
        end)
        if not okV then print('[Ranger Helper] шрифт пропущен: ' .. path .. ' - ' .. why); return nil end
        local ok, f = pcall(function()
            return imio.Fonts:AddFontFromFileTTF(path, PANEL_FONT_SIZE, nil, imio.Fonts:GetGlyphRangesCyrillic())
        end)
        if not ok or not f then print('[Ranger Helper] ImGui не смог загрузить шрифт: ' .. path); return nil end
        if not noIcons then
            pcall(function()
                local cfg = imgui.ImFontConfig()
                cfg.MergeMode = true
                cfg.PixelSnapH = true
                local rg = imgui.new.ImWchar[3](faicons.min_range, faicons.max_range, 0)
                fontKeep[#fontKeep + 1] = rg
                imio.Fonts:AddFontFromMemoryCompressedBase85TTF(faicons.get_font_data_base85('solid'), PANEL_FONT_SIZE, cfg, rg)
            end)
        end
        return f
    end
    local function addPanelFont(file) return addFontAt(CFG_DIR .. '\\fonts\\' .. file) end
    panelFont  = addPanelFont('Montserrat-Medium.ttf')
    panelFontB = addPanelFont('Montserrat-SemiBold.ttf') or panelFont

    binder.panelFontX = addPanelFont('Montserrat-Bold.ttf') or panelFontB

    local function firstFont(list)
        for _, p in ipairs(list) do
            local f = addFontAt(p, true)
            if f then return f end
        end
    end
    local fd = CFG_DIR .. '\\fonts\\'
    binder.tabFontSemi = firstFont({ fd .. 'Segoe UI Semibold.ttf', fd .. 'Segoe_UI_Semibold.ttf', fd .. 'SegoeUI-Semibold.ttf', fd .. 'seguisb.ttf', 'C:\\Windows\\Fonts\\seguisb.ttf' })
    binder.tabFontBold = firstFont({ fd .. 'Segoe UI Bold.ttf', fd .. 'Segoe_UI_Bold.ttf', fd .. 'SegoeUI-Bold.ttf', fd .. 'segoeuib.ttf', 'C:\\Windows\\Fonts\\segoeuib.ttf' })
        or binder.tabFontSemi

    binder.tabFontReg = firstFont({ fd .. 'Segoe UI.ttf', fd .. 'segoeui.ttf', fd .. 'Segoe_UI.ttf', 'C:\\Windows\\Fonts\\segoeui.ttf' }) or panelFont
    if not binder.tabFontSemi then

        print('[Ranger Helper] TAB: Segoe UI Semibold не загружен, используется Montserrat')
        binder.tabFontSemi = panelFontB
        binder.tabFontBold = binder.panelFontX
    end

    binder.tabIconFont = nil
    pcall(function()
        local cps, seen = {}, {}
        for _, nm in ipairs({ 'COPY', 'PHONE', 'CHECK', 'MAGNIFYING_GLASS' }) do
            local g = ico(nm)
            if #g == 3 then
                local b1, b2, b3 = g:byte(1, 3)
                local cp = bit.bor(bit.lshift(bit.band(b1, 0x0F), 12), bit.lshift(bit.band(b2, 0x3F), 6), bit.band(b3, 0x3F))
                if not seen[cp] then seen[cp] = true; cps[#cps + 1] = cp end
            end
        end
        if #cps > 0 then
            local rg = imgui.new.ImWchar[#cps * 2 + 1]()
            for i, cp in ipairs(cps) do rg[(i - 1) * 2], rg[(i - 1) * 2 + 1] = cp, cp end
            rg[#cps * 2] = 0
            fontKeep[#fontKeep + 1] = rg
            binder.tabIconFont = imio.Fonts:AddFontFromMemoryCompressedBase85TTF(faicons.get_font_data_base85('solid'), PANEL_FONT_SIZE, nil, rg)
        end
    end)

    imgui.SwitchContext()
    local style = imgui.GetStyle()
    pcall(function()
        style.AntiAliasedFill, style.AntiAliasedLines = true, true
        style.CurveTessellationTol = 0.5
        style.CircleSegmentMaxError = 0.25
    end)
    style.WindowRounding   = 8
    style.WindowBorderSize = 0
    style.FrameBorderSize  = 0
    style.ScrollbarSize    = 6
    style.ScrollbarRounding = 6
    style.GrabRounding     = 9
    style.PopupRounding    = 12
    style.PopupBorderSize  = 0
    style.Colors[imgui.Col.ScrollbarBg]          = imgui.ImVec4(0, 0, 0, 0)
    style.Colors[imgui.Col.ScrollbarGrab]        = C(58, 66, 98)
    style.Colors[imgui.Col.ScrollbarGrabHovered] = C(90, 100, 140)
    style.Colors[imgui.Col.ScrollbarGrabActive]  = C(110, 138, 250)
    SM.imReady = true
end)

local wasLocked = false
imgui.OnFrame(function() return window[0] end, function(player)
    DT = clamp(imgui.GetIO().DeltaTime, 0.001, 0.1)
    UI_ALPHA = 1.0

    pcall(function()
        local kd = imgui.GetIO().KeysDown
        local ks = SM.stuckKeys
        if not ks then ks = { 0x09, 0x0D, 0x25, 0x26, 0x27, 0x28 }; SM.stuckKeys = ks end
        for i = 1, #ks do
            local k = ks[i]
            if kd[k] and not vkDown(k) then kd[k] = false end
        end
    end)

    local liveStyle = imgui.GetStyle()
    liveStyle.Colors[imgui.Col.ScrollbarGrab] = P.accent
    liveStyle.Colors[imgui.Col.ScrollbarGrabHovered] = P.accentHov
    liveStyle.Colors[imgui.Col.ScrollbarGrabActive] = P.accentHov
    liveStyle.Colors[imgui.Col.SliderGrab] = P.accent
    liveStyle.Colors[imgui.Col.SliderGrabActive] = P.accentHov

    mainFocused, editorFocused = false, false

    edT = edT + ((editor[0] and 1 or 0) - edT) * clamp(DT * 10, 0, 1)
    if editor[0] then
        if edT > 0.995 then edT = 1 end
    elseif edT < 0.01 then
        edT = 0
    end

    drawMain()
    if edT > 0 then drawOverlay() end
    if editor[0] then
        if editMode == 'kpk' then drawKpkEditor()
        elseif editMode == 'sys' then binder.drawSysEditor()
        elseif editMode == 'pie' then binder.drawPieEditor()
        else drawEditor() end
    end

    if scrollReset > 0 then scrollReset = scrollReset - 1 end

    if cfgDirty and not imgui.IsMouseDown(0) then saveConfig() end
    if binder.needSync and not imgui.IsMouseDown(0) then binder.needSync = false; binder.sync() end
    player.LockPlayer = editor[0] or mainFocused or editorFocused
end)

local DLG_W, DLG_H = 520, 480

local function drawDialogWindow(player)
    DT = clamp(imgui.GetIO().DeltaTime, 0.001, 0.1)
    UI_ALPHA, GA = 1.0, 1
    local dlg = binder.dlg
    local d = binder.dlgCurrent()
    if not d then return end

    if dlg.aimId and not H.valid(dlg.aimId) then binder.dlgFlush(); return end

    local sw, sh = getScreenResolution()
    imgui.SetNextWindowPos(V(sw / 2, sh / 2), imgui.Cond.FirstUseEver, V(0.5, 0.5))
    imgui.SetNextWindowSize(V(DLG_W, DLG_H), imgui.Cond.Always)
    if dlg.focusNext then imgui.SetNextWindowFocus(); dlg.focusNext = false end
    imgui.Begin('RangerHelper Dialog', nil,
        imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoSavedSettings +
        imgui.WindowFlags.NoBackground + imgui.WindowFlags.NoResize +
        imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)

    local dl  = imgui.GetWindowDrawList()
    local pos = imgui.GetWindowPos()
    local p2  = V(pos.x + DLG_W, pos.y + DLG_H)

    local _fc = SM.clipOff(dl)
    rrf(dl, pos, p2, U(imgui.ImVec4(P.bg.x, P.bg.y, P.bg.z, 0.99)), 18)
    rr(dl, V(pos.x + 0.5, pos.y + 0.5), V(p2.x - 0.5, p2.y - 0.5), U(P.outline, 0.8), 18, 15, 1.5)
    SM.clipOn(dl, _fc)
    hairline(dl, pos.x + 24, p2.x - 24, pos.y + 1, P.accentSoft, 0.55)

    rrf(dl, V(pos.x + 24, pos.y + 16), V(pos.x + 64, pos.y + 56), U(P.active), 12)
    rr(dl, V(pos.x + 24.5, pos.y + 16.5), V(pos.x + 63.5, pos.y + 55.5), U(P.accent, 0.45), 12, 15, 1)
    centerText(dl, pos.x + 24, pos.y + 16, 40, 40, ico('LIST'), U(P.accentSoft))
    dl:AddTextFontPtr(imgui.GetFont(), 18, V(pos.x + 76, pos.y + 18), U(P.text), binder.cut(d.title, 40))
    local sub = 'Двойной клик или Enter - выбрать, Esc - закрыть'
    if dlg.aimId then
        local okN, nick = pcall(sampGetPlayerNickname, dlg.aimId)
        sub = 'Цель: ' .. (okN and nick or '?') .. '[' .. dlg.aimId .. '] - двойной клик или Enter'
    end
    dl:AddText(V(pos.x + 76, pos.y + 44), U(P.muted), sub)
    dl:AddLine(V(pos.x + 24, pos.y + 72), V(p2.x - 24, pos.y + 72), U(P.line), 1)

    local base, cdl = beginList('##dlglist', pos.x + 24, pos.y + 84, DLG_W - 48, DLG_H - 84 - 76)
    local iw = DLG_W - 48 - 10
    for i, b in ipairs(d.buttons) do
        local y = base.y + (i - 1) * 46
        imgui.SetCursorScreenPos(V(base.x, y))
        if imgui.InvisibleButton('##dbtn' .. i, V(iw, 40)) then
            dlg.selected = i
            if dlg.click.id == i and os.clock() - dlg.click.t < 0.3 then
                binder.dlgSelect()
            else
                dlg.click.id, dlg.click.t = i, os.clock()
            end
        end
        local t = hot('dbtn' .. i, imgui.IsItemHovered())
        local sel = (dlg.selected == i)
        card(cdl, base.x, y, iw, 40, 10, sel and P.active or lerpC(P.card, P.cardHover, t),
            sel and P.accent or lerpC(P.line, P.accent, t * 0.7))
        if sel then rrf(cdl, V(base.x + 4, y + 11), V(base.x + 7, y + 29), U(P.accent), 2) end
        centerText(cdl, base.x, y, iw, 40, binder.cut(b.title, 60), U(P.text))
        if dlg.scrollTo == i then
            if not imgui.IsItemVisible() then imgui.SetScrollHereY(0.5) end
            dlg.scrollTo = nil
        end
    end
    endList(base, #d.buttons * 46)

    local fy = pos.y + DLG_H - 58
    if #dlg.stack > 1 then
        if button(dl, '##dback', pos.x + 24, fy, 110, 38, 'Назад', false) then binder.dlgPop() end
    end
    if button(dl, '##dpick', pos.x + DLG_W / 2 - 70, fy, 140, 38, 'Выбрать', true) then binder.dlgSelect() end
    if button(dl, '##dclose', p2.x - 24 - 110, fy, 110, 38, 'Закрыть', false) then binder.dlgFlush() end

    dlg.focused = imgui.IsWindowFocused(imgui.FocusedFlags.RootAndChildWindows)
    player.LockPlayer = dlg.focused
    imgui.End()
end

imgui.OnFrame(function() return binder.ready and #binder.dlg.stack > 0 and not isPauseMenuActive() end,
    function(player) drawDialogWindow(player) end)

imgui.OnFrame(function() return binder.ready and (binder.kpk.pop.open or binder.kpk.curOn) end,
    function(player) binder.kpkFrame(player) end)

imgui.OnFrame(function() return binder.ready and (binder.note.open or binder.note.curOn) end,
    function(player) binder.noteFrame(player) end)

binder.DEP_FILE = CFG_DIR .. '\\dep.json'
binder.DEP_LINE_MAX = 136
binder.DEP_MSG_MAX  = 121
binder.DEP_LINE_CEIL = 136
binder.dep = {
    cmd = 'dep', auto = true, wrap = true, write = false, form = '[#1] $ [#2]:',
    tags = { 'Всем' }, waves = { '-' }, t1 = 1, w = 1, t2 = 1, limit = binder.DEP_MSG_MAX,
    open = false, curOn = false, edit = false, typing = false, focusNext = false,
    busy = false, queue = {}, worker = false, hooked = false, chatCur = false,
    maxParts = 8,
    lineMax = binder.DEP_LINE_MAX, lineFixed = false, hdr = 42, pending = nil, retry = 0,
    inTag = new.char[64](), inWave = new.char[64](), msg = new.char[1024](), refocus = false,
}

function binder.depSave()
    local d = binder.dep
    if not doesDirectoryExist(CFG_DIR) then createDirectory(CFG_DIR) end
    local function arr(t)
        local o = {}
        for i, v in ipairs(t) do o[i] = jsonStr(v) end
        return '[' .. table.concat(o, ', ') .. ']'
    end
    local text = table.concat({
        '{',
        '  "cmd": ' .. jsonStr(d.cmd) .. ',',
        '  "auto": ' .. tostring(d.auto) .. ',',
        '  "wrap": ' .. tostring(d.wrap) .. ',',
        '  "write": ' .. tostring(d.write) .. ',',
        '  "form": ' .. jsonStr(d.form) .. ',',
        '  "tags": ' .. arr(d.tags) .. ',',
        '  "waves": ' .. arr(d.waves) .. ',',
        '  "t1": ' .. d.t1 .. ',',
        '  "w": ' .. d.w .. ',',
        '  "t2": ' .. d.t2 .. ',',
        '  "limit": ' .. d.limit .. ',',
        '  "lineMax": ' .. d.lineMax .. ',',
        '  "lineFixed": ' .. tostring(d.lineFixed),
        '}',
    }, '\n') .. '\n'
    local f = io.open(binder.DEP_FILE, 'wb')
    if not f then return false end
    f:write(text); f:close()
    return true
end

function binder.depLoad()
    local f = io.open(binder.DEP_FILE, 'rb')
    if not f then return false end
    local text = f:read('*a'); f:close()
    text = text:gsub('^\239\187\191', '')
    local ok, data = pcall(decodeJson, text)
    if not ok or type(data) ~= 'table' then
        print('[RangerHelper] dep.json повреждён, используются значения по умолчанию')
        return true
    end
    local d = binder.dep
    if type(data.cmd) == 'string' and #data.cmd >= 1 and #data.cmd <= 24 and data.cmd:match('^[%w_]+$')
        and data.cmd:lower() ~= 'd' then d.cmd = data.cmd end
    d.auto = true
    if type(data.wrap) == 'boolean' then d.wrap = data.wrap end
    d.write = false
    if type(data.form) == 'string' and binder.trim(data.form) ~= '' and #data.form <= 60 then d.form = binder.trim(data.form) end
    local function clean(src, maxChars)
        local out, seen = {}, {}
        for _, v in ipairs(type(src) == 'table' and src or {}) do
            if type(v) == 'string' then
                v = binder.trim(v)
                local key = binder.lowerU8(v)
                if v ~= '' and not seen[key] and binder.cut(v, maxChars) == v and #out < 30 then
                    seen[key] = true
                    out[#out + 1] = v
                end
            end
        end
        return out
    end
    local tags, waves = clean(data.tags, 24), clean(data.waves, 12)
    if #tags > 0 then d.tags = tags end
    if #waves > 0 then d.waves = waves end
    d.t1 = clamp(math.floor(tonumber(data.t1) or 1), 1, #d.tags)
    d.t2 = clamp(math.floor(tonumber(data.t2) or 1), 1, #d.tags)
    d.w = clamp(math.floor(tonumber(data.w) or 1), 1, #d.waves)
    d.limit = binder.DEP_MSG_MAX
    return true
end

function binder.depForm()
    local d = binder.dep
    local t1, wv, t2 = d.tags[d.t1] or '', d.waves[d.w] or '', d.tags[d.t2] or ''
    local f, out, i = d.form, {}, 1
    while i <= #f do
        local c2 = f:sub(i, i + 1)
        if c2 == '#1' then out[#out + 1] = t1; i = i + 2
        elseif c2 == '#2' then out[#out + 1] = t2; i = i + 2
        elseif f:sub(i, i) == '$' then out[#out + 1] = wv; i = i + 1
        else out[#out + 1] = f:sub(i, i); i = i + 1 end
    end
    return table.concat(out)
end

function binder.depSetCmd(raw)
    local c = binder.trim((tostring(raw or ''):gsub('^/+', '')))
    local d = binder.dep
    if c == d.cmd then return true end
    if c == '' or #c > 24 or not c:match('^[A-Za-z0-9_]+$') then
        binder.say('Команда: только латиница, цифры и _')
        return false
    end
    if c:lower() == 'd' then
        binder.say('Команда {aaaaaa}/d{ffffff} - серверная рация, выберите другое имя.')
        return false
    end
    local who = binder.cmdTaken(c:lower(), nil, 'dep')
    if who then binder.say('Команда {aaaaaa}/' .. c .. '{ffffff} уже занята: ' .. who); return false end
    pcall(sampUnregisterChatCommand, d.cmd)
    d.cmd = c
    if binder.ready then pcall(sampRegisterChatCommand, c, function() binder.depToggle() end) end
    binder.depSave()
    return true
end

function binder.depFormField(dl, x, y, w)
    local d, st = binder.dep, binder.fn
    local buf = st.bufs.depform
    if not buf then buf = new.char[64](); st.bufs.depform = buf; imgui.StrCopy(buf, d.form) end
    imgui.SetCursorScreenPos(V(x, y))
    pushInput()
    imgui.PushStyleColor(imgui.Col.FrameBg, P.chip)
    imgui.PushStyleColor(imgui.Col.FrameBgHovered, P.item)
    imgui.PushStyleColor(imgui.Col.FrameBgActive, P.active)
    imgui.PushItemWidth(w)
    imgui.InputTextWithHint('##fn_depform', '[#1] $ [#2]:', buf, ffi.sizeof(buf))
    imgui.PopItemWidth()
    local act, hov = imgui.IsItemActive(), imgui.IsItemHovered()
    local mn, mx = imgui.GetItemRectMin(), imgui.GetItemRectMax()
    imgui.PopStyleColor(3)
    popInput()
    local ht = hot('fn_ring_depform', act or hov)
    if act and not SM.low then
        rr(dl, V(mn.x - 2, mn.y - 2), V(mx.x + 2, mx.y + 2), U(P.accent, 0.25), 11, 15, 2)
    end
    rr(dl, V(mn.x + 0.5, mn.y + 0.5), V(mx.x - 0.5, mx.y - 0.5), U(P.accent, act and 1 or (0.45 + 0.4 * ht)), 9, 15, 1.2)
    if act then
        st.was.depform = true
    else
        if st.was.depform then
            st.was.depform = false
            local txt = binder.trim(ffi.string(buf))
            if txt == '' then
                binder.say('Форма префикса не может быть пустой.')
            elseif txt ~= d.form then
                d.form = txt
                binder.depSave()
            end
        end
        if ffi.string(buf) ~= d.form then imgui.StrCopy(buf, d.form) end
    end
end

function binder.depSplit(body, prefix, limit)
    local pre = prefix ~= '' and (prefix .. ' ') or ''
    local cap = limit - #pre
    if #body <= cap then return { pre .. body } end
    cap = math.max(cap, 24)
    local chunks, cur = {}, ''
    local function room() return cap - 4 - (#chunks > 0 and 4 or 0) end
    for word in body:gmatch('%S+') do
        while true do
            local c = room()
            if cur == '' then
                if #word <= c then cur = word; break end
                chunks[#chunks + 1] = word:sub(1, c)
                word = word:sub(c + 1)
            elseif #cur + 1 + #word <= c then
                cur = cur .. ' ' .. word
                break
            else
                chunks[#chunks + 1] = cur
                cur = ''
            end
        end
    end
    if cur ~= '' then chunks[#chunks + 1] = cur end

    if #chunks >= 2 and #chunks[#chunks - 1] + 1 + #chunks[#chunks] <= cap - 4 then
        chunks[#chunks - 1] = chunks[#chunks - 1] .. ' ' .. chunks[#chunks]
        chunks[#chunks] = nil
    end
    local n = math.min(#chunks, binder.dep.maxParts)
    local out = {}
    for i = 1, n do
        out[i] = pre .. (i > 1 and '... ' or '') .. chunks[i] .. (i < #chunks and ' ...' or '')
    end
    if #chunks > n then binder.say('Сообщение слишком длинное: отправлено частей: ' .. n .. ', остаток отброшен.') end
    return out
end

function binder.depNorm(t)
    return binder.trim((t:gsub('%s+', ' ')))
end

function binder.depVerify(p)
    local d = binder.dep
    local exp, got = binder.depNorm(p.expect), binder.depNorm(p.echo)
    local full = got
    if #p.extra > 0 then full = binder.depNorm(got .. ' ' .. table.concat(p.extra, ' ')) end
    if full == exp then
        if #p.extra > 0 then

            d.limit = clamp(#got, 30, binder.DEP_MSG_MAX)
            binder.depSave()
        end
        return 'ok'
    end
    if #got < #exp and exp:sub(1, #got) == got then
        d.limit = clamp(#got, 30, binder.DEP_MSG_MAX)
        binder.depSave()
        return 'cut', #got
    end
    return 'ok'
end

function binder.depPump()
    local d = binder.dep
    if d.worker then return end
    d.worker = true
    lua_thread.create(function()
        while #d.queue > 0 do
            local msg = table.remove(d.queue, 1)
            local expect = msg:match('^/[dD]%s+(.*)$')
            local p = { expect = expect or '', extra = {} }
            d.pending = expect and p or nil
            d.busy = true
            pcall(sampSendChat, msg)
            d.busy = false
            if expect then
                local t = 0
                while not p.echo and t < 3500 do wait(100); t = t + 100 end
                if not p.echo then
                    d.pending = nil
                    if d.retry < 2 then
                        d.retry = d.retry + 1
                        table.insert(d.queue, 1, msg)
                        binder.say('Часть /d не подтверждена сервером, отправляю ещё раз (' .. d.retry .. ').')
                    else
                        d.retry = 0
                        binder.say('Часть /d так и не дошла: {aaaaaa}' .. u8:encode(expect))
                    end
                else
                    wait(450)
                    d.pending = nil
                    local res, cutAt = binder.depVerify(p)
                    if res == 'cut' and d.retry < 3 then
                        d.retry = d.retry + 1
                        local exp = binder.depNorm(p.expect)
                        local got = binder.depNorm(p.echo)
                        local tailFrom = cutAt + 1
                        if exp:sub(tailFrom, tailFrom) ~= ' ' then
                            local sp = got:match('^.*() ')
                            if sp then tailFrom = sp + 1 end
                        end
                        local prefix = u8:decode(binder.depForm())
                        local tail = binder.trim(exp:sub(tailFrom))
                        if #prefix > 0 and exp:sub(1, #prefix) == prefix and tailFrom > #prefix + 1 and tail ~= '' then
                            local parts = binder.depSplit('... ' .. tail, prefix, d.limit)
                            for i = #parts, 1, -1 do table.insert(d.queue, 1, '/d ' .. parts[i]) end
                            binder.say('Сервер обрезал /d, лимит сообщения уточнён: {aaaaaa}' .. d.limit .. '{ffffff} симв. Дослал хвост.')
                        end
                    else
                        d.retry = 0
                    end
                end
            end
            if #d.queue > 0 then wait(1500) end
        end
        d.pending = nil
        d.worker = false
    end)
end

function binder.depQueue(body)
    local d = binder.dep
    local prefix = u8:decode(binder.depForm())
    local parts
    if d.wrap then
        parts = binder.depSplit(body, prefix, d.limit)
    else
        parts = { (prefix ~= '' and (prefix .. ' ') or '') .. body }
    end
    for _, p in ipairs(parts) do d.queue[#d.queue + 1] = '/d ' .. p end
    binder.depPump()
end

function binder.depPost(utf)
    local body = binder.trim(utf)
    if body == '' then return false end
    binder.depQueue(u8:decode(body))
    return true
end

function binder.depSend(text)
    local d = binder.dep
    if d.busy or not d.auto then return end
    if (binder.fromScript or 0) > 0 then return end
    local body = text:match('^/[dD]%s+(.-)%s*$')
    if not body or body == '' then return end
    local prefix = u8:decode(binder.depForm())
    if prefix ~= '' and body:sub(1, #prefix) == prefix then return end
    binder.depQueue(body)
    return false
end

function binder.depLearn(text)
    if type(text) ~= 'string' then return end
    local clean = text:gsub('{%x%x%x%x%x%x}', '')
    local d = binder.dep
    if clean:sub(1, 3) ~= '[D]' then
        local p = d.pending
        if p and p.echo and #p.extra < 3 then p.extra[#p.extra + 1] = binder.trim(clean) end
        return
    end
    local ok, me = pcall(function() return sampGetPlayerNickname(H.myId()) end)
    if not ok or type(me) ~= 'string' or me == '' then return end
    local esc = me:gsub('%p', '%%%0')
    local _, e = clean:find('^%[D%][^\n]-' .. esc .. '%[%d+%]:%s')
    if not e then return end
    d.hdr = e
    local p = d.pending
    if p and not p.echo then p.echo = binder.trim(clean:sub(e + 1)) end
end

binder.TAB_FILE = CFG_DIR .. '\\tab.json'
binder.tab = {
    enabled = false, hoverColor = true, sortKey = 'id', sortDesc = false,
    list = {}, shown = {}, server = '', updated = 0, sel = -1,
    q = new.char[64](),
    open = false, selIdx = 1, hv = {}, openAt = 0, lastDraw = 0, scrollTop = true, vis = 0, wasOpen = false, se = 0,
    sc = { cur = 0, target = 0, last = 0, anim = false }, callAt = nil, callId = nil,
}
binder.TAB_WHITE = imgui.ImVec4(1, 1, 1, 1)

binder.TAB_JS_OFF = [==[
try {
    window._oldTabOff = true;
    if (window._oldTabInt) { clearInterval(window._oldTabInt); window._oldTabInt = null; }
    if (window._oldTabOrig) { window.executeEvent = window._oldTabOrig; window._oldTabOrig = null; window._oldTabHook = false; }
    if (typeof window.executeEvent === 'function') {
        window.executeEvent('event.scoreboard.setDisabled', `[false]`);
        window.executeEvent('event.scoreboard.setScoreboardDisabled', `[false]`);
    }
} catch (e) {}
]==]

function binder.tabSave()
    local t = binder.tab
    if not doesDirectoryExist(CFG_DIR) then createDirectory(CFG_DIR) end
    local f = io.open(binder.TAB_FILE, 'wb')
    if not f then return false end
    f:write('{\n  "enabled": ' .. tostring(t.enabled) .. ',\n  "hoverColor": ' .. tostring(t.hoverColor)
        .. ',\n  "sortKey": ' .. jsonStr(t.sortKey) .. ',\n  "sortDesc": ' .. tostring(t.sortDesc) .. '\n}\n')
    f:close()
    return true
end

function binder.tabLoad()
    local f = io.open(binder.TAB_FILE, 'rb')
    if not f then return false end
    local text = f:read('*a'); f:close()
    text = text:gsub('^\239\187\191', '')
    local ok, data = pcall(decodeJson, text)
    if not ok or type(data) ~= 'table' then return true end
    local t = binder.tab
    if type(data.enabled) == 'boolean' then t.enabled = data.enabled end
    if type(data.hoverColor) == 'boolean' then t.hoverColor = data.hoverColor end
    if type(data.sortDesc) == 'boolean' then t.sortDesc = data.sortDesc end
    if data.sortKey == 'id' or data.sortKey == 'nick' or data.sortKey == 'score' or data.sortKey == 'ping' then t.sortKey = data.sortKey end
    return true
end

function binder.tabHeal()
    local mem = require 'memory'
    local addr = sampGetBase() + ((getGameGlobal(707) <= 21) and 436752 or 452960)
    local f = io.open(CFG_DIR .. '\\tab_orig_byte.txt', 'rb')
    if not f then return end
    local orig = tonumber(f:read('*a')); f:close()
    if orig and orig ~= 195 and mem.getuint8(addr, true) == 195 then mem.write(addr, orig, 1, true) end
end

function binder.tabRunJs(js)
    local code = ('(() => {%s})()'):format(js)
    local bs = raknetNewBitStream()
    raknetBitStreamWriteInt8(bs, 17)
    raknetBitStreamWriteInt32(bs, 0)
    raknetBitStreamWriteInt16(bs, #code)
    raknetBitStreamWriteInt8(bs, 0)
    raknetBitStreamWriteString(bs, code)
    raknetEmulPacketReceiveBitStream(220, bs)
    raknetDeleteBitStream(bs)
end

function binder.tabApply()
    local t = binder.tab
    if not t.enabled then t.open = false end
end

function binder.tabCleanup()
    pcall(binder.tabHeal)
    pcall(binder.tabRunJs, binder.TAB_JS_OFF)
end

function binder.tabUpdate(force)
    local t = binder.tab
    if not force and os.clock() - t.updated < 1.0 then return end
    t.updated = os.clock()
    local list = {}
    local function add(id)
        local ok, nick = pcall(sampGetPlayerNickname, id)
        if not ok or type(nick) ~= 'string' then return end
        local c = sampGetPlayerColor(id)
        list[#list + 1] = {
            id = id, nick = nick, score = sampGetPlayerScore(id), ping = sampGetPlayerPing(id),
            r = bit.band(bit.rshift(c, 16), 255), g = bit.band(bit.rshift(c, 8), 255), b = bit.band(c, 255),
            color = imgui.ImVec4(bit.band(bit.rshift(c, 16), 255) / 255, bit.band(bit.rshift(c, 8), 255) / 255, bit.band(c, 255) / 255, 1),
        }
    end
    local okMe, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if okMe then add(myId) end
    for id = 0, 999 do
        if not (okMe and id == myId) and sampIsPlayerConnected(id) and not sampIsPlayerNpc(id) then add(id) end
    end
    local key, desc = t.sortKey, t.sortDesc
    table.sort(list, function(a, b)
        local a_me, b_me = (okMe and a.id == myId), (okMe and b.id == myId)
        if a_me ~= b_me then return a_me end
        local va, vb
        if key == 'nick' then va, vb = a.nick:lower(), b.nick:lower() else va, vb = a[key], b[key] end
        if va == vb then return a.id < b.id end
        if desc then return va > vb end
        return va < vb
    end)
    t.list = list
    local q = binder.trim(ffi.string(t.q))
    if q == '' then
        t.shown = list
    else
        local shown, num, low = {}, tonumber(q), q:lower()
        for _, p in ipairs(list) do
            if num then
                if p.id == num then shown[#shown + 1] = p end
            elseif p.nick:lower():find(low, 1, true) then
                shown[#shown + 1] = p
            end
        end
        t.shown = shown
    end
    if #t.shown < t.selIdx then t.selIdx = math.max(1, #t.shown) end
    local ok, name = pcall(sampGetCurrentServerName)
    t.server = (ok and type(name) == 'string') and u8:encode(name) or ''
end

function binder.tabClick(id)
    pcall(function()
        local bs = raknetNewBitStream()
        raknetBitStreamWriteInt16(bs, id)
        raknetBitStreamWriteInt8(bs, 0)
        raknetSendRpc(23, bs)
        raknetDeleteBitStream(bs)
    end)
    pcall(sampToggleScoreboard, false)
    binder.tab.open = false
end

function binder.tabCall(id)
    local t = binder.tab
    t.callAt, t.callId = os.clock(), id
    pcall(sampSendChat, '/number ' .. id)
    t.open = false
end

function binder.tabCallMsg(text)
    local t = binder.tab
    if not t.callAt then return end
    if os.clock() - t.callAt > 6 then t.callAt, t.callId = nil, nil; return end

    local clean = text:gsub('{%x%x%x%x%x%x}', '')
    local id, num = clean:match('%[(%d+)%]:%s+(%d+)')
    if not num and text:find('{33CCFF}%d+') then num = text:match('{33CCFF}(%d+)') end
    if not num then return end
    if id and tonumber(id) ~= t.callId then return end
    t.callAt, t.callId = nil, nil
    pcall(sampSendChat, '/call ' .. num)
    return false
end

function binder.tabCallDialog(dialogId, style, title, b1, b2, text)
    local t = binder.tab
    if not t.callAt then return end
    if os.clock() - t.callAt > 6 then t.callAt, t.callId = nil, nil; return end
    local raw = tostring(text or ''):gsub('{%x%x%x%x%x%x}', '')
    local clean = raw
    local okU, conv = pcall(function() return u8:encode(raw) end)
    if okU and type(conv) == 'string' then clean = conv end
    local num = clean:match('Номер телефона:%s*(%d+)') or clean:match(':%s*(%d+)%s*$')
    local id = clean:match('%[(%d+)%]')
    if not (num and id and tonumber(id) == t.callId) then return end
    t.callAt, t.callId = nil, nil
    pcall(sampSendDialogResponse, dialogId, 0, -1, '')
    lua_thread.create(function()
        wait(150)
        pcall(sampSendChat, '/call ' .. num)
    end)
    return false
end

function binder.tabKey(wparam, lparam)
    local t = binder.tab
    if not t.enabled or not binder.ready then return false end
    if wparam == vkeys.VK_ESCAPE and t.open then
        consumeWindowMessage(true, false)
        t.open = false
        return true
    end
    if wparam == vkeys.VK_TAB and bit.band(bit.rshift(lparam, 30), 1) == 0 then
        local okB, blocked = pcall(function()
            return sampIsChatInputActive() or sampIsDialogActive() or isSampfuncsConsoleActive() or isPauseMenuActive()
        end)

        local menuBusy = false
        if window[0] or editor[0] then
            local okM, busy = pcall(function()
                return imgui.GetIO().WantTextInput or hotCap ~= 0 or binder.note.cap or ed.capture or binder.pie.cap
            end)
            menuBusy = (not okM) or (busy and true or false)
        end
        if okB and not blocked and not menuBusy then
            consumeWindowMessage(true, false)
            t.open = not t.open
            if t.open and binder.tabFontLog then binder.say(binder.tabFontLog); binder.tabFontLog = nil end
            return true
        end
    end
    return false
end

function binder.tabGuard()
    if binder.tab.enabled and sampIsScoreboardOpen() then sampToggleScoreboard(false) end
end

function binder.tabCenterX(text)
    local w = imgui.GetColumnWidth(-1)
    return imgui.GetColumnOffset(-1) + (w - imgui.CalcTextSize(text).x) / 2
end

function binder.tabColumns(withLabels)
    local now = os.clock()
    local function lab(i, text)
        local e = 1 - (1 - clamp((now - binder.tab.openAt - 0.04 - i * 0.05) / 0.3, 0, 1)) ^ 3
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(P.text.x, P.text.y, P.text.z, P.text.w * e))
        imgui.SetCursorPosX((text == 'Ник' and imgui.GetCursorPosX() or binder.tabCenterX(text)) - (1 - e) * 12)
        imgui.TextUnformatted(text)
        imgui.PopStyleColor()
    end
    imgui.Columns(4, nil, false)
    imgui.SetCursorPosX(20)
    imgui.SetColumnWidth(-1, 90)
    if withLabels then lab(0, 'ID') end
    imgui.NextColumn()
    imgui.SetColumnWidth(-1, 352)
    if withLabels then lab(1, 'Ник') end
    imgui.NextColumn()
    imgui.SetColumnWidth(-1, 250)
    if withLabels then lab(2, 'Уровень') end
    imgui.NextColumn()
    imgui.SetColumnWidth(-1, 118)
    if withLabels then lab(3, 'Пинг') end
    imgui.NextColumn()
end

function binder.tabRowButtons(pl, st, np, rmin, rmax, tw)
    local k = 1 - math.exp(-DT * 16)
    st.b = st.b + ((st.want and 1 or 0) - st.b) * k
    if st.b < 0.01 then st.b = 0; st.over = false; return end
    local e = ease(clamp(st.b, 0, 1))
    local cdl = imgui.GetWindowDrawList()
    local cy = (rmin.y + rmax.y) / 2
    local okM, myId = pcall(H.myId)
    local list = { { 'COPY', 'Копировать ник', 'copy' } }
    if not (okM and pl.id == myId) then list[#list + 1] = { 'PHONE', 'Позвонить', 'call' } end
    local bw, bh, gap = 26, 24, 6
    local x = np.x + tw + 12 - (1 - e) * 14
    local over = false
    local wp, ws = imgui.GetWindowPos(), imgui.GetWindowSize()
    cdl:PushClipRect(V(wp.x, wp.y), V(wp.x + ws.x, wp.y + ws.y), false)
    for _, b in ipairs(list) do
        local p1, p2 = V(x, cy - bh / 2), V(x + bw, cy + bh / 2)
        local hov = st.b > 0.5 and imgui.IsMouseHoveringRect(p1, p2)
        if hov then over = true end
        local flash = (b[3] == 'copy' and st.flash and os.clock() - st.flash < 1.0)
        rrf(cdl, p1, p2, U(hov and P.accent or P.card, e), 7)
        local icon = ico(flash and 'CHECK' or b[1])
        if icon ~= '' then
            local itf = binder.tabIconFont
            if itf then

                local isz = 14
                imgui.PushFont(itf)
                local ts = imgui.CalcTextSize(icon)
                local k = isz / imgui.GetFontSize()
                imgui.PopFont()
                cdl:AddTextFontPtr(itf, isz, V(math.floor(x + (bw - ts.x * k) / 2 + 0.5), math.floor(cy - ts.y * k / 2 + 0.5)), U(P.text, e), icon)
            else
                local ts = imgui.CalcTextSize(icon)
                cdl:AddText(V(math.floor(x + (bw - ts.x) / 2 + 0.5), math.floor(cy - ts.y / 2 + 0.5)), U(P.text, e), icon)
            end
        end
        if hov then
            imgui.SetTooltip(b[2])
            if imgui.IsMouseClicked(0) then
                if b[3] == 'copy' then
                    imgui.SetClipboardText(pl.nick)
                    st.flash = os.clock()
                else
                    binder.tabCall(pl.id)
                end
            end
        end
        x = x + bw + gap
    end
    cdl:PopClipRect()
    st.over = over
end

function binder.tabRow(index, pl)
    local t = binder.tab
    local now = os.clock()
    local isSel = (t.selIdx == index)
    local st = t.hv[pl.id]
    if not st then st = { b = 0, over = false, want = false, h = 0, s = 0 }; t.hv[pl.id] = st end

    imgui.SetCursorPosX(15)

    imgui.PushStyleColor(imgui.Col.Header, imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.HeaderHovered, imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.HeaderActive, imgui.ImVec4(0, 0, 0, 0))
    local clicked = imgui.Selectable('##tsb' .. pl.id, isSel,
        imgui.SelectableFlags.SpanAllColumns + imgui.SelectableFlags.AllowDoubleClick, V(754, 0))
    imgui.PopStyleColor(3)
    if clicked and not st.over then
        t.selIdx = index
        isSel = true
        if imgui.IsMouseDoubleClicked(0) then binder.tabClick(pl.id) end
    end
    local hovered = imgui.IsItemHovered() or imgui.IsItemActive()
    local rmin, rmax = imgui.GetItemRectMin(), imgui.GetItemRectMax()
    st.want = hovered or st.over

    local k = 1 - math.exp(-DT * 16)
    st.h = st.h + ((hovered and 1 or 0) - st.h) * k
    st.s = st.s + ((isSel and 1 or 0) - st.s) * k
    if st.h < 0.003 then st.h = 0 end

    local hv, sv = st.h * (1 - st.s * 0.6), st.s
    if hv > 0.01 or sv > 0.01 then
        local wp, ws = imgui.GetWindowPos(), imgui.GetWindowSize()
        local cdl = imgui.GetWindowDrawList()
        cdl:PushClipRect(V(wp.x, wp.y), V(wp.x + ws.x, wp.y + ws.y), false)
        local x1, x2 = wp.x + 10, wp.x + ws.x - 14
        local y1, y2 = rmin.y - 4, rmax.y + 4
        if hv > 0.01 then rrf(cdl, V(x1, y1), V(x2, y2), U(P.cardHover, hv), 9) end
        if sv > 0.01 then
            rrf(cdl, V(x1, y1), V(x2, y2), U(P.active, sv), 9)
            local my, hh = (y1 + y2) / 2, 8 * sv
            rrf(cdl, V(x1 + 4, my - hh), V(x1 + 7, my + hh), U(P.accent, sv), 2)
        end
        cdl:PopClipRect()
    end

    local pr = clamp((now - math.max(t.openAt, t.searchAt or 0) - 0.05 - math.min(index, 14) * 0.02) / 0.28, 0, 1)
    local er = 1 - (1 - pr) ^ 3
    local dx = -(1 - er) * 16 + st.h * 2

    local base = (t.hoverColor and (isSel or hovered)) and binder.TAB_WHITE or pl.color
    imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(base.x, base.y, base.z, base.w * er))
    imgui.SameLine()
    local id_text = tostring(pl.id)
    imgui.SetCursorPosX(binder.tabCenterX(id_text) + dx)
    imgui.TextUnformatted(id_text)
    imgui.NextColumn()
    imgui.SetCursorPosX(imgui.GetCursorPosX() + dx)
    local np = imgui.GetCursorScreenPos()
    imgui.TextUnformatted(pl.nick)
    binder.tabRowButtons(pl, st, np, rmin, rmax, imgui.CalcTextSize(pl.nick).x)
    imgui.NextColumn()
    local score_text = tostring(pl.score)
    imgui.SetCursorPosX(binder.tabCenterX(score_text) + dx)
    imgui.TextUnformatted(score_text)
    imgui.NextColumn()
    local ping_text = tostring(pl.ping)
    imgui.SetCursorPosX(binder.tabCenterX(ping_text) + dx)
    imgui.TextUnformatted(ping_text)
    imgui.NextColumn()
    imgui.PopStyleColor()
end

function binder.tabRender(player)
    local t = binder.tab
    DT = clamp(imgui.GetIO().DeltaTime, 0.001, 0.1)
    local now = os.clock()

    if t.open and not t.wasOpen then
        t.openAt, t.hv, t.scrollTop, t.sFocus, t.se = now, {}, true, false, 0
    end
    t.wasOpen = t.open
    t.vis = t.vis + ((t.open and 1 or 0) - t.vis) * (1 - math.exp(-DT * 15))
    if t.open and t.vis > 0.995 then t.vis = 1 end
    if not t.open and t.vis < 0.02 then t.vis = 0; player.LockPlayer = false; return end
    local oe = clamp(t.vis, 0, 1)
    UI_ALPHA, GA = oe, 1
    player.HideCursor = not t.open
    if t.open then binder.tabUpdate(false) end

    local sw, sh = getScreenResolution()
    local W, H = 800, 465
    local FS = 16
    local boldF = binder.tabFontBold or binder.panelFontX or binder.nf and binder.nf.b or imgui.GetFont()

    local semiF = binder.tabFontSemi or panelFontB or binder.nf and binder.nf.b or imgui.GetFont()
    local regF  = binder.tabFontReg or panelFont or imgui.GetFont()

    imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, math.max(oe, 0.001))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 12)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 0)
    imgui.PushStyleVarFloat(imgui.StyleVar.ScrollbarSize, 5)
    imgui.PushStyleVarFloat(imgui.StyleVar.ScrollbarRounding, 12)
    imgui.PushStyleColor(imgui.Col.WindowBg, P.bg)
    imgui.PushStyleColor(imgui.Col.Header, P.item)
    imgui.PushStyleColor(imgui.Col.HeaderHovered, P.cardHover)
    imgui.PushStyleColor(imgui.Col.HeaderActive, P.active)
    imgui.PushStyleColor(imgui.Col.Text, P.text)
    local ease3 = 1 - (1 - oe) ^ 3
    imgui.SetNextWindowPos(V(sw / 2, sh / 2 + (1 - ease3) * 18), imgui.Cond.Always, V(0.5, 0.5))
    imgui.SetNextWindowSize(V(W, H), imgui.Cond.Always)
    if t.open and now - t.openAt < 0.2 then imgui.SetNextWindowFocus() end
    imgui.Begin('RangerHelper Tab', nil,
        imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoSavedSettings + imgui.WindowFlags.NoResize +
        imgui.WindowFlags.NoMove + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse +
        (t.open and 0 or imgui.WindowFlags.NoInputs))

    local sc = FS / 14
    imgui.SetWindowFontScale(sc)

    local dl  = imgui.GetWindowDrawList()
    local cur = imgui.GetCursorScreenPos()
    local wsz = imgui.GetWindowSize()
    local q = binder.trim(ffi.string(t.q))
    local searching = (q ~= '')

    local white = U(C(255, 255, 255, 251))
    local FSB = 17
    local ts0 = clamp((now - t.openAt) / 0.35, 0, 1)
    local te = 1 - (1 - ts0) ^ 3
    dl:AddTextFontPtr(boldF, FSB, V(cur.x + 20 - (1 - te) * 14, cur.y + 20), U(C(255, 255, 255, 251), te), t.server ~= '' and t.server or 'Игроки')
    imgui.PushFont(boldF)
    local cnt = searching and ('Найдено: ' .. #t.shown) or ('Игроков: ' .. #t.list)
    local cntW = imgui.CalcTextSize(cnt).x * (FSB / FS)
    imgui.PopFont()
    dl:AddTextFontPtr(boldF, FSB, V(cur.x + wsz.x - cntW - 26 - 11 + (1 - te) * 14, cur.y + 5 + 16), U(C(255, 255, 255, 251), te), cnt)

    imgui.PushFont(regF)

    local seE = ease(clamp(t.se, 0, 1))
    local sW = 150 + 90 * seE
    imgui.SetCursorPos(V(680 - sW, 23))
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 25)
    imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, V(36, 7))
    imgui.PushStyleColor(imgui.Col.FrameBg, P.card)
    imgui.PushStyleColor(imgui.Col.FrameBgHovered, P.cardHover)
    imgui.PushStyleColor(imgui.Col.FrameBgActive, P.cardHover)
    imgui.PushItemWidth(sW)
    local noKbFocus = pcall(imgui.PushAllowKeyboardFocus, false)
    if imgui.InputText('##searchPlayers', t.q, 64, imgui.InputTextFlags.CharsNoBlank) then
        t.searchAt = now
        binder.tabUpdate(true)
    end
    if noKbFocus then imgui.PopAllowKeyboardFocus() end
    imgui.PopItemWidth()
    local active = imgui.IsItemActive()
    t.sFocus = active and not isKeyDown(0x09)
    local rmin, rmax = imgui.GetItemRectMin(), imgui.GetItemRectMax()
    imgui.PopStyleColor(3)
    imgui.PopStyleVar(2)
    t.se = t.se + ((t.sFocus and 1 or 0) - t.se) * (1 - math.exp(-DT * 14))
    local rh = (rmax.y - rmin.y) / 2
    if t.se > 0.01 then
        local pulse = 0.85 + 0.15 * math.sin(now * 4)
        rr(dl, V(rmin.x - 2, rmin.y - 2), V(rmax.x + 2, rmax.y + 2), U(P.accent, 0.22 * t.se * pulse), rh + 2, 15, 3)
        rr(dl, rmin, rmax, U(P.accent, 0.9 * t.se), rh, 15, 1.5)

        dl:PushClipRect(rmin, rmax, true)
        local wdt = rmax.x - rmin.x
        local cx = rmin.x - 36 + (wdt + 72) * ((now * 0.9) % 1)
        local ga = 0.6 * t.se
        pcall(dl.AddRectFilledMultiColor, dl, V(cx - 36, rmax.y - 3), V(cx, rmax.y), U(P.accent, 0), U(P.accent, ga), U(P.accent, ga), U(P.accent, 0))
        pcall(dl.AddRectFilledMultiColor, dl, V(cx, rmax.y - 3), V(cx + 36, rmax.y), U(P.accent, ga), U(P.accent, 0), U(P.accent, 0), U(P.accent, ga))
        dl:PopClipRect()
    end

    do
        local sg = clamp(1 - (now - (t.searchAt or -10)) / 0.9, 0, 1)
        local k = clamp(t.se, 0, 1)
        local scl = 1 + 0.12 * seE + 0.1 * sg
        local lr = 4.6 * scl
        local lx, ly = rmin.x + 19 - 2 * scl, (rmin.y + rmax.y) / 2 - 2 * scl
        local ang = math.pi / 4 + math.sin(now * 2.2) * 0.12 * k + math.sin(now * 14) * 0.38 * sg
        local col = U(imgui.ImVec4(lerp(1, P.accent.x, k), lerp(1, P.accent.y, k), lerp(1, P.accent.z, k), lerp(0.55, 1, k)))
        dl:PushClipRect(rmin, rmax, true)
        dl:AddCircle(V(lx, ly), lr, col, 24, 1.7)
        dl:AddLine(V(lx + math.cos(ang) * lr, ly + math.sin(ang) * lr),
                   V(lx + math.cos(ang) * (lr + 4.6 * scl), ly + math.sin(ang) * (lr + 4.6 * scl)), col, 2.1)
        if sg > 0.02 then
            dl:AddCircle(V(lx, ly), lr + (1 - sg) * 10, U(P.accent, 0.55 * sg), 24, 1.3)
            for i = 0, 3 do
                local a2 = now * 9 - i * 0.5
                dl:AddCircleFilled(V(lx + math.cos(a2) * lr, ly + math.sin(a2) * lr), 1.9 - i * 0.3, U(P.accent, sg * (1 - i / 4)), 8)
            end
        end
        dl:PopClipRect()
    end

    if not searching then
        local ts = imgui.CalcTextSize('Поиск')
        dl:AddText(V(math.floor(rmin.x + 36 + 4 * seE + 0.5), math.floor((rmin.y + rmax.y) / 2 - ts.y / 2 + 0.5)),
            U(C(255, 255, 255, 119), 1 - 0.5 * seE), 'Поиск')
    end

    imgui.SetCursorPos(V(0, 75))
    imgui.BeginChild('##headScoreboard', V(788, 378), false)
    imgui.PushFont(semiF)
    imgui.SetWindowFontScale(sc)
    binder.tabColumns(true)
    imgui.Columns(1)
    imgui.SetCursorPosX(0)

    imgui.BeginChild('##bodyScoreboard', V(0, 0), false, imgui.WindowFlags.NoScrollbar)
    imgui.PushFont(regF)
    imgui.SetWindowFontScale(sc)
    if t.scrollTop then imgui.SetScrollY(0); t.scrollTop = false end
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, V(8, 16))
    imgui.SetCursorPosY(imgui.GetCursorPosY() + 11)
    binder.tabColumns(false)

    local n = #t.shown
    local clipper = imgui.ImGuiListClipper(n)
    while clipper:Step() do
        for i = clipper.DisplayStart + 1, clipper.DisplayEnd do
            local pl = t.shown[i]
            if pl then binder.tabRow(i, pl) end
        end
    end

    if searching and n == 0 then
        imgui.Columns(1)
        local msg = 'Игроков по вашему запросу нет'
        local ts = imgui.CalcTextSize(msg)
        local ws = imgui.GetWindowSize()
        imgui.SetCursorPos(V(ws.x / 2 - ts.x / 2, ws.y / 2 - ts.y / 2))
        imgui.TextUnformatted(msg)
    end

    local okSb, errSb = pcall(function()
        imgui.Columns(1)

        local okFg, sdl = pcall(imgui.GetForegroundDrawList)
        if not okFg or not sdl then sdl = imgui.GetWindowDrawList() end
        local wp3, ws3 = imgui.GetWindowPos(), imgui.GetWindowSize()

        local okM, m = pcall(imgui.GetScrollMaxY)
        local maxY = math.max(okM and tonumber(m) or 0, imgui.GetCursorPosY() + 10 - ws3.y)
        do
            if maxY < 1 then maxY = 0 end
            local curY = imgui.GetScrollY()
            local cxs = wp3.x + ws3.x - 3
            local ty1, ty2 = wp3.y + 8, wp3.y + ws3.y - 8
            local th = ty2 - ty1
            local gh = clamp(th * ws3.y / (ws3.y + maxY), 48, th)
            local range = math.max(th - gh, 1)

            if t.scDrag and t.scFrozen then
                maxY, gh, range = t.scFrozen.maxY, t.scFrozen.gh, t.scFrozen.range
            end
            local gy = ty1 + range * clamp(maxY > 0 and curY / maxY or 0, 0, 1)
            local mp3 = imgui.GetMousePos()
            local inLane = mp3.x >= cxs - 12 and mp3.x <= cxs + 12 and mp3.y >= ty1 - 4 and mp3.y <= ty2 + 4
            local onGrab = inLane and mp3.y >= gy and mp3.y <= gy + gh
            if t.scDrag and not imgui.IsMouseDown(0) then t.scDrag, t.scFrozen = nil, nil end
            if maxY > 0 and inLane and imgui.IsMouseClicked(0) and not t.scDrag then
                t.scDrag = onGrab and (mp3.y - gy) or (gh / 2)
                t.scFrozen = { maxY = maxY, gh = gh, range = range }
            end
            if t.scDrag and maxY > 0 then
                local frac = clamp((mp3.y - t.scDrag - ty1) / range, 0, 1)
                local target = math.floor(frac * maxY + 0.5)
                if target ~= math.floor(curY + 0.5) then imgui.SetScrollY(target) end
                gy = ty1 + range * frac
            end
            local hot = (inLane or t.scDrag) and 1 or 0
            t.scHot = (t.scHot or 0) + (hot - (t.scHot or 0)) * (1 - math.exp(-DT * 14))
            local hE = ease(clamp(t.scHot, 0, 1))
            local hw = 2.5 + 3.5 * hE
            rrf(sdl, V(cxs - hw, ty1), V(cxs + hw, ty2), U(P.card, 0.2 + 0.5 * hE), hw)
            local gcol = lerpC(C(255, 255, 255, 70), P.accent, 0.3 + 0.7 * hE)
            if t.scDrag then gcol = lerpC(P.accent, C(255, 255, 255, 255), 0.12) end
            if hE > 0.01 then rrf(sdl, V(cxs - hw - 2, gy - 2), V(cxs + hw + 2, gy + gh + 2), U(P.accent, 0.18 * hE), hw + 2) end
            rrf(sdl, V(cxs - hw, gy), V(cxs + hw, gy + gh), U(gcol, maxY > 0 and 1 or 0.45), hw)
        end
    end)
    if not okSb and not t.sbErr then
        t.sbErr = true
        print('[Ranger Helper] ошибка скроллбара TAB: ' .. tostring(errSb))
    end

    imgui.PopStyleVar()
    imgui.PopFont()
    imgui.EndChild()
    imgui.PopFont()
    imgui.EndChild()
    imgui.PopFont()
    imgui.End()
    imgui.PopStyleColor(5)
    imgui.PopStyleVar(5)
    UI_ALPHA = 1

    local okV, inCar = pcall(isCharInAnyCar, PLAYER_PED)
    player.LockPlayer = ((t.open and t.sFocus and not (okV and inCar)) or window[0] or editor[0]) and true or false
end

imgui.OnFrame(function()
    local t = binder.tab
    return binder.ready and t.enabled and (t.open or t.vis > 0.01) and not isPauseMenuActive()
end, function(player) binder.tabRender(player) end)

binder.CHAT_FILE = CFG_DIR .. '\\chat.json'
binder.CHAT_CMD_MAX = 124
binder.CHAT_LINE_MAX = 117
binder.CHAT_SAY_LINE_MAX = 136
binder.chat = { me = true, plain = true, wrap = true, busy = false, queue = {}, worker = false }

function binder.chatSave()
    local c = binder.chat
    if not doesDirectoryExist(CFG_DIR) then createDirectory(CFG_DIR) end
    local f = io.open(binder.CHAT_FILE, 'wb')
    if not f then return false end
    f:write('{\n  "me": ' .. tostring(c.me) .. ',\n  "plain": ' .. tostring(c.plain) .. ',\n  "wrap": ' .. tostring(c.wrap) .. '\n}\n')
    f:close()
    return true
end

function binder.chatLoad()
    local f = io.open(binder.CHAT_FILE, 'rb')
    if not f then return false end
    local text = f:read('*a'); f:close()
    text = text:gsub('^\239\187\191', '')
    local ok, data = pcall(decodeJson, text)
    if not ok or type(data) ~= 'table' then return true end
    local c = binder.chat
    if type(data.me) == 'boolean' then c.me = data.me end
    if type(data.plain) == 'boolean' then c.plain = data.plain end
    if type(data.wrap) == 'boolean' then c.wrap = data.wrap end
    return true
end

function binder.cpIsUpper(b) return (b >= 65 and b <= 90) or (b >= 192 and b <= 223) or b == 168 end
function binder.cpIsLower(b) return (b >= 97 and b <= 122) or (b >= 224 and b <= 255) or b == 184 end
function binder.cpLowerB(b)
    if (b >= 65 and b <= 90) or (b >= 192 and b <= 223) then return b + 32 end
    if b == 168 then return 184 end
    return b
end
function binder.cpUpperB(b)
    if (b >= 97 and b <= 122) or (b >= 224 and b <= 255) then return b - 32 end
    if b == 184 then return 168 end
    return b
end

function binder.cpFirst(s, upper)
    local b = s:byte(1)
    if not b then return s end
    return string.char(upper and binder.cpUpperB(b) or binder.cpLowerB(b)) .. s:sub(2)
end

function binder.cpIsAbbr(word)
    local up, low = 0, 0
    for i = 1, #word do
        local b = word:byte(i)
        if binder.cpIsUpper(b) then up = up + 1 elseif binder.cpIsLower(b) then low = low + 1 end
    end
    return up >= 2 and low == 0
end

function binder.chatFormat(kind, text)
    text = binder.trim(text)
    if text == '' then return text end

    local lead, rest = text:match('^(%.%.%.+%s*)(.*)$')
    if not lead then lead, rest = text:match('^(\133%s*)(.*)$') end
    if lead then
        if rest ~= '' and not binder.cpIsAbbr(rest:match('^%S+')) then rest = binder.cpFirst(rest, false) end
        text = lead .. rest
    elseif kind == 'me' then
        if not binder.cpIsAbbr(text:match('^%S+')) then text = binder.cpFirst(text, false) end
    else
        text = binder.cpFirst(text, true)
    end

    local last = text:byte(#text)
    if last and (binder.cpIsUpper(last) or binder.cpIsLower(last) or (last >= 48 and last <= 57)) then text = text .. '.' end
    return text
end

binder.chatIgnore = { [')'] = true, ['))'] = true, ['('] = true, ['(('] = true, ['q'] = true, ['<3'] = true }

function binder.chatOverhead()
    local ok, res = pcall(function()
        local id = H.myId()
        return #sampGetPlayerNickname(id) + #('[' .. id .. '] ')
    end)
    return (ok and res) or 18
end

function binder.chatSend(text, isCmd)
    local c = binder.chat
    if c.busy or binder.dep.busy or (binder.fromScript or 0) > 0 then return end
    if type(text) ~= 'string' or text == '' then return end
    local head, body = '', text
    if isCmd then
        local cmd, rest = text:match('^/(%a+)%s+(.-)%s*$')
        if not cmd or rest == '' then return end
        cmd = cmd:lower()
        if cmd ~= 'me' and cmd ~= 'do' then return end
        head, body = '/' .. cmd .. ' ', rest
        if c.me then body = binder.chatFormat(cmd, body) end
    else
        if text:sub(1, 1) == '/' or binder.chatIgnore[text] or #text < 2 then return end
        if c.plain then body = binder.chatFormat('plain', text) end
    end
    local cap
    if isCmd then
        cap = math.min(binder.CHAT_CMD_MAX - #head, binder.CHAT_LINE_MAX - binder.chatOverhead())
    else

        cap = math.min(binder.CHAT_CMD_MAX, binder.CHAT_SAY_LINE_MAX - (binder.chatOverhead() + 9))
    end
    if c.wrap and #body > cap then
        for _, part in ipairs(binder.depSplit(body, '', cap)) do
            c.queue[#c.queue + 1] = head .. part
        end
        binder.chatPump()
        return false
    end
    local out = head .. body
    if out ~= text then return { out } end
end

function binder.chatPump()
    local c = binder.chat
    if c.worker then return end
    c.worker = true
    lua_thread.create(function()
        while #c.queue > 0 do
            local msg = table.remove(c.queue, 1)
            c.busy = true
            pcall(sampSendChat, msg)
            c.busy = false
            if #c.queue > 0 then wait(2000) end
        end
        c.worker = false
    end)
end

binder.afind = { cmd = 'afind', active = false, id = -1, nick = '', delay = 2, gen = 0 }

function binder.afindStop(reason)
    local a = binder.afind
    if not a.active then return end
    a.active, a.id, a.nick, a.gen = false, -1, '', a.gen + 1
    if reason then binder.say(reason) end
end

function binder.afindCmd(arg)
    local a = binder.afind
    if a.active then
        local id, nick = a.id, a.nick
        binder.afindStop()
        binder.say('Автопоиск {aaaaaa}/find{ffffff} остановлен: ' .. nick:gsub('_', ' ') .. ' {aaaaaa}[' .. id .. ']{ffffff}.')
        binder.sysPlay('afindstop', id)
        return
    end
    local id = tonumber(binder.trim(tostring(arg or '')))
    if not id then
        binder.say('Автопоиск {aaaaaa}[ /' .. a.cmd .. ' ID ]{ffffff}. Повторная команда {aaaaaa}/' .. a.cmd .. '{ffffff} останавливает поиск.')
        return
    end
    if id == H.myId() then binder.say('Вы ввели свой ID.'); return end
    if not H.valid(id) then binder.say('Игрока с ID {aaaaaa}' .. id .. '{ffffff} нет на сервере.'); return end
    a.active, a.id, a.nick, a.gen = true, id, H.nick(id), a.gen + 1
    local gen = a.gen
    binder.say('Автопоиск {aaaaaa}/find{ffffff}: ' .. a.nick:gsub('_', ' ') .. ' {aaaaaa}[' .. id .. ']{ffffff}. Остановить: {aaaaaa}/' .. a.cmd)
    local rpTh = binder.sysPlay('afind', id)
    lua_thread.create(function()
        binder.sysWait(rpTh)
        while a.active and a.gen == gen do
            local okV, valid = pcall(H.valid, a.id)
            if not (okV and valid) or H.nick(a.id) ~= a.nick then
                binder.afindStop('Игрок {aaaaaa}' .. a.nick:gsub('_', ' ') .. '{ffffff} вышел с сервера, автопоиск остановлен.')
                break
            end
            pcall(sampSendChat, '/find ' .. a.id)
            wait(math.floor(a.delay * 1000))
        end
    end)
end

function binder.afindSetCmd(raw)
    local a = binder.afind
    local c = binder.trim((tostring(raw or ''):gsub('^/+', '')))
    if c == a.cmd then return true end
    if c == '' or #c > 24 or not c:match('^[A-Za-z0-9_]+$') then
        binder.say('Команда: только латиница, цифры и _')
        return false
    end
    local who = binder.cmdTaken(c:lower(), nil, 'afind')
    if who then binder.say('Команда {aaaaaa}/' .. c .. '{ffffff} уже занята: ' .. who); return false end
    pcall(sampUnregisterChatCommand, a.cmd)
    a.cmd = c
    if binder.ready then pcall(sampRegisterChatCommand, c, function(arg) binder.afindCmd(arg) end) end
    cfgDirty = true
    return true
end

function binder.afindSetDelay(raw)
    local v = tonumber((tostring(raw or ''):gsub(',', '.')))
    if not v then binder.say('Задержка: число в секундах, например {aaaaaa}2'); return false end
    v = math.max(0.5, math.min(30, v))
    binder.afind.delay = math.floor(v * 10 + 0.5) / 10
    cfgDirty = true
    return true
end

function binder.afindMsg(text)
    if not binder.afind.active or type(text) ~= 'string' then return end
    local okU, clean = pcall(function() return u8:encode((text:gsub('{%x%x%x%x%x%x}', ''))) end)
    if okU and type(clean) == 'string' and clean:find('^Местоположение .+ отмечено на карте красным маркером') then
        printStringNow('AUTO FIND', 500)
        return false
    end
end

binder.wanted = {
    open = false, curOn = false, vis = 0, apply = false, focusNext = false,
    curKeys = { 0x12 }, keyCap = false, keyCapSeen = 0, capKeys = {},
    list = {}, new = {}, scanning = false, reqLvl = nil, step = 0, stepAt = 0, gen = 0,
    maxLvl = 6,
    interval = 30,
    nextAt = 0, updated = 0, flash = {}, x = nil, y = nil,
    auto = true,
    requesting = false,
    denied = nil,
    remember = true,
    keepControl = true,
}

function binder.wantedSetInterval(raw)
    local v = tonumber((tostring(raw or ''):gsub(',', '.')))
    if not v then binder.say('Интервал: число секунд, например {aaaaaa}30'); return false end
    local W = binder.wanted
    W.interval = math.floor(clamp(v, 5, 300) + 0.5)
    if W.updated > 0 and not W.scanning then W.nextAt = math.max(os.clock() + 1, W.updated + W.interval) end
    cfgDirty = true
    return true
end

function binder.wantedSetAuto(on)
    local W = binder.wanted
    W.auto = on
    if on and not W.scanning then W.nextAt = math.max(os.clock() + 1, W.updated + W.interval) end
    cfgDirty = true
end

function binder.wantedCursor(on)
    local W = binder.wanted
    if on == W.curOn then return end
    W.curOn = on
    pcall(sampToggleCursor, on)
end

binder.WN_MODS = { [0x10] = 'Shift', [0x11] = 'Ctrl', [0x12] = 'Alt' }
binder.WN_DEFAULT = 0x12

function binder.wantedKeyOk(vk)
    return binder.WN_MODS[vk] ~= nil or binder.vkNames[vk] ~= nil
end

function binder.wantedKeyName(keys)
    local parts = {}
    for _, vk in ipairs(keys) do
        parts[#parts + 1] = binder.WN_MODS[vk] or binder.vkNames[vk] or string.format('0x%X', vk)
    end
    return table.concat(parts, ' + ')
end

function binder.wantedKeysHeld()
    local keys = binder.wanted.curKeys
    if #keys == 0 then return false end
    for _, vk in ipairs(keys) do
        if not vkDown(vk) then return false end
    end
    return true
end

function binder.wantedCapAlive()
    local W = binder.wanted
    if not W.keyCap then return false end
    if os.clock() - W.keyCapSeen > 0.5 or hotCap ~= 0 or binder.pie.cap or binder.note.cap then
        W.keyCap, W.capKeys = false, {}
        return false
    end
    return true
end

function binder.wantedCapDown(wparam)
    local W = binder.wanted
    if not binder.wantedCapAlive() then return false end
    if wparam == 0x1B then
        W.keyCap, W.capKeys = false, {}
        return true
    end
    if #W.capKeys == 0 and wparam == 0x2E then
        W.curKeys, W.keyCap = { binder.WN_DEFAULT }, false
        cfgDirty = true
        return true
    end
    if not binder.wantedKeyOk(wparam) then return true end
    for _, vk in ipairs(W.capKeys) do
        if vk == wparam then return true end
    end
    if #W.capKeys >= 2 then return true end
    W.capKeys[#W.capKeys + 1] = wparam
    return true
end

function binder.wantedCapUp()
    local W = binder.wanted
    if not W.keyCap or #W.capKeys == 0 then return end
    for _, vk in ipairs(W.capKeys) do
        if vkDown(vk) then return end
    end
    W.curKeys, W.capKeys, W.keyCap = W.capKeys, {}, false
    cfgDirty = true
end

function binder.wantedKeyPill(dl, id, x, y, w, h, label)
    local W = binder.wanted
    W.keyCapSeen = os.clock()
    imgui.SetCursorScreenPos(V(x, y))
    if imgui.InvisibleButton(id, V(w, h)) then
        W.keyCap, W.capKeys = not W.keyCap, {}
        hotCap = 0
        binder.pie.cap, binder.note.cap = false, false
        binder.ccReset()
    end
    local hov = imgui.IsItemHovered()
    local t = hot(id, hov)
    local cap = W.keyCap
    card(dl, x, y, w, h, 10, cap and P.active or lerpC(P.card, P.cardHover, t),
        cap and P.accent or lerpC(P.line, P.accent, t * 0.7))
    local val
    if cap then
        val = (#W.capKeys > 0) and binder.wantedKeyName(W.capKeys) or 'Зажмите...'
    else
        val = binder.wantedKeyName(W.curKeys)
    end
    local cwid = math.min(SM.tw(val) + 16, w * 0.75)
    local cxp, cyp = x + w - 8 - cwid, y + (h - 22) / 2
    rrf(dl, V(cxp, cyp), V(cxp + cwid, cyp + 22), U(P.chip), 7)
    dl:PushClipRect(V(cxp + 4, cyp), V(cxp + cwid - 4, cyp + 22), true)
    dl:AddText(V(cxp + 8, cyp + 4), U(cap and P.text or P.accentSoft), val)
    dl:PopClipRect()
    dl:PushClipRect(V(x + 8, y), V(cxp - 4, y + h), true)
    dl:AddText(V(x + 12, y + (h - imgui.GetTextLineHeight()) / 2),
        U(cap and P.text or lerpC(P.muted, P.text, 0.5 + 0.5 * t)), label or '')
    dl:PopClipRect()
    if showTooltips and hov then
        SM.tip('Удерживайте 1 или 2 клавиши одновременно.\nНажмите, чтобы изменить. Delete - вернуть Alt, Esc - отмена')
    end
end

function binder.wantedScan()
    local W = binder.wanted
    if W.scanning then return end
    W.scanning, W.new, W.gen = true, {}, W.gen + 1
    W.step, W.stepAt, W.reqLvl = 0, os.clock(), nil
    local gen = W.gen
    lua_thread.create(function()
        local aborted = false
        for lvl = W.maxLvl, 1, -1 do
            if W.gen ~= gen then return end

            local t0 = os.clock()
            while W.gen == gen and os.clock() - t0 < 3 do
                local okD, act = pcall(sampIsDialogActive)
                if not (okD and act) then break end
                wait(100)
            end
            if W.gen ~= gen then return end
            local okD, act = pcall(sampIsDialogActive)
            if okD and act then aborted = true; break end
            W.reqLvl, W.step, W.stepAt = lvl, W.maxLvl - lvl + 1, os.clock()
            pcall(sampSendChat, '/wanted ' .. lvl)
            wait(1000)
        end
        if W.gen ~= gen then return end
        W.reqLvl, W.scanning = nil, false
        if aborted then W.nextAt = os.clock() + 5; return end
        table.sort(W.new, function(a, b)
            if a.lvl ~= b.lvl then return a.lvl > b.lvl end
            if a.num ~= b.num then return a.num < b.num end
            return a.id < b.id
        end)
        W.list, W.updated, W.nextAt = W.new, os.clock(), os.clock() + W.interval
        pcall(binder.pursuitCheck, W.list)
    end)
end

function binder.wantedRequest()
    local W = binder.wanted
    if W.scanning then return end
    binder.wantedScan()
end

function binder.wantedTick()
    local W = binder.wanted
    if not W.open or W.scanning or W.requesting or not W.auto or os.clock() < W.nextAt then return end
    local okP, paused = pcall(isPauseMenuActive)
    if okP and paused then return end
    binder.wantedScan()
end

function binder.isArizona()
    local now = os.clock()
    if binder.arzAt and now - binder.arzAt < 2 then return binder.arzVal end
    binder.arzVal, binder.arzAt = binder.isArizonaRaw(), now
    return binder.arzVal
end

function binder.isArizonaRaw()
    local ok, addr, port = pcall(sampGetCurrentServerAddress)
    if ok and type(addr) == 'string' and addr ~= '' then
        local ip = addr .. ':' .. (tonumber(port) or 0)
        for _, sv in ipairs(binder.remote.servers) do
            if (sv.ip and sv.ip == ip) or (sv.host and sv.host:lower() == addr:lower()) then return true end
        end
        if addr:lower():find('arizona', 1, true) then return true end
    end
    local okN, name = pcall(sampGetCurrentServerName)
    if okN and type(name) == 'string' then
        local okU, u = pcall(function() return u8:encode(name) end)
        if okU and type(u) == 'string' and u:lower():find('arizona', 1, true) then return true end
    end
    return false
end

function binder.wantedOpen()
    local W = binder.wanted
    local okP, paused = pcall(isPauseMenuActive)
    if okP and paused then return end
    if not binder.isArizona() then
        binder.say('Розыск {aaaaaa}/wanteds{ffffff} работает только на Arizona RP.')
        return
    end
    if W.denied and os.clock() - W.denied < 60 then
        binder.say('Вы не полицейский, розыск недоступен.')
        return
    end
    W.open, W.apply, W.focusNext, W.seenX, W.seenY = true, true, true, nil, nil
    binder.wantedRequest()
end

function binder.wantedClose()
    local W = binder.wanted
    W.open, W.scanning, W.reqLvl, W.gen = false, false, nil, W.gen + 1
    W.keyCap, W.capKeys = false, {}
    if cfgDirty then saveConfig() end
end

function binder.wantedToggle()
    if binder.wanted.open then binder.wantedClose() else binder.wantedOpen() end
end

function binder.wantedDialog(dialogId, style, title, b1, b2, text)
    local W = binder.wanted
    if not W.scanning or not W.reqLvl then return end
    local raw = tostring(text or ''):gsub('{%x%x%x%x%x%x}', '')
    local okU, clean = pcall(function() return u8:encode(raw) end)
    if not okU or type(clean) ~= 'string' then return end
    if not (clean:find('Ник') and clean:find('Уровень розыска') and clean:find('Расстояние')) then return end
    local seen = {}
    for _, v in ipairs(W.new) do seen[v.id] = true end
    for line in clean:gmatch('[^\n]+') do
        local nick, id, lvl, dist = line:match('([%w_%.%[%]]+)%((%d+)%)%s+(%d+) уровень%s+%[(.-)%]')
        id, lvl = tonumber(id), tonumber(lvl)
        if nick and id and lvl and dist and not seen[id] then
            seen[id] = true
            local interior = dist:find('интерьер') ~= nil
            W.new[#W.new + 1] = {
                id = id, nick = nick, lvl = lvl,
                dist = interior and 'В интерьере' or dist, interior = interior,
                num = interior and 1e9 or (tonumber(dist:match('[%d%.]+')) or 1e8),
            }
        end
    end
    pcall(sampSendDialogResponse, dialogId, 0, 0, '')
    return false
end

function binder.wantedMsg(text)
    local W = binder.wanted
    if type(text) ~= 'string' then return end
    local okU, clean = pcall(function() return u8:encode((text:gsub('{%x%x%x%x%x%x}', ''))) end)
    if not okU or type(clean) ~= 'string' then return end
    if clean:find('Вы не полицейский', 1, true) then
        if W.denied and os.clock() - W.denied < 3 then return false end
        if not (W.scanning or W.requesting or W.open) then return end
        W.denied = os.clock()
        binder.wantedClose()
        binder.say('Вы не полицейский, запрос розыска остановлен.')
        return false
    end
    if not W.scanning then return end
    if clean:find('^%[Ошибка%].*/wanted') or clean:find('^%[Ошибка%].*Игроков с таким уровнем розыска нету') then
        return false
    end
end

binder.pursuit = {
    id = -1, nick = '',
    startFmt = '/pursuit %d',
    stopFmt  = '/pursuit %d',
}

function binder.pursuitToggle(pl)
    local pu = binder.pursuit
    if pu.id == pl.id then
        local cmd = pu.stopFmt:format(pl.id)
        if not binder.sysCmd('pursuitstop', pl.id, cmd) then pcall(sampSendChat, cmd) end
        pu.id, pu.nick = -1, ''
        binder.say('Погоня за {aaaaaa}' .. pl.nick:gsub('_', ' ') .. ' [' .. pl.id .. ']{ffffff} остановлена.')
        return
    end
    local cmd = pu.startFmt:format(pl.id)
    if not binder.sysCmd('pursuit', pl.id, cmd) then pcall(sampSendChat, cmd) end
    pu.id, pu.nick = pl.id, pl.nick
end

function binder.pursuitCheck(list)
    local pu = binder.pursuit
    if pu.id == -1 then return end
    local ok, valid = pcall(H.valid, pu.id)
    local alive = ok and valid and sampGetPlayerNickname(pu.id) == pu.nick
    if alive and list then
        alive = false
        for _, v in ipairs(list) do if v.id == pu.id then alive = true; break end end
    end
    if not alive then pu.id, pu.nick = -1, '' end
end

function binder.wantedFind(pl)
    local a = binder.afind
    if a.active and a.id == pl.id then binder.afindCmd(''); return end
    if a.active then binder.afindStop() end
    binder.afindCmd(tostring(pl.id))
end

function binder.wantedColor(pl)
    local ok, valid = pcall(H.valid, pl.id)
    if ok and valid and sampGetPlayerNickname(pl.id) == pl.nick then
        local c = sampGetPlayerColor(pl.id)
        if c ~= 368966908 then
            return imgui.ImVec4(bit.band(bit.rshift(c, 16), 255) / 255, bit.band(bit.rshift(c, 8), 255) / 255,
                bit.band(c, 255) / 255, 1), true
        end
        return P.text, true
    end
    return P.muted, false
end

function binder.wantedFrame(player)
    local W = binder.wanted
    DT = clamp(imgui.GetIO().DeltaTime, 0.001, 0.1)
    local okP, paused = pcall(isPauseMenuActive)
    paused = okP and paused and true or false
    W.vis = W.vis + ((W.open and 1 or 0) - W.vis) * (1 - math.exp(-DT * 15))
    if W.open and W.vis > 0.995 then W.vis = 1 end

    local hold = false
    if W.open and not paused and not W.keyCap then
        local okT, typing = pcall(sampIsChatInputActive)
        hold = not (okT and typing) and binder.wantedKeysHeld()
    end
    local wantCur = W.open and not paused and (not W.keepControl or hold)
    binder.wantedCursor(wantCur and true or false)
    local okC, extCur = pcall(sampIsCursorActive)
    local interactive = W.open and not paused and (wantCur or (okC and extCur) or false)
    if paused or (not W.open and W.vis < 0.02) then
        if not W.open then W.vis = 0 end
        player.HideCursor, player.LockPlayer = true, false
        return
    end
    local oe = clamp(W.vis, 0, 1)
    UI_ALPHA, GA = oe, 1
    player.HideCursor, player.LockPlayer = not interactive, false

    local now = os.clock()
    local sw, sh = getScreenResolution()
    local WW, ROW_H = 520, 44
    local n = #W.list
    local listH = (n == 0) and 110 or math.min(n, 5) * ROW_H
    local WH = 90 + listH + 12
    local star = ico('STAR')

    imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, math.max(oe, 0.001))
    imgui.PushStyleVarFloat(imgui.StyleVar.ScrollbarSize, 5)
    imgui.PushStyleVarFloat(imgui.StyleVar.ScrollbarRounding, 12)
    imgui.PushStyleColor(imgui.Col.ScrollbarGrab, P.accentSoft)
    imgui.PushStyleColor(imgui.Col.ScrollbarGrabHovered, P.accent)
    imgui.PushStyleColor(imgui.Col.ScrollbarGrabActive, P.accentHov)
    local ease3 = 1 - (1 - oe) ^ 3
    if W.apply then
        local px = clamp((W.remember and W.x) or (sw - WW - 24), 0, math.max(0, sw - 120))
        local py = clamp((W.remember and W.y) or 140, 0, math.max(0, sh - 80))
        imgui.SetNextWindowPos(V(px, py + (1 - ease3) * 12), imgui.Cond.Always)
        if oe > 0.9 then W.apply = false end
    end
    imgui.SetNextWindowSize(V(WW, WH), imgui.Cond.Always)
    if W.focusNext then imgui.SetNextWindowFocus(); W.focusNext = false end
    imgui.Begin('RangerHelper Wanted', nil,
        imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoSavedSettings + imgui.WindowFlags.NoBackground +
        imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse +
        imgui.WindowFlags.NoResize + (interactive and 0 or imgui.WindowFlags.NoInputs))

    local dl = imgui.GetWindowDrawList()
    local pos, size = imgui.GetWindowPos(), imgui.GetWindowSize()
    local p2 = V(pos.x + size.x, pos.y + size.y)
    local _fc = SM.clipOff(dl)
    rrf(dl, pos, p2, U(imgui.ImVec4(P.bg.x, P.bg.y, P.bg.z, 0.97)), 14)
    rr(dl, V(pos.x + 0.5, pos.y + 0.5), V(p2.x - 0.5, p2.y - 0.5), U(P.outline, 0.8), 14, 15, 1.2)
    SM.clipOn(dl, _fc)
    hairline(dl, pos.x + 18, p2.x - 18, pos.y + 1, P.accentSoft, 0.5)

    local function mini(drawL, id, x, y, glyph, fallback, tip, enabled, lit)
        imgui.SetCursorScreenPos(V(x, y))
        local clicked = imgui.InvisibleButton(id, V(26, 26))
        local hov = imgui.IsItemHovered()
        local t = hot(id, hov and enabled)
        local base = lit and P.accent or P.item
        rrf(drawL, V(x, y), V(x + 26, y + 26), U(lerpC(base, P.accentHov, t), enabled and 1 or 0.45), 7)
        centerText(drawL, x, y, 26, 26, (glyph ~= '') and glyph or fallback, U(P.text, enabled and 1 or 0.4))
        if hov and showTooltips then SM.tip(tip) end
        return clicked and enabled
    end

    local title = (star ~= '' and (star .. ' ') or '') .. 'Розыск'
    dl:AddTextFontPtr(imgui.GetFont(), 16, V(pos.x + 16, pos.y + 14), U(P.text), title)
    local cx = pos.x + 16 + SM.tw(title) * 16 / 14 + 12
    chipL(dl, cx, pos.y + 13, 'Всего: ' .. n, P.chip, n > 0 and P.accentSoft or P.muted)
    if mini(dl, '##wn_x', p2.x - 16 - 26, pos.y + 10, ico('XMARK'), 'X', 'Закрыть (Esc)', true) then binder.wantedClose() end
    local ricon = ico('ARROWS_ROTATE')
    if mini(dl, '##wn_r', p2.x - 16 - 26 - 6 - 26, pos.y + 10, ricon, 'R', 'Обновить сейчас', not W.scanning and not W.requesting) then
        binder.wantedRequest()
    end
    dl:AddLine(V(pos.x + 14, pos.y + 46), V(p2.x - 14, pos.y + 46), U(P.line), 1)

    local status, frac
    if W.scanning then
        local st = math.max(W.step, 1)
        status = string.format('Сканирование: уровень %d (%d из %d)', W.reqLvl or W.maxLvl, st, W.maxLvl)
        frac = clamp(((st - 1) + clamp(now - W.stepAt, 0, 1)) / W.maxLvl, 0, 1)
    elseif W.requesting then
        status, frac = 'Запрос розыска...', 0
    elseif W.auto then
        local left = math.max(0, W.nextAt - now)
        status = string.format('Автообновление через %d с', math.ceil(left))
        frac = clamp(left / W.interval, 0, 1)
    else
        status = (W.updated > 0) and string.format('Автообновление выключено, обновлено %d с назад', math.floor(now - W.updated))
            or 'Автообновление выключено'
        frac = 0
    end
    dl:AddText(V(pos.x + 16, pos.y + 54), U(P.muted), status)
    if W.keepControl then
        local hint = binder.wantedKeyName(W.curKeys) .. ' - курсор'
        dl:AddText(V(p2.x - 16 - SM.tw(hint), pos.y + 54), U(hold and P.accentSoft or P.muted, hold and 1 or 0.7), hint)
    end
    local barX1, barX2, barY = pos.x + 16, p2.x - 16, pos.y + 76
    rrf(dl, V(barX1, barY), V(barX2, barY + 4), U(P.chip), 2)
    local fw2 = (barX2 - barX1) * anim('wanted_bar', frac, 10)
    if fw2 > 3 then rrf(dl, V(barX1, barY), V(barX1 + fw2, barY + 4), U(W.scanning and P.accentHov or P.accent), 2) end

    local rw = size.x - 28 - 10
    local base, cdl = beginList('##wantedbody', pos.x + 14, pos.y + 90, size.x - 28, listH)
    if n == 0 then
        local msg = W.scanning and 'Идёт сканирование...' or 'Сейчас на сервере нет игроков в розыске'
        local mw = SM.tw(msg)
        cdl:AddText(V(base.x + (size.x - 28 - mw) / 2, base.y + listH / 2 - 8), U(P.muted), msg)
    end
    for i, pl in ipairs(W.list) do
        local ry = base.y + (i - 1) * ROW_H
        local p1r, p2r = V(base.x, ry + 2), V(base.x + rw, ry + ROW_H - 2)
        local hov = imgui.IsMouseHoveringRect(p1r, p2r) and imgui.IsWindowHovered()
        local t = hot('wr' .. pl.id, hov)
        rrf(cdl, p1r, p2r, U(lerpC(P.card, P.cardHover, t)), 10)

        local lc = LV[clamp(pl.lvl, 1, #LV)]
        rrf(cdl, V(base.x + 8, ry + 10), V(base.x + 54, ry + 34), U(lc, 0.18), 8)
        rr(cdl, V(base.x + 8.5, ry + 10.5), V(base.x + 53.5, ry + 33.5), U(lc, 0.7), 8, 15, 1)
        centerText(cdl, base.x + 8, ry + 10, 46, 24, pl.lvl .. (star ~= '' and (' ' .. star) or ''), U(lc))

        local col, online = binder.wantedColor(pl)
        cdl:PushClipRect(V(base.x + 60, ry), V(base.x + 292, ry + ROW_H), true)
        cdl:AddText(V(base.x + 64, ry + 14), U(col), pl.nick)
        cdl:AddText(V(base.x + 64 + SM.tw(pl.nick) + 6, ry + 14), U(P.muted), '[' .. pl.id .. ']')
        cdl:PopClipRect()

        local bx = base.x + rw - 8 - 86
        cdl:AddText(V(bx - 10 - SM.tw(pl.dist), ry + 14), U(pl.interior and P.muted or P.text, pl.interior and 0.8 or 1), pl.dist)
        local by = ry + 9
        local flash = W.flash[pl.id] and now - W.flash[pl.id] < 1.0
        if mini(cdl, '##wc' .. pl.id, bx, by, ico(flash and 'CHECK' or 'COPY'), 'C', 'Копировать ник', true) then
            imgui.SetClipboardText(pl.nick)
            W.flash[pl.id] = now
        end
        local a = binder.afind
        local finding = a.active and a.id == pl.id
        if mini(cdl, '##wf' .. pl.id, bx + 30, by, ico('MAGNIFYING_GLASS'), 'F',
            finding and 'Остановить автопоиск /find' or 'Автопоиск /find', online, finding) then
            binder.wantedFind(pl)
        end
        local chasing = binder.pursuit.id == pl.id
        if mini(cdl, '##wp' .. pl.id, bx + 60, by, ico('PERSON_RUNNING'), 'P',
            chasing and 'Остановить погоню' or (pl.interior and 'Игрок в интерьере' or 'Погоня /pursuit'),
            online and (chasing or not pl.interior), chasing) then
            binder.pursuitToggle(pl)
        end
    end
    endList(base, math.max(n * ROW_H + 4, listH))

    if W.open and not W.apply and not imgui.IsMouseDown(0) then
        local rx, ry = W.seenX, W.seenY
        if not rx then
            W.seenX, W.seenY = pos.x, pos.y
        elseif math.abs(rx - pos.x) > 0.5 or math.abs(ry - pos.y) > 0.5 then
            W.seenX, W.seenY = pos.x, pos.y
            if W.remember then
                W.x, W.y = pos.x, pos.y
                cfgDirty = true
                saveConfig()
            end
        end
    end
    imgui.End()
    imgui.PopStyleColor(3)
    imgui.PopStyleVar(3)
    UI_ALPHA = 1
end

imgui.OnFrame(function() return binder.ready and (binder.wanted.open or binder.wanted.vis > 0.01) end,
    function(player) binder.wantedFrame(player) end)

do
    local okEv, sampev = pcall(require, 'lib.samp.events')
    binder.dep.hooked = okEv and type(sampev) == 'table'
    if binder.dep.hooked then
        function sampev.onSendCommand(text)
            local ok, res = pcall(binder.depSend, text)
            if ok and res ~= nil then return res end
            local ok2, r2 = pcall(binder.chatSend, text, true)
            if ok2 and r2 ~= nil then return r2 end
        end
        function sampev.onSendChat(text)
            local ok, r = pcall(binder.chatSend, text, false)
            if ok and r ~= nil then return r end
        end
        function sampev.onShowDialog(dialogId, style, title, b1, b2, text)
            local okD, rD = pcall(binder.tabCallDialog, dialogId, style, title, b1, b2, text)
            if okD and rD == false then return false end
            local okW, rW = pcall(binder.wantedDialog, dialogId, style, title, b1, b2, text)
            if okW and rW == false then return false end
        end
        function sampev.onServerMessage(color, text)
            pcall(binder.depLearn, text)
            local okC, rC = pcall(binder.tabCallMsg, text)
            if okC and rC == false then return false end
            local okA, rA = pcall(binder.afindMsg, text)
            if okA and rA == false then return false end
            local okW, rW = pcall(binder.wantedMsg, text)
            if okW and rW == false then return false end
        end
    end
end

function binder.depAdd(kind, buf)
    local d = binder.dep
    local list = (kind == 'tag') and d.tags or d.waves
    local s = binder.trim(ffi.string(buf))
    if s == '' then return false end
    if binder.cut(s, (kind == 'tag') and 24 or 12) ~= s then
        binder.say((kind == 'tag') and 'Тег: не длиннее 24 символов.' or 'Волна: не длиннее 12 символов.')
        return false
    end
    if #list >= 30 then binder.say('В списке не может быть больше 30 элементов.'); return false end
    local low = binder.lowerU8(s)
    for _, v in ipairs(list) do
        if binder.lowerU8(v) == low then binder.say('Такой элемент уже есть в списке.'); return false end
    end
    list[#list + 1] = s
    imgui.StrCopy(buf, '')
    binder.depSave()
    return true
end

function binder.depRemove(kind, i)
    local d = binder.dep
    local list = (kind == 'tag') and d.tags or d.waves
    if #list <= 1 then binder.say('В списке должен остаться хотя бы один элемент.'); return end
    table.remove(list, i)
    local function fix(idx)
        if idx > i then return idx - 1 end
        return math.min(idx, #list)
    end
    if kind == 'tag' then d.t1, d.t2 = fix(d.t1), fix(d.t2) else d.w = fix(d.w) end
    binder.depSave()
end

function binder.depToggle()
    local d = binder.dep
    if d.open then d.open = false; return end
    local okP, paused = pcall(isPauseMenuActive)
    if okP and paused then return end
    if window[0] then setOpen(false) end
    d.open, d.edit, d.focusNext, d.refocus = true, true, true, true
end

function binder.depCursor(on)
    local d = binder.dep
    if on == d.curOn then return end
    d.curOn = on
    pcall(sampToggleCursor, on)
end

function binder.depFlow(items, maxW, edit)
    local pos, x, y = {}, 0, 0
    for i, s in ipairs(items) do
        local w = math.min(SM.tw(s) + 24 + (edit and 20 or 0), maxW)
        if x > 0 and x + w > maxW then x = 0; y = y + 32 end
        pos[i] = { x = x, y = y, w = w }
        x = x + w + 6
    end
    return pos, y + 26
end

function binder.depChips(dl, id, items, sel, ox, oy, maxW, edit)
    local pos = binder.depFlow(items, maxW, edit)
    local lh = imgui.GetTextLineHeight()
    local picked, removed
    for i, s in ipairs(items) do
        local p = pos[i]
        local x, y, w = ox + p.x, oy + p.y, p.w
        local cid = id .. i
        imgui.SetCursorScreenPos(V(x, y))
        local clicked = imgui.InvisibleButton(cid, V(edit and (w - 22) or w, 26))
        local t = hot(cid, imgui.IsItemHovered())
        local on = (not edit) and sel == i
        if on then
            rrf(dl, V(x, y), V(x + w, y + 26), U(lerpC(P.accent, P.accentHov, t)), 8)
        else
            card(dl, x, y, w, 26, 8, lerpC(P.chip, P.cardHover, t), lerpC(P.line, P.accent, t * 0.8))
        end
        dl:PushClipRect(V(x + 4, y), V(x + w - (edit and 22 or 4), y + 26), true)
        dl:AddText(V(x + 12, y + (26 - lh) / 2), on and U(C(255, 255, 255)) or U(P.text), s)
        dl:PopClipRect()
        if clicked and not edit then picked = i end
        if edit then
            local bx = x + w - 22
            imgui.SetCursorScreenPos(V(bx, y))
            local del = imgui.InvisibleButton(cid .. 'x', V(22, 26))
            local dt = hot(cid .. 'x', imgui.IsItemHovered())
            local xc = U(lerpC(P.muted, P.danger, dt))
            local cx, cy = bx + 11, y + 13
            dl:AddLine(V(cx - 3.5, cy - 3.5), V(cx + 3.5, cy + 3.5), xc, 1.5)
            dl:AddLine(V(cx + 3.5, cy - 3.5), V(cx - 3.5, cy + 3.5), xc, 1.5)
            if del then removed = i end
        end
    end
    return picked, removed
end

function binder.drawDepWindow(player)
    DT = clamp(imgui.GetIO().DeltaTime, 0.001, 0.1)
    UI_ALPHA, GA = 1.0, 1
    local d = binder.dep
    local DW, M, LBL = 480, 20, 84
    local IW = DW - M * 2
    local CW = IW - LBL
    local edit = true
    local lh = imgui.GetTextLineHeight()

    local _, hT = binder.depFlow(d.tags, CW, edit)
    local _, hW = binder.depFlow(d.waves, CW, edit)
    local DH
    if edit then
        DH = 62 + (hT + 8 + 32 + 12) + (hW + 8 + 32 + 12) + 34 + 32 + 16
    else
        DH = 62 + 34 + 8 + 24 + 10 + (hT + 10) * 2 + (hW + 10) + (d.write and 44 or 0) + 32 + 16
    end

    local sw, sh = getScreenResolution()
    imgui.SetNextWindowPos(V(sw / 2, sh / 2), imgui.Cond.Appearing, V(0.5, 0.5))
    imgui.SetNextWindowSize(V(DW, DH), imgui.Cond.Always)
    if d.focusNext then imgui.SetNextWindowFocus(); d.focusNext = false end
    imgui.Begin('RangerHelper Dep', nil,
        imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoSavedSettings +
        imgui.WindowFlags.NoBackground + imgui.WindowFlags.NoResize +
        imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)

    local dl   = imgui.GetWindowDrawList()
    local pos  = imgui.GetWindowPos()
    local p2   = V(pos.x + DW, pos.y + DH)
    local font = imgui.GetFont()
    local x0   = pos.x + M

    local _fc = SM.clipOff(dl)
    rrf(dl, pos, p2, U(imgui.ImVec4(P.bg.x, P.bg.y, P.bg.z, 0.99)), 16)
    rr(dl, V(pos.x + 0.5, pos.y + 0.5), V(p2.x - 0.5, p2.y - 0.5), U(P.outline, 0.8), 16, 15, 1.5)
    SM.clipOn(dl, _fc)
    hairline(dl, pos.x + 24, p2.x - 24, pos.y + 1, P.accentSoft, 0.55)

    local g = ico('TOWER_BROADCAST')
    if g == '' then g = ico('RADIO') end
    if g == '' then g = ico('SIGNAL') end
    rrf(dl, V(x0, pos.y + 11), V(x0 + 34, pos.y + 45), U(P.active), 10)
    rr(dl, V(x0 + 0.5, pos.y + 11.5), V(x0 + 33.5, pos.y + 44.5), U(P.accent, 0.45), 10, 15, 1)
    centerText(dl, x0, pos.y + 11, 34, 34, g, U(P.accentSoft))
    dl:AddTextFontPtr(font, 16, V(x0 + 44, pos.y + 11), U(P.text), 'Рация департамента')
    dl:AddText(V(x0 + 44, pos.y + 30), U(P.muted), 'Списки тегов и волн для сообщений /d')
    dl:AddLine(V(pos.x + M, pos.y + 52), V(p2.x - M, pos.y + 52), U(P.line), 1)

    local cx0, cy0 = pos.x + DW - M - 22, pos.y + 17
    imgui.SetCursorScreenPos(V(cx0, cy0))
    if imgui.InvisibleButton('##depclosex', V(22, 22)) then d.open = false end
    local ect = hot('depclosex', imgui.IsItemHovered())
    if ect > 0.01 then dl:AddCircleFilled(V(cx0 + 11, cy0 + 11), 13, U(P.danger, 0.22 * ect), 32) end
    local xc = U(lerpC(P.muted, P.danger, ect))
    dl:AddLine(V(cx0 + 6, cy0 + 6), V(cx0 + 16, cy0 + 16), xc, 1.6)
    dl:AddLine(V(cx0 + 16, cy0 + 6), V(cx0 + 6, cy0 + 16), xc, 1.6)

    local y = pos.y + 62
    local typing = false
    local prefix = binder.depForm()
    local by = pos.y + DH - 48

    if not edit then
        card(dl, x0, y, IW, 34, 10, P.card, P.line)
        dl:PushClipRect(V(x0 + 8, y), V(x0 + IW - 8, y + 34), true)
        dl:AddTextFontPtr(font, 16, V(x0 + 14, y + 9), U(P.accentSoft), prefix)
        dl:PopClipRect()
        y = y + 34 + 8

        if checkDraw(dl, '##depchk_auto', x0, y, d.auto, 'Автоподстановка') then d.auto = not d.auto; binder.depSave() end
        if showTooltips and imgui.IsItemHovered() then
            SM.tip(d.hooked and 'Сообщения /d из чата отправляются с этим префиксом.\nПока чат открыт, справа от поля ввода - выбор тегов.'
                or 'Не найден lib.samp.events - подстановка в чат недоступна.')
        end
        local wx = x0 + 20 + 10 + SM.tw('Автоподстановка') + 26
        if checkDraw(dl, '##depchk_write', wx, y, d.write, 'Писать в окне') then
            d.write = not d.write; d.refocus = d.write; binder.depSave()
        end
        if showTooltips and imgui.IsItemHovered() then
            SM.tip('В окне появится поле ввода и кнопка «Отправить».')
        end
        y = y + 24 + 10

        local function group(id, label, items, sel, h)
            dl:AddText(V(x0, y + (26 - lh) / 2), U(P.muted), label)
            local picked = binder.depChips(dl, id, items, sel, x0 + LBL, y, CW, false)
            y = y + h + 10
            return picked
        end
        local a = group('##dc1_', 'Первый тег', d.tags, d.t1, hT)
        if a then d.t1 = a; binder.depSave() end
        local b = group('##dcw_', 'Волна', d.waves, d.w, hW)
        if b then d.w = b; binder.depSave() end
        local c = group('##dc2_', 'Второй тег', d.tags, d.t2, hT)
        if c then d.t2 = c; binder.depSave() end

        if d.write then
            imgui.SetCursorScreenPos(V(x0, y + 2))
            pushInput()
            binder.fieldBegin()
            imgui.PushItemWidth(IW - 118)
            if d.refocus then imgui.SetKeyboardFocusHere(0); d.refocus = false end
            local enter = imgui.InputTextWithHint('##depmsg', 'Сообщение в /d', d.msg, ffi.sizeof(d.msg),
                imgui.InputTextFlags.EnterReturnsTrue)
            if imgui.IsItemActive() then typing = true end
            imgui.PopItemWidth()
            binder.fieldEnd(dl, false)
            popInput()
            local send = button(dl, '##depsend', x0 + IW - 110, y, 110, 34, 'Отправить', true)
            if enter or send then
                if binder.depPost(ffi.string(d.msg)) then imgui.StrCopy(d.msg, '') end
                d.refocus = true
            end
            y = y + 44
        end

        if d.write then
            if button(dl, '##depedit', x0, by, 100, 32, 'Списки', false) then d.edit = true end
        else
            if button(dl, '##depchat', x0, by, 110, 32, 'В чат', true) then
                local txt = d.auto and '/d ' or ('/d ' .. prefix .. ' ')
                d.open = false
                pcall(sampSetChatInputEnabled, true)
                pcall(sampSetChatInputText, u8:decode(txt))
            end
            if button(dl, '##depedit', x0 + 118, by, 100, 32, 'Списки', false) then d.edit = true end
        end
        if button(dl, '##depclose', p2.x - M - 100, by, 100, 32, 'Закрыть', false) then d.open = false end
    else
        local function section(id, label, items, h, kind, buf, hint)
            dl:AddText(V(x0, y + (26 - lh) / 2), U(P.muted), label)
            local _, removed = binder.depChips(dl, id, items, 0, x0 + LBL, y, CW, true)
            local iy = y + h + 8
            imgui.SetCursorScreenPos(V(x0 + LBL, iy + 1))
            pushInput()
            binder.fieldBegin()
            imgui.PushItemWidth(CW - 98)
            local enter = imgui.InputTextWithHint('##depin' .. kind, hint, buf, ffi.sizeof(buf),
                imgui.InputTextFlags.EnterReturnsTrue)
            if imgui.IsItemActive() then typing = true end
            imgui.PopItemWidth()
            binder.fieldEnd(dl, false)
            popInput()
            local add = button(dl, '##depadd' .. kind, x0 + IW - 90, iy, 90, 32, 'Добавить', false)
            if enter or add then binder.depAdd(kind, buf) end
            if removed then binder.depRemove(kind, removed) end
            y = iy + 32 + 12
        end
        section('##det_', 'Теги', d.tags, hT, 'tag', d.inTag, 'Новый тег')
        section('##dew_', 'Волны', d.waves, hW, 'wave', d.inWave, 'Новая волна')
        if checkDraw(dl, '##depchk_wrap', x0, y, d.wrap, 'Переносить длинные сообщения на несколько строк') then
            d.wrap = not d.wrap; binder.depSave()
        end
        if showTooltips and imgui.IsItemHovered() then
            SM.tip('Текст, не помещающийся в одну строку чата, делится на несколько /d\n(до ' .. d.maxParts .. ' строк с паузой между ними).')
        end
        if button(dl, '##depclose', x0, by, 110, 32, 'Закрыть', true) then d.open = false end
    end

    d.typing = typing
    player.HideCursor, player.LockPlayer = false, typing
    imgui.End()
end

function binder.depFrame(player)
    local d = binder.dep
    local okP, paused = pcall(isPauseMenuActive)
    if d.open and okP and paused then d.open = false end
    if not d.open then
        binder.depCursor(false)
        d.typing = false
        player.HideCursor, player.LockPlayer = true, false
        return
    end
    binder.depCursor(true)
    binder.drawDepWindow(player)
end

imgui.OnFrame(function() return binder.ready and (binder.dep.open or binder.dep.curOn) end,
    function(player) binder.depFrame(player) end)

function binder.depChatTyped()
    local ok, txt = pcall(sampGetChatInputText)
    if not ok or type(txt) ~= 'string' then return false end
    return txt:match('^/[dD]$') ~= nil or txt:match('^/[dD]%s') ~= nil
end

function binder.depChatInfo()
    local d = binder.dep
    if not (d.auto and d.hooked) or window[0] or d.open then return false end
    local ok, active = pcall(function()
        return sampIsChatInputActive() and not isPauseMenuActive() and not sampIsDialogActive()
    end)
    if not (ok and active) then return false end
    return binder.depChatTyped()
end

function binder.depChatCursor(on)
    local d = binder.dep
    if on == d.chatCur then return end
    d.chatCur = on
    pcall(sampToggleCursor, on)
end

function binder.depInputRect()
    local sw, sh = getScreenResolution()
    local ok, x, y, w, h = pcall(function()
        local ptr = sampGetInputInfoPtr()
        local base = getStructElement(ptr, 0x8, 4)
        return getStructElement(base, 0x8, 4), getStructElement(base, 0xC, 4),
            getStructElement(base, 0x10, 4), getStructElement(base, 0x14, 4)
    end)
    if not ok or not x or not y or x < 0 or y < 0 or x > sw or y > sh then x, y, w, h = 20, sh * 0.35, nil, nil end
    if not w or w < 80 or w > sw then w = sw * 0.4 end
    if not h or h < 12 or h > 80 then h = 24 end
    return x, y, w, h
end

imgui.OnFrame(function() return binder.ready and (binder.depChatInfo() or binder.dep.chatCur) end, function(player)
    local d = binder.dep
    if not binder.depChatInfo() then
        binder.depChatCursor(false)
        player.HideCursor, player.LockPlayer = true, false
        return
    end
    binder.depChatCursor(true)
    player.HideCursor, player.LockPlayer = false, false
    DT = clamp(imgui.GetIO().DeltaTime, 0.001, 0.1)
    UI_ALPHA, GA = 1.0, 1

    local sw, sh = getScreenResolution()
    local ix, iy, iw, ih = binder.depInputRect()
    local lh = imgui.GetTextLineHeight()

    local PADX, GAP = 4, 4
    local H     = math.max(ih + 6, 28)
    local PH    = H - 8
    local tile  = PH
    local capT  = { '', 'Волна', '' }
    local lists = { d.tags, d.waves, d.tags }
    local widths = {}
    for k = 1, 3 do
        local m = 0
        for _, v in ipairs(lists[k]) do m = math.max(m, SM.tw(v)) end
        widths[k] = math.min(math.max(m, 30), 150) + (capT[k] ~= '' and (SM.tw(capT[k]) + 6) or 0) + 30
    end
    local total  = PADX + tile + GAP + widths[1] + widths[2] + widths[3] + GAP * 2 + PADX
    local WH     = H

    local x, y = ix + iw + 8, iy - (H - ih) / 2
    if x + total > sw - 4 then
        x, y = ix, iy + ih + 6
        if x + total > sw - 4 then x = math.max(4, sw - total - 4) end
    end

    imgui.SetNextWindowPos(V(x, y), imgui.Cond.Always)
    imgui.SetNextWindowSize(V(total, WH), imgui.Cond.Always)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V(0, 0))
    imgui.Begin('RangerHelper DepChat', nil,
        imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoSavedSettings + imgui.WindowFlags.NoBackground +
        imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoScrollbar +
        imgui.WindowFlags.NoScrollWithMouse + imgui.WindowFlags.NoFocusOnAppearing + imgui.WindowFlags.NoNav)
    imgui.PopStyleVar(1)

    local dl  = imgui.GetWindowDrawList()
    local pos = imgui.GetWindowPos()
    local _fc = SM.clipOff(dl)

    rrf(dl, pos, V(pos.x + total, pos.y + H), U(imgui.ImVec4(P.bg.x, P.bg.y, P.bg.z, 0.94)), 12)
    rr(dl, V(pos.x + 0.5, pos.y + 0.5), V(pos.x + total - 0.5, pos.y + H - 0.5), U(P.accent, 0.75), 12, 15, 1.2)
    hairline(dl, pos.x + 14, pos.x + total - 14, pos.y + 1, P.accentSoft, 0.35)

    local tx, ty = pos.x + PADX, pos.y + 4
    imgui.SetCursorScreenPos(V(tx, ty))
    if imgui.InvisibleButton('##dcopen', V(tile, PH)) then
        pcall(sampSetChatInputEnabled, false)
        binder.depToggle()
    end
    local tHov = imgui.IsItemHovered()
    local th = hot('dcopen', tHov)
    rrf(dl, V(tx, ty), V(tx + tile, ty + PH), U(lerpC(P.active, P.accent, th * 0.45)), 8)
    rr(dl, V(tx + 0.5, ty + 0.5), V(tx + tile - 0.5, ty + PH - 0.5), U(lerpC(P.accent, P.accentSoft, th), 0.5 + 0.5 * th), 8, 15, 1)
    local g = ico('TOWER_BROADCAST')
    if g == '' then g = ico('RADIO') end
    if g == '' then g = ico('SIGNAL') end
    centerText(dl, tx, ty, tile, PH, g ~= '' and g or 'D', U(lerpC(P.accentSoft, P.text, th)))
    if showTooltips and tHov then SM.tip('Открыть меню рации') end

    local function selector(k, cx)
        local items, idx, cap = lists[k], (k == 1 and d.t1) or (k == 2 and d.w) or d.t2, capT[k]
        local w = widths[k]
        local id = '##dcsel' .. k
        imgui.SetCursorScreenPos(V(cx, ty))
        if imgui.InvisibleButton(id, V(w, PH)) then imgui.OpenPopup(id .. 'pop') end
        local hov  = imgui.IsItemHovered()
        local open = imgui.IsPopupOpen(id .. 'pop')
        local t = hot(id, hov or open)
        rrf(dl, V(cx, ty), V(cx + w, ty + PH), U(lerpC(P.chip, P.cardHover, t)), 9)
        rr(dl, V(cx + 0.5, ty + 0.5), V(cx + w - 0.5, ty + PH - 0.5),
            U(lerpC(P.line, P.accent, math.max(t, open and 1 or 0)), 0.95), 9, 15, 1)
        local cy = ty + (PH - lh) / 2
        if cap ~= '' then dl:AddText(V(cx + 9, cy), U(P.muted), cap) end
        local vx = cx + 9 + (cap ~= '' and (SM.tw(cap) + 6) or 0)
        dl:PushClipRect(V(vx, ty), V(cx + w - 22, ty + PH), true)
        dl:AddText(V(vx, cy), U(P.text), items[idx] or '')
        dl:PopClipRect()
        local ax, ay = cx + w - 14, ty + PH / 2
        local ac = U(lerpC(P.muted, P.accentSoft, t))
        if open then
            dl:AddLine(V(ax - 3.5, ay + 2), V(ax, ay - 2), ac, 1.6)
            dl:AddLine(V(ax, ay - 2), V(ax + 3.5, ay + 2), ac, 1.6)
        else
            dl:AddLine(V(ax - 3.5, ay - 2), V(ax, ay + 2), ac, 1.6)
            dl:AddLine(V(ax, ay + 2), V(ax + 3.5, ay - 2), ac, 1.6)
        end

        if showTooltips and hov and not open then SM.tip(k == 2 and 'Волна' or (k == 1 and 'Первый тег' or 'Второй тег')) end

        local rowH, nItems = 26, #items
        local pw = w
        for _, v in ipairs(items) do pw = math.max(pw, SM.tw(v) + 60) end
        pw = math.min(pw, 280)
        local ph = math.min(12 + 28 + nItems * (rowH + 3), 310)
        local iwid = pw - 12
        local title = (k == 2) and 'Волна' or ((k == 1) and 'Первый тег' or 'Второй тег')
        local clear = imgui.ImVec4(0, 0, 0, 0)
        imgui.SetNextWindowPos(V(cx, ty + PH + 8), imgui.Cond.Always)
        imgui.SetNextWindowSize(V(pw, ph), imgui.Cond.Always)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 12)
        imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V(6, 6))
        imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, V(0, 3))
        imgui.PushStyleVarFloat(imgui.StyleVar.PopupBorderSize, 1.2)
        imgui.PushStyleColor(imgui.Col.PopupBg, imgui.ImVec4(P.bg.x, P.bg.y, P.bg.z, 0.98))
        imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(P.accent.x, P.accent.y, P.accent.z, 0.8))
        imgui.PushStyleColor(imgui.Col.Header, clear)
        imgui.PushStyleColor(imgui.Col.HeaderHovered, clear)
        imgui.PushStyleColor(imgui.Col.HeaderActive, clear)
        imgui.PushStyleColor(imgui.Col.Text, P.text)
        local picked
        if imgui.BeginPopup(id .. 'pop', imgui.WindowFlags.NoScrollbar) then
            local pdl = imgui.GetWindowDrawList()
            local hc = imgui.GetCursorScreenPos()
            pdl:AddText(V(hc.x + 8, hc.y + 3), U(P.accentSoft), title)
            pdl:AddLine(V(hc.x + 4, hc.y + 23), V(hc.x + iwid - 4, hc.y + 23), U(P.line), 1)
            imgui.Dummy(V(iwid, 28))
            for i, v in ipairs(items) do
                local sp = imgui.GetCursorScreenPos()
                if imgui.Selectable('##' .. id .. 'i' .. i, false, 0, V(iwid, rowH)) then picked = i end
                local th = hot(id .. 'i' .. i, imgui.IsItemHovered())
                local sel = (i == idx)
                local p2 = V(sp.x + iwid, sp.y + rowH)
                if sel then
                    rrf(pdl, sp, p2, U(P.active), 8)
                    rr(pdl, V(sp.x + 0.5, sp.y + 0.5), V(p2.x - 0.5, p2.y - 0.5), U(P.accent, 0.6), 8, 15, 1)
                elseif th > 0.01 then
                    rrf(pdl, sp, p2, U(P.cardHover, th), 8)
                end
                pdl:PushClipRect(V(sp.x + 6, sp.y), V(p2.x - 26, p2.y), true)
                pdl:AddText(V(sp.x + 12 + 2 * th, sp.y + (rowH - lh) / 2), U(sel and P.accentSoft or P.text), v)
                pdl:PopClipRect()
                if sel then
                    local kx, ky = p2.x - 16, sp.y + rowH / 2
                    local kc = U(P.accentSoft)
                    pdl:AddLine(V(kx - 4, ky), V(kx - 1, ky + 3), kc, 1.8)
                    pdl:AddLine(V(kx - 1, ky + 3), V(kx + 4, ky - 3), kc, 1.8)
                end
            end
            imgui.EndPopup()
        end
        imgui.PopStyleColor(6)
        imgui.PopStyleVar(4)
        return picked
    end

    local cx = tx + tile + GAP
    local p = selector(1, cx);                              if p then d.t1 = p; binder.depSave() end
    p = selector(2, cx + widths[1] + GAP);                  if p then d.w  = p; binder.depSave() end
    p = selector(3, cx + widths[1] + widths[2] + GAP * 2);  if p then d.t2 = p; binder.depSave() end

    SM.clipOn(dl, _fc)
    imgui.End()
end)

local panelData = { at = -10, city = '', area = '', square = '', dir = '', interior = false,
                    nick = '', id = 0, ping = 0, fps = 0 }

local function panelRefresh()
    local now = os.clock()
    if now - panelData.at < 0.4 then return end
    panelData.at = now
    pcall(function()
        local x, y, z = getCharCoordinates(PLAYER_PED)
        panelData.city, panelData.area, panelData.square = H.city(x, y, z), H.area(x, y, z), H.square(x, y)
        panelData.dir = H.direction(PLAYER_PED, false)
        panelData.interior = getActiveInterior() ~= 0
        local id = H.myId()
        panelData.id = id
        panelData.nick = (H.nick(id):gsub('_', ' '))
        panelData.ping = sampGetPlayerPing(id)
    end)
    panelData.fps = math.floor(imgui.GetIO().Framerate + 0.5)
end

local PCOL = { good = C(94, 230, 70), warn = C(255, 132, 132), bad = C(255, 89, 89) }
local PSZ = 14

local function panelRows()
    local d = panelData
    local I, T = P.accent, P.muted
    local function S(t, c, b) return { t, c, b = b } end
    local function icon(name, c) local g = ico(name); return S(g ~= '' and (g .. ' ') or '', c or I) end
    local rows = {}

    rows[#rows + 1] = { S('Ranger Helper', P.accentSoft, true) }
    rows[#rows + 1] = { sep = true }
    rows[#rows + 1] = { icon('CIRCLE_USER'), S(d.nick .. ' [' .. d.id .. ']', P.text) }

    local parts = {}
    if PANEL.city then parts[#parts + 1] = d.interior and 'Нет' or d.city end
    if PANEL.square then parts[#parts + 1] = d.interior and 'Нет' or d.square end
    if #parts > 0 then
        local r = { icon('LOCATION_DOT') }
        for i, t in ipairs(parts) do
            if i > 1 then r[#r + 1] = S(', ', P.text) end
            r[#r + 1] = S(t, T)
        end
        rows[#rows + 1] = r
    end
    if PANEL.area then
        rows[#rows + 1] = { (#parts == 0) and icon('MAP_PIN') or S('', T), S(d.interior and 'Вы в интерьере' or d.area, T) }
    end
    if PANEL.dir then rows[#rows + 1] = { icon('EYE'), S(d.dir, T) } end

    local pf = {}
    if PANEL.ping then
        local pc = (d.ping <= 80) and PCOL.good or (d.ping <= 120) and PCOL.warn or PCOL.bad
        pf[#pf + 1] = { icon('SATELLITE_DISH'), S(tostring(d.ping), pc) }
    end
    if PANEL.fps then
        local fc = (d.fps < 30) and PCOL.bad or (d.fps < 60) and PCOL.warn or PCOL.good
        pf[#pf + 1] = { icon('GAUGE_HIGH'), S(tostring(d.fps), fc) }
    end
    if #pf > 0 then
        local r = {}
        for i, grp in ipairs(pf) do
            if i > 1 then r[#r + 1] = S('  |  ', P.line) end
            for _, sg in ipairs(grp) do r[#r + 1] = sg end
        end
        rows[#rows + 1] = r
    end

    local tf = {}
    if PANEL.time then tf[#tf + 1] = '%H:%M' .. (PANEL.secs and ':%S' or '') end
    if PANEL.date then tf[#tf + 1] = '%d.%m.%Y' end
    if #tf > 0 then
        rows[#rows + 1] = { sep = true }
        rows[#rows + 1] = { icon('CLOCK'), S(os.date('!' .. table.concat(tf, ' | '), H.msk()), T) }
    end
    return rows
end

local function panelMeasure(rows)
    local f  = panelFont or imgui.GetFont()
    local fb = panelFontB or f
    local W, Hh = 130, 18
    imgui.PushFont(f)
    local step = imgui.GetTextLineHeight() + 4
    imgui.PopFont()
    for _, r in ipairs(rows) do
        if r.sep then
            Hh = Hh + 9
        else
            local w = 0
            for _, sg in ipairs(r) do
                imgui.PushFont(sg.b and fb or f)
                sg.w = imgui.CalcTextSize(sg[1]).x
                imgui.PopFont()
                w = w + sg.w
            end
            r.w = w
            W = math.max(W, w + 28)
            Hh = Hh + step
        end
    end
    return math.ceil(W), math.ceil(Hh), step
end

local function panelDraw(dl, px, py, W, Hh, step, rows, active)
    px, py = math.floor(px + 0.5), math.floor(py + 0.5)
    W, Hh = math.ceil(W), math.ceil(Hh)
    local unclipped = pcall(function() dl:PushClipRectFullScreen() end)
    local f  = panelFont or imgui.GetFont()
    local fb = panelFontB or f
    rrf(dl, V(px, py), V(px + W, py + Hh), U(imgui.ImVec4(P.bg.x, P.bg.y, P.bg.z, 0.88)), 12)
    rr(dl, V(px + 0.5, py + 0.5), V(px + W - 0.5, py + Hh - 0.5),
        U(active and P.accent or P.line, active and 1 or 0.9), 12, 15, active and 1.6 or 1)
    hairline(dl, px + 14, px + W - 14, py + 1, P.accentSoft, 0.4)
    if unclipped then pcall(function() dl:PopClipRect() end) end
    local y = py + 9
    for _, r in ipairs(rows) do
        if r.sep then
            dl:AddLine(V(px + 12, y + 4), V(px + W - 12, y + 4), U(P.line, 0.9), 1)
            y = y + 9
        else
            local x = px + (W - r.w) / 2
            for _, sg in ipairs(r) do
                if sg[1] ~= '' then dl:AddTextFontPtr(sg.b and fb or f, PSZ, V(x, y), U(sg[2]), sg[1]) end
                x = x + sg.w
            end
            y = y + step
        end
    end
end

panelPreview = function(dl, x, y, w, h)
    panelRefresh()
    local rows = panelRows()
    local W, Hh, step = panelMeasure(rows)
    panelDraw(dl, x + (w - W) / 2, y + (h - Hh) / 2, W, Hh, step, rows, false)
end

local function panelRender(player)
    DT = clamp(imgui.GetIO().DeltaTime, 0.001, 0.1)
    UI_ALPHA, GA = 1.0, 1
    player.HideCursor = not panelMove
    player.LockPlayer = panelMove
    panelRefresh()

    local rows = panelRows()
    local W, Hh, step = panelMeasure(rows)

    local sw, sh = getScreenResolution()
    local cxp, cyp = PANEL.x or (sw * 585 / 640), PANEL.y or (sh * 265 / 448)
    if panelMove then
        local m = imgui.GetMousePos()
        cxp, cyp = m.x, m.y
        if imgui.IsMouseClicked(0) and os.clock() - panelMoveAt > 0.25 then
            PANEL.x, PANEL.y = clamp(cxp, W / 2, sw - W / 2), clamp(cyp, Hh / 2, sh - Hh / 2)
            panelMove, cfgDirty = false, true
            player.HideCursor, player.LockPlayer = true, false
            setOpen(true)
        end
    end
    cxp, cyp = clamp(cxp, W / 2, math.max(W / 2, sw - W / 2)), clamp(cyp, Hh / 2, math.max(Hh / 2, sh - Hh / 2))

    local okBg, bg = pcall(imgui.GetBackgroundDrawList)
    if okBg and bg then
        panelDraw(bg, cxp - W / 2, cyp - Hh / 2, W, Hh, step, rows, panelMove)
        return
    end

    imgui.SetNextWindowPos(V(math.floor(cxp - W / 2 + 0.5), math.floor(cyp - Hh / 2 + 0.5)), imgui.Cond.Always)
    imgui.SetNextWindowSize(V(W, Hh), imgui.Cond.Always)
    imgui.Begin('RangerHelper InfoPanel', nil,
        imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoSavedSettings + imgui.WindowFlags.NoBackground +
        imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoScrollbar +
        imgui.WindowFlags.NoScrollWithMouse + imgui.WindowFlags.NoInputs +
        imgui.WindowFlags.NoFocusOnAppearing + imgui.WindowFlags.NoBringToFrontOnFocus)
    local pos = imgui.GetWindowPos()
    panelDraw(imgui.GetWindowDrawList(), pos.x, pos.y, W, Hh, step, rows, panelMove)
    imgui.End()
end

panelStartMove = function()
    PANEL.enabled = true
    panelOld = { x = PANEL.x, y = PANEL.y }
    panelMove, panelMoveAt = true, os.clock()
    setOpen(false)
end

imgui.OnFrame(function()
    return binder.ready and PANEL.enabled and (panelMove or (not isPauseMenuActive() and sampIsChatVisible()))
end, function(player) panelRender(player) end)

function binder.pieBuild()
    local vis = {}
    for _, it in ipairs(binder.pie.items) do
        if it.on ~= false then
            if it.children then
                local kids = {}
                for _, c in ipairs(it.children) do
                    if c.on ~= false and binder.trim(c.text) ~= '' then kids[#kids + 1] = c end
                end
                if #kids > 0 then vis[#vis + 1] = { it = it, kids = kids } end
            elseif binder.trim(it.text) ~= '' then
                vis[#vis + 1] = { it = it }
            end
        end
    end
    return vis
end

function binder.pieBlocked()
    if window[0] or editor[0] or #binder.dlg.stack > 0 or panelMove or binder.kpk.pop.open then return true end
    local ok, b = pcall(function()
        return isPauseMenuActive() or sampIsChatInputActive() or sampIsDialogActive()
            or isSampfuncsConsoleActive() or sampIsCursorActive()
    end)
    return (not ok) or b
end

function binder.pieTrigger()
    local p = binder.pie
    if p.mode == 1 then
        local k = binder.parseKey(binder.hotkeyOf(binder.HK_PIE))
        if not k or not vkDown(0x02) or not binder.keysHeld(k) then return false end
        local ctrl, alt, shift = binder.mods()
        return k.ctrl == ctrl and k.alt == alt and k.shift == shift
    end
    return vkDown(0x04)
end

function binder.pieBtn()
    return (binder.pie.mode == 1) and 0x02 or 0x04
end

function binder.pieCursor(on)
    local p = binder.pie
    if on == p.curOn then return end
    p.curOn = on
    if on then

        local ok = pcall(sampSetCursorMode, 3)
        if not ok then pcall(sampToggleCursor, true) end
    else
        pcall(sampToggleCursor, false)
    end
end

function binder.pieClose()
    local p = binder.pie
    p.open, p.needRelease = false, true
    binder.pieCursor(false)
end

function binder.pieLines(text, maxW)
    local c = binder.pie.cache
    local key = maxW .. '|' .. text
    if c[key] then return c[key] end
    local lines, cur = {}, ''
    for word in tostring(text):gmatch('%S+') do
        local try = (cur == '') and word or (cur .. ' ' .. word)
        if cur ~= '' and imgui.CalcTextSize(try).x > maxW then
            lines[#lines + 1] = cur
            cur = word
        else
            cur = try
        end
    end
    if cur ~= '' then lines[#lines + 1] = cur end
    if #lines > 3 then
        lines[3] = lines[3] .. ' ' .. table.concat(lines, ' ', 4)
        for i = #lines, 4, -1 do lines[i] = nil end
    end
    for i, l in ipairs(lines) do lines[i] = ellipsize(l, maxW) end
    c[key] = lines
    return lines
end

function binder.pieSectorEven(dl, cx, cy, r0, r1, a0, a1, fill, border, h)
    local d0 = math.asin(math.min(0.99, h / r0))
    local d1 = math.asin(math.min(0.99, h / r1))
    local ia0, ia1 = a0 + d0, a1 - d0
    local oa0, oa1 = a0 + d1, a1 - d1
    local segs = math.max(3, math.ceil((a1 - a0) * r1 / 8))
    local function pt(r, a) return V(cx + r * math.sin(a), cy - r * math.cos(a)) end
    local ei, eo = 1.0 / r0, 1.0 / r1
    for i = 0, segs - 1 do
        local t0, t1 = i / segs, (i + 1) / segs
        local ai0, ai1 = ia0 + (ia1 - ia0) * t0, ia0 + (ia1 - ia0) * t1
        local ao0, ao1 = oa0 + (oa1 - oa0) * t0, oa0 + (oa1 - oa0) * t1
        if i > 0 then ai0, ao0 = ai0 - ei, ao0 - eo end
        if i < segs - 1 then ai1, ao1 = ai1 + ei, ao1 + eo end
        dl:PathClear()
        dl:PathLineTo(pt(r0, ai0)); dl:PathLineTo(pt(r1, ao0))
        dl:PathLineTo(pt(r1, ao1)); dl:PathLineTo(pt(r0, ai1))
        dl:PathFillConvex(fill)
    end
    if border then
        dl:PathClear()
        for i = 0, segs do dl:PathLineTo(pt(r1, oa0 + (oa1 - oa0) * i / segs)) end
        for i = segs, 0, -1 do dl:PathLineTo(pt(r0, ia0 + (ia1 - ia0) * i / segs)) end
        dl:PathStroke(border, 1, 1.2)
    end
end

function binder.pieSector(dl, cx, cy, r0, r1, a0, a1, fill, border, h)
    if h and h > 0 then return binder.pieSectorEven(dl, cx, cy, r0, r1, a0, a1, fill, border, h) end
    local rm, th = (r0 + r1) / 2, r1 - r0
    local segs = math.max(6, math.ceil((a1 - a0) * r1 / 6))
    local function arc(r, col, w)
        dl:PathClear()
        for i = 0, segs do
            local a = a0 + (a1 - a0) * i / segs
            dl:PathLineTo(V(cx + r * math.sin(a), cy - r * math.cos(a)))
        end
        dl:PathStroke(col, 0, w)
    end
    arc(rm, fill, th)
    if border then
        arc(r0 + 0.5, border, 1.2)
        arc(r1 - 0.5, border, 1.2)
        if (a1 - a0) < math.pi * 2 - 0.01 then
            for _, a in ipairs({ a0, a1 }) do
                dl:AddLine(V(cx + r0 * math.sin(a), cy - r0 * math.cos(a)),
                           V(cx + r1 * math.sin(a), cy - r1 * math.cos(a)), border, 1.2)
            end
        end
    end
end

function binder.pieLabel(dl, px, py, title, maxW, col)
    local lines = binder.pieLines(title, maxW)
    local lh = imgui.GetTextLineHeight()
    local y0 = py - #lines * lh / 2
    for i, l in ipairs(lines) do
        local w = imgui.CalcTextSize(l).x
        dl:AddText(V(px - w / 2, y0 + (i - 1) * lh), col, l)
    end
end

function binder.pieRender(player)
    local p = binder.pie
    DT = clamp(imgui.GetIO().DeltaTime, 0.001, 0.1)
    UI_ALPHA = 1.0
    local imio = imgui.GetIO()
    local sw, sh = imio.DisplaySize.x, imio.DisplaySize.y
    if sw < 2 or sh < 2 then sw, sh = getScreenResolution() end
    local twoPi = math.pi * 2

    player.HideCursor = true
    if not p.open then
        local vis = binder.pieBuild()
        if #vis == 0 then
            p.needRelease = true
            if os.clock() - (p.hintAt or -10) > 5 then
                p.hintAt = os.clock()
                binder.say('Круговое меню пусто: добавьте пункты на вкладке {aaaaaa}Круговое меню{ffffff} и включите их.')
            end
            return
        end
        p.open, p.vis, p.act, p.lastAct, p.t0 = true, vis, 0, 0, os.clock()
        p.cx, p.cy = sw / 2, sh / 2
        hv['pie_ring2'] = 0
        for i = 1, math.max(binder.pie.MAX, binder.pie.MAX_KIDS) do hv['pie1_' .. i] = 0; hv['pie2_' .. i] = 0 end
        imio.MousePos = V(p.cx, p.cy)
    end
    player.HideCursor, player.LockPlayer = false, false
    binder.pieCursor(true)

    local R_IN, R1, R2I, R2O = 38, 116, 122, 194
    local sc = math.min(1, (math.min(sw, sh) / 2 - 12) / R2O)
    local fade = ease(clamp((os.clock() - p.t0) / 0.14, 0, 1))
    local k = sc * (0.88 + 0.12 * fade)
    local rIn, r1, r2i, r2o = R_IN * k, R1 * k, R2I * k, R2O * k
    local cx, cy = p.cx, p.cy
    local vis = p.vis
    local n1 = #vis
    local step1 = twoPi / n1

    local mp = imgui.GetMousePos()
    local dx, dy = mp.x - cx, mp.y - cy
    local dist = math.sqrt(dx * dx + dy * dy)
    local ang = math.atan2(dx, -dy)
    if ang < 0 then ang = ang + twoPi end

    local h1, h2 = 0, 0
    local step2, span, start2 = 0, 0, 0
    if dist < rIn then
        p.act = 0
    elseif dist <= r1 + 2 then
        h1 = (n1 == 1) and 1 or ((math.floor((ang + step1 / 2) / step1) % n1) + 1)
        p.act = (vis[h1] and vis[h1].kids) and h1 or 0
    end
    if p.act > 0 then p.lastAct = p.act end

    local shown = (p.act > 0) and p.act or p.lastAct
    local par = vis[shown]
    if par and par.kids then
        local n2 = #par.kids
        span = twoPi
        step2 = span / n2
        start2 = (shown - 1) * step1 - step2 / 2
        if p.act > 0 and dist > r1 + 2 and dist <= (R2O + 70) * k then
            local d = (ang - start2) % twoPi
            if d <= span then
                h2 = math.min(n2, math.floor(d / step2) + 1)
            elseif d > twoPi - step2 * 0.6 then
                h2 = 1
            elseif d < span + step2 * 0.6 then
                h2 = n2
            end
        end
    end

    local hit, hitCat
    if h2 > 0 then
        hit = par.kids[h2]
    elseif h1 > 0 then
        if vis[h1].kids then hitCat = vis[h1] else hit = vis[h1].it end
    end

    local okP, paused = pcall(isPauseMenuActive)
    if okP and paused then binder.pieClose(); return end
    if not binder.pieTrigger() then
        binder.pieClose()
        if hit then binder.play(hit.text, {}, '') end
        return
    end

    imgui.SetNextWindowPos(V(0, 0), imgui.Cond.Always)
    imgui.SetNextWindowSize(V(sw, sh), imgui.Cond.Always)
    imgui.Begin('RangerHelper Pie', nil,
        imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoSavedSettings +
        imgui.WindowFlags.NoBackground + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove +
        imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse +
        imgui.WindowFlags.NoFocusOnAppearing + imgui.WindowFlags.NoBringToFrontOnFocus)
    local dl = imgui.GetWindowDrawList()
    local fc = SM.clipOff(dl)
    GA = fade

    dl:AddRectFilled(V(-64, -64), V(sw + 64, sh + 64), U(C(6, 8, 16, 150)))

    local rm1 = (rIn + r1) / 2
    for i, v in ipairs(vis) do
        local th = (i - 1) * step1
        local a0, a1 = th - step1 / 2, th + step1 / 2
        local gap = (n1 > 1) and (3.5 * k) or nil
        local t = hot('pie1_' .. i, (h1 == i) or (p.act == i))
        local fill = lerpC(P.card, P.accent, t * 0.85)
        fill.w = 0.94
        binder.pieSector(dl, cx, cy, rIn, r1, a0, a1, U(fill), U(lerpC(P.line, P.accentSoft, t)), gap)
        local maxW = (n1 == 1) and 92 or clamp(2 * rm1 * math.sin(step1 / 2) - 12, 50, 92)
        binder.pieLabel(dl, cx + rm1 * math.sin(th), cy - rm1 * math.cos(th), v.it.title, maxW, U(P.text))
        if v.kids then
            local ux, uy = math.sin(th), -math.cos(th)
            local vx, vy = math.cos(th), math.sin(th)
            local tipx, tipy = cx + (r1 - 7) * ux, cy + (r1 - 7) * uy
            local c = U(lerpC(P.muted, P.text, t))
            dl:AddLine(V(tipx - 4 * ux - 5 * vx, tipy - 4 * uy - 5 * vy), V(tipx, tipy), c, 1.8)
            dl:AddLine(V(tipx, tipy), V(tipx - 4 * ux + 5 * vx, tipy - 4 * uy + 5 * vy), c, 1.8)
        end
    end

    local ringT = anim('pie_ring2', (p.act > 0) and 1 or 0, 20)
    if par and par.kids and ringT > 0.02 then
        GA = fade * ringT
        local rm2 = (r2i + r2o) / 2
        local maxW = clamp(2 * rm2 * math.sin(step2 / 2) * 0.9, 56, 96)
        for j, c in ipairs(par.kids) do
            local a0 = start2 + (j - 1) * step2
            local a1 = a0 + step2
            local t = hot('pie2_' .. j, h2 == j)
            local fill = lerpC(P.item, P.accent, t * 0.85)
            fill.w = 0.94
            binder.pieSector(dl, cx, cy, r2i, r2o, a0, a1, U(fill), U(lerpC(P.line, P.accentSoft, t)), (#par.kids > 1) and (3.5 * k) or nil)
            local mid = (a0 + a1) / 2
            binder.pieLabel(dl, cx + rm2 * math.sin(mid), cy - rm2 * math.cos(mid), c.title, maxW, U(P.text))
        end
        GA = fade
    end

    dl:AddCircleFilled(V(cx, cy), rIn - 5 * k, U(lerpC(P.bg, P.chip, 0.5), 0.97), 64)
    dl:AddCircle(V(cx, cy), rIn - 5 * k, U(lerpC(P.line, P.accent, hit and 0.9 or 0.3)), 64, 1.5)
    local g = ico(hit and 'PLAY' or 'XMARK')
    if g == '' then g = hit and '>' or 'x' end
    centerText(dl, cx - 20, cy - 20, 40, 40, g, U(hit and P.accentSoft or P.muted))

    local tip = hit or (hitCat and hitCat.it)
    if tip then
        local line2
        if hit then
            line2 = hit.preview or binder.preview(hit.text or '')
        else
            local cnt = #hitCat.kids
            line2 = 'Категория: ' .. cnt .. ((cnt == 1) and ' пункт' or (cnt >= 2 and cnt <= 4) and ' пункта' or ' пунктов')
        end
        local t1 = binder.cut(tip.title, 40)
        local w = math.max(imgui.CalcTextSize(t1).x, imgui.CalcTextSize(line2).x) + 28
        local ry = (par and par.kids and p.act > 0) and r2o or r1
        local py = math.min(cy + ry + 18, sh - 56)
        card(dl, cx - w / 2, py, w, 44, 10, P.card, P.accent, 0.9)
        centerText(dl, cx - w / 2, py + 4, w, 18, t1, U(P.text))
        centerText(dl, cx - w / 2, py + 23, w, 18, line2, U(P.muted))
    end

    GA = 1
    SM.clipOn(dl, fc)
    imgui.End()
end

imgui.OnFrame(function()
    local p = binder.pie
    if p.open then return true end
    if not (binder.ready and p.enabled) then return false end
    local trig = binder.pieTrigger()
    if p.needRelease then
        if not trig then p.needRelease = false end
        return false
    end
    return trig and not binder.pieBlocked()
end, function(player) binder.pieRender(player) end)

local MOD_VK = { [0x10] = true, [0x11] = true, [0x12] = true,
                 [0xA0] = true, [0xA1] = true, [0xA2] = true, [0xA3] = true, [0xA4] = true, [0xA5] = true }

function onWindowMessage(msg, wparam, lparam)
    if msg == 0x101 or msg == 0x105 then
        pcall(binder.capUp)
        pcall(binder.wantedCapUp)
        return
    end
    local keyDown = (msg == 0x100 or msg == 0x104)
    if not keyDown then return end

    if msg == 0x100 then
        local okT, handled = pcall(binder.tabKey, wparam, lparam)
        if okT and handled then return end
    end

    if binder.kpk.pop.open then
        if wparam == vkeys.VK_ESCAPE then
            consumeWindowMessage(true, false)
            binder.kpk.pop.open = false
            return
        end
        if wparam == 0x0D and binder.kpk.pop.typing then
            consumeWindowMessage(true, false)
            local pop = binder.kpk.pop
            if pop.first and binder.trim(ffi.string(pop.q)) ~= '' then binder.kpkPick(pop.first) end
            return
        end
    end

    if binder.wanted.open and binder.wanted.curOn and wparam == vkeys.VK_ESCAPE and not window[0] then
        consumeWindowMessage(true, false)
        binder.wantedClose()
        return
    end

    if binder.dep.open and wparam == vkeys.VK_ESCAPE then
        consumeWindowMessage(true, false)
        binder.dep.open = false
        return
    end

    if binder.pie.open and wparam == vkeys.VK_ESCAPE then
        consumeWindowMessage(true, false)
        binder.pieClose()
        return
    end

    if panelMove and wparam == vkeys.VK_ESCAPE then
        consumeWindowMessage(true, false)
        panelMove = false
        if panelOld then PANEL.x, PANEL.y = panelOld.x, panelOld.y end
        setOpen(true)
        return
    end

    if editor[0] and ed.capture then
        consumeWindowMessage(true, false)
        binder.capDown(wparam, {
            cancel = function() ed.capture = false end,
            clearVk = { [vkeys.VK_BACK] = true },
            clear = function() ed.key, ed.capture = 'Не задана', false end,
            commit = function(name) if ed.capture then ed.key, ed.capture = name, false end end,
        })
        return
    end

    if binder.note.open and not binder.note.pin and not window[0] and wparam == vkeys.VK_ESCAPE then
        consumeWindowMessage(true, false)
        if binder.note.search then
            binder.note.search = false
            imgui.StrCopy(binder.note.nq, '')
        else
            binder.noteClose()
        end
        return
    end

    if window[0] and not editor[0] and binder.wanted.keyCap then
        local okC, used = pcall(binder.wantedCapDown, wparam)
        if okC and used then
            consumeWindowMessage(true, false)
            return
        end
    end

    if window[0] and not editor[0] and binder.note.cap then
        consumeWindowMessage(true, false)
        local n = binder.notes[binder.note.sel]
        binder.capDown(wparam, {
            cancel = function() binder.note.cap = false end,
            clearVk = n and { [vkeys.VK_BACK] = true, [vkeys.VK_DELETE] = true } or nil,
            clear = function()
                if n then n.key, binder.note.cap = 'Нет', false; binder.noteSave(); binder.needSync = true end
            end,
            commit = function(name)
                local nn = binder.notes[binder.note.sel]
                if binder.note.cap and nn then
                    nn.key, binder.note.cap = name, false
                    binder.noteSave(); binder.needSync = true
                end
            end,
        })
        return
    end

    if window[0] and not editor[0] and hotCap ~= 0 then
        consumeWindowMessage(true, false)
        local slot = hotCap
        binder.capDown(wparam, {
            cancel = function() hotCap = 0 end,
            clearVk = { [vkeys.VK_DELETE] = true },
            clear = function()
                hotkeys[slot][2] = (slot == 1) and 'F2' or (slot == 6) and 'R' or 'Не задана'; hotCap = 0; cfgDirty = true
            end,
            commit = function(name)
                if hotCap == slot then hotkeys[slot][2] = name; hotCap = 0; cfgDirty = true end
            end,
        })
        return
    end

    if binder.dlg.focused and #binder.dlg.stack > 0 then
        if wparam == 0x26 then consumeWindowMessage(true, false); binder.dlgMove(-1); return end
        if wparam == 0x28 then consumeWindowMessage(true, false); binder.dlgMove(1); return end
        if wparam == 0x0D then consumeWindowMessage(true, false); binder.dlgSelect(); return end
        if wparam == vkeys.VK_ESCAPE then consumeWindowMessage(true, false); binder.dlgFlush(); return end
    end

    if wparam == vkeys.VK_ESCAPE then
        if editor[0] then
            consumeWindowMessage(true, false)
            editor[0] = false
        elseif window[0] then
            consumeWindowMessage(true, false)
            setOpen(false)
        end
        return
    end

    binder.onKeyDown(wparam, lparam)
end

SM.px = {
    card = card, button = button, chipL = chipL, chipR = chipR, centerText = centerText, heading = heading,
    iconBadge = iconBadge, beginList = beginList, endList = endList, hot = hot, anim = anim, hv = hv,
    clamp = clamp, lerpC = lerpC, U = U, V = V, C = C, rrf = rrf, rr = rr, ico = ico,
    pushInput = pushInput, popInput = popInput, P = P, PAL = PAL, pages = pages,
    readIni = readIni, escVal = escVal, unescVal = unescVal,
    saveConfig = saveConfig, saveWeapons = saveWeapons, loadWeapons = loadWeapons,
    profile = profile, binds = binds, dialogs = dialogs, weapons = weapons, kpkSecs = kpkSecs,
    editor = editor, CFG_DIR = CFG_DIR, WIN_H = WIN_H, MARGIN = MARGIN,
    pageReset = function() pageStart = os.clock(); scrollReset = 2 end,
    setWeaponFile = function(p) WEAPON_FILE = p; weaponLastJson = nil end,
    clearKpkOpen = function() kpkOpen = {} end,
    cfgClean = function() cfgDirty = false end,
    setCfgFile = function(p) CFG_FILE = p end,
    saveSettings = function() return SM.writeSettings() end,
    loadSettings = function(keepWin) return loadConfig(keepWin) end,
}

;(function()
local X = SM.px
local PF = binder.pf
local P, PAL, hv = X.P, X.PAL, X.hv
local card, button, chipL, chipR, centerText, heading, iconBadge = X.card, X.button, X.chipL, X.chipR, X.centerText, X.heading, X.iconBadge
local beginList, endList, hot, anim, clamp, lerpC = X.beginList, X.endList, X.hot, X.anim, X.clamp, X.lerpC
local U, V, C, rrf, rr, ico = X.U, X.V, X.C, X.rrf, X.rr, X.ico
local pushInput, popInput = X.pushInput, X.popInput
local readIni, escVal, unescVal = X.readIni, X.escVal, X.unescVal
local profile, binds, dialogs, weapons, kpkSecs, editor = X.profile, X.binds, X.dialogs, X.weapons, X.kpkSecs, X.editor
local CFG_DIR, WIN_H, MARGIN = X.CFG_DIR, X.WIN_H, X.MARGIN

local ROOT     = CFG_DIR
local PROF_DIR = ROOT .. '\\profiles'
local SRV_DIR  = ROOT .. '\\servers'
local DEF_DIR  = PROF_DIR .. '\\_defaults'
local IDX_FILE = ROOT .. '\\profiles.ini'
local SRV_FILE = ROOT .. '\\servers.ini'
local MAX_PROFILES = 6
local CHAR_KEYS = { 'name', 'surname', 'fraction', 'rank', 'phone', 'callsign' }

PF.gen, PF.list, PF.meta, PF.active, PF.nextId = 0, {}, {}, nil, 1
PF.max = MAX_PROFILES
PF.srvList, PF.srvMeta, PF.srvKey, PF.lastKey = {}, {}, nil, nil
PF.cache, PF.kcache = {}, {}

pcall(ffi.cdef, 'int RemoveDirectoryA(const char* lpPathName);')

local function mkdir(p) if not doesDirectoryExist(p) then createDirectory(p) end end
local function readAll(p)
    local f = io.open(p, 'rb')
    if not f then return nil end
    local s = f:read('*a'); f:close()
    return s
end
local function writeAll(p, s)
    local f = io.open(p, 'wb')
    if not f then return false end
    f:write(s); f:close()
    return true
end
local function exists(p)
    local f = io.open(p, 'rb')
    if f then f:close(); return true end
    return false
end
local function copyFile(a, b)
    local s = readAll(a)
    if not s then return false end
    return writeAll(b, s)
end
local function trim(s) return (tostring(s or ''):match('^%s*(.-)%s*$')) end
local function pdir(id) return PROF_DIR .. '\\' .. id end

local function legacyFile(key) return SRV_DIR .. '\\' .. key .. '\\kpk.ini' end

local function srvKeyOf(s) return (tostring(s):gsub('[^%w]', '_')) end

local function srvFolder(key, byName)
    if key == '_local' then return key end
    local R = binder.remote
    for _, s in ipairs(R and R.servers or {}) do
        if s.ip and srvKeyOf(s.ip) == key then return s.number end
        if s.host and key:find('^' .. srvKeyOf(s.host) .. '_%d+$') then return s.number end
    end
    if byName and R then
        local num = R.number()
        if num then return num end
    end
    return key
end

local function sdir(key, byName) return SRV_DIR .. '\\' .. srvFolder(key, byName) end

function PF.useKpk(key, byName)
    local dir = sdir(key, byName)
    if not doesDirectoryExist(SRV_DIR) then createDirectory(SRV_DIR) end
    if not doesDirectoryExist(dir) then createDirectory(dir) end
    binder.kpkDir, binder.kpkLegacy = dir, legacyFile(key)
end

local function kpkHasJson(dir)
    for _, name in ipairs(binder.KPK_FILES) do
        if doesFileExist(dir .. '\\' .. name .. '.json') then return true end
    end
    return false
end

local function copyKpkFiles(from, to)
    local n = 0
    for _, name in ipairs(binder.KPK_FILES) do
        local dst = to .. '\\' .. name .. '.json'
        local s = readAll(from .. '\\' .. name .. '.json')
        if s then
            if writeAll(dst, s) then n = n + 1 end
        else
            os.remove(dst)
        end
    end
    return n
end

function PF.saveChar()
    mkdir(PF.dir)
    local out = { '[profile]', 'sex=' .. tostring(profile.sex) }
    for _, k in ipairs(CHAR_KEYS) do out[#out + 1] = k .. '=' .. ffi.string(profile[k]) end
    return writeAll(PF.dir .. '\\character.ini', table.concat(out, '\n') .. '\n')
end

function PF.loadChar()
    local ini = readIni(PF.dir .. '\\character.ini')
    if not ini or not ini.profile then return false end
    local pr = ini.profile
    profile.sex = (tonumber(pr.sex) == 1) and 1 or 0
    for _, k in ipairs(CHAR_KEYS) do imgui.StrCopy(profile[k], pr[k] or '') end
    return true
end

local CATS = {
    { id = 'general', name = 'Общие настройки', ico = 'GEAR', files = { 'settings.ini' },
      save = function() X.saveSettings() end, load = function() return X.loadSettings(true) end,
      info = function() return 'тема, панели, клавиши' end },
    { id = 'binds', name = 'Биндер', ico = 'KEYBOARD', files = { 'binder.ini' },
      save = function() binder.save() end, load = function() return binder.load() end,
      info = function(s) return s.binds .. ' шт.' end },
    { id = 'dialogs', name = 'Диалоги', ico = 'LIST', files = { 'dialogs.ini' },
      save = function() binder.saveDialogs() end, load = function() return binder.loadDialogs() end,
      info = function(s) return s.dialogs .. ' шт.' end },
    { id = 'weapons', name = 'Отыгровка оружий', ico = 'GUN', files = { 'weaponBinds.json' },
      save = function() X.saveWeapons() end, load = function() return X.loadWeapons() end,
      info = function(s) return 'включено: ' .. s.weapons end },
    { id = 'pie', name = 'Круговое меню', ico = 'BULLSEYE', files = { 'pie.json' },
      save = function() binder.pieSave() end, load = function() return binder.pieLoad() end,
      info = function(s) return s.pie .. ' пунктов' end },
    { id = 'notes', name = 'Заметки', ico = 'NOTE_STICKY', files = { 'notes.json' },
      save = function() binder.noteSave() end, load = function() return binder.noteLoad() end,
      info = function(s) return s.notes .. ' шт.' end },
    { id = 'dep', name = 'Рация департамента', ico = 'TOWER_BROADCAST', files = { 'dep.json' },
      save = function() binder.depSave() end, load = function() return binder.depLoad() end,
      info = function() return 'теги, волны, формат' end },
    { id = 'chat', name = 'Правка чата', ico = 'COMMENT', files = { 'chat.json' },
      save = function() binder.chatSave() end, load = function() return binder.chatLoad() end,
      info = function() return '/me, /do, обычный чат' end },
    { id = 'tab', name = 'Список игроков', ico = 'TABLE_LIST', files = { 'tab.json' },
      save = function() binder.tabSave() end, load = function() return binder.tabLoad() end,
      info = function() return 'настройки TAB' end },
    { id = 'char', name = 'Данные персонажа', ico = 'CIRCLE_USER', files = { 'character.ini' },
      save = function() PF.saveChar() end, load = function() return PF.loadChar() end,
      info = function(s) return (s.char and s.char ~= '') and binder.cut(s.char, 22) or 'не заполнено' end },
}
PF.CATS = CATS

local function allCats()
    local s = {}
    for _, c in ipairs(CATS) do s[c.id] = true end
    return s
end

function PF.setDir(dir)
    PF.dir = dir
    binder.file        = dir .. '\\binder.ini'
    binder.dialogsFile = dir .. '\\dialogs.ini'
    binder.DEP_FILE    = dir .. '\\dep.json'
    binder.TAB_FILE    = dir .. '\\tab.json'
    binder.CHAT_FILE   = dir .. '\\chat.json'
    X.setWeaponFile(dir .. '\\weaponBinds.json')
    X.setCfgFile(dir .. '\\settings.ini')
end

function PF.withDir(dir, fn)
    local old = PF.dir
    PF.setDir(dir)
    local ok, err = pcall(fn)
    PF.setDir(old)
    if not ok then print('[RangerHelper] профили: ' .. tostring(err)) end
end

function PF.saveIndex()
    mkdir(ROOT); mkdir(PROF_DIR)
    local out = { '; Ranger Helper - индекс профилей', '[meta]', 'active=' .. tostring(PF.active),
                  'next=' .. PF.nextId, 'order=' .. table.concat(PF.list, ',') }
    for _, id in ipairs(PF.list) do
        local m = PF.meta[id]
        out[#out + 1] = ''
        out[#out + 1] = '[' .. id .. ']'
        out[#out + 1] = 'name=' .. escVal(m.name)
        out[#out + 1] = 'color=' .. m.color
        out[#out + 1] = 'created=' .. m.created
    end
    writeAll(IDX_FILE, table.concat(out, '\n') .. '\n')
end

function PF.loadIndex()
    PF.list, PF.meta = {}, {}
    local ini = readIni(IDX_FILE)
    if not ini or not ini.meta then return false end
    for id in tostring(ini.meta.order or ''):gmatch('[^,]+') do
        local t = ini[id]
        if t and id:match('^p%d+$') then
            local nm = trim(unescVal(t.name))
            PF.list[#PF.list + 1] = id
            PF.meta[id] = {
                name = nm ~= '' and nm or 'Профиль',
                color = clamp(math.floor(tonumber(t.color) or 1), 1, #PAL),
                created = tonumber(t.created) or 0,
            }
        end
    end
    PF.nextId = tonumber(ini.meta.next) or 1
    for _, id in ipairs(PF.list) do
        local n = tonumber(id:match('%d+'))
        if n and n >= PF.nextId then PF.nextId = n + 1 end
    end
    PF.active = ini.meta.active
    if not PF.meta[PF.active or ''] then PF.active = PF.list[1] end
    return #PF.list > 0
end

function PF.saveServers()
    mkdir(ROOT)
    local out = { '; Ranger Helper - известные серверы (КПК хранится отдельно для каждого)', '[meta]',
                  'last=' .. tostring(PF.srvKey or PF.lastKey or ''), 'order=' .. table.concat(PF.srvList, ',') }
    for _, k in ipairs(PF.srvList) do
        local m = PF.srvMeta[k]
        out[#out + 1] = ''
        out[#out + 1] = '[' .. k .. ']'
        out[#out + 1] = 'name=' .. escVal(m.name)
        out[#out + 1] = 'addr=' .. escVal(m.addr)
        out[#out + 1] = 'seen=' .. tostring(m.seen or 0)
    end
    writeAll(SRV_FILE, table.concat(out, '\n') .. '\n')
end

function PF.loadServers()
    PF.srvList, PF.srvMeta, PF.lastKey = {}, {}, nil
    local ini = readIni(SRV_FILE)
    if not ini or not ini.meta then return false end
    for k in tostring(ini.meta.order or ''):gmatch('[^,]+') do
        local t = ini[k]
        if t and k:match('^[%w_]+$') and k ~= '_local' then
            PF.srvList[#PF.srvList + 1] = k
            PF.srvMeta[k] = { name = unescVal(t.name), addr = unescVal(t.addr), seen = tonumber(t.seen) or 0 }
        end
    end
    local last = tostring(ini.meta.last or '')
    if last:match('^[%w_]+$') then PF.lastKey = last end
    return true
end

local leaves
leaves = function(items)
    local n = 0
    for _, it in ipairs(type(items) == 'table' and items or {}) do
        if type(it) == 'table' then
            if type(it.children) == 'table' then n = n + leaves(it.children) else n = n + 1 end
        end
    end
    return n
end

local function jsonFile(path)
    local t = readAll(path)
    if not t then return nil end
    t = t:gsub('^\239\187\191', '')
    local ok, d = pcall(decodeJson, t)
    if ok and type(d) == 'table' then return d end
    return nil
end

local function liveStat()
    local pieN, wn = 0, 0
    for _, it in ipairs(binder.pie.items) do
        if it.children then pieN = pieN + #it.children else pieN = pieN + 1 end
    end
    for _, w in ipairs(weapons) do if w.on then wn = wn + 1 end end
    local nm = trim(ffi.string(profile.name) .. ' ' .. ffi.string(profile.surname))
    return { binds = #binds, dialogs = #dialogs, notes = #binder.notes, pie = pieN, weapons = wn, char = nm }
end

local function fileStat(dir)
    local s = { binds = 0, dialogs = 0, notes = 0, pie = 0, weapons = 0, char = '' }
    local ini = readIni(dir .. '\\binder.ini')
    if ini and ini.meta then s.binds = tonumber(ini.meta.count) or 0 end
    ini = readIni(dir .. '\\dialogs.ini')
    if ini and ini.meta then s.dialogs = tonumber(ini.meta.count) or 0 end
    local d = jsonFile(dir .. '\\notes.json')
    if d and type(d.notes) == 'table' then s.notes = #d.notes end
    d = jsonFile(dir .. '\\pie.json')
    if d then s.pie = leaves(d.items) end
    d = jsonFile(dir .. '\\weaponBinds.json')
    if d and type(d.weapons) == 'table' then
        for _, w in ipairs(d.weapons) do
            if type(w) == 'table' and w.on == true then s.weapons = s.weapons + 1 end
        end
    end
    ini = readIni(dir .. '\\character.ini')
    if ini and ini.profile then s.char = trim((ini.profile.name or '') .. ' ' .. (ini.profile.surname or '')) end
    return s
end

function PF.stat(id)
    if id == PF.active then return liveStat() end
    local c = PF.cache[id]
    if c and c.gen == PF.gen then return c end
    c = fileStat(pdir(id))
    c.gen = PF.gen
    PF.cache[id] = c
    return c
end

local function kpkLive()
    local ch, it = 0, 0
    for si = 1, 3 do
        for _, c in ipairs(kpkSecs[si].chapters) do ch = ch + 1; it = it + #c.items end
    end
    return ch, it
end

local function kpkFileStat(key)
    local c = PF.kcache[key]
    if c and c.gen == PF.gen then return c.ch, c.it end
    local dir = sdir(key)
    local ch, it = 0, 0
    for si = 1, 3 do
        local d = jsonFile(dir .. '\\' .. binder.KPK_FILES[si] .. '.json')
        local list = type(d) == 'table' and (d.chapters or d) or {}
        for _, chap in ipairs(type(list) == 'table' and list or {}) do
            if type(chap) == 'table' then
                ch = ch + 1
                local items = chap.items or chap.item
                if type(items) == 'table' then it = it + #items end
            end
        end
    end
    PF.kcache[key] = { gen = PF.gen, ch = ch, it = it }
    return ch, it
end

function PF.copyCat(c, from, to)
    mkdir(to)
    for _, fn in ipairs(c.files) do
        local s = readAll(from .. '\\' .. fn)
        if not s then s = readAll(DEF_DIR .. '\\' .. fn) end
        if s then writeAll(to .. '\\' .. fn, s) end
    end
end

function PF.ensureFiles(dir)
    mkdir(dir)
    for _, c in ipairs(CATS) do
        for _, fn in ipairs(c.files) do
            if not exists(dir .. '\\' .. fn) then copyFile(DEF_DIR .. '\\' .. fn, dir .. '\\' .. fn) end
        end
    end
end

function PF.genDefaults()
    mkdir(ROOT); mkdir(PROF_DIR); mkdir(DEF_DIR)
    local oldDir = PF.dir
    PF.setDir(DEF_DIR)
    for _, c in ipairs(CATS) do pcall(c.save) end
    PF.setDir(oldDir)
end

function PF.flush()
    pcall(X.saveConfig)
    for _, c in ipairs(CATS) do pcall(c.save) end
end

function PF.after(old)
    if type(old) ~= 'table' then old = { dep = old } end
    binder.needSave, binder.needSync = false, false
    X.cfgClean()
    pcall(binder.dlgFlush)
    local N = binder.note
    N.open, N.cur, N.loaded, N.sel, N.delAsk, N.cap = false, nil, nil, 1, nil, false
    pcall(binder.noteCursor, false)
    binder.fn.bufs = {}
    editor[0] = false
    local d = binder.dep
    if d.cmd ~= old.dep then
        pcall(sampUnregisterChatCommand, old.dep)
        if binder.ready then pcall(sampRegisterChatCommand, d.cmd, function() binder.depToggle() end) end
    end
    if binder.ready then
        if old.main and old.main ~= SM.cmd and SM.cmdFn then
            if old.main ~= 'ph' then pcall(sampUnregisterChatCommand, old.main) end
            pcall(sampRegisterChatCommand, SM.cmd, SM.cmdFn)
        end
        if old.mark and old.mark ~= binder.mark.cmd then
            pcall(sampUnregisterChatCommand, old.mark)
            pcall(sampRegisterChatCommand, binder.mark.cmd, function(arg) binder.targetCmd(arg) end)
        end
        if old.afind and old.afind ~= binder.afind.cmd then
            pcall(sampUnregisterChatCommand, old.afind)
            pcall(sampRegisterChatCommand, binder.afind.cmd, function(arg) binder.afindCmd(arg) end)
        end
    end
    pcall(binder.sync)
    pcall(binder.tabApply)
    PF.gen = PF.gen + 1
end

function PF.loadCats(set)
    local oldCmds = { dep = binder.dep.cmd, main = SM.cmd, mark = binder.mark.cmd, afind = binder.afind.cmd }
    PF.ensureFiles(PF.dir)
    for _, c in ipairs(CATS) do
        if not set or set[c.id] then
            PF.withDir(DEF_DIR, function() c.load() end)
            pcall(c.load)
        end
    end
    PF.after(oldCmds)
end

function PF.create(name, srcId, set)
    PF.flush()
    local id = 'p' .. PF.nextId
    PF.nextId = PF.nextId + 1
    mkdir(pdir(id))
    for _, c in ipairs(CATS) do
        local from = (srcId and set and set[c.id]) and pdir(srcId) or DEF_DIR
        PF.copyCat(c, from, pdir(id))
    end
    PF.list[#PF.list + 1] = id
    PF.meta[id] = { name = name, color = ((#PF.list - 1) % #PAL) + 1, created = os.time() }
    PF.saveIndex()
    PF.gen = PF.gen + 1
    return id
end

function PF.transfer(srcId, dstId, set)
    PF.flush()
    for _, c in ipairs(CATS) do
        if set[c.id] then PF.copyCat(c, pdir(srcId), pdir(dstId)) end
    end
    if dstId == PF.active then PF.loadCats(set) end
    PF.gen = PF.gen + 1
end

function PF.switch(id)
    if id == PF.active or not PF.meta[id] then return false end
    pcall(binder.stopAll)
    PF.flush()
    PF.active = id
    PF.setDir(pdir(id))
    PF.saveIndex()
    PF.loadCats(nil)
    return true
end

function PF.delete(id)
    if id == PF.active or #PF.list <= 1 or not PF.meta[id] then return false end
    for _, c in ipairs(CATS) do
        for _, fn in ipairs(c.files) do os.remove(pdir(id) .. '\\' .. fn) end
    end
    pcall(function() ffi.C.RemoveDirectoryA(pdir(id)) end)
    for i, v in ipairs(PF.list) do
        if v == id then table.remove(PF.list, i); break end
    end
    PF.meta[id], PF.cache[id] = nil, nil
    PF.saveIndex()
    PF.gen = PF.gen + 1
    return true
end

function PF.activeName()
    local m = PF.meta[PF.active or '']
    return m and m.name or nil
end

function PF.kpkSub()
    local m = PF.srvMeta[PF.srvKey or '']
    if m and m.name ~= '' then return '  -  ' .. binder.cut(m.name, 20) end
    return ''
end

function PF.serverUse(key, addr, name)
    local isNew = (PF.srvMeta[key] == nil)
    local first = isNew and (#PF.srvList == 0)
    local old = PF.srvKey
    if old and old ~= key then pcall(binder.saveKpk) end

    local m = PF.srvMeta[key]
    if not m then
        m = { name = '', addr = '', seen = 0 }
        PF.srvMeta[key] = m
        PF.srvList[#PF.srvList + 1] = key
    end
    if name and name ~= '' then m.name = name end
    if addr and addr ~= '' then m.addr = addr end
    m.seen = os.time()

    PF.srvKey = key
    PF.useKpk(key, true)
    if not kpkHasJson(binder.kpkDir) then

        local lo = SRV_DIR .. '\\_local'
        if copyKpkFiles(lo, binder.kpkDir) == 0 then
            if exists(legacyFile('_local')) then binder.kpkLegacy = legacyFile('_local')
            elseif exists(ROOT .. '\\kpk.ini') then binder.kpkLegacy = ROOT .. '\\kpk.ini' end
        end
    end
    if binder.loadKpk() == 'missing' then pcall(binder.saveKpk) end
    PF.dropLocal()
    binder.kpk.pop.open = false
    pcall(binder.kpkCursor, false)
    X.clearKpkOpen()
    editor[0] = false
    pcall(binder.sync)
    PF.saveServers()
    PF.gen = PF.gen + 1

    if old and old ~= key then
        local label = (m.name ~= '' and m.name) or addr or key
        binder.say('Сервер: {aaaaaa}' .. binder.cut(label, 40) .. '{ffffff}. Загружен КПК этого сервера.')
    end
end

function PF.serverTick()
    local ok, addr, port = pcall(sampGetCurrentServerAddress)
    if not ok or type(addr) ~= 'string' or addr == '' then return end
    port = tonumber(port) or 0
    local key = (addr .. '_' .. port):gsub('[^%w]', '_')
    local name
    local okS, state = pcall(sampGetGamestate)
    if (not okS) or state == 3 then
        local okN, nm = pcall(sampGetCurrentServerName)
        if okN and type(nm) == 'string' and nm ~= '' then name = u8:encode(nm) end
    end
    if key ~= PF.srvKey then
        PF.serverUse(key, addr .. ':' .. port, name)
    elseif name then
        local m = PF.srvMeta[key]
        if m and m.name ~= name then m.name = name; PF.saveServers() end
    end
end

function PF.dropLocal()
    local lo = SRV_DIR .. '\\_local'
    if not doesDirectoryExist(lo) then return end
    for _, n in ipairs(binder.KPK_FILES) do
        pcall(os.remove, lo .. '\\' .. n .. '.json')
        pcall(os.remove, lo .. '\\' .. n .. '.json.bad')
    end
    for _, n in ipairs({ 'kpk.ini', 'kpk.ini.old', 'kpk.ini.bad' }) do pcall(os.remove, lo .. '\\' .. n) end
    pcall(function() ffi.C.RemoveDirectoryA(lo) end)
end

function PF.copyKpk(fromKey)
    if not binder.kpkDir then return false end
    if not PF.srvMeta[fromKey] or fromKey == PF.srvKey then return false end
    local from = sdir(fromKey)
    if from == binder.kpkDir or not kpkHasJson(from) then return false end
    if copyKpkFiles(from, binder.kpkDir) == 0 then return false end
    binder.kpk.pop.open = false
    pcall(binder.kpkCursor, false)
    X.clearKpkOpen()
    editor[0] = false
    pcall(binder.loadKpk)
    pcall(binder.sync)
    PF.gen = PF.gen + 1
    return true
end

function PF.migrate()
    local id = 'p1'
    PF.list, PF.meta, PF.nextId, PF.active = { id }, { [id] = { name = 'Основной', color = 1, created = os.time() } }, 2, id
    mkdir(pdir(id))
    for _, c in ipairs(CATS) do
        if c.id ~= 'char' then
            for _, fn in ipairs(c.files) do
                local s = readAll(ROOT .. '\\' .. fn)
                if s then writeAll(pdir(id) .. '\\' .. fn, s) end
            end
        end
    end
    PF.saveIndex()
    mkdir(SRV_DIR)
    PF.saveServers()
end

function PF.init()
    mkdir(ROOT); mkdir(PROF_DIR); mkdir(SRV_DIR)
    PF.genDefaults()
    if not PF.loadIndex() then PF.migrate() end
    mkdir(pdir(PF.active))

    local legacy = ROOT .. '\\settings.ini'
    if exists(legacy) then
        for _, id in ipairs(PF.list) do
            mkdir(pdir(id))
            local f = pdir(id) .. '\\settings.ini'
            if not exists(f) then copyFile(legacy, f) end
        end
        pcall(os.remove, legacy .. '.old')
        pcall(os.rename, legacy, legacy .. '.old')
    end
    PF.setDir(pdir(PF.active))
    PF.loadServers()

    local key = PF.lastKey
    if key == '_local' then key = nil end
    PF.srvKey = key
    if key then PF.useKpk(key, false) else binder.kpkDir, binder.kpkLegacy = nil, nil end
end

local UI = {
    view = 'list', form = nil, edit = nil, err = nil,
    confirm = nil, confirmT = 0, toastMsg = nil, toastT = 0,
    name = new.char[48](),
}
PF.ui = UI

local function toast(msg) UI.toastMsg, UI.toastT = msg, os.clock() end
local function go(view)
    UI.view, UI.err, UI.confirm = view, nil, nil
    X.pageReset()
end

local function cardA(dl, x, y, w, h, r, fill, border, a)
    rrf(dl, V(x, y), V(x + w, y + h), U(fill, a), r)
    rr(dl, V(x + 0.5, y + 0.5), V(x + w - 0.5, y + h - 0.5), U(border or P.line, 0.9 * a), r, 15, 1)
end

local function firstChar(name)
    local ch = tostring(name or ''):match('^[%z\1-\127\194-\244][\128-\191]*') or '?'
    return ch:upper()
end

local function nameTaken(name, exceptId)
    local l = binder.lowerU8(name)
    for _, id in ipairs(PF.list) do
        if id ~= exceptId and binder.lowerU8(PF.meta[id].name) == l then return true end
    end
    return false
end

local function chipsHeight(items, w)
    local px, rows = 0, 1
    for _, it in ipairs(items) do
        local cw2 = SM.tw(it.label) + 26
        if px + cw2 > w and px > 0 then px = 0; rows = rows + 1 end
        px = px + cw2 + 6
    end
    return rows * 28 + (rows - 1) * 6
end

local function chipPick(dl, idp, x, y, w, items, cur)
    local px, py, res = x, y, nil
    for i, it in ipairs(items) do
        local cw2 = SM.tw(it.label) + 26
        if px + cw2 > x + w and px > x then px = x; py = py + 34 end
        imgui.SetCursorScreenPos(V(px, py))
        if imgui.InvisibleButton(idp .. i, V(cw2, 28)) then res = it.key end
        local t = hot(idp .. i, imgui.IsItemHovered())
        local on = (cur == it.key)
        card(dl, px, py, cw2, 28, 8, on and P.active or lerpC(P.chip, P.cardHover, t),
            on and P.accent or lerpC(P.line, P.accentSoft, t * 0.6))
        centerText(dl, px, py, cw2, 28, it.label, U(on and P.text or lerpC(P.muted, P.text, t)))
        px = px + cw2 + 6
    end
    return res, (py + 28 - y)
end

local function iconBtn(dl, id, x, y, glyph, tip, danger, confirming, dim)
    imgui.SetCursorScreenPos(V(x, y))
    local clicked = imgui.InvisibleButton(id, V(32, 32))
    local hov = imgui.IsItemHovered()
    local t = hot(id, hov and not dim)
    local a = dim and 0.4 or 1
    local acc = danger and P.danger or P.accent
    cardA(dl, x, y, 32, 32, 9, confirming and P.danger or lerpC(P.chip, P.cardHover, t), lerpC(P.line, acc, t * 0.9), a)
    local fg = confirming and C(255, 255, 255) or lerpC(P.muted, danger and P.danger or P.text, t)
    centerText(dl, x, y, 32, 32, glyph, U(fg, a))
    if hov and tip then SM.tip(tip) end
    return clicked and not dim
end

local function catTile(dl, id, x, y, w, c, on, info, dim)
    imgui.SetCursorScreenPos(V(x, y))
    local clicked = imgui.InvisibleButton(id, V(w, 46))
    local t = hot(id, imgui.IsItemHovered() and not dim)
    local ck = id .. 'ck'
    if hv[ck] == nil then hv[ck] = on and 1 or 0 end
    local k = anim(ck, on and 1 or 0, 18)
    local a = dim and 0.45 or 1
    cardA(dl, x, y, w, 46, 10, on and lerpC(P.active, P.cardHover, t * 0.5) or lerpC(P.chip, P.cardHover, t),
        on and P.accent or lerpC(P.line, P.accent, t * 0.6), a)
    rrf(dl, V(x + 8, y + 8), V(x + 38, y + 38), U(P.item, a), 8)
    centerText(dl, x + 8, y + 8, 30, 30, ico(c.ico), U(on and P.accentSoft or P.muted, a))
    dl:PushClipRect(V(x + 46, y), V(x + w - 38, y + 46), true)
    dl:AddText(V(x + 46, y + 6), U(P.text, a), c.name)
    dl:AddText(V(x + 46, y + 24), U(P.muted, a), info)
    dl:PopClipRect()
    local bx, by = x + w - 30, y + 13
    rrf(dl, V(bx, by), V(bx + 20, by + 20), U(lerpC(P.chip, P.accent, k), a), 6)
    rr(dl, V(bx + 0.5, by + 0.5), V(bx + 19.5, by + 19.5), U(lerpC(P.line, P.accent, k), a), 6, 15, 1.2)
    if k > 0.02 then
        local cc = U(C(255, 255, 255), k * a)
        dl:AddLine(V(bx + 5, by + 10.5), V(bx + 8.6, by + 14.2), cc, 2.2)
        dl:AddLine(V(bx + 8.6, by + 14.2), V(bx + 15.4, by + 6.4), cc, 2.2)
    end
    return clicked and not dim
end

local function drawToast(cdl, x, iw, base, viewH)
    if not UI.toastMsg then return end
    local dt = os.clock() - UI.toastT
    if dt > 3.2 then UI.toastMsg = nil; return end
    local a = clamp((3.2 - dt) / 0.45, 0, 1) * clamp(dt / 0.12, 0, 1)
    local msg = UI.toastMsg
    local w = SM.tw(msg) + 58
    local tx = x + (iw - w) / 2
    local ty = base.y + imgui.GetScrollY() + viewH - 50
    cardA(cdl, tx, ty, w, 36, 11, P.card, P.accent, a)
    cdl:AddCircleFilled(V(tx + 20, ty + 18), 9, U(P.accent, a), 20)
    cdl:AddLine(V(tx + 16, ty + 18), V(tx + 19, ty + 21), U(C(255, 255, 255), a), 2)
    cdl:AddLine(V(tx + 19, ty + 21), V(tx + 24.5, ty + 14.5), U(C(255, 255, 255), a), 2)
    cdl:AddText(V(tx + 38, ty + 10), U(P.text, a), msg)
end

local function fieldBegin()
    pushInput()
    imgui.PushStyleColor(imgui.Col.FrameBg, P.chip)
    imgui.PushStyleColor(imgui.Col.FrameBgHovered, P.item)
    imgui.PushStyleColor(imgui.Col.FrameBgActive, P.active)
end
local function fieldEnd()
    imgui.PopStyleColor(3)
    popInput()
end

local function backButton(dl, id, cx, cw, pos)
    return button(dl, id, cx + cw - 108, pos.y + 20, 108, 34, ico('ARROW_LEFT') .. ' Назад', false)
end

local function openForm(kind, srcId, dstId)
    UI.form = { kind = kind, src = srcId, dst = dstId, sel = allCats() }
    local nm = ''
    if dstId == 'new' then
        if kind == 'dup' and PF.meta[srcId] then
            nm = binder.cut(PF.meta[srcId].name, 30) .. ' (копия)'
        else
            nm = 'Профиль ' .. (#PF.list + 1)
        end
    end
    imgui.StrCopy(UI.name, nm)
    go('form')
end

local function openEdit(id)
    UI.edit = { id = id, color = PF.meta[id].color }
    imgui.StrCopy(UI.name, PF.meta[id].name)
    go('edit')
end

local function submitForm()
    local F = UI.form
    if not F then return end
    if F.dst == 'new' then
        local name = trim(ffi.string(UI.name))
        if name == '' then UI.err = 'Введите название профиля'; return end
        if #PF.list >= MAX_PROFILES then UI.err = 'Достигнут лимит профилей: ' .. MAX_PROFILES; return end
        if nameTaken(name) then UI.err = 'Профиль с таким названием уже есть'; return end
        PF.create(name, (F.src ~= 'blank') and F.src or nil, F.sel)
        toast('Профиль «' .. binder.cut(name, 30) .. '» создан')
    else
        if F.src == F.dst or not PF.meta[F.src] or not PF.meta[F.dst] then UI.err = 'Выберите разные профили'; return end
        local n = 0
        for _, v in pairs(F.sel) do if v then n = n + 1 end end
        if n == 0 then UI.err = 'Отметьте хотя бы один раздел'; return end
        PF.transfer(F.src, F.dst, F.sel)
        toast('Данные перенесены в «' .. binder.cut(PF.meta[F.dst].name, 30) .. '»')
    end
    go('list')
end

local function drawForm(dl, pos, cx, cw)
    local F = UI.form
    if not F then go('list'); return end
    local isNew = (F.dst == 'new')
    if F.src ~= 'blank' and not PF.meta[F.src] then F.src = PF.active end
    if not isNew and not PF.meta[F.dst] then F.dst = PF.active end

    heading(dl, cx, pos.y + 18, isNew and (F.kind == 'dup' and 'Копия профиля' or 'Новый профиль') or 'Перенос данных',
        isNew and 'Что скопировать из источника; остальное - по умолчанию' or 'Выбранные разделы в целевом профиле будут заменены')
    local back = backButton(dl, '##pf_back', cx, cw, pos)

    local ly = pos.y + 70
    local viewH = pos.y + WIN_H - MARGIN - ly
    local base, cdl = beginList('##pf_form', cx, ly, cw, viewH)
    local iw, x = cw - 10, base.x
    local font = imgui.GetFont()
    local y = base.y
    local pad = 16
    local innerW = iw - pad * 2

    local itemsSrc, itemsDst = {}, {}
    if isNew then itemsSrc[1] = { key = 'blank', label = 'Пустой профиль' } end
    for _, id in ipairs(PF.list) do
        itemsSrc[#itemsSrc + 1] = { key = id, label = binder.cut(PF.meta[id].name, 22) }
        itemsDst[#itemsDst + 1] = { key = id, label = binder.cut(PF.meta[id].name, 22) }
    end

    local hA = pad + 4
    if isNew then hA = hA + 20 + 38 + 8 end
    hA = hA + 20 + chipsHeight(itemsSrc, innerW) + 12
    if not isNew then hA = hA + 20 + chipsHeight(itemsDst, innerW) + 12 end
    card(cdl, x, y, iw, hA, 14, P.card)

    local ty = y + pad
    if isNew then
        cdl:AddText(V(x + pad + 2, ty), U(P.muted), 'Название профиля')
        ty = ty + 20
        fieldBegin()
        imgui.SetCursorScreenPos(V(x + pad, ty))
        imgui.PushItemWidth(innerW)
        imgui.InputTextWithHint('##pf_name', 'Например: Основной, Рейнджер, Тестовый', UI.name, ffi.sizeof(UI.name))
        imgui.PopItemWidth()
        if imgui.IsItemActive() then
            local mn, mx = imgui.GetItemRectMin(), imgui.GetItemRectMax()
            rr(cdl, V(mn.x + 0.5, mn.y + 0.5), V(mx.x - 0.5, mx.y - 0.5), U(P.accent, 0.9), 9, 15, 1.2)
        end
        fieldEnd()
        ty = ty + 38 + 8
    end

    cdl:AddText(V(x + pad + 2, ty), U(P.muted), isNew and 'Источник данных' or 'Из профиля')
    ty = ty + 20
    local r, h = chipPick(cdl, '##pf_src', x + pad, ty, innerW, itemsSrc, F.src)
    if r and r ~= F.src then
        if not isNew and r == F.dst then F.dst = F.src end
        F.src = r
        UI.err = nil
    end
    ty = ty + h + 12

    if not isNew then
        cdl:AddText(V(x + pad + 2, ty), U(P.muted), 'В профиль')
        ty = ty + 20
        local r2, h2 = chipPick(cdl, '##pf_dst', x + pad, ty, innerW, itemsDst, F.dst)
        if r2 and r2 ~= F.dst then
            if r2 == F.src then F.src = F.dst end
            F.dst = r2
            UI.err = nil
        end
        ty = ty + h2 + 12
    end
    y = y + hA + 10

    local blank = isNew and F.src == 'blank'
    local st = (not blank) and PF.stat(F.src) or nil
    local rows = math.ceil(#CATS / 2)
    local hB = 62 + rows * 54 + 8
    card(cdl, x, y, iw, hB, 14, P.card)
    rrf(cdl, V(x + 14, y + 15), V(x + 18, y + 37), U(P.accent), 2)
    cdl:AddTextFontPtr(font, 16, V(x + 28, y + 14), U(P.text), 'Разделы')
    cdl:AddText(V(x + 28, y + 36), U(P.muted), blank and 'Пустой профиль: все разделы создаются по умолчанию' or 'Отметьте, что копировать')
    if not blank then
        if button(cdl, '##pf_none', x + iw - 16 - 100, y + 14, 100, 28, 'Снять все', false) then F.sel = {} end
        if button(cdl, '##pf_all', x + iw - 16 - 100 - 8 - 112, y + 14, 112, 28, 'Выбрать все', false) then F.sel = allCats() end
    end
    local tw = (innerW - 10) / 2
    for i, c in ipairs(CATS) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local tx, tyy = x + pad + col * (tw + 10), y + 56 + row * 54
        local info = st and c.info(st) or 'по умолчанию'
        if catTile(cdl, '##pf_cat' .. c.id, tx, tyy, tw, c, (not blank) and F.sel[c.id] == true, info, blank) then
            F.sel[c.id] = not F.sel[c.id]
            UI.err = nil
        end
    end
    y = y + hB + 12

    local okLabel = isNew and (ico('PLUS') .. ' Создать профиль') or (ico('ARROW_RIGHT_ARROW_LEFT') .. ' Перенести')
    local okW = 190
    local msg, mcol = UI.err, P.danger
    if not msg and not isNew then
        msg, mcol = 'Данные профиля «' .. binder.cut(PF.meta[F.dst].name, 24) .. '» будут перезаписаны', P.muted
    end
    if msg then
        cdl:PushClipRect(V(x, y), V(x + iw - okW - 130, y + 36), true)
        cdl:AddText(V(x + 4, y + 10), U(mcol), msg)
        cdl:PopClipRect()
    end
    local doOk = button(cdl, '##pf_ok', x + iw - okW, y, okW, 36, okLabel, true)
    local doCancel = button(cdl, '##pf_cancel', x + iw - okW - 10 - 110, y, 110, 36, 'Отмена', false)
    y = y + 36 + 8
    endList(base, y - base.y)

    if doOk then submitForm() elseif doCancel or back then go('list') end
end

local function drawEdit(dl, pos, cx, cw)
    local E = UI.edit
    if not E or not PF.meta[E.id] then go('list'); return end
    heading(dl, cx, pos.y + 18, 'Изменить профиль', 'Название и цвет карточки')
    local back = backButton(dl, '##pf_back3', cx, cw, pos)

    local ly = pos.y + 70
    local viewH = pos.y + WIN_H - MARGIN - ly
    local base, cdl = beginList('##pf_edit', cx, ly, cw, viewH)
    local iw, x = cw - 10, base.x
    local y, pad = base.y, 16
    local innerW = iw - pad * 2

    local hA = 16 + 20 + 38 + 16 + 20 + 52 + 20
    card(cdl, x, y, iw, hA, 14, P.card)
    local ty = y + 16
    cdl:AddText(V(x + pad + 2, ty), U(P.muted), 'Название профиля')
    ty = ty + 20
    fieldBegin()
    imgui.SetCursorScreenPos(V(x + pad, ty))
    imgui.PushItemWidth(innerW)
    imgui.InputTextWithHint('##pf_ename', 'Название профиля', UI.name, ffi.sizeof(UI.name))
    imgui.PopItemWidth()
    if imgui.IsItemActive() then
        local mn, mx = imgui.GetItemRectMin(), imgui.GetItemRectMax()
        rr(cdl, V(mn.x + 0.5, mn.y + 0.5), V(mx.x - 0.5, mx.y - 0.5), U(P.accent, 0.9), 9, 15, 1.2)
    end
    fieldEnd()
    ty = ty + 38 + 16
    cdl:AddText(V(x + pad + 2, ty), U(P.muted), 'Цвет')
    ty = ty + 20
    local gap = 8
    local swW = (innerW - gap * (#PAL - 1)) / #PAL
    for i, color in ipairs(PAL) do
        local sx = x + pad + (i - 1) * (swW + gap)
        imgui.SetCursorScreenPos(V(sx, ty))
        if imgui.InvisibleButton('##pf_col' .. i, V(swW, 52)) then E.color = i end
        local t = hot('pf_col' .. i, imgui.IsItemHovered())
        local chosen = (E.color == i)
        local cc = C(color[1], color[2], color[3])
        card(cdl, sx, ty, swW, 52, 10, lerpC(P.item, P.cardHover, t), chosen and cc or lerpC(P.line, cc, t * 0.8))
        local lift = t * 2
        rrf(cdl, V(sx + 5, ty + 5 - lift), V(sx + swW - 5, ty + 47 - lift), U(cc), 7)
        if chosen then
            rr(cdl, V(sx, ty), V(sx + swW, ty + 52), U(cc), 10, 15, 2.0)
            local ccx, ccy = sx + swW / 2, ty + 26
            cdl:AddCircleFilled(V(ccx, ccy), 9, U(C(255, 255, 255)), 28)
            cdl:AddLine(V(ccx - 4, ccy), V(ccx - 1, ccy + 3.5), U(C(30, 34, 50)), 2)
            cdl:AddLine(V(ccx - 1, ccy + 3.5), V(ccx + 4.5, ccy - 3.5), U(C(30, 34, 50)), 2)
        end
    end
    y = y + hA + 12

    local okW = 170
    if UI.err then
        cdl:AddText(V(x + 4, y + 10), U(P.danger), UI.err)
    end
    local doOk = button(cdl, '##pf_eok', x + iw - okW, y, okW, 36, 'Сохранить', true)
    local doCancel = button(cdl, '##pf_ecancel', x + iw - okW - 10 - 110, y, 110, 36, 'Отмена', false)
    y = y + 36 + 8
    endList(base, y - base.y)

    if doOk then
        local name = trim(ffi.string(UI.name))
        if name == '' then UI.err = 'Введите название профиля'
        elseif nameTaken(name, E.id) then UI.err = 'Профиль с таким названием уже есть'
        else
            PF.meta[E.id].name, PF.meta[E.id].color = name, E.color
            PF.saveIndex()
            toast('Профиль сохранён')
            go('list')
        end
    elseif doCancel or back then
        go('list')
    end
end

local function drawKpk(dl, pos, cx, cw)
    heading(dl, cx, pos.y + 18, 'КПК других серверов', 'Скопируйте готовый КПК на текущий сервер')
    local back = backButton(dl, '##pf_back2', cx, cw, pos)

    local ly = pos.y + 70
    local viewH = pos.y + WIN_H - MARGIN - ly
    local base, cdl = beginList('##pf_kpk', cx, ly, cw, viewH)
    local iw, x = cw - 10, base.x
    local font = imgui.GetFont()
    local y = base.y

    local cur = PF.srvMeta[PF.srvKey or '']
    local curName = (cur and cur.name ~= '' and cur.name) or (cur and cur.addr) or 'текущий сервер'
    cdl:AddText(V(x + 4, y + 2), U(P.muted), 'КПК сервера «' .. binder.cut(curName, 34) .. '» будет полностью заменён выбранным.')
    y = y + 28

    local doCopy
    local n = 0
    for _, k in ipairs(PF.srvList) do
        if k ~= PF.srvKey then
            n = n + 1
            local m = PF.srvMeta[k]
            local ch, it = kpkFileStat(k)
            card(cdl, x, y, iw, 66, 12, P.card)
            iconBadge(cdl, x + 14, y + 13, 40, 'SERVER', P.active)
            local confirming = (UI.confirm == 'kpk' .. k) and (os.clock() - UI.confirmT < 4)
            local bw = 170
            cdl:PushClipRect(V(x + 64, y), V(x + iw - bw - 28, y + 66), true)
            cdl:AddTextFontPtr(font, 16, V(x + 64, y + 10), U(P.text), (m.name ~= '' and m.name) or m.addr)
            chipL(cdl, x + 64, y + 36, ch .. ' гл. / ' .. it .. ' пунктов', P.chip, P.accentSoft)
            cdl:PopClipRect()
            local label = confirming and 'Заменить?' or (ico('COPY') .. ' Скопировать сюда')
            if confirming then
                imgui.SetCursorScreenPos(V(x + iw - bw - 14, y + 17))
                if imgui.InvisibleButton('##pf_kc' .. k, V(bw, 32)) then doCopy = k end
                rrf(cdl, V(x + iw - bw - 14, y + 17), V(x + iw - 14, y + 49), U(P.danger), 9)
                centerText(cdl, x + iw - bw - 14, y + 17, bw, 32, label, U(C(255, 255, 255)))
            elseif button(cdl, '##pf_kc' .. k, x + iw - bw - 14, y + 17, bw, 32, label, false) then
                UI.confirm, UI.confirmT = 'kpk' .. k, os.clock()
            end
            y = y + 74
        end
    end
    if n == 0 then
        cdl:AddText(V(x + 4, y + 6), U(P.muted), 'Других серверов пока нет. Они появятся, когда вы зайдёте на другой сервер.')
        y = y + 30
    end
    endList(base, y - base.y + 4)

    if doCopy then
        if PF.copyKpk(doCopy) then toast('КПК скопирован') else toast('Не удалось скопировать КПК') end
        go('list')
    elseif back then
        go('list')
    end
end

local function drawList(dl, pos, cx, cw)
    heading(dl, cx, pos.y + 18, 'Профили', 'Отыгровки и настройки; КПК - отдельно для каждого сервера')
    if button(dl, '##pf_home', cx + cw - 164 - 8 - 108, pos.y + 20, 108, 34, ico('HOUSE') .. ' Главная', false) then
        SM.goTab(1)
        return
    end
    if #PF.list < MAX_PROFILES then
        if button(dl, '##pf_new', cx + cw - 164, pos.y + 20, 164, 34, ico('PLUS') .. ' Новый профиль', true) then
            openForm('new', PF.active, 'new')
            return
        end
    end

    local ly = pos.y + 70
    local viewH = pos.y + WIN_H - MARGIN - ly
    local base, cdl = beginList('##pf_list', cx, ly, cw, viewH)
    local iw, x = cw - 10, base.x
    local font = imgui.GetFont()
    local y = base.y
    local act

    local sk = PF.srvKey
    local sm = PF.srvMeta[sk or '']
    local real = (sm ~= nil)
    local sName = (sm and sm.name ~= '' and sm.name) or (sm and sm.addr ~= '' and sm.addr) or 'Сервер не определён'
    local others = 0
    for _, k in ipairs(PF.srvList) do if k ~= sk then others = others + 1 end end
    local sh = 88
    card(cdl, x, y, iw, sh, 14, P.card)
    iconBadge(cdl, x + 16, y + 18, 52, 'SERVER', P.active, 0.5)
    local rightW = (others > 0) and 196 or 0
    cdl:PushClipRect(V(x + 84, y), V(x + iw - rightW - 12, y + sh), true)
    cdl:AddTextFontPtr(font, 18, V(x + 84, y + 14), U(P.text), sName)
    cdl:AddText(V(x + 84, y + 40), U(P.muted), real and ((sm.name ~= '' and sm.addr ~= '') and sm.addr or 'Название сервера определится после входа')
        or 'Зайдите на сервер - КПК привяжется к нему автоматически')
    local ch, it = kpkLive()
    chipL(cdl, x + 84, y + 60, 'КПК: ' .. ch .. ' гл. / ' .. it .. ' пунктов', P.chip, P.accentSoft)
    cdl:PopClipRect()
    if others > 0 then
        if button(cdl, '##pf_srvs', x + iw - 186, y + 14, 172, 32, ico('CLONE') .. ' КПК других серверов', false) then act = { kind = 'kpk' } end
    end
    y = y + sh + 14

    cdl:AddText(V(x + 4, y), U(P.muted), 'ПРОФИЛИ  ' .. #PF.list .. ' / ' .. MAX_PROFILES)
    y = y + 24

    for _, id in ipairs(PF.list) do
        local m = PF.meta[id]
        local isAct = (id == PF.active)
        local st = PF.stat(id)
        local pc = PAL[m.color] or PAL[1]
        local cc = C(pc[1], pc[2], pc[3])
        local ch2 = 94

        card(cdl, x, y, iw, ch2, 14, isAct and P.active or P.card, isAct and P.accent or P.line)
        rrf(cdl, V(x + 1, y + 22), V(x + 5, y + 72), U(cc), 2)
        cdl:AddCircleFilled(V(x + 40, y + 36), 22, U(cc, 0.92), 36)
        centerText(cdl, x + 18, y + 14, 44, 44, firstChar(m.name), U(C(255, 255, 255)))

        local selX = x + iw - 14 - 254
        cdl:PushClipRect(V(x + 74, y), V(selX - 10, y + 60), true)
        cdl:AddTextFontPtr(font, 17, V(x + 74, y + 13), U(P.text), m.name)
        cdl:AddText(V(x + 74, y + 38), U(P.muted), (m.created > 0) and ('Создан ' .. os.date('%d.%m.%Y', m.created)) or 'Профиль')
        cdl:PopClipRect()
        if isAct then
            local nw = SM.tw(m.name) * 17 / imgui.GetFontSize()
            local chipX = math.min(x + 74 + nw + 10, selX - 80)
            chipL(cdl, chipX, y + 12, 'Активен', P.chip, P.accentSoft)
        end

        local by = y + 14
        if isAct then
            cardA(cdl, selX, by, 100, 32, 9, P.chip, P.accent, 1)
            centerText(cdl, selX, by, 100, 32, ico('CHECK') .. ' Активен', U(P.accentSoft))
        elseif button(cdl, '##pfs' .. id, selX, by, 100, 32, 'Выбрать', true) then
            act = { kind = 'sw', id = id }
        end

        local ix = selX + 100 + 8
        if iconBtn(cdl, '##pfd' .. id, ix, by, ico('COPY'), 'Создать копию профиля') then act = { kind = 'dup', id = id } end
        ix = ix + 38
        if iconBtn(cdl, '##pft' .. id, ix, by, ico('ARROW_RIGHT_ARROW_LEFT'),
            (#PF.list > 1) and 'Перенести выбранные разделы в другой профиль' or 'Нужен второй профиль',
            false, false, #PF.list < 2) then act = { kind = 'tr', id = id } end
        ix = ix + 38
        if iconBtn(cdl, '##pfe' .. id, ix, by, ico('PEN'), 'Изменить название и цвет') then act = { kind = 'edit', id = id } end
        ix = ix + 38
        local canDel = (not isAct) and #PF.list > 1
        local confirming = canDel and (UI.confirm == 'del' .. id) and (os.clock() - UI.confirmT < 4)
        local tip = (not canDel) and (isAct and 'Нельзя удалить активный профиль' or 'Нельзя удалить единственный профиль')
            or (confirming and 'Нажмите ещё раз, чтобы удалить навсегда' or 'Удалить профиль')
        if iconBtn(cdl, '##pfx' .. id, ix, by, ico('TRASH'), tip, true, confirming, not canDel) then
            if confirming then act = { kind = 'del', id = id } else UI.confirm, UI.confirmT = 'del' .. id, os.clock() end
        end

        local sx = x + 18
        local function stat(label, n) sx = chipL(cdl, sx, y + 62, label .. ': ' .. n, P.chip, n > 0 and P.accentSoft or P.muted) end
        stat('Бинды', st.binds); stat('Диалоги', st.dialogs); stat('Оружие', st.weapons)
        stat('Круг. меню', st.pie); stat('Заметки', st.notes)

        y = y + ch2 + 8
    end

    local nh = 82
    y = y + 4
    card(cdl, x, y, iw, nh, 12, P.chip)
    local ic = ico('CIRCLE_INFO')
    if ic ~= '' then cdl:AddText(V(x + 16, y + 14), U(P.accentSoft), ic) end
    cdl:AddText(V(x + 40, y + 12), U(P.muted), 'Профиль хранит биндер, диалоги, оружие, круговое меню, заметки,')
    cdl:AddText(V(x + 40, y + 30), U(P.muted), 'настройки рации, чата и TAB, а также данные персонажа.')
    cdl:AddText(V(x + 40, y + 52), U(P.text), 'КПК общий для всех профилей, но у каждого сервера свой.')
    y = y + nh + 8

    drawToast(cdl, x, iw, base, viewH)
    endList(base, y - base.y)

    if act then
        if act.kind == 'sw' then
            if PF.switch(act.id) then toast('Профиль «' .. binder.cut(PF.meta[act.id].name, 30) .. '» загружен') end
        elseif act.kind == 'dup' then
            openForm('dup', act.id, 'new')
        elseif act.kind == 'tr' then
            local dst = PF.active
            if dst == act.id then
                for _, v in ipairs(PF.list) do if v ~= act.id then dst = v; break end end
            end
            openForm('transfer', act.id, dst)
        elseif act.kind == 'edit' then
            openEdit(act.id)
        elseif act.kind == 'del' then
            local nm = PF.meta[act.id] and PF.meta[act.id].name or ''
            if PF.delete(act.id) then toast('Профиль «' .. binder.cut(nm, 30) .. '» удалён') end
        elseif act.kind == 'kpk' then
            go('kpk')
        end
    end
end

function SM.pfNew() openForm('new', PF.active, 'new') end

X.pages[8] = function(dl, pos, cx, cw)
    local v = UI.view
    if v == 'form' then drawForm(dl, pos, cx, cw)
    elseif v == 'edit' then drawEdit(dl, pos, cx, cw)
    elseif v == 'kpk' then drawKpk(dl, pos, cx, cw)
    else drawList(dl, pos, cx, cw) end
end
end)()

function SM.setCmd(name)
    if SM.cmdFn then
        pcall(sampUnregisterChatCommand, SM.cmd)
        pcall(sampRegisterChatCommand, name, SM.cmdFn)
    end
    SM.cmd = name
    imgui.StrCopy(SM.cmdBuf, name)
end

binder.remote = {

    base  = 'https://raw.githubusercontent.com/aven1xx/ranger-helper/main/',
    root  = 'Ranger Helper/',
    auto  = true,
    cmd   = 'rhupdate',
    busy  = false,
    state = CFG_DIR .. '\\remote.ini',
    st    = { files = {} },

    secFiles = { 'asu', 'aticket', 'apun', 'acarc' },

    kpk_mode     = 'replace',

    servers = {
        { number = '01', name = 'Phoenix', ip = '185.169.134.3:7777' },     { number = '02', name = 'Tucson', ip = '185.169.134.4:7777' },
        { number = '03', name = 'Scottdale', ip = '185.169.134.43:7777' },   { number = '04', name = 'Chandler', ip = '185.169.134.44:7777' },
        { number = '05', name = 'Brainburg', ip = '185.169.134.45:7777' },   { number = '06', name = 'SaintRose', ip = '185.169.134.5:7777' },
        { number = '07', name = 'Mesa', ip = '185.169.134.59:7777' },        { number = '08', name = 'Red Rock', ip = '185.169.134.61:7777' },
        { number = '09', name = 'Yuma', ip = '185.169.134.107:7777' },        { number = '10', name = 'Surprise', ip = '185.169.134.109:7777' },
        { number = '11', name = 'Prescott', ip = '185.169.134.166:7777' },    { number = '12', name = 'Glendale', ip = '185.169.134.171:7777' },
        { number = '13', name = 'Kingman', ip = '185.169.134.172:7777' },     { number = '14', name = 'Winslow', ip = '185.169.134.173:7777' },
        { number = '15', name = 'Payson', ip = '185.169.134.174:7777' },      { number = '16', name = 'Gilbert', ip = '80.66.82.191:7777' },
        { number = '17', name = 'Show Low', ip = '80.66.82.190:7777' },    { number = '18', name = 'Casa Grande', ip = '80.66.82.188:7777' },
        { number = '19', name = 'Page', ip = '80.66.82.168:7777' },        { number = '20', name = 'Sun City', ip = '80.66.82.159:7777' },
        { number = '21', name = 'Queen Creek', ip = '80.66.82.200:7777' }, { number = '22', name = 'Sedona', ip = '80.66.82.144:7777' },
        { number = '23', name = 'Holiday', ip = '80.66.82.132:7777' },     { number = '24', name = 'Wednesday', ip = '80.66.82.128:7777' },
        { number = '25', name = 'Yava', ip = '80.66.82.113:7777' },        { number = '26', name = 'Faraway', ip = '80.66.82.82:7777' },
        { number = '27', name = 'Bumble Bee', ip = '80.66.82.87:7777' },  { number = '28', name = 'Christmas', ip = '80.66.82.54:7777' },
        { number = '29', name = 'Mirage', ip = '80.66.82.39:7777' },      { number = '30', name = 'Love', ip = '80.66.82.33:7777' },
        { number = '31', name = 'Drake', ip = '80.66.82.22:7777' },       { number = '32', name = 'Space' },
        { number = '33', name = 'Home', ip = '80.66.82.235:7777', host = 'home.arizona-rp.com' },
        { number = '200', name = 'Vice City' },
        { number = '301', name = 'Центральный округ' }, { number = '302', name = 'Южный округ' },
        { number = '303', name = 'Северный округ' },    { number = '304', name = 'Восточный округ' },
        { number = '305', name = 'Западный округ' },    { number = '306', name = 'Приморский округ' },
        { number = '307', name = 'Федеральный округ' },
        { number = '101', name = 'Mobile I' }, { number = '102', name = 'Mobile II' }, { number = '103', name = 'Mobile III' },
        { number = '401', name = 'Москва' },    { number = '402', name = 'Санкт Петербург' },
    },
}

;(function()
local R = binder.remote
local unpack = table.unpack or unpack

local function key(s) return (tostring(s or ''):match('^%s*(.-)%s*$')):lower() end
local function say(m) binder.say(m) end

function R.loadState()
    R.st = { files = {} }
    local ini = readIni(R.state)
    if ini and ini.files then for k, v in pairs(ini.files) do R.st.files[k] = v end end
end

function R.saveState()
    local out = { '; Ranger Helper - состояние удалённой загрузки', '[files]' }
    for k, v in pairs(R.st.files) do out[#out + 1] = k .. '=' .. v end
    local f = io.open(R.state, 'w')
    if f then f:write(table.concat(out, '\n'), '\n'); f:close() end
end

function R.enc(s)
    return (s:gsub('[^A-Za-z0-9%-%._~/]', function(c) return string.format('%%%02X', c:byte()) end))
end

local function dlCodes()
    local t = rawget(_G, 'dlstatus')
    if type(t) ~= 'table' then
        for _, name in ipairs({ 'moonloader', 'lib.moonloader' }) do
            local ok, m = pcall(require, name)
            if ok and type(m) == 'table' and type(m.download_status) == 'table' then t = m.download_status; break end
        end
    end
    t = (type(t) == 'table') and t or {}
    return t.STATUS_ENDDOWNLOADDATA or 6, t.STATUSEX_ENDDOWNLOAD or 58
end

function R.fetch(url, dest, timeout)
    local part = dest .. '.part'
    os.remove(part)
    local done = false
    local codeEnd, codeEndEx = dlCodes()
    local ok = pcall(downloadUrlToFile, url, part, function(_, st)
        if st == codeEnd or st == codeEndEx then done = true end
    end)
    if not ok then return false end
    local t0 = os.clock()
    while not done and os.clock() - t0 < (timeout or 30) do wait(50) end
    local f = io.open(part, 'rb')
    if not f then return false end
    local head = f:read(1) or ''
    local size = f:seek('end') or 0
    f:close()

    if not done or size == 0 or head == '<' then os.remove(part); return false end
    os.remove(dest)
    if not os.rename(part, dest) then os.remove(part); return false end
    return true
end

function R.download(rel, dest)
    return R.fetch(R.base .. R.enc(R.root .. rel) .. '?t=' .. os.time(), dest)
end

local TMP = CFG_DIR .. '\\_remote.tmp'

function R.getJson(rel)
    if not R.download(rel, TMP) then return nil end
    local f = io.open(TMP, 'rb')
    if not f then return nil end
    local data = f:read('*a'); f:close(); os.remove(TMP)
    data = data:gsub('^\239\187\191', '')
    local ok, t = pcall(decodeJson, data)
    if ok and type(t) == 'table' then return t end
    return nil
end

function R.getManifest(force)
    local c = R.mc
    if c and not force and os.clock() - c.t < 30 then return c.m end
    local m = R.getJson('manifest.json')
    if m and type(m.files) == 'table' then R.mc = { t = os.clock(), m = m }; return m end
    return nil
end

function R.number()
    local ok, addr, port = pcall(sampGetCurrentServerAddress)
    if ok and type(addr) == 'string' and addr ~= '' then
        local ip = addr .. ':' .. (tonumber(port) or 0)
        for _, s in ipairs(R.servers) do
            if (s.ip and s.ip == ip) or (s.host and s.host:lower() == addr:lower()) then return s.number, s.name end
        end
    end
    local okN, name = pcall(sampGetCurrentServerName)
    if okN and type(name) == 'string' and name ~= '' then
        name = (u8:encode(name):gsub('%-', ' '))
        local best
        for _, s in ipairs(R.servers) do
            if name:find(s.name, 1, true) and (not best or #s.name > #best.name) then best = s end
        end
        if best then return best.number, best.name end
    end
    return nil
end

local function jstr(v) return (type(v) == 'string') and v or '' end

function R.chapterList(data)
    if type(data) ~= 'table' then return nil end
    if type(data.chapters) == 'table' then return data.chapters end
    if data[1] ~= nil then return data end
    return nil
end

function R.chapters(data, si, sec)
    local out = {}
    local list = R.chapterList(data)
    if not list then return out end
    for _, c in ipairs(list) do
        if type(c) == 'table' then
            local ch = { title = jstr(c.title ~= nil and c.title or c.name), items = {} }
            local src = c.items ~= nil and c.items or c.item
            if type(src) == 'table' then
                for _, it in ipairs(src) do
                    if type(it) == 'table' and type(it.text) == 'string' and it.lower ~= true then
                        ch.items[#ch.items + 1] = {
                            text   = it.text,
                            value  = binder.kpkClamp(sec, it.value ~= nil and it.value or (it.lvl ~= nil and it.lvl or it.time)),
                            reason = jstr(it.reason),
                            rp     = jstr(it.rp),
                        }
                    end
                end
            end
            out[#out + 1] = ch
        end
    end
    return out
end

function R.mergeKpk(data, si)
    local sec = kpkSecs[si]
    local rch = R.chapters(data, si, sec)
    if not R.chapterList(data) then return nil end

    for _, c in ipairs(rch) do
        if c.title:find('ЗАПОЛНИТЕ', 1, true) then return nil end
        for _, it in ipairs(c.items) do
            if it.text:find('ЗАПОЛНИТЕ', 1, true) then return nil end
        end
    end
    if R.kpk_mode ~= 'merge' then
        sec.chapters = rch
    else
        for _, rc in ipairs(rch) do
            local lc
            for _, c in ipairs(sec.chapters) do if key(c.title) == key(rc.title) then lc = c; break end end
            if not lc then
                sec.chapters[#sec.chapters + 1] = rc
            else
                for _, ri in ipairs(rc.items) do
                    local li
                    for _, it in ipairs(lc.items) do if key(it.text) == key(ri.text) then li = it; break end end
                    if li then
                        li.value, li.reason = ri.value, ri.reason
                    else
                        lc.items[#lc.items + 1] = ri
                    end
                end
            end
        end
    end
    local chs, its = #sec.chapters, 0
    for _, c in ipairs(sec.chapters) do its = its + #c.items end
    return chs, its
end

function R.updateSections(list)
    local num, sname = R.number()
    if not num then
        say('Сервер не определён. Добавьте его в таблицу {aaaaaa}binder.remote.servers{ffffff}.')
        return
    end
    local m = R.getManifest(true)
    local ok, bad, backed = {}, {}, false
    for _, si in ipairs(list) do
        local rel = 'servers/' .. num .. '/' .. R.secFiles[si] .. '.json'
        local data = R.getJson(rel)
        if data then
            if not backed then
                backed = true
                for _, bsi in ipairs(list) do
                    local p = binder.kpkPath(bsi)
                    local f = io.open(p, 'rb')
                    if f then
                        local d = f:read('*a'); f:close()
                        local b = io.open(p .. '.bak', 'wb')
                        if b then b:write(d); b:close() end
                    end
                end
            end
            local c, i = R.mergeKpk(data, si)
            if c then
                ok[#ok + 1] = string.format('%s - глав %d, пунктов %d', kpkSecs[si].name, c, i)
                if m and m.files[rel] then R.st.files[rel] = tostring(m.files[rel]) end
            else
                bad[#bad + 1] = kpkSecs[si].name
            end
        else
            bad[#bad + 1] = kpkSecs[si].name
        end
    end
    if #ok > 0 then
        binder.saveKpk()
        binder.kpk.bufs = {}
        pcall(SM.px.clearKpkOpen)
        R.saveState()
        say('Сервер {aaaaaa}' .. sname .. '[' .. num .. ']' .. '{ffffff}: загружено. ' .. table.concat(ok, '; ') .. '.')
    end
    if #bad > 0 then
        say('Для сервера ' .. num .. ' нет статей: {aaaaaa}' .. table.concat(bad, ', ') .. '{ffffff} (или нет связи).')
    end
end

function R.syncFonts()
    local m = R.getManifest(true)
    if not m then return end
    local fdir, got = CFG_DIR .. '\\fonts', false
    for rel in pairs(m.files) do
        local name = rel:match('^fonts/([^/]+%.[TtOo][Tt][Ff])$')
        if name then
            local dest = fdir .. '\\' .. name
            if not doesFileExist(dest) then
                if not doesDirectoryExist(fdir) then createDirectory(fdir) end
                if R.download(rel, dest) then got = true end
            end
        end
    end
    if got then
        say('Шрифты загружены, скрипт перезапускается...')
        wait(1500)
        thisScript():reload()
    end
end

function R.notify()
    local num = R.number()
    local m = num and R.getManifest()
    if not m then return end
    local n = 0
    for _, f in ipairs(R.secFiles) do
        local rel = 'servers/' .. num .. '/' .. f .. '.json'
        if m.files[rel] and R.st.files[rel] ~= tostring(m.files[rel]) then n = n + 1 end
    end
    if n > 0 then
        say('Для сервера ' .. num .. ' есть новые статьи (' .. n .. ' из ' .. #R.secFiles .. '). Кнопка загрузки во вкладке КПК или {aaaaaa}/' .. R.cmd .. '{ffffff}.')
    end
end

function R.run(fn, ...)
    if R.busy then return end
    local args = { ... }
    R.busy = true
    lua_thread.create(function()
        local ok, err = pcall(fn, unpack(args))
        R.busy = false
        if not ok then
            print('[RangerHelper] remote: ' .. tostring(err))
            say('Ошибка загрузки, подробности в moonloader.log.')
        end
    end)
end

function R.runSections(list) R.run(R.updateSections, list) end

function R.start()
    R.loadState()
    if not R.auto then return end
    lua_thread.create(function()
        R.busy = true
        pcall(R.syncFonts)
        R.busy = false
        local t0 = os.clock()
        while not binder.pf.srvKey and os.clock() - t0 < 60 do wait(500) end
        wait(3000)
        R.busy = true
        pcall(R.notify)
        R.busy = false
    end)
end

function R.register()
    sampRegisterChatCommand(R.cmd, function()
        R.run(R.updateSections, { 1, 2, 3, 4 })
    end)
end
end)()

;(function()
local R = binder.remote

local UP = {
    url      = R.base .. 'update.json',
    fallback = 'https://raw.githubusercontent.com/aven1xx/ranger-helper/main/Ranger%20Helper.lua',
    cmd      = 'rhcheck',
    auto     = true,
    open     = false,
    curOn    = false,
    busy     = false,
    state    = 'ask',
    version  = '',
    link     = '',
    err      = '',
    info     = {},
    lines    = nil,
    vis      = 0,
}
binder.upd = UP

local TMP = CFG_DIR .. '\\_update.tmp'
local WIN_W = 480
local MAX_ROWS = 8

local function say(m) binder.say(m) end

local function parts(v)
    local t = {}
    for n in tostring(v or ''):gmatch('%d+') do t[#t + 1] = tonumber(n) end
    return t
end

function UP.newer(remote, localv)
    local a, b = parts(remote), parts(localv)
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then return x > y end
    end
    return false
end

function UP.readInfo(raw)
    local out = {}
    local function add(s)
        s = tostring(s):gsub('\r', ''):gsub('^%s*[%-%*\226\128\162]%s*', ''):gsub('^%s+', ''):gsub('%s+$', '')
        if s ~= '' then out[#out + 1] = s end
    end
    if type(raw) == 'table' then
        for _, s in ipairs(raw) do add(s) end
    elseif type(raw) == 'string' then
        for s in raw:gmatch('[^\n]+') do add(s) end
    end
    if #out == 0 then out[1] = 'Исправления и улучшения' end
    return out
end

function UP.wrap(width)
    local out = {}
    for _, entry in ipairs(UP.info) do
        local line, first = '', true
        for word in entry:gmatch('%S+') do
            local try = (line == '') and word or (line .. ' ' .. word)
            if line ~= '' and SM.tw(try) > width then
                out[#out + 1] = { text = line, bullet = first }
                first, line = false, word
            else
                line = try
            end
        end
        if line ~= '' then out[#out + 1] = { text = line, bullet = first } end
    end
    return out
end

function UP.cursor(on)
    if on == UP.curOn then return end
    UP.curOn = on
    pcall(sampToggleCursor, on)
end

function UP.getJson()
    if not R.fetch(UP.url .. '?t=' .. os.time(), TMP, 15) then return nil end
    local f = io.open(TMP, 'rb')
    if not f then return nil end
    local data = f:read('*a')
    f:close()
    os.remove(TMP)
    data = data:gsub('^\239\187\191', '')
    local ok, t = pcall(decodeJson, data)
    if ok and type(t) == 'table' then return t end
    return nil
end

function UP.checkRun(manual)
    local j = UP.getJson()
    if not j then
        if manual then say('Не удалось проверить обновления, попробуйте позже.') end
        return
    end
    local ver = tostring(j.version or j.current_version or '')
    local cur = thisScript().version
    if ver == '' or not UP.newer(ver, cur) then
        if manual then say('Установлена последняя версия: {aaaaaa}' .. cur .. '{ffffff}.') end
        return
    end
    if UP.open then return end
    UP.version = ver
    UP.info = UP.readInfo(j.info ~= nil and j.info or j.update_info)
    local link = tostring(j.url or j.update_url or '')
    UP.link = link:find('^https://') and link or UP.fallback
    if not manual then
        while not binder.ready or not select(2, pcall(sampIsLocalPlayerSpawned)) do wait(500) end
        wait(2000)
    end
    UP.state, UP.err, UP.lines, UP.vis = 'ask', '', nil, 0
    UP.open = true
    say('Доступна новая версия: {aaaaaa}' .. ver .. '{ffffff} (установлена ' .. cur .. ').')
end

function UP.check(manual)
    if UP.busy then return end
    UP.busy = true
    lua_thread.create(function()
        local ok, err = pcall(UP.checkRun, manual)
        UP.busy = false
        if not ok then print('[RangerHelper] update: ' .. tostring(err)) end
    end)
end

local function fail(msg)
    UP.state, UP.err = 'fail', msg
end

function UP.installRun()
    local path = thisScript().path
    local new = path .. '.new'
    local url = UP.link .. (UP.link:find('?', 1, true) and '&' or '?') .. 't=' .. os.time()
    if not R.fetch(url, new, 90) then
        os.remove(new)
        return fail('Не удалось скачать файл. Проверьте соединение.')
    end
    local f = io.open(new, 'rb')
    local data = f and f:read('*a')
    if f then f:close() end
    local body = data and data:gsub('^\239\187\191', '')
    if not body or #body < 100000 or not body:find("script_name('Ranger Helper')", 1, true) or not loadstring(body) then
        os.remove(new)
        return fail('Скачанный файл повреждён, обновление отменено.')
    end
    local old = io.open(path, 'rb')
    local odata = old and old:read('*a')
    if old then old:close() end
    if odata then
        local b = io.open(CFG_DIR .. '\\Ranger_Helper.backup', 'wb')
        if b then b:write(odata); b:close() end
    end
    os.remove(path)
    if not os.rename(new, path) then
        if odata then
            local r = io.open(path, 'wb')
            if r then r:write(odata); r:close() end
        end
        os.remove(new)
        return fail('Не удалось заменить файл скрипта.')
    end
    UP.state = 'done'
    say('Обновлено до версии {aaaaaa}' .. UP.version .. '{ffffff}, скрипт перезапускается.')
    wait(1500)
    UP.open = false
    thisScript():reload()
end

function UP.install()
    if UP.busy or UP.state == 'busy' then return end
    UP.state, UP.busy = 'busy', true
    lua_thread.create(function()
        local ok, err = pcall(UP.installRun)
        UP.busy = false
        if not ok then
            print('[RangerHelper] update: ' .. tostring(err))
            fail('Ошибка обновления, подробности в moonloader.log.')
        end
    end)
end

function UP.start()
    if UP.auto then UP.check(false) end
end

function UP.register()
    sampRegisterChatCommand(UP.cmd, function() UP.check(true) end)
end

local function withIcon(name, text)
    local i = ico(name)
    return (i ~= '') and (i .. ' ' .. text) or text
end

imgui.OnFrame(function() return binder.ready and (UP.open or UP.curOn) end, function(player)
    if not UP.open then
        UP.cursor(false)
        player.HideCursor, player.LockPlayer = true, false
        UP.vis = 0
        return
    end
    local okP, paused = pcall(isPauseMenuActive)
    if okP and paused then return end
    DT = clamp(imgui.GetIO().DeltaTime, 0.001, 0.1)
    UP.vis = UP.vis + (1 - UP.vis) * (1 - math.exp(-DT * 12))
    UI_ALPHA, GA = UP.vis, 1
    UP.cursor(true)
    player.HideCursor = false

    local pad, inner = 22, WIN_W - 44
    if not UP.lines then UP.lines = UP.wrap(inner - 18) end
    local rows = math.min(#UP.lines, MAX_ROWS)
    local extra = #UP.lines > rows
    local listEnd = 116 + rows * 20 + (extra and 20 or 0)
    local H = listEnd + 14 + 34 + 22

    local sw, sh = getScreenResolution()
    imgui.SetNextWindowSize(V(WIN_W, H), imgui.Cond.Always)
    imgui.SetNextWindowPos(V(sw / 2, sh / 2), imgui.Cond.FirstUseEver, V(0.5, 0.5))
    local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoSavedSettings + imgui.WindowFlags.NoBackground +
        imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse +
        imgui.WindowFlags.NoResize
    imgui.Begin('RangerHelper Update', nil, flags)

    local dl = imgui.GetWindowDrawList()
    local pos = imgui.GetWindowPos()
    local p2 = V(pos.x + WIN_W, pos.y + H)
    local _fc = SM.clipOff(dl)
    rrf(dl, pos, p2, U(imgui.ImVec4(P.bg.x, P.bg.y, P.bg.z, 0.98)), 14)
    rr(dl, V(pos.x + 0.5, pos.y + 0.5), V(p2.x - 0.5, p2.y - 0.5), U(P.outline, 0.8), 14, 15, 1.2)
    SM.clipOn(dl, _fc)
    hairline(dl, pos.x + 18, p2.x - 18, pos.y + 1, P.accentSoft, 0.5)

    iconBadge(dl, pos.x + pad, pos.y + 20, 40, 'DOWNLOAD', P.active, 0.6)
    dl:AddTextFontPtr(imgui.GetFont(), 18, V(pos.x + pad + 54, pos.y + 18), U(P.text), 'Доступно обновление')
    local cx = chipL(dl, pos.x + pad + 54, pos.y + 46, 'Сейчас ' .. thisScript().version, P.chip, P.muted)
    chipL(dl, cx, pos.y + 46, 'Новая ' .. UP.version, P.active, P.accentSoft)
    hairline(dl, pos.x + pad, p2.x - pad, pos.y + 82, P.line, 0.9)

    dl:AddText(V(pos.x + pad, pos.y + 92), U(P.muted), 'Список изменений')
    for i = 1, rows do
        local ln = UP.lines[i]
        local y = pos.y + 116 + (i - 1) * 20
        if ln.bullet then dl:AddCircleFilled(V(pos.x + pad + 4, y + 8), 2.5, U(P.accent), 12) end
        dl:AddText(V(pos.x + pad + 18, y), U(P.text), ln.text)
    end
    if extra then
        dl:AddText(V(pos.x + pad + 18, pos.y + 116 + rows * 20), U(P.muted), '...')
    end

    local by = pos.y + listEnd + 14
    local bx = pos.x + pad
    if UP.state == 'ask' then
        local bw = (inner - 10) / 2
        if button(dl, '##upd_later', bx, by, bw, 34, withIcon('CLOCK', 'Напомнить позже'), false) then
            UP.open = false
        end
        if button(dl, '##upd_go', bx + bw + 10, by, bw, 34, withIcon('DOWNLOAD', 'Обновить'), true) then
            UP.install()
        end
    elseif UP.state == 'busy' or UP.state == 'done' then
        local t = (UP.state == 'done') and 'Готово, перезапуск...' or ('Загрузка обновления' .. string.rep('.', math.floor(os.clock() * 2) % 4))
        centerText(dl, bx, by, inner, 34, t, U(P.accentSoft))
    else
        dl:AddText(V(bx, by - 18), U(P.danger), UP.err)
        if button(dl, '##upd_close', bx, by, inner, 34, 'Закрыть', false) then
            UP.open = false
        end
    end

    imgui.End()
    UI_ALPHA = 1
end)
end)()

function onScriptTerminate(s, quit)
    if s == thisScript() then
        pcall(binder.pieCursor, false)
        pcall(binder.kpkCursor, false)
        pcall(binder.noteCursor, false)
        pcall(binder.depCursor, false)
        pcall(binder.depChatCursor, false)
        if binder.note.dirty then pcall(binder.noteSave) end
        if cfgDirty then saveConfig() end
        for name in pairs(binder.cmds) do pcall(sampUnregisterChatCommand, name) end
        pcall(binder.markBlipRemove)
        pcall(sampUnregisterChatCommand, binder.mark.cmd)
        pcall(sampUnregisterChatCommand, binder.dep.cmd)
        pcall(sampUnregisterChatCommand, binder.afind.cmd)
        pcall(sampUnregisterChatCommand, 'wanteds')
        pcall(sampUnregisterChatCommand, binder.remote.cmd)
        pcall(sampUnregisterChatCommand, binder.upd.cmd)
        pcall(binder.upd.cursor, false)
        pcall(binder.wantedCursor, false)
        binder.afind.active = false
        pcall(sampUnregisterChatCommand, SM.cmd)
        pcall(sampUnregisterChatCommand, 'ph')
    end
end

function main()
    binder.pf.init()
    loadConfig()
    if not binder.pf.loadChar() then binder.pf.saveChar() end
    if not loadWeapons() then saveWeapons() end
    if not binder.pieLoad() then binder.pieSave() end
    if binder.load() == 'missing' then binder.save() end
    if binder.loadDialogs() == 'missing' then binder.saveDialogs() end
    if binder.loadKpk() == 'missing' then binder.saveKpk() end
    if not binder.noteLoad() then binder.noteSave() end
    if not binder.depLoad() then binder.depSave() end
    if not binder.chatLoad() then binder.chatSave() end
    if not binder.tabLoad() then binder.tabSave() end
    binder.sync()
    while not isSampAvailable() do wait(100) end
    binder.ready = true
    binder.sync()
    pcall(binder.remote.register)
    pcall(binder.remote.start)
    pcall(binder.upd.register)
    pcall(binder.upd.start)
    pcall(binder.pf.serverTick)
    lua_thread.create(function()
        while true do wait(1000); pcall(binder.pf.serverTick) end
    end)
    lua_thread.create(function() wait(1500); binder.tabCleanup(); binder.tabApply() end)
    lua_thread.create(function()
        while true do wait(0); pcall(binder.tabGuard) end
    end)
    SM.cmdFn = function() setOpen(not window[0]) end
    sampRegisterChatCommand(SM.cmd, SM.cmdFn)
    if SM.cmd ~= 'ph' then sampRegisterChatCommand('ph', SM.cmdFn) end
    if SM.greet then
        local k = hotkeys[1][2]
        binder.say('Скрипт загружен. Меню: {aaaaaa}/' .. SM.cmd .. '{ffffff}'
            .. ((k and k ~= 'Не задана') and (' или клавиша {aaaaaa}' .. k .. '{ffffff}') or '') .. '.')
    end
    sampRegisterChatCommand(binder.mark.cmd, function(arg) binder.targetCmd(arg) end)
    sampRegisterChatCommand(binder.dep.cmd, function() binder.depToggle() end)
    sampRegisterChatCommand(binder.afind.cmd, function(arg) binder.afindCmd(arg) end)
    sampRegisterChatCommand('wanteds', function() binder.wantedToggle() end)
    lua_thread.create(function()
        while true do wait(250); pcall(binder.wantedTick) end
    end)
    lua_thread.create(function()
        while true do wait(100); pcall(binder.markTick) end
    end)
    binder.weaponLoop()
end