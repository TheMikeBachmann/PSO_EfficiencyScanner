local core_mainmenu  = require("core_mainmenu")
local lib_helpers    = require("solylib.helpers")
local lib_items_list = require("solylib.items.items_list")
local lib_level_exp  = require("Efficiency Scanner.level_exp")
local cfg            = require("Efficiency Scanner.configuration")
local optionsLoaded, options = pcall(require, "Efficiency Scanner.options")
local historyLoaded, savedHistory = pcall(require, "Efficiency Scanner.history")

local optionsFileName  = "addons/Efficiency Scanner/options.lua"
local historyFileName  = "addons/Efficiency Scanner/history.lua"
local firstPresent = true
local sessionInitialized = false
local ConfigurationWindow

-- Memory addresses
local _PlayerArray       = 0x00A94254
local _MyPlayerIndex     = 0x00A9C4F4
local _OffsetExp         = 0xE48
local _CurrentFloor      = 0xAAFCA0
local _Difficulty        = 0x00A9CD68
local _ItemArrayPtr      = 0x00A8D81C
local _ItemArrayCount    = 0x00A8D820
local _QuestPtrRoot      = 0x00A95AA8  -- non-zero when a quest is loaded

-- Floor names derived from newserv StaticGameData floor table
local floorNames = {
    [0x00] = "Pioneer 2",
    [0x01] = "Forest 1",       [0x02] = "Forest 2",
    [0x03] = "Caves 1",        [0x04] = "Caves 2",        [0x05] = "Caves 3",
    [0x06] = "Mines 1",        [0x07] = "Mines 2",
    [0x08] = "Ruins 1",        [0x09] = "Ruins 2",        [0x0A] = "Ruins 3",
    [0x0B] = "Dragon",         [0x0C] = "De Rol Le",
    [0x0D] = "Vol Opt",        [0x0E] = "Dark Falz",
    [0x0F] = "Lobby",          [0x10] = "Battle Stage 1", [0x11] = "Battle Stage 2",
    [0x12] = "Pioneer 2",
    [0x13] = "VR Temple Alpha",    [0x14] = "VR Temple Beta",
    [0x15] = "VR Spaceship Alpha", [0x16] = "VR Spaceship Beta",
    [0x17] = "Central Control Area",
    [0x18] = "Jungle North",   [0x19] = "Jungle South",
    [0x1A] = "Mountain",       [0x1B] = "Seaside",
    [0x1C] = "Seabed Upper",   [0x1D] = "Seabed Lower",
    [0x1E] = "Gal Gryphon",    [0x1F] = "Olga Flow",
    [0x20] = "Barba Ray",      [0x21] = "Gol Dragon",
    [0x22] = "Spaceship",      [0x23] = "Control Tower",
    [0x24] = "Pioneer 2",
    [0x25] = "Crater Route 1", [0x26] = "Crater Route 2",
    [0x27] = "Crater Route 3", [0x28] = "Crater Route 4",
    [0x29] = "Crater Interior",
    [0x2A] = "Desert 1",       [0x2B] = "Desert 2",       [0x2C] = "Desert 3",
    [0x2D] = "Saint-Milion",
}

local floorAbbrev = {
    [0x01] = "F1",  [0x02] = "F2",
    [0x03] = "C1",  [0x04] = "C2",  [0x05] = "C3",
    [0x06] = "M1",  [0x07] = "M2",
    [0x08] = "R1",  [0x09] = "R2",  [0x0A] = "R3",
    [0x0B] = "DRG", [0x0C] = "DRL", [0x0D] = "VO",  [0x0E] = "DF",
    [0x13] = "VTa", [0x14] = "VTb",
    [0x15] = "VSa", [0x16] = "VSb",
    [0x17] = "CCA",
    [0x18] = "JN",  [0x19] = "JS",
    [0x1A] = "MTN", [0x1B] = "SEA",
    [0x1C] = "SBU", [0x1D] = "SBL",
    [0x1E] = "GG",  [0x1F] = "OF",
    [0x20] = "BR",  [0x21] = "GD",
    [0x22] = "SP",  [0x23] = "TWR",
    [0x25] = "CR1", [0x26] = "CR2", [0x27] = "CR3", [0x28] = "CR4",
    [0x29] = "CRI",
    [0x2A] = "D1",  [0x2B] = "D2",  [0x2C] = "D3",
    [0x2D] = "SM",
}

-- Floors that count as "not in a quest" for session tracking
local pioneerTwoFloors = {
    [0x00] = true,
    [0x0F] = true,
    [0x12] = true,
    [0x24] = true,
}

local STATE_IDLE        = "IDLE"
local STATE_ACTIVE      = "ACTIVE"
local STATE_PENDING_END = "PENDING_END"
local STATE_COMPLETE    = "COMPLETE"

local PENDING_END_TIMEOUT_MS = 180000  -- 3 minutes

local session = {
    state            = STATE_IDLE,
    questName        = "",
    startTick        = 0,
    endTick          = 0,
    startExp         = 0,
    expGained        = 0,
    elapsedMs        = 0,
    currentFloor     = 0,
    prevFloor        = 0,
    lastEarnedFloor  = 0,
    pendingEndTick   = 0,
    endReason        = "complete",
    difficulty       = 0,
    playerCount      = 1,
    drops            = { techCount = 0, hitCount = 0, rareCount = 0 },
    seenDropIds      = {},
    lastDropScanTick = 0,
}

-- Graph data — sampled every 10s, capped at 120 points (~20 min of history)
local graph = {
    sampleIntervalMs  = 10000,
    maxSamples        = 120,
    lastSampleTick    = 0,
    lastSampleExp     = 0,
    rateData          = {},    -- EXP/hr per sample interval
    cumulativeData    = {},    -- total EXP gained per sample interval
    floorValues       = {},    -- EXP gained per floor visit
    floorLabels       = {},    -- full floor name per visit
    floorIds          = {},    -- floor number per visit (for abbreviations)
    lastFloorExp      = 0,
    dropTechData      = {},    -- cumulative tech drop count per sample
    dropHitData       = {},    -- cumulative hit drop count per sample
    dropRareData      = {},    -- cumulative rare drop count per sample
    floorDropTech     = {},    -- tech drops per floor visit
    floorDropHit      = {},    -- hit drops per floor visit
    floorDropRare     = {},    -- rare drops per floor visit
    lastFloorDropTech = 0,
    lastFloorDropHit  = 0,
    lastFloorDropRare = 0,
}

local graphModeNames = {
    "EXP/hr Rate", "Cumulative EXP", "EXP per Floor",
    "Drops over Time", "Drops per Floor", "Drop Breakdown",
}
local difficultyAbbrev   = {"Norm", "Hard", "VH", "Ult"}
local historySort        = 1
local historySortNames   = { "Recent", "Name", "EXP", "EXP/hr" }

local MAX_HISTORY    = 50
local sessionHistory = {}
if historyLoaded and type(savedHistory) == "table" then
    sessionHistory = savedHistory
    while table.getn(sessionHistory) > MAX_HISTORY do
        table.remove(sessionHistory)
    end
end

-- Options
if optionsLoaded then
    if options == nil or type(options) ~= "table" then
        options = {}
    end
    options.configurationEnableWindow = lib_helpers.NotNilOrDefault(options.configurationEnableWindow, true)
    options.enable                    = lib_helpers.NotNilOrDefault(options.enable, true)
    options.windowX                   = lib_helpers.NotNilOrDefault(options.windowX, 100)
    options.windowY                   = lib_helpers.NotNilOrDefault(options.windowY, 100)
    options.windowW                   = lib_helpers.NotNilOrDefault(options.windowW, 310)
    options.windowH                   = lib_helpers.NotNilOrDefault(options.windowH, 190)
    options.windowAnchor              = lib_helpers.NotNilOrDefault(options.windowAnchor, 1)
    options.windowChanged             = lib_helpers.NotNilOrDefault(options.windowChanged, false)
    options.windowNoTitleBar          = lib_helpers.NotNilOrDefault(options.windowNoTitleBar, "")
    options.windowNoResize            = lib_helpers.NotNilOrDefault(options.windowNoResize, "")
    options.windowNoMove              = lib_helpers.NotNilOrDefault(options.windowNoMove, "")
    options.windowTransparent         = lib_helpers.NotNilOrDefault(options.windowTransparent, false)
    options.windowAlwaysAutoResize    = lib_helpers.NotNilOrDefault(options.windowAlwaysAutoResize, "AlwaysAutoResize")
    options.lastQuestName             = lib_helpers.NotNilOrDefault(options.lastQuestName, "")
    options.graphMode                 = lib_helpers.NotNilOrDefault(options.graphMode, 1)
    options.dropTechLevel             = lib_helpers.NotNilOrDefault(options.dropTechLevel, 20)
    options.dropHitPercent            = lib_helpers.NotNilOrDefault(options.dropHitPercent, 30)
    options.dropRareEnabled           = lib_helpers.NotNilOrDefault(options.dropRareEnabled, true)
    options.dropCountPlayerDrops      = lib_helpers.NotNilOrDefault(options.dropCountPlayerDrops, false)
else
    options =
    {
        configurationEnableWindow = true,
        enable = true,
        windowX = 100,
        windowY = 100,
        windowW = 310,
        windowH = 190,
        windowAnchor = 1,
        windowChanged = false,
        windowNoTitleBar = "",
        windowNoResize = "",
        windowNoMove = "",
        windowTransparent = false,
        windowAlwaysAutoResize = "AlwaysAutoResize",
        lastQuestName   = "",
        graphMode       = 1,
        dropTechLevel        = 20,
        dropHitPercent       = 30,
        dropRareEnabled      = true,
        dropCountPlayerDrops = false,
    }
end

local function SaveOptions()
    local file = io.open(optionsFileName, "w")
    if file ~= nil then
        io.output(file)
        io.write("return\n{\n")
        io.write(string.format("    configurationEnableWindow = %s,\n",  tostring(options.configurationEnableWindow)))
        io.write(string.format("    enable = %s,\n",                     tostring(options.enable)))
        io.write(string.format("    windowX = %i,\n",                    options.windowX))
        io.write(string.format("    windowY = %i,\n",                    options.windowY))
        io.write(string.format("    windowW = %i,\n",                    options.windowW))
        io.write(string.format("    windowH = %i,\n",                    options.windowH))
        io.write(string.format("    windowAnchor = %i,\n",               options.windowAnchor))
        io.write(string.format("    windowChanged = %s,\n",              tostring(options.windowChanged)))
        io.write(string.format("    windowNoTitleBar = \"%s\",\n",       options.windowNoTitleBar))
        io.write(string.format("    windowNoResize = \"%s\",\n",         options.windowNoResize))
        io.write(string.format("    windowNoMove = \"%s\",\n",           options.windowNoMove))
        io.write(string.format("    windowTransparent = %s,\n",          tostring(options.windowTransparent)))
        io.write(string.format("    windowAlwaysAutoResize = \"%s\",\n", options.windowAlwaysAutoResize))
        io.write(string.format("    lastQuestName = %q,\n",              options.lastQuestName))
        io.write(string.format("    graphMode = %i,\n",                  options.graphMode))
        io.write(string.format("    dropTechLevel = %i,\n",              options.dropTechLevel))
        io.write(string.format("    dropHitPercent = %i,\n",             options.dropHitPercent))
        io.write(string.format("    dropRareEnabled = %s,\n",            tostring(options.dropRareEnabled)))
        io.write(string.format("    dropCountPlayerDrops = %s,\n",       tostring(options.dropCountPlayerDrops)))
        io.write("}\n")
        io.close(file)
    end
end

local function SaveHistory()
    local file = io.open(historyFileName, "w")
    if file == nil then return end
    io.output(file)
    io.write("return\n{\n")
    for _, r in ipairs(sessionHistory) do
        io.write("    {\n")
        io.write(string.format("        questName   = %q,\n",  r.questName))
        io.write(string.format("        elapsedMs   = %i,\n",  r.elapsedMs))
        io.write(string.format("        expGained   = %i,\n",  r.expGained))
        io.write(string.format("        expPerHour  = %i,\n",  r.expPerHour))
        io.write(string.format("        endReason    = %q,\n",  r.endReason))
        io.write(string.format("        endFloor     = %i,\n",  r.endFloor or 0))
        io.write(string.format("        difficulty   = %q,\n",  r.difficulty))
        io.write(string.format("        playerCount  = %i,\n",  r.playerCount))
        io.write(string.format("        timestamp    = %i,\n",  r.timestamp or 0))
        local d = r.drops or {}
        io.write(string.format("        drops = { techCount=%i, hitCount=%i, rareCount=%i },\n",
            d.techCount or 0, d.hitCount or 0, d.rareCount or 0))
        io.write("    },\n")
    end
    io.write("}\n")
    io.close(file)
end

local function GetPlayerBase()
    local myIndex = pso.read_u32(_MyPlayerIndex)
    return pso.read_u32(_PlayerArray + myIndex * 4)
end

local function GetCurrentExp()
    local base = GetPlayerBase()
    if base == 0 then return 0 end
    return pso.read_u32(base + _OffsetExp)
end

local function GetCurrentLevel()
    local base = GetPlayerBase()
    if base == 0 then return 0 end
    local ok, lv = pcall(pso.read_u32, base + 0xE44)
    return ok and (lv + 1) or 0
end

local function GetLevelInfo()
    local level = GetCurrentLevel()
    if level < 1 or level >= 200 then return nil, nil end
    local xpForLevel = lib_level_exp[level + 1] - lib_level_exp[level]
    if xpForLevel <= 0 or session.expGained <= 0 then return nil, nil end
    local pct = session.expGained / xpForLevel * 100
    local xpRemaining = lib_level_exp[level + 1] - (session.startExp + session.expGained)
    local runs = xpRemaining > 0 and math.ceil(xpRemaining / session.expGained) or 0
    return pct, runs
end

local function PresentLevelInfo()
    local pct, runs = GetLevelInfo()
    if not pct then return end
    if runs > 0 then
        imgui.Text(string.format("  %.1f%% of current lvl  (~%d runs)", pct, runs))
    else
        imgui.Text(string.format("  %.1f%% of current lvl", pct))
    end
end

local function GetDifficulty()
    local ok, val = pcall(pso.read_u32, _Difficulty)
    if ok and val >= 0 and val <= 3 then return val end
    return 0
end

local function GetPlayerCount()
    local count = 0
    local ok = pcall(function()
        for i = 0, 3 do
            if pso.read_u32(_PlayerArray + i * 4) ~= 0 then
                count = count + 1
            end
        end
    end)
    return (ok and count > 0) and count or 1
end

local function GetCurrentFloor()
    return pso.read_u32(_CurrentFloor)
end

local function IsOnPioneerTwo(floor)
    return pioneerTwoFloors[floor] == true
end

local function FloorName(floor)
    return floorNames[floor] or string.format("Unknown (0x%02X)", floor)
end

local function FloorAbbrev(floor)
    return floorAbbrev[floor] or string.format("%02X", floor)
end

local function FormatTime(ms)
    local h = math.floor(ms / 3600000)
    local m = math.floor(ms / 60000) % 60
    local s = math.floor(ms / 1000) % 60
    return string.format("%02d:%02d:%02d", h, m, s)
end

local function FormatNumber(n)
    local s = tostring(math.floor(n))
    local result = ""
    local len = string.len(s)
    for i = 1, len do
        if i > 1 and (len - i + 1) % 3 == 0 then
            result = result .. ","
        end
        result = result .. string.sub(s, i, i)
    end
    return result
end

local function FormatNumberShort(n)
    n = math.floor(n)
    if n >= 1000000 then
        return string.format("%.1fM", n / 1000000)
    elseif n >= 1000 then
        return string.format("%.1fk", n / 1000)
    else
        return tostring(n)
    end
end

local function CalcExpPerHour(expGained, elapsedMs)
    if elapsedMs < 1000 then return 0 end
    return math.floor(expGained * 3600000 / elapsedMs)
end


local function ResetGraph()
    graph.lastSampleTick    = 0
    graph.lastSampleExp     = 0
    graph.rateData          = {}
    graph.cumulativeData    = {}
    graph.floorValues       = {}
    graph.floorLabels       = {}
    graph.floorIds          = {}
    graph.lastFloorExp      = 0
    graph.dropTechData      = {}
    graph.dropHitData       = {}
    graph.dropRareData      = {}
    graph.floorDropTech     = {}
    graph.floorDropHit      = {}
    graph.floorDropRare     = {}
    graph.lastFloorDropTech = 0
    graph.lastFloorDropHit  = 0
    graph.lastFloorDropRare = 0
end

local function SampleGraph()
    local tick = pso.get_tick_count()

    if graph.lastSampleTick == 0 then
        graph.lastSampleTick = tick
        return
    end

    local timeDelta = tick - graph.lastSampleTick
    if timeDelta < graph.sampleIntervalMs then
        return
    end

    local expDelta = session.expGained - graph.lastSampleExp
    local rate     = CalcExpPerHour(expDelta, timeDelta)

    if table.getn(graph.rateData) >= graph.maxSamples then
        table.remove(graph.rateData, 1)
    end
    table.insert(graph.rateData, rate)

    if table.getn(graph.cumulativeData) >= graph.maxSamples then
        table.remove(graph.cumulativeData, 1)
    end
    table.insert(graph.cumulativeData, session.expGained)

    if table.getn(graph.dropTechData) >= graph.maxSamples then
        table.remove(graph.dropTechData, 1)
    end
    table.insert(graph.dropTechData, session.drops.techCount)

    if table.getn(graph.dropHitData) >= graph.maxSamples then
        table.remove(graph.dropHitData, 1)
    end
    table.insert(graph.dropHitData, session.drops.hitCount)

    if table.getn(graph.dropRareData) >= graph.maxSamples then
        table.remove(graph.dropRareData, 1)
    end
    table.insert(graph.dropRareData, session.drops.rareCount)

    graph.lastSampleTick = tick
    graph.lastSampleExp  = session.expGained
end

local function RecordFloorExit(floor)
    local expOnFloor = session.expGained - graph.lastFloorExp
    table.insert(graph.floorValues, expOnFloor)
    table.insert(graph.floorLabels, FloorName(floor))
    table.insert(graph.floorIds, floor)
    graph.lastFloorExp = session.expGained

    table.insert(graph.floorDropTech, session.drops.techCount - graph.lastFloorDropTech)
    table.insert(graph.floorDropHit,  session.drops.hitCount  - graph.lastFloorDropHit)
    table.insert(graph.floorDropRare, session.drops.rareCount - graph.lastFloorDropRare)
    graph.lastFloorDropTech = session.drops.techCount
    graph.lastFloorDropHit  = session.drops.hitCount
    graph.lastFloorDropRare = session.drops.rareCount
end

local function PreloadInventoryIds()
    local ok, count = pcall(pso.read_u32, _ItemArrayCount)
    if not ok or count == 0 or count > 1024 then return end
    local ok0, itemArray = pcall(pso.read_u32, _ItemArrayPtr)
    if not ok0 or itemArray == 0 then return end
    local playerIdx = pso.read_u32(_MyPlayerIndex)
    for i = 0, count - 1 do
        local ok2, entity = pcall(pso.read_u32, itemArray + i * 4)
        if ok2 and entity ~= 0 then
            local ok3, owner = pcall(pso.read_i8, entity + 0xE4)
            if ok3 and owner == playerIdx then
                local ok4, itemId = pcall(pso.read_u32, entity + 0xD8)
                if ok4 and itemId ~= 0 then
                    session.seenDropIds[itemId] = true
                end
            end
        end
    end
end

local function ReadQuestName()
    local ok1, root = pcall(pso.read_u32, _QuestPtrRoot)
    if not ok1 or root == 0 then return nil end
    local ok2, header = pcall(pso.read_u32, root + 0x19C)
    if not ok2 or header == 0 then return nil end
    local ok3, name = pcall(pso.read_wstr, header + 0x18, 32)
    if not ok3 or name == nil or name == "" then return nil end
    return name
end

local function StartSession()
    local exp          = GetCurrentExp()
    session.state      = STATE_ACTIVE
    session.startTick  = pso.get_tick_count()
    session.endTick    = 0
    session.startExp   = exp
    session.expGained  = 0
    session.elapsedMs  = 0
    session.endReason        = "complete"
    session.difficulty       = GetDifficulty()
    session.playerCount      = GetPlayerCount()
    session.drops            = { techCount = 0, hitCount = 0, rareCount = 0 }
    session.seenDropIds      = {}
    session.lastDropScanTick = 0
    session.lastEarnedFloor  = session.currentFloor
    if not options.dropCountPlayerDrops then
        PreloadInventoryIds()
    end
    local autoName = ReadQuestName()
    if autoName then
        session.questName = autoName
    end
    ResetGraph()
    options.lastQuestName = session.questName
    SaveOptions()
end

local function EndSession()
    session.state     = STATE_COMPLETE
    session.endTick   = pso.get_tick_count()
    session.elapsedMs = session.endTick - session.startTick

    local finalExp = GetCurrentExp()
    if finalExp >= session.startExp then
        session.expGained = finalExp - session.startExp
    end

    -- Flush remaining exp and drops on the last quest floor
    local expOnLastFloor = session.expGained - graph.lastFloorExp
    if expOnLastFloor > 0 or table.getn(graph.floorValues) > 0 then
        table.insert(graph.floorValues, expOnLastFloor)
        table.insert(graph.floorLabels, FloorName(session.prevFloor))
        table.insert(graph.floorIds, session.prevFloor)
        table.insert(graph.floorDropTech, session.drops.techCount - graph.lastFloorDropTech)
        table.insert(graph.floorDropHit,  session.drops.hitCount  - graph.lastFloorDropHit)
        table.insert(graph.floorDropRare, session.drops.rareCount - graph.lastFloorDropRare)
    end

    -- Final time-series sample to close the graph
    if graph.lastSampleTick > 0 then
        local timeDelta = session.endTick - graph.lastSampleTick
        if timeDelta > 0 then
            local expDelta = session.expGained - graph.lastSampleExp
            local rate     = CalcExpPerHour(expDelta, timeDelta)
            table.insert(graph.rateData, rate)
            table.insert(graph.cumulativeData, session.expGained)
        end
        table.insert(graph.dropTechData, session.drops.techCount)
        table.insert(graph.dropHitData,  session.drops.hitCount)
        table.insert(graph.dropRareData, session.drops.rareCount)
    end

    -- Push to session history
    local record = {
        questName    = session.questName ~= "" and session.questName or "(unnamed)",
        elapsedMs    = session.elapsedMs,
        expGained    = session.expGained,
        expPerHour   = CalcExpPerHour(session.expGained, session.elapsedMs),
        endReason    = session.endReason,
        endFloor     = session.lastEarnedFloor,
        difficulty   = difficultyAbbrev[session.difficulty + 1] or "?",
        playerCount  = session.playerCount,
        timestamp    = os.time(),
        drops        = {
            techCount = session.drops.techCount,
            hitCount  = session.drops.hitCount,
            rareCount = session.drops.rareCount,
        },
    }
    table.insert(sessionHistory, 1, record)
    if table.getn(sessionHistory) > MAX_HISTORY then
        table.remove(sessionHistory)
    end

    options.lastQuestName = session.questName
    SaveOptions()
    SaveHistory()
end

local function CommitEndSession()
    if session.state == STATE_PENDING_END then
        local now = pso.get_tick_count()
        session.startTick = session.startTick + (now - session.pendingEndTick)
    end
    EndSession()
end

local function ResetSession()
    session.state            = STATE_IDLE
    session.startTick        = 0
    session.endTick          = 0
    session.startExp         = 0
    session.expGained        = 0
    session.elapsedMs        = 0
    session.pendingEndTick   = 0
    session.drops            = { techCount = 0, hitCount = 0, rareCount = 0 }
    session.seenDropIds      = {}
    session.lastDropScanTick = 0
    ResetGraph()
end

local function ClassifyDrop(entity)
    local cat     = pso.read_u8(entity + 0xF2)
    local typ     = pso.read_u8(entity + 0xF3)
    local subtype = pso.read_u8(entity + 0xF4)

    -- Tech disk: tool (3), type byte 2 = technique
    -- data[3] at +0xF4 is level-1; technique identity is stored separately at +0x108
    if cat == 3 and typ == 2 then
        local level = pso.read_u8(entity + 0xF4) + 1
        if level >= options.dropTechLevel then
            session.drops.techCount = session.drops.techCount + 1
        end
    end

    -- Weapon hit%: 3 attribute pairs at _ItemWepStats = 0x1C8 (type, value bytes interleaved)
    if cat == 0 then
        for j = 0, 2 do
            local statType  = pso.read_u8(entity + 0x1C8 + j * 2)
            local statValue = pso.read_u8(entity + 0x1C9 + j * 2)
            if statType == 5 and statValue >= options.dropHitPercent then
                session.drops.hitCount = session.drops.hitCount + 1
                break
            end
        end
    end

    -- Rare: look up hex ID in solylib items list; COLOR_RARE = 0xFFFF0000 (red)
    if options.dropRareEnabled then
        local hex   = cat * 0x10000 + typ * 0x100 + subtype
        local entry = lib_items_list.t[hex]
        if entry and entry[1] == 0xFFFF0000 then
            session.drops.rareCount = session.drops.rareCount + 1
        end
    end
end

local function ScanDrops()
    local tick = pso.get_tick_count()
    if tick - session.lastDropScanTick < 200 then return end
    session.lastDropScanTick = tick

    local ok, count = pcall(pso.read_u32, _ItemArrayCount)
    if not ok or count == 0 or count > 1024 then return end

    local ok0, itemArray = pcall(pso.read_u32, _ItemArrayPtr)
    if not ok0 or itemArray == 0 then return end

    for i = 0, count - 1 do
        local ok2, entity = pcall(pso.read_u32, itemArray + i * 4)
        if ok2 and entity ~= 0 then
            local ok3, owner = pcall(pso.read_i8, entity + 0xE4)
            if ok3 and owner == -1 then
                local ok4, itemId = pcall(pso.read_u32, entity + 0xD8)
                if ok4 and itemId ~= 0 and not session.seenDropIds[itemId] then
                    session.seenDropIds[itemId] = true
                    pcall(ClassifyDrop, entity)
                end
            end
        end
    end
end

local function UpdateSession()
    local floor = GetCurrentFloor()

    if not sessionInitialized then
        sessionInitialized   = true
        session.prevFloor    = floor
        session.currentFloor = floor
        return
    end

    session.prevFloor    = session.currentFloor
    session.currentFloor = floor

    if session.state == STATE_IDLE then
        if not IsOnPioneerTwo(floor) and IsOnPioneerTwo(session.prevFloor) then
            StartSession()
        end

    elseif session.state == STATE_ACTIVE then
        local tick        = pso.get_tick_count()
        session.elapsedMs = tick - session.startTick

        local exp = GetCurrentExp()
        if exp >= session.startExp then
            local newExpGained = exp - session.startExp
            if newExpGained > session.expGained then
                session.lastEarnedFloor = floor
            end
            session.expGained = newExpGained
        end

        if floor ~= session.prevFloor and not IsOnPioneerTwo(session.prevFloor) then
            RecordFloorExit(session.prevFloor)
        end

        SampleGraph()
        ScanDrops()

        if IsOnPioneerTwo(floor) and not IsOnPioneerTwo(session.prevFloor) then
            if floor == 0x0F then
                -- Lobby means $exit command — end immediately
                session.endReason = "exit"
                EndSession()
            else
                session.state          = STATE_PENDING_END
                session.pendingEndTick = pso.get_tick_count()
            end
        end

    elseif session.state == STATE_PENDING_END then
        local tick = pso.get_tick_count()

        if not IsOnPioneerTwo(floor) then
            -- Skew startTick forward so town time is excluded from all future calculations
            session.startTick      = session.startTick + (tick - session.pendingEndTick)
            session.pendingEndTick = 0
            session.state          = STATE_ACTIVE
        elseif tick - session.pendingEndTick >= PENDING_END_TIMEOUT_MS then
            CommitEndSession()
        end
    end
end


-- Returns table of labeled floor abbreviations; duplicates get ".1"/".2"/etc. suffixes
local function FloorLegendParts(ids, count)
    local seen, isDupe = {}, {}
    for i = 1, count do
        local id = ids[i]
        if seen[id] then isDupe[id] = true end
        seen[id] = true
    end
    local parts, counter = {}, {}
    for i = 1, count do
        local id   = ids[i]
        local abbr = FloorAbbrev(id)
        if isDupe[id] then
            counter[id] = (counter[id] or 0) + 1
            abbr = abbr .. "." .. counter[id]
        end
        table.insert(parts, abbr)
    end
    return parts
end

local function PresentGraph()
    local modeCount = table.getn(graphModeNames)

    if imgui.Button("<##gmode_ES") then
        options.graphMode = options.graphMode > 1 and options.graphMode - 1 or modeCount
        SaveOptions()
    end
    imgui.SameLine()
    imgui.Text(graphModeNames[options.graphMode])
    imgui.SameLine()
    if imgui.Button(">##gmode_ES") then
        options.graphMode = options.graphMode < modeCount and options.graphMode + 1 or 1
        SaveOptions()
    end

    local graphW = imgui.GetWindowWidth() - 16
    local graphH = 80

    if options.graphMode == 1 then
        local data      = graph.rateData
        local dataCount = table.getn(data)
        if dataCount >= 2 then
            local maxVal = 1
            for i = 1, dataCount do
                if data[i] > maxVal then maxVal = data[i] end
            end
            local overlay = "Now: " .. FormatNumber(data[dataCount]) .. "/hr"
            imgui.PlotLines("##rategraph_ES", data, dataCount, 0, overlay, 0.0, maxVal * 1.1, graphW, graphH)
        else
            imgui.Text("Collecting data... (samples every 10s)")
        end

    elseif options.graphMode == 2 then
        local data      = graph.cumulativeData
        local dataCount = table.getn(data)
        if dataCount >= 2 then
            local maxVal  = data[dataCount] > 0 and data[dataCount] or 1
            local overlay = FormatNumber(data[dataCount]) .. " EXP"
            imgui.PlotLines("##cumulgraph_ES", data, dataCount, 0, overlay, 0.0, maxVal * 1.1, graphW, graphH)
        else
            imgui.Text("Collecting data... (samples every 10s)")
        end

    elseif options.graphMode == 3 then
        local data      = graph.floorValues
        local dataCount = table.getn(data)
        if dataCount >= 1 then
            local maxVal = 1
            for i = 1, dataCount do
                if data[i] > maxVal then maxVal = data[i] end
            end
            local lastLabel = graph.floorLabels[dataCount] or ""
            local overlay   = lastLabel .. ": " .. FormatNumber(data[dataCount])
            imgui.PlotHistogram("##floorgraph_ES", data, dataCount, 0, overlay, 0.0, maxVal * 1.1, graphW, graphH)

            -- Floor legend: abbreviated names with EXP amounts
            local abbrs = FloorLegendParts(graph.floorIds, dataCount)
            local parts = {}
            for i = 1, dataCount do
                table.insert(parts, abbrs[i] .. ":" .. FormatNumberShort(data[i]))
            end
            imgui.Text(table.concat(parts, "  "))
        else
            imgui.Text("No floor transitions yet")
        end

    elseif options.graphMode == 4 then
        -- Cumulative drops over time — three stacked line graphs
        local miniH    = 35
        local seriesD  = { graph.dropTechData,  graph.dropHitData,  graph.dropRareData  }
        local curCount = { session.drops.techCount, session.drops.hitCount, session.drops.rareCount }
        local seriesID = { "##droptech_ES",     "##drophit_ES",     "##droprare_ES"     }
        local seriesLbl = {
            "Tech Lv" .. options.dropTechLevel .. "+",
            "Hit " .. options.dropHitPercent .. "%+",
            "Rare",
        }
        for di = 1, 3 do
            local data      = seriesD[di]
            local dataCount = table.getn(data)
            if dataCount >= 2 then
                local maxVal = 1
                for i = 1, dataCount do
                    if data[i] > maxVal then maxVal = data[i] end
                end
                local overlay = seriesLbl[di] .. ": " .. data[dataCount]
                imgui.PlotLines(seriesID[di], data, dataCount, 0, overlay, 0.0, maxVal + 1, graphW, miniH)
            else
                imgui.Text(seriesLbl[di] .. ": " .. curCount[di] .. "  (samples every 10s)")
            end
        end

    elseif options.graphMode == 5 then
        -- Drops per floor — three stacked histograms
        local dataCount = table.getn(graph.floorDropTech)
        if dataCount >= 1 then
            local miniH    = 30
            local seriesD  = { graph.floorDropTech, graph.floorDropHit, graph.floorDropRare }
            local seriesID = { "##fdroptech_ES", "##fdrophit_ES", "##fdroprare_ES" }
            local seriesLbl = { "Tech", "Hit", "Rare" }
            for di = 1, 3 do
                local data   = seriesD[di]
                local maxVal = 1
                for i = 1, dataCount do
                    if data[i] > maxVal then maxVal = data[i] end
                end
                imgui.PlotHistogram(seriesID[di], data, dataCount, 0, seriesLbl[di], 0.0, maxVal + 1, graphW, miniH)
            end
            -- Floor legend
            imgui.Text(table.concat(FloorLegendParts(graph.floorIds, dataCount), "  "))
        else
            imgui.Text("No floor transitions yet")
        end

    elseif options.graphMode == 6 then
        -- Drop category breakdown — single 3-bar histogram
        local breakdown = { session.drops.rareCount, session.drops.hitCount, session.drops.techCount }
        local maxVal    = 1
        for i = 1, 3 do
            if breakdown[i] > maxVal then maxVal = breakdown[i] end
        end
        local total = breakdown[1] + breakdown[2] + breakdown[3]
        imgui.PlotHistogram("##dropbreak_ES", breakdown, 3, 0, "Total: " .. total, 0.0, maxVal + 1, graphW, graphH)
        imgui.Text(string.format("Rare:%d   Hit%d+:%d   Lv%d+:%d",
            breakdown[1], options.dropHitPercent, breakdown[2],
            options.dropTechLevel, breakdown[3]))
    end
end

local HIST_ENTRY_H  = 56   -- 3 text lines + separator
local HIST_MAX_VIS  = 4    -- entries visible before scrolling

local function PresentHistory()
    local count = table.getn(sessionHistory)
    imgui.Separator()
    if count == 0 then
        imgui.Text("No completed runs recorded")
        return
    end

    imgui.Text(string.format("History (%d)", count))
    imgui.SameLine(0, 8)
    if imgui.Button("<##hsort_ES") then
        historySort = historySort == 1 and 4 or historySort - 1
    end
    imgui.SameLine(0, 4)
    imgui.Text(historySortNames[historySort])
    imgui.SameLine(0, 4)
    if imgui.Button(">##hsort_ES") then
        historySort = historySort == 4 and 1 or historySort + 1
    end

    -- Build display order without mutating sessionHistory
    local indices = {}
    for i = 1, count do indices[i] = i end
    if historySort == 2 then
        table.sort(indices, function(a, b)
            return sessionHistory[a].questName < sessionHistory[b].questName
        end)
    elseif historySort == 3 then
        table.sort(indices, function(a, b)
            return (sessionHistory[a].expGained or 0) > (sessionHistory[b].expGained or 0)
        end)
    elseif historySort == 4 then
        table.sort(indices, function(a, b)
            return (sessionHistory[a].expPerHour or 0) > (sessionHistory[b].expPerHour or 0)
        end)
    end

    local childH = math.min(count, HIST_MAX_VIS) * HIST_ENTRY_H
    imgui.BeginChild("##hist_ES", 0, childH, false)
    local deleteIndex = nil
    for pos = 1, count do
        local i = indices[pos]
        local r = sessionHistory[i]
        local name = r.questName
        if string.len(name) > 20 then
            name = string.sub(name, 1, 17) .. "..."
        end
        imgui.Text(string.format("#%d %s", pos, name))
        imgui.SameLine()
        if imgui.Button("x##del_ES_" .. i) then
            deleteIndex = i
        end

        local tag = ""
        if r.endReason == "exit"       then tag = "  [exit]"
        elseif r.endReason == "manual" then tag = "  [stop]"
        end
        local dateStr  = r.timestamp and os.date("%b %d", r.timestamp) or "?"
        local floorStr = r.endFloor and r.endFloor > 0 and FloorAbbrev(r.endFloor) or "?"
        imgui.Text(string.format("  %s  %dP  %s  %s%s",
            r.difficulty or "?",
            r.playerCount or 1,
            dateStr,
            floorStr,
            tag))

        imgui.Text(string.format("  %s  %s/hr",
            FormatTime(r.elapsedMs),
            FormatNumberShort(r.expPerHour)))

        if pos < count then imgui.Separator() end
    end
    imgui.EndChild()

    if deleteIndex then
        table.remove(sessionHistory, deleteIndex)
        SaveHistory()
    end
end

local function PresentMainWindow()
    local changed, newName

    if session.state == STATE_IDLE then
        imgui.Text("Status: Waiting for quest...")
        imgui.Text("Quest Name")
        changed, newName = imgui.InputText("##questname_ES", session.questName, 64)
        if changed then
            session.questName = newName
        end
        if imgui.Button("Start Manually##ES") then
            StartSession()
        end
        PresentHistory()

    elseif session.state == STATE_ACTIVE then
        local expPerHour  = CalcExpPerHour(session.expGained, session.elapsedMs)
        local displayName = session.questName ~= "" and session.questName or "(unnamed)"

        imgui.Text("Quest:  " .. displayName)
        imgui.Text("Area:   " .. FloorName(session.currentFloor))
        imgui.Text(string.format("Diff:   %s / %dP", difficultyAbbrev[session.difficulty + 1] or "?", session.playerCount))
        imgui.Separator()
        imgui.Text("Time:   " .. FormatTime(session.elapsedMs))
        imgui.Text("EXP:    " .. FormatNumber(session.expGained))
        PresentLevelInfo()
        imgui.Text("EXP/hr: " .. FormatNumber(expPerHour))
        imgui.Text(string.format("Drops:  Rare:%d  Hit:%d  Tech:%d",
            session.drops.rareCount, session.drops.hitCount, session.drops.techCount))
        imgui.Separator()
        PresentGraph()
        imgui.Separator()
        imgui.Text("Quest Name")
        changed, newName = imgui.InputText("##questname_ES", session.questName, 64)
        if changed then
            session.questName = newName
        end
        if imgui.Button("Stop Manually##ES") then
            session.endReason = "manual"
            CommitEndSession()
        end

    elseif session.state == STATE_PENDING_END then
        local expPerHour   = CalcExpPerHour(session.expGained, session.elapsedMs)
        local displayName  = session.questName ~= "" and session.questName or "(unnamed)"
        local tick         = pso.get_tick_count()
        local remainingSec = math.max(0, math.ceil((PENDING_END_TIMEOUT_MS - (tick - session.pendingEndTick)) / 1000))

        imgui.Text("In town (telepipe?)")
        imgui.Text(string.format("Auto-completing in %ds", remainingSec))
        imgui.Separator()
        imgui.Text("Quest:  " .. displayName)
        imgui.Text("Time:   " .. FormatTime(session.elapsedMs))
        imgui.Text("EXP:    " .. FormatNumber(session.expGained))
        imgui.Text("EXP/hr: " .. FormatNumber(expPerHour))
        imgui.Separator()
        if imgui.Button("End Now##ES") then
            CommitEndSession()
        end
        imgui.SameLine()
        if imgui.Button("Discard##ES") then
            ResetSession()
        end

    elseif session.state == STATE_COMPLETE then
        local expPerHour  = CalcExpPerHour(session.expGained, session.elapsedMs)
        local displayName = session.questName ~= "" and session.questName or "(unnamed)"

        imgui.Text("-- Quest Complete --")
        imgui.Separator()
        imgui.Text("Quest:  " .. displayName)
        imgui.Text(string.format("Diff:   %s / %dP", difficultyAbbrev[session.difficulty + 1] or "?", session.playerCount))
        imgui.Text("Time:   " .. FormatTime(session.elapsedMs))
        imgui.Text("EXP:    " .. FormatNumber(session.expGained))
        PresentLevelInfo()
        imgui.Text("EXP/hr: " .. FormatNumber(expPerHour))
        imgui.Text(string.format("Drops:  Rare:%d  Hit:%d  Tech:%d",
            session.drops.rareCount, session.drops.hitCount, session.drops.techCount))
        imgui.Separator()
        PresentGraph()
        imgui.Separator()
        if imgui.Button("New Run##ES") then
            ResetSession()
        end
        PresentHistory()
    end
end

local function present()
    if options.configurationEnableWindow then
        ConfigurationWindow.open = true
        options.configurationEnableWindow = false
    end

    ConfigurationWindow.Update()
    if ConfigurationWindow.changed then
        ConfigurationWindow.changed = false
        SaveOptions()
    end

    if options.enable == false then
        return
    end

    UpdateSession()

    if firstPresent or options.windowChanged then
        options.windowChanged = false
        local ps = lib_helpers.GetPosBySizeAndAnchor(
            options.windowX,
            options.windowY,
            options.windowW,
            options.windowH,
            options.windowAnchor)
        imgui.SetNextWindowPos(ps[1], ps[2], "Always")
        if options.windowAlwaysAutoResize ~= "AlwaysAutoResize" then
            imgui.SetNextWindowSize(options.windowW, options.windowH, "Always")
        end
    end

    if options.windowTransparent then
        imgui.PushStyleColor("WindowBg", 0.0, 0.0, 0.0, 0.0)
    end

    if imgui.Begin("Efficiency Scanner", nil,
        {
            options.windowNoTitleBar,
            options.windowNoResize,
            options.windowNoMove,
            options.windowAlwaysAutoResize,
        }
    ) then
        PresentMainWindow()

        -- Track auto-resized height for use in repositioning calculations,
        -- but do NOT force position every frame — that would block window dragging.
        if options.windowAlwaysAutoResize == "AlwaysAutoResize" then
            options.windowH = imgui.GetWindowHeight()
        end
    end
    imgui.End()

    if options.windowTransparent then
        imgui.PopStyleColor()
    end

    if firstPresent then
        firstPresent = false
    end
end

local function init()
    ConfigurationWindow = cfg.ConfigurationWindow(options)
    session.questName = options.lastQuestName

    local function mainMenuButtonHandler()
        ConfigurationWindow.open = not ConfigurationWindow.open
    end

    core_mainmenu.add_button("Efficiency Scanner", mainMenuButtonHandler)

    return
    {
        name        = "Efficiency Scanner",
        version     = "0.3.0",
        author      = "serio",
        description = "Tracks quest efficiency: time, EXP, EXP/hr, and graphs per run",
        present     = present,
        toggleable  = true,
    }
end

return
{
    __addon =
    {
        init = init
    }
}
