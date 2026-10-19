-- RUIN Finder
-- Flag yourself as looking, or list your group with the roles it still
-- needs; see everyone in the org who is looking and whisper or invite them
-- in one click. Players and groups that fit each other are matched and
-- alerted automatically. A small on-screen badge shows that you're listed.
-- With RUIN Muster installed, events that still need players appear on the board.
local ADDON, ns = ...
local R = RUIN_API
if not R or (R.apiLevel or 1) < 3 then
    print("|cff54b7d9[RUIN]|r Finder needs a newer RUIN Core (0.3.0 or later).")
    return
end
local W = R.Widgets
local C = W.COLORS

local M = R:RegisterModule("Finder", { version = "0.3.2" })

local ACTIVITIES = { "Dungeon", "Raid", "PvP", "Questing", "Professions", "Social" }
local FILTERS = { "All", "Dungeon", "Raid", "PvP", "Questing", "Professions", "Social" }
local LEVELS = { "All levels", "Within 3", "Within 5", "Within 10" }
local LEVEL_RANGE = { ["Within 3"] = 3, ["Within 5"] = 5, ["Within 10"] = 10 }
local LISTING = { "Player", "Group" }
local BEACON_EVERY, EXPIRE = 120, 300
local MATCH_REPEAT = 600              -- don't alert the same match again for 10 minutes

local DEFAULTS = { looking = false, tank = false, healer = false, dps = true,
                   activity = "Dungeon", detail = "", note = "", spec = "", toasts = true,
                   listing = "Player", needT = 0, needH = 1, needD = 0, badge = true, badgePos = nil,
                   levels = "All levels" }

local db
local board = {}          -- GUID -> entry
local lastSent = -999
local sendPending = false
local filter = "All"
local alerted = {}        -- GUID -> time of the last match alert
local ui = {}
local badge

---------------------------------------------------------------------------
-- Spec guess from talent points (falls back to the manual Spec field)
---------------------------------------------------------------------------
local function guessSpec()
    if not GetTalentTabInfo then return nil end
    local bestName, bestPoints = nil, 0
    for tab = 1, 3 do
        local res = { pcall(GetTalentTabInfo, tab) }
        if res[1] then
            local name, points
            for i = 2, #res do
                local v = res[i]
                if not name and type(v) == "string" and v ~= "" then
                    name = v
                elseif name and points == nil and type(v) == "number" and v >= 0 and v <= 61 and v == math.floor(v) then
                    points = v
                end
            end
            if name and points and points > bestPoints then bestName, bestPoints = name, points end
        end
    end
    return bestName
end

local function mySpec()
    if db.spec ~= "" then return db.spec end
    return guessSpec()
end

local function roleText(e)
    local t = {}
    if e.rt == 1 then t[#t + 1] = W.RoleIcon("T") end
    if e.rh == 1 then t[#t + 1] = W.RoleIcon("H") end
    if e.rd == 1 then t[#t + 1] = W.RoleIcon("D") end
    return #t > 0 and table.concat(t, "") or (C.dim .. "any|r")
end

local function needText(e)
    local t = {}
    if (e.qt or 0) > 0 then t[#t + 1] = e.qt .. W.RoleIcon("T") end
    if (e.qh or 0) > 0 then t[#t + 1] = e.qh .. W.RoleIcon("H") end
    if (e.qd or 0) > 0 then t[#t + 1] = e.qd .. W.RoleIcon("D") end
    return #t > 0 and ("needs " .. table.concat(t, " ")) or "full"
end

---------------------------------------------------------------------------
-- Beacons
---------------------------------------------------------------------------
local function isGroup() return db.listing == "Group" end

local function buildBeacon()
    local p = R:GetPlayer()
    local b = {
        g = p.guid, gu = p.guild, c = p.class, l = p.level, sp = mySpec(),
        rt = db.tank and 1 or 0, rh = db.healer and 1 or 0, rd = db.dps and 1 or 0,
        a = db.activity, d = db.detail, nt = db.note,
        z = GetZoneText and GetZoneText() or nil,
        gs = GetNumGroupMembers and GetNumGroupMembers() or 0,
        on = db.looking and 1 or 0,
    }
    if isGroup() then
        b.lt = "G"
        b.qt, b.qh, b.qd = db.needT or 0, db.needH or 0, db.needD or 0
        b.gs = math.max(1, b.gs)
    end
    return b
end

local function sendBeacon()
    if not R:IsConnected() then return end
    lastSent = GetTime()
    M:Send("BEACON", buildBeacon(), "ORG")
end

local function scheduleSend()
    if sendPending then return end
    sendPending = true
    C_Timer.After(2, function()
        sendPending = false
        sendBeacon()
    end)
end

---------------------------------------------------------------------------
-- Matching: a player who can fill a role a group of the same activity needs
---------------------------------------------------------------------------
local function fills(player, group)
    return (player.rt == 1 and (group.qt or 0) > 0) or (player.rh == 1 and (group.qh or 0) > 0)
        or (player.rd == 1 and (group.qd or 0) > 0)
end

local function filledRole(player, group)
    if player.rt == 1 and (group.qt or 0) > 0 then return "Tank" end
    if player.rh == 1 and (group.qh or 0) > 0 then return "Healer" end
    if player.rd == 1 and (group.qd or 0) > 0 then return "DPS" end
end

-- Does this board entry fit you (or your group)?
local function isMatch(e)
    if not db.looking or e.a ~= db.activity then return false end
    local me = buildBeacon()
    if isGroup() and e.lt ~= "G" then return fills(e, me) end
    if not isGroup() and e.lt == "G" then return fills(me, e) end
    return false
end

local function levelOk(e)
    local range = LEVEL_RANGE[db.levels]
    if not range then return true end
    local mine = UnitLevel and UnitLevel("player") or 0
    return math.abs((tonumber(e.l) or mine) - mine) <= range
end

local function maybeAlertMatch(e)
    if not db.toasts or not isMatch(e) then return end
    local now = GetTime()
    if alerted[e.g] and now - alerted[e.g] < MATCH_REPEAT then return end
    alerted[e.g] = now
    local where = e.d ~= "" and (": " .. e.d) or ""
    if e.lt == "G" then
        M:Toast(("Match: %s's group for %s%s needs a %s. Whisper them from the Finder page."):format(
            W.ClassName(e.name, e.c), e.a, where, filledRole(buildBeacon(), e) or "player"), { sound = true })
    else
        M:Toast(("Match: %s (%s) is looking for %s%s."):format(W.ClassName(e.name, e.c),
            filledRole(e, buildBeacon()) or "player", e.a, where), { sound = true })
    end
end

---------------------------------------------------------------------------
-- Board
---------------------------------------------------------------------------
local updateBadge = function() end

local function updateStatusLine()
    if not ui.status then return end
    if not db.looking then
        ui.status:SetText(C.dim .. "You are not listed. Tick \"I'm looking\" to post your listing.|r")
    elseif not R:IsConnected() then
        ui.status:SetText(C.bad .. "Not connected to the RUIN org channel, so nobody else can see your listing yet. Set up or import the org key on the Org page.|r")
    else
        ui.status:SetText(C.good .. (isGroup() and "Your group's listing is live across RUIN." or "Your listing is live across RUIN.") .. "|r")
    end
end

-- Muster events that still need players, as board rows.
local function musterRows()
    local mu = R:GetModule("Muster")
    if not mu or not mu.GetOpenSlots then return {} end
    local ok, slots = pcall(mu.GetOpenSlots, mu)
    if not ok or type(slots) ~= "table" then return {} end
    local rows = {}
    for _, s in ipairs(slots) do
        local kind = s.kind == "Raid" and "Raid" or (s.kind == "Dungeon" and "Dungeon" or (s.kind == "PvP" and "PvP" or "Social"))
        if filter == "All" or filter == kind then
            rows[#rows + 1] = { muster = s, a = kind, name = s.by or "?", t = GetTime() }
        end
    end
    return rows
end

local function boardItems()
    local items, now = {}, GetTime()
    for _, e in pairs(board) do
        if now - e.t <= EXPIRE and (filter == "All" or e.a == filter) and levelOk(e) then
            e.match = isMatch(e)
            items[#items + 1] = e
        end
    end
    table.sort(items, function(a, b)
        if a.match ~= b.match then return a.match end
        if a.a ~= b.a then return a.a < b.a end
        return tostring(a.name) < tostring(b.name)
    end)
    return items
end

local function matchCount()
    local n, now = 0, GetTime()
    for _, e in pairs(board) do
        if now - e.t <= EXPIRE and isMatch(e) then n = n + 1 end
    end
    return n
end

local function refresh()
    updateBadge()
    if not ui.list or not ui.panel:IsVisible() then return end
    updateStatusLine()
    local items = boardItems()
    local others = #items
    -- Muster events come after your listing, before everyone else.
    local events = musterRows()
    for i = #events, 1, -1 do table.insert(items, 1, events[i]) end
    -- Your own listing goes first, so you can see exactly what others see.
    if db.looking then
        local me = buildBeacon()
        me.name, me.t, me.self = UnitName("player"), GetTime(), true
        table.insert(items, 1, me)
    end
    ui.list:SetItems(items)
    local matches = matchCount()
    ui.count:SetText(("%d other%s looking%s"):format(others, others == 1 and "" or "s",
        matches > 0 and ("  ·  " .. C.good .. matches .. " match" .. (matches == 1 and "" or "es") .. "|r") or ""))
    if ui.needRow then ui.needRow:SetShown(isGroup()) end
end

function M:OnBeacon(d, sender)
    if type(d.g) ~= "string" or d.g == R:GetPlayerGUID() then return end
    if d.on ~= 1 then
        if board[d.g] then board[d.g] = nil; refresh() end
        return
    end
    local isNew = board[d.g] == nil
    d.name, d.t = sender, GetTime()
    d.a = type(d.a) == "string" and d.a or "Social"
    d.d = type(d.d) == "string" and d.d or ""
    d.nt = type(d.nt) == "string" and d.nt or ""
    if d.lt ~= "G" then d.lt = nil end
    d.qt, d.qh, d.qd = tonumber(d.qt) or 0, tonumber(d.qh) or 0, tonumber(d.qd) or 0
    board[d.g] = d
    if isMatch(d) then
        maybeAlertMatch(d)
    elseif isNew and db.looking and db.toasts and d.a == db.activity then
        M:Toast(("%s is also looking for %s%s"):format(W.ClassName(sender, d.c), d.a,
            d.d ~= "" and (": " .. d.d) or ""))
    end
    refresh()
end

-- Someone just came online and wants the current board.
function M:OnAsk()
    if not db.looking then return end
    C_Timer.After(1 + math.random() * 5, sendBeacon)
end

local function setLooking(on)
    db.looking = on
    if ui.lookingCheck then ui.lookingCheck:Refresh() end
    if on and not R:IsConnected() then
        M:Print("You are looking for " .. db.activity .. ", but you're not connected to the RUIN org channel yet, so only you can see it.")
    else
        M:Print(on and ("You are now looking for " .. db.activity .. ".") or "You are no longer looking.")
    end
    alerted = {}
    sendBeacon()
    refresh()
    -- Matches already on the board are announced right away.
    if on then for _, e in pairs(board) do maybeAlertMatch(e) end end
end

-- A status field changed: send soon, and redraw your own row now.
local function changed()
    scheduleSend()
    refresh()
end

-- Start a group listing in one call, for other RUIN modules (Muster's "Find
-- group" on a boss, rare or enemy sighting). activity is one of ACTIVITIES.
function M:QuickList(activity, detail, needT, needH, needD)
    local ok = false
    for _, a in ipairs(ACTIVITIES) do if a == activity then ok = true end end
    db.activity = ok and activity or "Questing"
    db.detail = tostring(detail or ""):sub(1, 30)
    db.listing = "Group"
    db.needT, db.needH, db.needD = needT or 0, needH or 0, needD or 0
    if ui.activity then ui.activity:Refresh() end
    if ui.listing and ui.listing.Refresh then ui.listing:Refresh() end
    if ui.detail then ui.detail:SetText(db.detail) end
    for key, box in pairs(ui.need or {}) do box:SetText(tostring(db[key] or 0)) end
    setLooking(true)
    changed()
    return true
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
local function whisper(name)
    local send = ChatFrame_SendTell or (ChatFrameUtil and ChatFrameUtil.SendTell)
    if send then send(name) end
end

local function invite(name)
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(name)
    elseif InviteUnit then
        InviteUnit(name)
    end
end

-- Sign up for a Muster event in the first role you're flagged for that is open.
local function joinEvent(s)
    local mu = R:GetModule("Muster")
    if not mu then return end
    local role
    if db.tank and (s.open.T or 0) > 0 then role = "T"
    elseif db.healer and (s.open.H or 0) > 0 then role = "H"
    elseif db.dps and (s.open.D or 0) > 0 then role = "D" end
    if not role then
        M:Print("None of your roles (Tank / Healer / DPS boxes) is open for " .. s.title .. ". Opening Muster.")
        mu:OpenTab()
        return
    end
    mu:SignUp(s.id, role)
    M:Print(("Signed up for %s as %s."):format(s.title, role == "T" and "Tank" or (role == "H" and "Healer" or "DPS")))
end

---------------------------------------------------------------------------
-- On-screen badge: shows you're listed and how many matches there are.
-- Left-click opens Finder; right-click stops looking.
---------------------------------------------------------------------------
updateBadge = function()
    if not db then return end
    if not db.looking or not db.badge then
        if badge then badge:Hide() end
        return
    end
    if not badge then
        badge = W.HudFrame("RUIN_FinderBadge", "Finder", db, "badgePos", { "TOP", UIParent, "TOP", 220, -24 })
        badge:SetSize(230, 34)
        badge.icon = badge:CreateTexture(nil, "ARTWORK")
        badge.icon:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")
        badge.icon:SetSize(22, 22)
        badge.icon:SetPoint("LEFT", 7, -1)
        pcall(badge.icon.SetMask, badge.icon, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
        badge.text = W.Label(badge, "", "GameFontNormalSmall")
        badge.text:SetPoint("LEFT", badge.icon, "RIGHT", 6, 0)
        badge.text:SetPoint("RIGHT", badge, "RIGHT", -8, 0)
        badge.text:SetWordWrap(false)
        badge:SetScript("OnMouseUp", function(_, mouse)
            if mouse == "RightButton" then setLooking(false) else M:OpenTab() end
        end)
        badge:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine("RUIN Finder", 0.82, 0.31, 0.54)
            GameTooltip:AddLine("Left-click: open Finder.  Right-click: stop looking.  Drag to move.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        badge:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    local m = matchCount()
    local what = db.activity .. (db.detail ~= "" and (": " .. db.detail) or "")
    badge.text:SetText((isGroup() and "Group LFM · " or "Looking · ") .. C.white .. what .. "|r"
        .. (m > 0 and ("  " .. C.good .. m .. " match" .. (m == 1 and "" or "es") .. "|r") or ""))
    badge:Show()
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
local function buildPage(panel)
    ui.panel = panel
    local card = W.Card(panel)
    card:SetPoint("TOPLEFT", 0, 0)
    card:SetPoint("RIGHT", panel, "RIGHT", -4, 0)
    card:SetHeight(122)
    local h = W.Header(card, "Your status")
    h:SetPoint("TOPLEFT", 8, -6)

    ui.lookingCheck = W.Check(card, "I'm looking", function() return db.looking end, setLooking)
    ui.lookingCheck:SetPoint("TOPLEFT", 4, -22)
    local listing = W.Cycle(card, 104, LISTING, function() return db.listing end,
        function(v) db.listing = v; alerted = {}; changed() end, "As: ")
    listing:SetPoint("TOPLEFT", 112, -22)
    local roles = { { W.RoleIcon("T") .. " Tank", "tank", 228 }, { W.RoleIcon("H") .. " Healer", "healer", 316 },
                    { W.RoleIcon("D") .. " DPS", "dps", 416 } }
    for _, r in ipairs(roles) do
        local key = r[2]
        local c = W.Check(card, r[1], function() return db[key] end, function(v) db[key] = v; changed() end)
        c:SetPoint("TOPLEFT", r[3], -22)
    end
    local toasts = W.Check(card, "Alerts", function() return db.toasts end, function(v) db.toasts = v end)
    toasts:SetPoint("TOPLEFT", 500, -22)
    local badgeCheck = W.Check(card, "Badge", function() return db.badge end, function(v) db.badge = v; updateBadge() end)
    badgeCheck:SetPoint("TOPLEFT", 576, -22)

    local labels = { { "Activity", 8 }, { "Which / where", 126 }, { "Note", 276 }, { "Spec (blank = auto)", 454 } }
    for _, l in ipairs(labels) do
        local fs = W.Label(card, C.dim .. l[1] .. "|r", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", l[2], -50)
    end
    local activity = W.Cycle(card, 110, ACTIVITIES, function() return db.activity end,
        function(v) db.activity = v; alerted = {}; changed() end)
    activity:SetPoint("TOPLEFT", 8, -64)
    ui.activity, ui.listing = activity, listing
    local detail = W.EditBox(card, 140, function(t) db.detail = t:sub(1, 30); changed() end)
    detail:SetPoint("TOPLEFT", 132, -64)
    detail:SetText(db.detail)
    ui.detail = detail
    local note = W.EditBox(card, 166, function(t) db.note = t:sub(1, 60); changed() end)
    note:SetPoint("TOPLEFT", 282, -64)
    note:SetText(db.note)
    local spec = W.EditBox(card, 100, function(t) db.spec = t:sub(1, 20); changed() end)
    spec:SetPoint("TOPLEFT", 460, -64)
    spec:SetText(db.spec)

    -- Group listings: how many of each role the group still needs.
    ui.needRow = CreateFrame("Frame", nil, card)
    ui.needRow:SetPoint("TOPLEFT", 8, -92)
    ui.needRow:SetSize(560, 24)
    local nl = W.Label(ui.needRow, C.gold .. "Your group needs|r", "GameFontNormalSmall")
    nl:SetPoint("LEFT", 0, 0)
    local x = 110
    for _, r in ipairs({ { "T", "needT" }, { "H", "needH" }, { "D", "needD" } }) do
        local key = r[2]
        local icon = W.Label(ui.needRow, W.RoleIcon(r[1], 16))
        icon:SetPoint("LEFT", x, 0)
        local box = W.EditBox(ui.needRow, 28, function(t) db[key] = math.max(0, math.min(39, tonumber(t) or 0)); changed() end)
        box:SetPoint("LEFT", x + 20, 0)
        box:SetText(tostring(db[key] or 0))
        ui.need = ui.need or {}
        ui.need[key] = box
        if box.SetNumeric then box:SetNumeric(true) end
        x = x + 70
    end
    local nh = W.Label(ui.needRow, C.dim .. "Players who can fill a role are alerted.|r", "GameFontHighlightSmall")
    nh:SetPoint("LEFT", x + 6, 0)

    local h2 = W.Header(panel, "Looking now across RUIN")
    h2:SetPoint("TOPLEFT", 0, -132)
    ui.count = W.Label(panel, "", "GameFontHighlightSmall")
    ui.count:SetPoint("LEFT", h2, "RIGHT", 10, 0)
    local filt = W.Cycle(panel, 120, FILTERS, function() return filter end,
        function(v) filter = v; refresh() end, "Show: ")
    filt:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -128)
    local lv = W.Cycle(panel, 110, LEVELS, function() return db.levels end,
        function(v) db.levels = v; refresh() end)
    lv:SetPoint("RIGHT", filt, "LEFT", -4, 0)

    ui.status = W.Label(panel, "", "GameFontHighlightSmall")
    ui.status:SetPoint("TOPLEFT", 0, -152)
    ui.status:SetPoint("RIGHT", panel, "RIGHT", -10, 0)

    ui.list = W.List(panel, 24, function(row)
        row.text = W.Label(row, "")
        row.text:SetPoint("LEFT", 4, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -132, 0)
        row.text:SetWordWrap(false)
        row.inv = W.Button(row, "Invite", 58)
        row.inv:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.wsp = W.Button(row, "Whisper", 66)
        row.wsp:SetPoint("RIGHT", row.inv, "LEFT", -2, 0)
    end, function(row, e)
        if e.muster then
            local s = e.muster
            local open = {}
            for _, r in ipairs({ "T", "H", "D" }) do
                if (s.open[r] or 0) > 0 then open[#open + 1] = s.open[r] .. W.RoleIcon(r) end
            end
            row.text:SetText(("%sMuster|r  %s%s|r  %s  %s%s|r  needs %s"):format("|cffd9622b", C.white, s.title, s.kind or "",
                C.gold, date("%a %H:%M", s.at), table.concat(open, " ")))
            row.wsp:SetText("Sign up")
            row.wsp:Show()
            row.inv:Hide()
            row.wsp:SetScript("OnClick", function() joinEvent(s) end)
            row.tip = function(tip)
                tip:AddLine(s.title, 0.85, 0.38, 0.17)
                tip:AddLine("A RUIN Muster event that still needs players. Sign up uses the first role you ticked that is open.", 1, 1, 1, true)
            end
            return
        end
        row.wsp:SetText(e.lt == "G" and "Ask" or "Whisper")
        local where = e.d ~= "" and (": " .. e.d) or ""
        local note = e.nt ~= "" and (C.dim .. " · " .. e.nt .. "|r") or ""
        local tag = e.self and (C.good .. "You:|r ") or (e.match and (C.good .. "Match|r ") or "")
        if e.lt == "G" then
            row.text:SetText(("%s%sGroup of %d|r %s  %s%s%s|r  %s%s  %s%s|r"):format(tag, C.white, tonumber(e.gs) or 1,
                W.ClassName(e.name, e.c), C.gold, e.a, where, needText(e), note, C.dim, e.gu and (" · " .. e.gu) or ""))
        else
            row.text:SetText(("%s%s %s %s%d %s|r  %s%s%s|r%s  %s%s|r"):format(tag, roleText(e), W.ClassName(e.name, e.c),
                C.dim, tonumber(e.l) or 0, e.sp or "", C.gold, e.a, where, note, C.dim, e.gu and (" · " .. e.gu) or ""))
        end
        row.wsp:SetShown(not e.self)
        row.inv:SetShown(not e.self and e.lt ~= "G")
        row.wsp:SetScript("OnClick", function() whisper(e.name) end)
        row.inv:SetScript("OnClick", function() invite(e.name) end)
        row.tip = (not e.self) and function(tip)
            tip:AddLine(W.ClassName(e.name, e.c), 1, 1, 1)
            tip:AddLine(("Level %d %s  ·  %s"):format(tonumber(e.l) or 0, e.sp or "", e.gu or "?"), 0.8, 0.8, 0.8)
            if e.z then tip:AddLine("In " .. e.z, 0.7, 0.7, 0.7) end
            if e.match then tip:AddLine("Fits what you're looking for.", 0.25, 1, 0.25) end
        end or nil
    end)
    ui.list:SetEmptyText("Nobody is looking right now. Tick \"I'm looking\" and you'll be the first on the board.")
    ui.list.frame:SetPoint("TOPLEFT", 0, -170)
    ui.list.frame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -24, 0)

    panel:SetScript("OnShow", refresh)
    refresh()
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------
function M:OnEnable()
    if type(RUIN_FinderCharDB) ~= "table" then RUIN_FinderCharDB = {} end
    db = RUIN_FinderCharDB
    for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end

    self:Listen("BEACON", "OnBeacon")
    self:Listen("ASK", "OnAsk")
    self:AddTab("Finder", buildPage)
    R:Subscribe("Muster:EVENTS", function() refresh() end)

    local function ask()
        if R:IsConnected() then
            self:Send("ASK", {}, "ORG")
            if db.looking then scheduleSend() end
        end
    end
    R:Subscribe("CHANNELS_CHANGED", function() C_Timer.After(3, ask); C_Timer.After(3.5, refresh) end)
    C_Timer.After(5, ask)

    C_Timer.NewTicker(5, function()
        local now, gone = GetTime(), false
        for g, e in pairs(board) do
            if now - e.t > EXPIRE then board[g] = nil; gone = true end
        end
        if db.looking and now - lastSent >= BEACON_EVERY then sendBeacon() end
        if gone then refresh() end
    end)
    updateBadge()
end

---------------------------------------------------------------------------
-- Slash command and key bindings
---------------------------------------------------------------------------
function RUIN_Finder_Open() M:OpenTab() end
function RUIN_Finder_ToggleLooking() if db then setLooking(not db.looking) end end

BINDING_HEADER_RUIN_FINDER = "RUIN Finder"
BINDING_NAME_RUIN_FINDER_OPEN = "Open Finder"
BINDING_NAME_RUIN_FINDER_TOGGLE = "Toggle 'I'm looking'"

-- /finder on [activity]      look as a player
-- /finder group [activity]   list your group (set needed roles on the page)
-- /finder off | badge
SLASH_RUINFINDER1 = "/finder"
SlashCmdList.RUINFINDER = function(msg)
    msg = (msg or ""):lower()
    local cmd, rest = msg:match("^(%S*)%s*(.*)$")
    if cmd == "on" or cmd == "off" or cmd == "group" then
        if rest ~= "" then
            for _, a in ipairs(ACTIVITIES) do
                if a:lower() == rest:match("^(%S+)") then db.activity = a end
            end
        end
        if cmd ~= "off" then db.listing = (cmd == "group") and "Group" or "Player" end
        setLooking(cmd ~= "off")
    elseif cmd == "badge" then
        db.badge = not db.badge
        updateBadge()
        M:Print("Looking badge " .. (db.badge and "on." or "off."))
    else
        M:OpenTab()
    end
end
