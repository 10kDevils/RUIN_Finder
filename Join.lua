-- RUIN Finder: join a member (layer hops the way the game allows)
-- WoW Forever splits busy zones into layers (copies of the zone). Since the
-- November 2026 hotfix the game no longer lets addons tell one layer from
-- another, so RUIN can't say which layer you or anyone else is on, and it
-- can't send you to a chosen layer. What the game still does: joining
-- someone's group in your zone puts you in their copy of the zone.
--
--   Join   ask one member in your zone to invite you. You end up wherever
--          they are (the way to reach a friend who's on another layer).
--   Hop    ask any member in your zone. Whoever answers first invites you.
--          It may well be your own layer: nobody can tell any more.
--
-- Finder accepts only the invite you asked for, and Leave group (or
-- /finder leave) leaves once you've arrived.
local ADDON, ns = ...
local R = RUIN_API
if not R or (R.apiLevel or 1) < 11 then return end
local W = R.Widgets
local C = W.COLORS

local Join = {}
ns.Join = Join

local WAIT = 120               -- a request lasts two minutes

local M, db
local ask = nil                -- my request: { at, zone, to (name) or any = true, helper }
local offers = {}              -- name -> { zone, at, any } (requests others sent me)

local function myZone() return (GetRealZoneText and GetRealZoneText()) or nil end
local function norm(n) return R.Util.ShortName(n or ""):lower() end
local function inGroup() return IsInGroup and IsInGroup() and true or false end
local function inCombat() return UnitAffectingCombat and UnitAffectingCombat("player") and true or false end
local function isMember(name)
    if R.IsMember then return R:IsMember(name) and true or false end
    return true
end

-- The member's zone as RUIN last heard it (nil when unknown or offline).
local function zoneOf(name)
    local n = norm(name)
    for _, m in ipairs(R:GetOrgMembers()) do
        if m.online and norm(m.name) == n then return m.zone end
    end
end

-- Can I ask this member to pull me in? nil, or why not.
function Join.CanAsk(name)
    if inGroup() then return "Leave your group first: joining needs an invite." end
    if inCombat() then return "Not in combat." end
    local here = myZone()
    if name then
        if norm(name) == norm(R:GetPlayer().name) then return "That's you." end
        local z = zoneOf(name)
        if not z then return R.Util.ShortName(name) .. " isn't online with RUIN." end
        if z ~= here then return R.Util.ShortName(name) .. " is in " .. z .. ", not here." end
    end
    return nil
end

-- Ask one member (name) or anyone in my zone (name = nil) to invite me.
function Join.Ask(name)
    if not R:IsConnected() then return false, "Not connected to RUIN yet." end
    local why = Join.CanAsk(name)
    if why then return false, why end
    local zone = myZone()
    ask = { at = GetTime(), zone = zone, to = name, any = name == nil }
    if name then
        M:Send("JOINME", { z = zone }, "PEER", name, R.PRIORITY.ALERT)
    else
        M:Send("HOPANY", { z = zone }, "ORG", nil, R.PRIORITY.ALERT)
    end
    Join.Refresh()
    return true
end

function Join.AskAny() return Join.Ask(nil) end

local function onRequest(any)
    return function(_, d, sender)
        if type(d) ~= "table" or type(d.z) ~= "string" or not isMember(sender) then return end
        if norm(sender) == norm(R:GetPlayer().name) or d.z ~= myZone() then return end
        -- a full group or a raid can't take one more for a hop
        if IsInRaid and IsInRaid() then return end
        if any and GetNumGroupMembers and GetNumGroupMembers() >= 5 then return end
        offers[sender] = { zone = d.z, at = GetTime(), any = any }
        if db.autoHop and not inCombat() then
            Join.Help(sender)
        else
            M:Toast(("%s asks to join you in %s. Finder > Where to invite."):format(W.ClassName(sender), d.z), { sound = true })
        end
        Join.Refresh()
    end
end

-- Invite someone who asked, and tell the others a "Hop" request is taken.
function Join.Help(name)
    local o = offers[name]
    if not o or GetTime() - o.at > WAIT then offers[name] = nil; return false, "That request has expired." end
    offers[name] = nil
    if o.any then M:Send("HOPTAKEN", { n = name }, "ORG", nil, R.PRIORITY.ALERT) end
    local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if invite then invite(name) end
    M:Print(("Invited %s. They leave your group once they've arrived."):format(R.Util.ShortName(name)))
    Join.Refresh()
    return true
end

local function onTaken(_, d, sender)
    if type(d) ~= "table" or type(d.n) ~= "string" or not isMember(sender) then return end
    offers[d.n] = nil
    if ask and ask.any and not ask.helper and norm(d.n) == norm(R:GetPlayer().name) and GetTime() - ask.at < WAIT then
        ask.helper = sender
        M:Print(("%s is inviting you; RUIN accepts it for you."):format(R.Util.ShortName(sender)))
    end
    Join.Refresh()
end

-- Accept the invite I asked for, and only that one: the member I asked, or
-- for a hop, whoever took it (or, if their "taken" is still on its way, any
-- member RUIN last saw in my zone).
local function onInvite(_, inviter)
    if not (ask and inviter and GetTime() - ask.at < WAIT) then return end
    local who = norm(inviter)
    local ok = (ask.to and who == norm(ask.to)) or (ask.helper and who == norm(ask.helper))
    if not ok and ask.any and not ask.helper and isMember(inviter) and zoneOf(inviter) == ask.zone then
        ok = true
        ask.helper = inviter
    end
    if not ok then return end
    ask.joined = true
    if AcceptGroup then AcceptGroup() end
    if StaticPopup_Hide then StaticPopup_Hide("PARTY_INVITE") end
end

function Join.Leave()
    local leave = (C_PartyInfo and C_PartyInfo.LeaveParty) or LeaveParty
    if leave then leave() end
    ask = nil
    Join.Refresh()
end

function Join.State() return ask end
function Join.Offers()
    local out = {}
    for name, o in pairs(offers) do
        if GetTime() - o.at <= WAIT then out[#out + 1] = { name = name, at = o.at, any = o.any } else offers[name] = nil end
    end
    table.sort(out, function(a, b) return a.at > b.at end)
    return out
end

-- The Where tab draws the buttons; this redraws it.
function Join.Refresh()
    if ns.Where and ns.Where.Refresh then ns.Where.Refresh() end
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------
function Join.Init(module, cdb)
    M, db = module, cdb
    if db.autoHop == nil then db.autoHop = false end
    M:Listen("JOINME", onRequest(false))
    M:Listen("HOPANY", onRequest(true))
    M:Listen("HOPREQ", onRequest(true))        -- older Finders' "ask for a hop"
    M:Listen("HOPTAKEN", onTaken)
    M:RegisterEvent("PARTY_INVITE_REQUEST", onInvite)
    M:RegisterEvent("GROUP_ROSTER_UPDATE", function()
        if ask and ask.joined and inGroup() and not ask.arrived then
            ask.arrived = true
            M:Print("You've joined. Leave the group when you're ready: Finder > Where > Leave group, or /finder leave.")
        elseif ask and ask.arrived and not inGroup() then
            ask = nil
        end
        Join.Refresh()
    end)
    C_Timer.NewTicker(30, function()
        if ask and not ask.joined and GetTime() - ask.at > WAIT then ask = nil end
        Join.Refresh()
    end)
end
