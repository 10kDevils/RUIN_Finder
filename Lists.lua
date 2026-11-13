-- RUIN Finder: what the listing card's dropdowns offer.
-- Details: the dungeon, raid, zone or kind of thing per activity.
-- Spec: your talent spec for adventuring activities, a profession for
-- Professions, and the tone of the chat for Social.
local ADDON, ns = ...

local L = {}
ns.Lists = L

-- Dungeons in level order, then WoW Forever's new ones.
local DUNGEONS = {
    "Ragefire Chasm", "Wailing Caverns", "The Deadmines", "Shadowfang Keep", "The Stockade",
    "Blackfathom Deeps", "Gnomeregan", "Razorfen Kraul", "Scarlet Monastery", "Razorfen Downs",
    "Uldaman", "Zul'Farrak", "Maraudon", "Sunken Temple", "Blackrock Depths", "Dire Maul",
    "Blackrock Spire", "Scholomance", "Stratholme",
    "Hall of Thanes", "Ruins of Lordaeron", "Excavation Site: Wetlands", "City of Dalaran",
    "The Drowned City", "Krol'dok Stronghold", "Alcaz Prison", "Blackmaw Hold", "Shaper's Terrace",
}

local RAIDS = {
    "Zul'Gurub", "Ruins of Ahn'Qiraj", "Onyxia's Lair", "Molten Core", "Blackwing Lair",
    "Temple of Ahn'Qiraj", "Naxxramas",
}

-- Every zone you quest in; capital cities are left out.
local ZONES = {
    -- Eastern Kingdoms
    "Alterac Mountains", "Arathi Highlands", "Badlands", "Blasted Lands", "Burning Steppes",
    "Deadwind Pass", "Dun Morogh", "Duskwood", "Eastern Plaguelands", "Elwynn Forest",
    "Hillsbrad Foothills", "Loch Modan", "Redridge Mountains", "Riverglades", "Searing Gorge",
    "Silverpine Forest", "Stranglethorn Vale", "Swamp of Sorrows", "The Hinterlands",
    "Tirisfal Glades", "Western Plaguelands", "Westfall", "Wetlands",
    -- Kalimdor
    "Ashenvale", "Azshara", "Darkshore", "Desolace", "Durotar", "Dustwallow Marsh", "Felwood",
    "Feralas", "Moonglade", "Mulgore", "Silithus", "Stonetalon Mountains", "Tanaris", "Teldrassil",
    "The Barrens", "Thousand Needles", "Un'Goro Crater", "Winterspring",
}
table.sort(ZONES)

L.DETAILS = {
    Dungeon = DUNGEONS,
    Raid = RAIDS,
    PvP = { "Dueling", "World", "Battlegrounds" },
    Questing = ZONES,
    Rares = { "Mobs", "Items", "Secrets" },
    Professions = { "Farming", "Services" },
    Social = { "Just Chatting", "Theory Craft", "RP" },
}

-- Activities where the Spec box shows your talent spec.
L.ADVENTURE = { Dungeon = true, Raid = true, PvP = true, Questing = true, Rares = true }

L.PROFESSIONS = {
    -- primary
    "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism", "Leatherworking",
    "Mining", "Skinning", "Tailoring",
    -- secondary
    "Cooking", "First Aid", "Fishing",
    -- class
    "Lockpicking", "Poisons",
}

L.TONES = { "Casual", "Mutual", "Engaged" }

-- The same spec names (and order) Codex uses.
L.SPECS = {
    WARRIOR = { "Arms", "Fury", "Protection" },
    PALADIN = { "Holy", "Protection", "Retribution" },
    HUNTER  = { "Beast Mastery", "Marksmanship", "Survival" },
    ROGUE   = { "Assassination", "Combat", "Subtlety" },
    PRIEST  = { "Discipline", "Holy", "Shadow" },
    SHAMAN  = { "Elemental", "Enhancement", "Restoration" },
    MAGE    = { "Arcane", "Fire", "Frost" },
    WARLOCK = { "Affliction", "Demonology", "Destruction" },
    DRUID   = { "Balance", "Feral (cat)", "Feral (bear)", "Restoration" },
}
L.ALIAS = { ["Feral Combat"] = "Feral (cat)", Feral = "Feral (cat)", Guardian = "Feral (bear)", Outlaw = "Combat" }

function L.Has(list, v)
    for _, x in ipairs(list or {}) do if x == v then return true end end
    return false
end

---------------------------------------------------------------------------
-- Your spec from your talents, for when Codex isn't installed: the talent
-- tree with the most points. WoW Forever keeps its talent trees in the trait
-- system (the active config's tree, one trait group per tab); older clients
-- answer GetTalentTabInfo.
---------------------------------------------------------------------------
local function sv(v) return not (issecretvalue and issecretvalue(v)) and v or nil end

local function traitPoints(order)
    local CT, TR = rawget(_G, "C_ClassTalents"), rawget(_G, "C_Traits")
    if not (CT and CT.GetActiveConfigID and TR and TR.GetConfigInfo and TR.GetGroupDisplayInfoByTreeID and TR.GetGroupCurrencyInfo) then return nil end
    local ok, configID = pcall(CT.GetActiveConfigID)
    configID = ok and sv(configID)
    if not configID then return nil end
    local okc, info = pcall(TR.GetConfigInfo, configID)
    local treeID = okc and type(info) == "table" and type(info.treeIDs) == "table" and sv(info.treeIDs[1])
    if not treeID then return nil end
    local okg, groups = pcall(TR.GetGroupDisplayInfoByTreeID, treeID)
    if not (okg and type(groups) == "table" and #groups > 0) then return nil end
    table.sort(groups, function(a, b) return (tonumber(a.orderIndex) or 0) < (tonumber(b.orderIndex) or 0) end)
    local ids = {}
    for _, g in ipairs(groups) do if sv(g.groupID) then ids[#ids + 1] = g.groupID end end
    local spent = {}
    local okp, list = pcall(TR.GetGroupCurrencyInfo, configID, ids)
    if okp and type(list) == "table" then
        for _, e in ipairs(list) do
            local n = 0
            for _, c in ipairs(type(e.currencyInfos) == "table" and e.currencyInfos or {}) do n = n + (tonumber(sv(c.spent)) or 0) end
            if sv(e.traitNodeGroupID) then spent[e.traitNodeGroupID] = n end
        end
    end
    local out = {}
    for i, g in ipairs(groups) do
        local name = sv(g.displayName)
        name = name and (L.ALIAS[name] or name)
        if not L.Has(order, name) then name = order[i] end
        if name then out[#out + 1] = { name, spent[g.groupID] or 0 } end
    end
    return #out > 0 and out or nil
end

local function tabPoints(order)
    if not GetTalentTabInfo then return nil end
    local out = {}
    for tab = 1, 3 do
        local res = { pcall(GetTalentTabInfo, tab) }
        if res[1] then
            local name, points
            for i = 2, #res do
                local v = res[i]
                if not name and type(v) == "string" and v ~= "" then name = v
                elseif name and points == nil and type(v) == "number" and v >= 0 and v <= 61 and v == math.floor(v) then points = v end
            end
            name = name and (L.ALIAS[name] or name)
            if not L.Has(order, name) then name = order[tab] end
            if name then out[#out + 1] = { name, points or 0 } end
        end
    end
    return #out > 0 and out or nil
end

function L.TalentSpec(class)
    local order = L.SPECS[class] or {}
    local trees = traitPoints(order) or tabPoints(order)
    local best
    for _, t in ipairs(trees or {}) do
        if t[2] > 0 and (not best or t[2] > best[2]) then best = t end
    end
    return best and best[1] or nil
end
