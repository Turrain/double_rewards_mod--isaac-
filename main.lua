-----------------------------
-- Double Rewards Mod (Offsets + UniqueRoomID + Reset per run)
-----------------------------
local mod = RegisterMod("DoubleRewardsMod", 1)
local game = Game()
local json = require("json")

-----------------------------
-- Настройки
-----------------------------
local settings = {
    extraTreasureItems = 2,  -- сколько дополнительных предметов в Treasure Room
    extraBossItems     = 2,  -- сколько дополнительных предметов после босса
    treasureRadius     = 60, -- радиус разброса предметов в Treasure Room
    bossRadius         = 70, -- радиус разброса предметов в Boss Room
}

-----------------------------
-- Таблица для отметок "здесь уже спавнили доп. предметы"
-- Сбрасывается при начале нового рана
-----------------------------
local SpawnedRooms = {}

-----------------------------
-- Сохранение / Загрузка настроек и данных о комнатах
-----------------------------
local function SaveSettings()
    local dataToSave = {
        settings = settings,
        rooms    = SpawnedRooms
    }
    local ok, encoded = pcall(function()
        return json.encode(dataToSave)
    end)
    if ok then
        mod:SaveData(encoded)
    else
        Isaac.DebugString("DoubleRewardsMod: Ошибка кодирования JSON!")
    end
end

local function LoadSettings()
    if not mod:HasData() then return end

    local raw = mod:LoadData()
    local ok, decoded = pcall(function()
        return json.decode(raw)
    end)
    if ok and type(decoded) == "table" then
        -- Восстанавливаем настройки
        if type(decoded.settings) == "table" then
            for k, v in pairs(decoded.settings) do
                if settings[k] ~= nil then
                    settings[k] = v
                end
            end
        end
        -- Восстанавливаем список комнат
        if type(decoded.rooms) == "table" then
            SpawnedRooms = decoded.rooms
        end
    else
        Isaac.DebugString("DoubleRewardsMod: Ошибка декодирования JSON!")
    end
end

-----------------------------
-- Функция генерирует уникальный идентификатор комнаты
-- Учитывая этаж, индекс комнаты, seed комнаты и т.п.
-----------------------------
local function GetUniqueRoomID()
    local level    = game:GetLevel()
    local stage    = level:GetStage()
    local desc     = level:GetCurrentRoomDesc()
    local roomID   = desc and desc.RoomID or 0
    local safeIdx  = desc and desc.SafeGridIndex or 0
    local roomSeed = desc and desc.SpawnSeed or 0

    return string.format("%d-%d-%d-%d", stage, safeIdx, roomID, roomSeed)
end

-----------------------------
-- Локальные флаги на случай,
-- если надо предотвратить повторный спавн
-- в момент одного и того же входа в комнату
-----------------------------
local hasSpawnedTreasureItem = false
local hasSpawnedBossItem     = false

-----------------------------
-- При запуске или продолжении игры
-- загружаем данные. 
-- Если это НОВЫЙ забег (isContinued == false),
-- сбрасываем SpawnedRooms.
-----------------------------
function mod:onGameStart(isContinued)
    -- Сначала загружаем (чтобы вернуть настройки и прошлые данные)
    LoadSettings()
    -- Если это действительно новый ран (а не Continue),
    -- сбрасываем SpawnedRooms, чтобы в новом забеге 
    -- предметы опять спавнились заново
    if not isContinued then
        SpawnedRooms = {}
    end
end
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.onGameStart)

-----------------------------
-- Сохраняем данные при выходе из игры
-----------------------------
function mod:onPreGameExit()
    SaveSettings()
end
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, mod.onPreGameExit)

-----------------------------
-- Обработчик "Новая комната"
-----------------------------
function mod:onNewRoom()
    local room = game:GetRoom()
    local roomType = room:GetType()

    -- Сбрасываем флаги на случай,
    -- если несколько событий в одной комнате
    hasSpawnedTreasureItem = false
    hasSpawnedBossItem     = false

    -- Если это Treasure Room, пытаемся спавнить (если ещё не спавнили)
    if roomType == RoomType.ROOM_TREASURE then
        mod:trySpawnTreasure(room)
    end
end
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.onNewRoom)

-----------------------------
-- Спавним предметы в Treasure Room
-- С оффсетом по кругу
-----------------------------
function mod:trySpawnTreasure(room)
    if hasSpawnedTreasureItem then
        return
    end

    local roomKey = GetUniqueRoomID()
    if SpawnedRooms[roomKey] then
        -- уже спавнили здесь
        return
    end

    hasSpawnedTreasureItem = true

    -- Спавним предметы вокруг центра
    local centerPos = room:GetCenterPos()
    local radius    = settings.treasureRadius
    local count     = settings.extraTreasureItems

    -- Раскладываем их по окружности
    for i = 1, count do
        local angle = (2 * math.pi / count) * (i - 1)
        local offset = Vector(
            radius * math.cos(angle),
            radius * math.sin(angle)
        )
        local spawnPos = room:FindFreePickupSpawnPosition(centerPos + offset, 0, true)
        Isaac.Spawn(EntityType.ENTITY_PICKUP,
                    PickupVariant.PICKUP_COLLECTIBLE,
                    0,
                    spawnPos,
                    Vector(0, 0),
                    nil)
    end

    -- Помечаем комнату
    SpawnedRooms[roomKey] = true
    SaveSettings()
end

-----------------------------
-- Когда умирает NPC
-- Если это босс в Boss Room, пытаемся спавнить
-----------------------------
function mod:onBossDeath(npc)
    if not npc:IsBoss() then return end

    local room = game:GetRoom()
    if room:GetType() ~= RoomType.ROOM_BOSS then
        return
    end
    if hasSpawnedBossItem then
        return
    end

    local roomKey = GetUniqueRoomID()
    if SpawnedRooms[roomKey] then
        return
    end

    hasSpawnedBossItem = true

    -- Спавним предметы вокруг центра, с оффсетом
    local centerPos = room:GetCenterPos()
    local radius    = settings.bossRadius
    local count     = settings.extraBossItems

    for i = 1, count do
        local angle = (2 * math.pi / count) * (i - 1)
        local offset = Vector(
            radius * math.cos(angle),
            radius * math.sin(angle)
        )
        local spawnPos = room:FindFreePickupSpawnPosition(centerPos + offset, 0, true)
        Isaac.Spawn(EntityType.ENTITY_PICKUP,
                    PickupVariant.PICKUP_COLLECTIBLE,
                    0,
                    spawnPos,
                    Vector(0, 0),
                    nil)
    end

    SpawnedRooms[roomKey] = true
    SaveSettings()
end
mod:AddCallback(ModCallbacks.MC_POST_NPC_DEATH, mod.onBossDeath)

-----------------------------
-- (Необязательно) простой пример MCM
-----------------------------
local function SetupMCM()
    if not ModConfigMenu then return end

    local cat = "Double Rewards (Offsets)"
    ModConfigMenu.AddTitle(cat, nil, "Double Rewards Mod")
    ModConfigMenu.AddText(cat, nil, "Spawns offset items. Resets per new run.")

    -- Пример настройки количества предметов в Treasure Room
    ModConfigMenu.AddSetting(cat, nil, {
        Type = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return settings.extraTreasureItems end,
        Minimum = 0,
        Maximum = 6,
        Display = function() return "Extra Treasure Items: " .. tostring(settings.extraTreasureItems) end,
        OnChange = function(val)
            settings.extraTreasureItems = val
            SaveSettings()
        end,
        Info = {"Сколько дополнительных предметов будет в Treasure Room?"}
    })

    ModConfigMenu.AddSetting(cat, nil, {
        Type = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return settings.treasureRadius end,
        Minimum = 20,
        Maximum = 120,
        Display = function() return "Treasure Radius: " .. tostring(settings.treasureRadius) end,
        OnChange = function(val)
            settings.treasureRadius = val
            SaveSettings()
        end,
        Info = {"Радиус разброса предметов в Treasure Room."}
    })

    ModConfigMenu.AddSpace(cat, nil)

    -- Пример настройки количества предметов в Boss Room
    ModConfigMenu.AddSetting(cat, nil, {
        Type = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return settings.extraBossItems end,
        Minimum = 0,
        Maximum = 6,
        Display = function() return "Extra Boss Items: " .. tostring(settings.extraBossItems) end,
        OnChange = function(val)
            settings.extraBossItems = val
            SaveSettings()
        end,
        Info = {"Сколько дополнительных предметов будет после босса?"}
    })

    ModConfigMenu.AddSetting(cat, nil, {
        Type = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return settings.bossRadius end,
        Minimum = 20,
        Maximum = 150,
        Display = function() return "Boss Radius: " .. tostring(settings.bossRadius) end,
        OnChange = function(val)
            settings.bossRadius = val
            SaveSettings()
        end,
        Info = {"Радиус разброса предметов в Boss Room."}
    })
end

function mod:onPlayerInit(_)
    -- Чтобы не создавать повторно меню каждый раз при новом заходе
    if mod._mcmInitialized then return end
    mod._mcmInitialized = true
    SetupMCM()
end
mod:AddCallback(ModCallbacks.MC_POST_PLAYER_INIT, mod.onPlayerInit)
