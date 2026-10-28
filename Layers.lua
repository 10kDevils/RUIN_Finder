-- RUIN Finder: layers and layer hops
-- WoW Forever splits busy zones into layers (copies of the zone). RUIN works
-- out which layer you're on from the creatures around you: each creature's
-- ID carries the number of the zone copy it lives in. Two different
-- creatures have to agree, and keep agreeing for a few seconds, before RUIN
-- says you changed layer, so a pet or a creature that followed you doesn't
-- fool it. Members share their layer (zone and number, nothing else) on the
-- org channel, so the Layers tab shows who is on which layer.
--
-- Hop: ask for a hop and a member on another layer of your zone invites you;
-- you accept automatically (that invite only), the game moves you to their
-- layer, and RUIN offers to leave the group once you've arrived.
local ADDON, ns = ...
local R = RUIN_API
if not R or (R.apiLevel or 1) < 11 then return end
local W = R.Widgets
local C = W.COLORS

local Layers = {}
ns.Layers = Layers

local HOLD = 6                 -- seconds a new layer must hold before it counts
local KEEP = 20 * 60           -- members' layers are kept this long
local SEND_GAP = 30
local HOP_WAIT = 120           -- a hop request lasts two minutes

local M, db
local ui = {}
local mine = { zone = nil, layer = nil }
local candidate = { layer = nil, npcs = {}, since = 0 }
local peers = {}               -- name -> { zone, layer, t, guild }
local lastSent, sendPending = -999, false
local hop = nil                -- my request: { at, zone, from, helper }
local offers = {}              -- name -> { zone, layer, at } (hop requests others sent)

local function zoneName() return (GetRealZoneText and GetRealZoneText()) or "?" end
local function norm(n) return R.Util.ShortName(n or ""):lower() end

-- "Creature-0-<server>-<instance>-<zoneUID>-<npcID>-<spawn>": the zone copy and the creature.
function Layers.Parse(guid)
    if type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then return nil end
    local kind, zoneUID, npcID = guid:match("^(%a+)%-%d+%-%d+%-%d+%-(%d+)%-(%d+)%-")
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    zoneUID, npcID = tonumber(zoneUID), tonumber(npcID)
    if not zoneUID or zoneUID == 0 or not npcID then return nil end
    return zoneUID, npcID
end

function Layers.Mine() return mine.layer, mine.zone end

local function sendMine()
    if not R:IsConnected() or not mine.layer then return end
    if GetTime() - lastSent < SEND_GAP then
        if not sendPending then
            sendPending = true
            C_Timer.After(SEND_GAP - (GetTime() - lastSent) + 1, function() sendPending = false; sendMine() end)
        end
        return
    end
    lastSent = GetTime()
    M:Send("LAYER", { z = mine.zone, l = mine.layer }, "ORG", nil, R.PRIORITY.BULK)
end

local function setLayer(layer)
    local old = mine.layer
    mine.layer, mine.zone = layer, zoneName()
    if old and old ~= layer then
        M:Print(("You're now on layer %s of %s."):format(Layers.Label(layer), mine.zone))
        if hop and hop.helper and GetTime() - hop.at < 600 then
            hop.arrived = true
            M:Print("Hop done. Leave the group with the Layers tab's Leave group button (or /finder leave).")
        end
    end
    sendMine()
    Layers.Refresh()
end

-- A creature seen: count it toward the layer it says.
function Layers.Observe(unit)
    if not UnitExists(unit) or (UnitIsPlayer and UnitIsPlayer(unit)) or (UnitPlayerControlled and UnitPlayerControlled(unit)) then return end
    local layer, npc = Layers.Parse(UnitGUID(unit))
    if not layer then return end
    if layer == mine.layer then candidate.layer, candidate.npcs = nil, {}; return end
    if candidate.layer ~= layer then
        candidate.layer, candidate.npcs, candidate.since = layer, {}, GetTime()
    end
    candidate.npcs[npc] = true
    local n = 0
    for _ in pairs(candidate.npcs) do n = n + 1 end
    if n >= 2 and GetTime() - candidate.since >= (mine.layer and HOLD or 0) then
        setLayer(layer)
        candidate.layer, candidate.npcs = nil, {}
    elseif n >= 2 then
        C_Timer.After(HOLD + 0.2, function()
            if candidate.layer == layer then
                local c = 0
                for _ in pairs(candidate.npcs) do c = c + 1 end
                if c >= 2 then setLayer(layer); candidate.layer, candidate.npcs = nil, {} end
            end
        end)
    end
end

-- Layer numbers are long; show the last digits, which is enough to tell layers apart.
function Layers.Label(layer)
    if not layer then return "?" end
    local s = tostring(layer)
    return #s > 4 and s:sub(-4) or s
end

local function onLayer(_, d, sender)
    if type(d) ~= "table" or not tonumber(d.l) or type(d.z) ~= "string" then return end
    local who = R:GetPlayer()
    if norm(sender) == norm(who.name) then return end
    peers[sender] = { zone = d.z:sub(1, 40), layer = tonumber(d.l), t = GetTime() }
    Layers.Refresh()
end

-- Members by zone and layer: { { zone, layers = { { layer, names = {...}, mine } } } }
function Layers.Table()
    local zones = {}
    local function add(zone, layer, name)
        zones[zone] = zones[zone] or {}
        zones[zone][layer] = zones[zone][layer] or {}
        table.insert(zones[zone][layer], name)
    end
    for name, p in pairs(peers) do
        if GetTime() - p.t <= KEEP then add(p.zone, p.layer, name) else peers[name] = nil end
    end
    if mine.layer then add(mine.zone, mine.layer, "you") end
    local out = {}
    for zone, layers in pairs(zones) do
        local e = { zone = zone, layers = {} }
        for layer, names in pairs(layers) do
            table.sort(names)
            e.layers[#e.layers + 1] = { layer = layer, names = names, mine = layer == mine.layer and zone == mine.zone }
        end
        table.sort(e.layers, function(a, b) return #a.names > #b.names end)
        out[#out + 1] = e
    end
    table.sort(out, function(a, b)
        if (a.zone == mine.zone) ~= (b.zone == mine.zone) then return a.zone == mine.zone end
        return a.zone < b.zone
    end)
    return out
end

---------------------------------------------------------------------------
-- Hops
---------------------------------------------------------------------------
function Layers.AskHop()
    if not mine.layer then return false, "RUIN doesn't know your layer yet: target or mouse over a couple of creatures." end
    if IsInGroup and IsInGroup() then return false, "Leave your group first: a hop needs an invite." end
    hop = { at = GetTime(), zone = mine.zone, from = mine.layer }
    M:Send("HOPREQ", { z = mine.zone, l = mine.layer }, "ORG", nil, R.PRIORITY.ALERT)
    return true
end

local function onHopRequest(_, d, sender)
    if type(d) ~= "table" or type(d.z) ~= "string" then return end
    local me = R:GetPlayer()
    if norm(sender) == norm(me.name) then return end
    if not mine.layer or d.z ~= mine.zone or tonumber(d.l) == mine.layer then return end
    offers[sender] = { zone = d.z, layer = tonumber(d.l), at = GetTime() }
    if db.autoHop and not (UnitAffectingCombat and UnitAffectingCombat("player")) then
        Layers.Help(sender)
    else
        M:Toast(("%s asks for a hop to your layer of %s. Finder > Layers to invite."):format(W.ClassName(sender), d.z), { sound = true })
    end
    Layers.Refresh()
end

-- Invite someone who asked for a hop, and tell the others it's taken.
function Layers.Help(name)
    local o = offers[name]
    if not o or GetTime() - o.at > HOP_WAIT then return false, "That request has expired." end
    offers[name] = nil
    M:Send("HOPTAKEN", { n = name, l = mine.layer }, "ORG", nil, R.PRIORITY.ALERT)
    local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if invite then invite(name) end
    M:Print(("Invited %s for a hop. Once they arrive they leave your group."):format(R.Util.ShortName(name)))
    Layers.Refresh()
    return true
end

local function onHopTaken(_, d, sender)
    if type(d) ~= "table" or type(d.n) ~= "string" then return end
    offers[d.n] = nil
    local me = R:GetPlayer()
    -- only a member who shared a different layer of this zone can be the helper
    -- (RUIN accepts that one's invite for you)
    local p = peers[sender]
    local couldHelp = p and hop and p.zone == hop.zone and p.layer ~= hop.from and GetTime() - p.t <= KEEP
    if hop and couldHelp and norm(d.n) == norm(me.name) and GetTime() - hop.at < HOP_WAIT then
        hop.helper = sender
        M:Print(("%s is inviting you for a hop; RUIN accepts it for you."):format(R.Util.ShortName(sender)))
    end
    Layers.Refresh()
end

-- Accept the helper's invite (and only that one).
-- The invite can arrive before the helper's HOPTAKEN, so a member who shared
-- a layer of this zone counts too.
local function onInvite(_, inviter)
    if not (hop and inviter and GetTime() - hop.at < HOP_WAIT) then return end
    local ok = hop.helper and norm(inviter) == norm(hop.helper)
    if not ok and not hop.helper then
        for name, p in pairs(peers) do
            if norm(name) == norm(inviter) and p.zone == hop.zone and p.layer ~= hop.from then ok = true; hop.helper = name end
        end
    end
    if not ok then return end
    if AcceptGroup then AcceptGroup() end
    if StaticPopup_Hide then StaticPopup_Hide("PARTY_INVITE") end
end

function Layers.Leave()
    local leave = (C_PartyInfo and C_PartyInfo.LeaveParty) or LeaveParty
    if leave then leave() end
    hop = nil
    Layers.Refresh()
end

function Layers.HopState() return hop end

---------------------------------------------------------------------------
-- The Layers tab
---------------------------------------------------------------------------
function Layers.Build(page)
    ui.page = page
    ui.mine = W.Label(page, "", "GameFontHighlight")
    ui.mine:SetPoint("TOPLEFT", 2, -4)
    ui.mine:SetPoint("RIGHT", page, "RIGHT", -430, 0)
    ui.mine:SetWordWrap(false)
    ui.ask = W.Button(page, "Ask for a hop", 120, function()
        local ok, err = Layers.AskHop()
        M:Print(ok and "Asked the members on other layers of this zone." or err)
    end)
    ui.ask:SetPoint("TOPRIGHT", page, "TOPRIGHT", -200, 0)
    ui.ask.tip = "A member on another layer of your zone invites you; you move to their layer and leave the group."
    ui.leave = W.Button(page, "Leave group", 100, function() Layers.Leave() end)
    ui.leave:SetPoint("RIGHT", ui.ask, "LEFT", -6, 0)
    ui.auto = W.Check(page, "Help hops automatically", function() return db.autoHop end, function(v) db.autoHop = v end)
    ui.auto:SetPoint("TOPLEFT", page, "TOPRIGHT", -190, -1)
    ui.auto.tip = "Invite members who ask for a hop to your layer without asking you (not in combat)."
    ui.sub = W.Label(page, C.dim .. "Layers come from the creatures around you: target or mouse over a couple to find yours. Only zone and layer are shared.|r", "GameFontHighlightSmall")
    ui.sub:SetPoint("TOPLEFT", 2, -30)
    ui.sub:SetPoint("RIGHT", page, "RIGHT", -6, 0)

    ui.list = W.List(page, 24, function(row)
        row.a = W.Label(row, "")
        row.a:SetPoint("LEFT", 6, 0); row.a:SetWidth(220); row.a:SetWordWrap(false)
        row.b = W.Label(row, "", "GameFontHighlightSmall")
        row.b:SetPoint("LEFT", 232, 0); row.b:SetPoint("RIGHT", row, "RIGHT", -110, 0); row.b:SetWordWrap(false)
        row.btn = W.Button(row, "Invite", 96)
        row.btn:SetPoint("RIGHT", -2, 0)
    end, function(row, e)
        row.btn:Hide()
        if e.offer then
            row.a:SetText(C.gold .. "Hop request|r  " .. W.ClassName(e.name))
            row.b:SetText(C.dim .. ("from layer %s, %d s ago|r"):format(Layers.Label(e.o.layer), GetTime() - e.o.at))
            row.btn:SetText("Invite")
            row.btn:SetScript("OnClick", function() local ok, err = Layers.Help(e.name); if not ok then M:Print(err) end end)
            row.btn:Show()
        elseif e.zoneHead then
            row.a:SetText(C.gold .. e.zone .. "|r")
            row.b:SetText(C.dim .. #e.layers .. " layer" .. (#e.layers == 1 and "" or "s") .. "|r")
        else
            row.a:SetText(("   %sLayer %s|r%s"):format(e.l.mine and C.good or C.white, Layers.Label(e.l.layer), e.l.mine and (C.good .. "  (yours)|r") or ""))
            local names = {}
            for i, n in ipairs(e.l.names) do
                if i > 8 then names[#names + 1] = "+" .. (#e.l.names - 8); break end
                names[#names + 1] = n == "you" and "you" or R.Util.ShortName(n)
            end
            row.b:SetText(C.dim .. table.concat(names, ", ") .. "|r")
        end
    end)
    ui.list:SetEmptyText("Nobody has shared a layer yet.")
    ui.list.frame:SetPoint("TOPLEFT", 0, -50)
    ui.list.frame:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -24, 0)
    page:SetScript("OnShow", Layers.Refresh)
end

function Layers.Refresh()
    if not (ui.page and ui.page:IsVisible()) then return end
    ui.mine:SetText(mine.layer and ("Your layer: %s%s|r in %s"):format(C.good, Layers.Label(mine.layer), mine.zone or "?")
        or (C.dim .. "Your layer isn't known yet.|r"))
    local inGroup = IsInGroup and IsInGroup()
    ui.leave:SetShown(hop ~= nil and inGroup and true or false)
    ui.ask:SetEnabled(not inGroup and mine.layer ~= nil)
    local items = {}
    for name, o in pairs(offers) do
        if GetTime() - o.at <= HOP_WAIT then items[#items + 1] = { offer = true, name = name, o = o } else offers[name] = nil end
    end
    for _, z in ipairs(Layers.Table()) do
        items[#items + 1] = { zoneHead = true, zone = z.zone, layers = z.layers }
        for _, l in ipairs(z.layers) do items[#items + 1] = { l = l } end
    end
    ui.list:SetItems(items)
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------
function Layers.Init(module, cdb)
    M, db = module, cdb
    if db.autoHop == nil then db.autoHop = false end
    M:Listen("LAYER", onLayer)
    M:Listen("HOPREQ", onHopRequest)
    M:Listen("HOPTAKEN", onHopTaken)
    M:RegisterEvent("PLAYER_TARGET_CHANGED", function() Layers.Observe("target") end)
    M:RegisterEvent("UPDATE_MOUSEOVER_UNIT", function() Layers.Observe("mouseover") end)
    M:RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, unit) Layers.Observe(unit) end)
    M:RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
        mine.layer, mine.zone = nil, zoneName()
        candidate.layer, candidate.npcs = nil, {}
        Layers.Refresh()
    end)
    M:RegisterEvent("PARTY_INVITE_REQUEST", onInvite)
    M:RegisterEvent("GROUP_ROSTER_UPDATE", function()
        if hop and hop.arrived and not (IsInGroup and IsInGroup()) then hop = nil end
        Layers.Refresh()
    end)
    C_Timer.NewTicker(60, function() if mine.layer and GetTime() - lastSent > 600 then sendMine() end; Layers.Refresh() end)
end
