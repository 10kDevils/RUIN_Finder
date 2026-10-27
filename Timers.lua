-- RUIN Finder: world boss and world buff timers (moved here from RUIN Muster)
-- Press Now when a boss dies or a buff drops, or announce a buff drop ahead
-- of time; every RUIN member's Timers tab shows it and buff drops get a
-- warning a minute before. Timers travel as "Muster:TIMER", the kind Muster
-- used, so members on older Muster versions still send and get them.
local ADDON, ns = ...
local R = RUIN_API
if not R or (R.apiLevel or 1) < 6 then return end
local W = R.Widgets
local C = W.COLORS

local Timers = {}
ns.Timers = Timers

-- Respawn windows are WoW Classic's; Forever may differ, so they are a guide only.
local TIMERS = {
    { key = "azuregos",     label = "Azuregos",             kind = "boss", where = "Azshara",       window = { 3 * 86400, 7 * 86400 },
      icon = "Interface\\Icons\\INV_Misc_Head_Dragon_Blue" },
    { key = "kazzak",       label = "Lord Kazzak",          kind = "boss", where = "Blasted Lands", window = { 3 * 86400, 7 * 86400 },
      icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01" },
    { key = "nightmare",    label = "Dragons of Nightmare", kind = "boss", where = "Duskwood, Ashenvale, Feralas, Hinterlands",
      window = { 3 * 86400, 7 * 86400 }, icon = "Interface\\Icons\\INV_Misc_Head_Dragon_Green" },
    { key = "dragonslayer", label = "Rallying Cry (Onyxia / Nefarian head)", kind = "buff", where = "Stormwind",
      icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01" },
    { key = "zg",           label = "Spirit of Zandalar (Hakkar's heart)",   kind = "buff", where = "Yojamba Isle, Stranglethorn",
      icon = "Interface\\Icons\\Ability_Creature_Poison_05" },
    { key = "songflower",   label = "Songflower Serenade",  kind = "buff", where = "Felwood",       window = { 25 * 60, 25 * 60 },
      icon = "Interface\\Icons\\Spell_Holy_MindVision" },
}
local TIMER = {}
for _, t in ipairs(TIMERS) do TIMER[t.key] = t end
Timers.LIST, Timers.BY = TIMERS, TIMER

local BOSS, BUFF = "|cffff8000", "|cff40c0ff"
local M, db
local ui = {}

local function now() return GetServerTime() end
local function short(n) return R.Util.ShortName(n or "?") end

local function send(rec, key, prio)
    if not M.SendRaw then return end            -- RUIN Core before 0.4.3
    M:SendRaw("Muster:TIMER", { k = key, l = rec.last, p = rec.plan, t = rec.t }, "ORG", nil, prio or R.PRIORITY.ALERT)
end

function Timers.Set(key, minutesFromNow)
    local t = TIMER[key]
    if not t then return false end
    local rec = db.timers[key] or {}
    if minutesFromNow and minutesFromNow > 0 then
        rec.plan = now() + math.floor(minutesFromNow * 60)
    else
        rec.last, rec.plan = now(), nil
    end
    rec.by, rec.t, rec.warned = UnitName("player"), now(), nil
    db.timers[key] = rec
    send(rec, key)
    M:Print(rec.plan and ("%s dropping in %d min, RUIN told."):format(t.label, minutesFromNow)
        or ("%s marked %s now."):format(t.label, t.kind == "boss" and "killed" or "dropped"))
    Timers.Refresh()
    return true
end

function Timers.OnTimer(d, sender)
    if type(d) ~= "table" or type(d.k) ~= "string" then return end
    lastHeard = GetTime()
    local t = TIMER[d.k]
    if not t or not tonumber(d.t) then return end
    local rec = db.timers[d.k] or {}
    if (rec.t or 0) >= tonumber(d.t) then return end
    local newPlan, wasPlan = tonumber(d.p), rec.plan
    rec.last, rec.plan, rec.by, rec.t, rec.warned = tonumber(d.l) or rec.last, newPlan, sender, tonumber(d.t), nil
    db.timers[d.k] = rec
    if db.timerAlerts then
        if newPlan and newPlan ~= wasPlan then
            M:Toast(("%s%s|r drops in %s (%s)"):format(BUFF, t.label, W.Duration(math.max(0, newPlan - now())), W.ClassName(sender)), { sound = true })
        elseif not newPlan then
            M:Toast(("%s%s|r %s (%s)"):format(t.kind == "boss" and BOSS or BUFF, t.label, t.kind == "boss" and "killed" or "dropped", W.ClassName(sender)))
        end
    end
    Timers.Refresh()
end

-- Someone just connected (Finder's ASK): one member shares what they know.
-- Each waits a random moment and stays quiet if another already answered.
local lastHeard, sharePending = -999, false
function Timers.Share()
    if sharePending then return end
    sharePending = true
    local asked = GetTime()
    C_Timer.After(2 + math.random() * 8, function()
        sharePending = false
        if lastHeard >= asked then return end
        for key, rec in pairs(db.timers) do
            if rec.t and now() - rec.t < 8 * 86400 then send(rec, key, R.PRIORITY.BULK) end
        end
    end)
end

function Timers.Status(t, rec)
    local n = now()
    if rec and rec.plan and rec.plan > n then return C.good .. "drops in " .. W.Duration(rec.plan - n) .. "|r" end
    if not rec or not rec.last then return C.dim .. "no report yet|r" end
    local ago = n - rec.last
    local s = C.white .. (t.kind == "boss" and "killed " or "dropped ") .. W.Ago(ago) .. "|r"
    if t.window then
        local lo, hi = t.window[1], t.window[2]
        if ago < lo then s = s .. C.dim .. "  ·  back in " .. W.Duration(lo - ago) .. (hi > lo and "+" or "") .. "|r"
        elseif ago < hi then s = s .. C.gold .. "  ·  may be up now|r"
        else s = s .. C.good .. "  ·  should be up|r" end
    end
    return s
end

local function tick()
    local n = now()
    for key, rec in pairs(db.timers) do
        local t = TIMER[key]
        if t and rec.plan and not rec.warned and rec.plan - n <= 60 and rec.plan > n then
            rec.warned = true
            if db.timerAlerts then M:Toast(("%s%s|r drops in under a minute!"):format(BUFF, t.label), { sound = true }) end
        end
        if rec.plan and rec.plan <= n then rec.last, rec.plan = rec.plan, nil end
    end
end

---------------------------------------------------------------------------
-- The Timers tab
---------------------------------------------------------------------------
function Timers.Build(page)
    ui.page = page
    local h = W.Header(page, "World bosses and world buffs")
    h:SetPoint("TOPLEFT", 0, -2)
    local alerts = W.Check(page, "Alerts", function() return db.timerAlerts end, function(v) db.timerAlerts = v end)
    alerts:SetPoint("TOPRIGHT", page, "TOPRIGHT", -60, 0)
    alerts.tip = "Pop up an alert when a timer is reported, and a minute before an announced buff drops."
    local sub = W.Label(page, C.dim .. "Press Now when a boss dies or a buff drops, or announce a buff drop ahead of time. Respawn windows are WoW Classic's, as a guide.|r", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", 0, -26)
    sub:SetPoint("RIGHT", page, "RIGHT", -6, 0)
    ui.list = W.List(page, 40, function(row)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(28, 28)
        row.icon:SetPoint("LEFT", 6, 0)
        row.name = W.Label(row, "", "GameFontNormal")
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 2)
        row.name:SetPoint("RIGHT", row, "RIGHT", -260, 0)
        row.name:SetWordWrap(false)
        row.status = W.Label(row, "", "GameFontHighlightSmall")
        row.status:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
        row.status:SetPoint("RIGHT", row, "RIGHT", -260, 0)
        row.status:SetWordWrap(false)
        row.now = W.Button(row, "Now", 50)
        row.now:SetPoint("RIGHT", -4, 0)
        row.go = W.Button(row, "Announce", 78)
        row.go:SetPoint("RIGHT", row.now, "LEFT", -10, 0)
        row.minsLabel = W.Label(row, C.dim .. "min|r", "GameFontHighlightSmall")
        row.minsLabel:SetPoint("RIGHT", row.go, "LEFT", -6, 0)
        row.mins = W.EditBox(row, 34)
        row.mins:SetPoint("RIGHT", row.minsLabel, "LEFT", -4, 0)
        if row.mins.SetNumeric then row.mins:SetNumeric(true) end
        row.inLabel = W.Label(row, C.dim .. "Drops in|r", "GameFontHighlightSmall")
        row.inLabel:SetPoint("RIGHT", row.mins, "LEFT", -5, 0)
    end, function(row, t)
        row.icon:SetTexture(t.icon)
        row.name:SetText(t.label .. "  " .. C.dim .. t.where .. "|r")
        row.status:SetText(Timers.Status(t, db.timers[t.key]))
        local buff = t.kind == "buff"
        row.go:SetShown(buff); row.mins:SetShown(buff); row.minsLabel:SetShown(buff); row.inLabel:SetShown(buff)
        row.now:SetScript("OnClick", function() Timers.Set(t.key) end)
        row.go:SetScript("OnClick", function()
            local m = tonumber(row.mins:GetText())
            if m and m > 0 then Timers.Set(t.key, m); row.mins:SetText("") end
        end)
        local rec = db.timers[t.key]
        row.tip = function(tip)
            tip:AddLine(t.label, 1, 0.82, 0)
            tip:AddLine(t.where, 1, 1, 1)
            tip:AddLine(t.kind == "boss" and "Now: it was killed just now." or
                "Now: it dropped just now.  Announce: it drops in the minutes you type.", 0.7, 0.75, 0.8, true)
            if rec and rec.by then tip:AddLine("Last report by " .. short(rec.by), 0.7, 0.7, 0.7) end
        end
    end)
    ui.list.frame:SetPoint("TOPLEFT", 0, -52)
    ui.list.frame:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -24, 0)
    page:SetScript("OnShow", Timers.Refresh)
end

function Timers.Refresh()
    if ui.list and ui.page:IsVisible() then ui.list:SetItems(TIMERS) end
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------
function Timers.Init(module, fdb)
    M, db = module, fdb
    db.timers = type(db.timers) == "table" and db.timers or {}
    if db.timerAlerts == nil then db.timerAlerts = true end
    -- Muster kept them before Finder 0.4.1: take them over once
    if not db.timersMoved then
        db.timersMoved = true
        local old = type(RUIN_MusterDB) == "table" and type(RUIN_MusterDB.world) == "table" and RUIN_MusterDB.world.timers
        if type(old) == "table" then
            for k, rec in pairs(old) do
                if TIMER[k] and type(rec) == "table" and (not db.timers[k] or (db.timers[k].t or 0) < (rec.t or 0)) then db.timers[k] = rec end
            end
        end
    end
    -- Old Muster (and older Intel) clients send these kinds
    M:ListenRaw("Muster:TIMER", function(_, d, sender) Timers.OnTimer(d, sender) end)
    M:ListenRaw("Intel:TIMER", function(_, d, sender) Timers.OnTimer(d, sender) end)
    C_Timer.NewTicker(5, tick)
    C_Timer.NewTicker(30, Timers.Refresh)
end
