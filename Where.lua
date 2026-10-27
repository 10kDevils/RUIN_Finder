-- RUIN Finder: where the members are, and member marks
-- Where: the org's online members by continent and zone (from the guild
-- rosters RUIN already has; nobody's exact position is shared), with a pin on
-- each zone of the world map showing how many are there. Click a zone for
-- the names and a whisper.
-- Marks: a small RUIN mark on the nameplates of players from the org's
-- guilds, and their guild tag under your target frame, so you know a friend
-- when you see one. Settings on the Where tab.
local ADDON, ns = ...
local R = RUIN_API
if not R or (R.apiLevel or 1) < 11 then return end
local W = R.Widgets
local C = W.COLORS

local Where = {}
ns.Where = Where

local PIN_OWNER = "FinderWhere"
local MARK_TEX = "Interface\\Icons\\INV_Banner_03"
local M, db
local ui = {}

---------------------------------------------------------------------------
-- Where
---------------------------------------------------------------------------
-- Online members in a zone: { { name, guild, class, level } }
function Where.Members(zone)
    local out = {}
    for _, m in ipairs(R:GetOrgMembers()) do
        if m.online and m.zone == zone then out[#out + 1] = m end
    end
    table.sort(out, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return out
end

function Where.UpdatePins()
    R.Map:ClearPins(PIN_OWNER)
    if not db.wherePins then return end
    local w = R:GetWhere()
    for _, z in ipairs(w.zones) do
        local id = R.Map.ZoneMapID and R.Map:ZoneMapID(z.zone)
        if id then
            local gs = {}
            for g, n in pairs(z.guilds) do gs[#gs + 1] = g .. " " .. n end
            table.sort(gs)
            R.Map:SetPin(PIN_OWNER, z.zone, { map = id, x = 0.5, y = 0.5, icon = MARK_TEX, color = { 0.33, 0.72, 0.85 },
                title = ("%d RUIN member%s"):format(z.count, z.count == 1 and "" or "s"), text = z.zone .. ": " .. table.concat(gs, ", "),
                minimap = false, worldmap = true })
        end
    end
end

function Where.Build(page)
    ui.page = page
    ui.total = W.Label(page, "", "GameFontHighlight")
    ui.total:SetPoint("TOPLEFT", 2, -4)
    ui.pins = W.Check(page, "Map pins", function() return db.wherePins end, function(v) db.wherePins = v; Where.UpdatePins() end)
    ui.pins:SetPoint("TOPLEFT", page, "TOPRIGHT", -330, -1)
    ui.pins.tip = "A pin on each zone of the world map with how many members are there."
    ui.marks = W.Check(page, "Member marks", function() return db.marks end, function(v) db.marks = v; Where.RefreshMarks() end)
    ui.marks:SetPoint("TOPLEFT", page, "TOPRIGHT", -200, -1)
    ui.marks.tip = "A RUIN mark on org members' nameplates and their guild tag under your target frame."
    ui.sub = W.Label(page, C.dim .. "Online members of every RUIN guild by zone. Only zones are known: nobody's exact position is shared.|r", "GameFontHighlightSmall")
    ui.sub:SetPoint("TOPLEFT", 2, -28)

    ui.zones = W.List(page, 22, function(row)
        row.a = W.Label(row, "")
        row.a:SetPoint("LEFT", 6, 0); row.a:SetWidth(200); row.a:SetWordWrap(false)
        row.b = W.Label(row, "", "GameFontHighlightSmall")
        row.b:SetPoint("RIGHT", -6, 0)
        row:SetScript("OnMouseUp", function(self) if self.e and self.e.zone then ui.sel = self.e.zone; Where.Refresh() end end)
    end, function(row, e)
        row.e = e
        if e.continent then
            row.a:SetText(C.gold .. e.continent .. "|r")
            row.b:SetText(C.good .. e.count .. "|r")
        else
            row.a:SetText((ui.sel == e.zone and (C.gold .. "> |r") or "   ") .. C.white .. e.zone .. "|r")
            row.b:SetText(tostring(e.count))
        end
    end)
    ui.zones.frame:SetPoint("TOPLEFT", 0, -48)
    ui.zones.frame:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
    ui.zones.frame:SetWidth(290)

    ui.people = W.List(page, 22, function(row)
        row.a = W.Label(row, "")
        row.a:SetPoint("LEFT", 6, 0); row.a:SetWidth(170); row.a:SetWordWrap(false)
        row.b = W.Label(row, "", "GameFontHighlightSmall")
        row.b:SetPoint("LEFT", 180, 0); row.b:SetPoint("RIGHT", row, "RIGHT", -70, 0); row.b:SetWordWrap(false)
        row.w = W.Button(row, "Whisper", 64)
        row.w:SetPoint("RIGHT", -2, 0)
    end, function(row, m)
        row.a:SetText(W.ClassName(m.name, m.class))
        row.b:SetText(C.dim .. tostring(m.level or "") .. "  ·  " .. (m.guild or "") .. "|r")
        row.w:SetScript("OnClick", function()
            if ChatFrame_SendTell then ChatFrame_SendTell(m.name) end
        end)
    end)
    ui.people.frame:SetPoint("TOPLEFT", ui.zones.frame, "TOPRIGHT", 30, 0)
    ui.people.frame:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -24, 0)
    page:SetScript("OnShow", Where.Refresh)
end

function Where.Refresh()
    if not (ui.page and ui.page:IsVisible()) then return end
    local w = R:GetWhere()
    ui.total:SetText(("%s%d|r members online with a known zone, in %d zone%s"):format(C.good, w.total, #w.zones, #w.zones == 1 and "" or "s"))
    -- the continents' totals, then the zones
    local items = {}
    for _, c in ipairs(w.continents) do items[#items + 1] = { continent = c.name, count = c.count } end
    for _, z in ipairs(w.zones) do items[#items + 1] = { zone = z.zone, count = z.count } end
    if not ui.sel and w.zones[1] then ui.sel = w.zones[1].zone end
    ui.zones:SetEmptyText("Nobody online with a known zone.")
    ui.zones:SetItems(items)
    ui.people:SetEmptyText(ui.sel and "Nobody there now." or "")
    ui.people:SetItems(ui.sel and Where.Members(ui.sel) or {})
end

---------------------------------------------------------------------------
-- Member marks
---------------------------------------------------------------------------
local orgGuilds = {}
local function loadGuilds()
    orgGuilds = {}
    local org = R:GetOrg()
    for _, g in ipairs(org and org.guilds or {}) do orgGuilds[g.name] = g.tag or g.name end
end

-- The org guild tag of a player unit, or nil.
function Where.TagOf(unit)
    if not (UnitExists(unit) and UnitIsPlayer(unit)) or not GetGuildInfo then return nil end
    local g = GetGuildInfo(unit)
    if type(g) ~= "string" or (issecretvalue and issecretvalue(g)) then return nil end
    return orgGuilds[g]
end

local function plateFrame(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    local f = plate and plate.UnitFrame
    if not f or (f.IsForbidden and f:IsForbidden()) then return nil end
    return f
end

local function markPlate(unit)
    local f = plateFrame(unit)
    if not f then return end
    local tag = db.marks and Where.TagOf(unit)
    if tag then
        if not f.RUINMark then
            f.RUINMark = f:CreateTexture(nil, "OVERLAY")
            f.RUINMark:SetSize(14, 14)
            f.RUINMark:SetTexture(MARK_TEX)
            f.RUINMark:SetPoint("BOTTOM", f, "TOP", 0, 2)
        end
        f.RUINMark:Show()
    elseif f.RUINMark then
        f.RUINMark:Hide()
    end
end

local targetBadge
local function markTarget()
    if not targetBadge then
        local parent = TargetFrame or UIParent
        targetBadge = CreateFrame("Frame", nil, parent)
        targetBadge:SetSize(140, 16)
        targetBadge:SetPoint("TOP", parent, "BOTTOM", 20, 6)
        targetBadge.icon = targetBadge:CreateTexture(nil, "ARTWORK")
        targetBadge.icon:SetSize(14, 14)
        targetBadge.icon:SetPoint("LEFT", 0, 0)
        targetBadge.icon:SetTexture(MARK_TEX)
        targetBadge.text = W.Label(targetBadge, "", "GameFontHighlightSmall")
        targetBadge.text:SetPoint("LEFT", targetBadge.icon, "RIGHT", 4, 0)
    end
    local tag = db.marks and Where.TagOf("target")
    if tag then
        targetBadge.text:SetText(C.gold .. "RUIN [" .. tag .. "]|r")
        targetBadge:Show()
    else
        targetBadge:Hide()
    end
end

function Where.RefreshMarks()
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then markPlate(unit) end
    end
    markTarget()
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------
function Where.Init(module, cdb)
    M, db = module, cdb
    if db.marks == nil then db.marks = true end
    if db.wherePins == nil then db.wherePins = true end
    loadGuilds()
    R:Subscribe("KEY_CHANGED", function() loadGuilds(); Where.RefreshMarks() end)
    M:RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, unit) markPlate(unit) end)
    M:RegisterEvent("PLAYER_TARGET_CHANGED", markTarget)
    local function update() Where.UpdatePins(); Where.Refresh() end
    R:Subscribe("ORG_ROSTER_UPDATED", update)
    R:Subscribe("ROSTER_UPDATED", update)
    C_Timer.NewTicker(120, update)
    C_Timer.After(10, update)
end
