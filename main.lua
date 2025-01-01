-----------------------------------
-- Пример: Double Rewards с защитой
-- от повторного спавна предметов
-----------------------------------
local mod = RegisterMod("DoubleRewardsMod", 1)
local game = Game()

-----------------------------------
-- Настройки (пример)
-----------------------------------
local settings = {
    extraTreasureItems = 1,
    extraBossItems     = 1
}

-----------------------------------
-- Таблица, где мы храним "ID комнат"
-- где уже заспавнили предметы
-----------------------------------
local SpawnedRooms = {}
-- А также будем хранить seed активного забега,
-- чтобы знать, не начался ли новый рандомный забег
local currentRunSeed = nil

-----------------------------------
-- JSON для сохранения
-----------------------------------
local json = require("json")

-- Сохранение данных
local function saveData()
    -- Соберём структуру для сохранения
    local dataToSave = {
        settings     = settings,
        spawnedRooms = SpawnedRooms,
        runSeed      = currentRunSeed
    }
    local success, encoded = pcall(function()
        return json.encode(dataToSave)
    end)
    if success then
        mod:SaveData(encoded)
    else
        Isaac.DebugString("DoubleRewardsMod: ошибка при encode!")
    end
end

-- Загрузка данных
local function loadData()
    if not mod:HasData() then return end

    local success, decoded = pcall(function()
        return json.decode(mod:LoadData())
    end)
    if not success or type(decoded) ~= "table" then
        Isaac.DebugString("DoubleRewardsMod: ошибка при decode!")
        return
    end

    -- Проверим ключи
    if type(decoded.settings) == "table" then
        for k, v in pairs(decoded.settings) do
            if settings[k] ~= nil then
                settings[k] = v
            end
        end
    end

    if type(decoded.spawnedRooms) == "table" then
        SpawnedRooms = decoded.spawnedRooms
    end

    if decoded.runSeed ~= nil then
        currentRunSeed = decoded.runSeed
    end
end

-----------------------------------
-- Функция для генерации "Room ID"
-- Учитываем номер этажа, индекс комнаты и т.д.
-----------------------------------
local function getCurrentRoomID()
    local level = game:GetLevel()
    local roomDesc = level:GetCurrentRoomDesc()
    local stage = level:GetStage()
    local roomIndex = roomDesc.SafeGridIndex
    local dimension = roomDesc.Dimension

    -- Можно комбинировать, как угодно. Пример:
    return string.format("stage_%d_dim_%d_idx_%d", stage, dimension, roomIndex)
end

-----------------------------------
-- Инициализация нового (или загруженного) забега
-----------------------------------
function mod:onGameStart(isContinue)
    loadData()

    -- Получим seed текущего забега
    local rng = RNG()
    rng:SetSeed(game:GetSeeds():GetStartSeed(), 1)
    local newSeed = rng:GetSeed()

    -- Если seed отличается (начали новый ран), то сбросим SpawnedRooms
    if currentRunSeed == nil or currentRunSeed ~= newSeed then
        SpawnedRooms = {}
        currentRunSeed = newSeed
        saveData()  -- сразу сохраним, чтобы зафиксировать новый seed
    end
end
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.onGameStart)

-----------------------------------
-- Логика спавна: Treasure Room
-----------------------------------
local hasSpawnedTreasureItem = false

function mod:onNewRoom()
    local room = game:GetRoom()
    local roomType = room:GetType()

    -- Для каждой новой комнаты обнуляем флаг
    hasSpawnedTreasureItem = false

    -- Если Treasure Room, попытаемся заспавнить предметы
    if roomType == RoomType.ROOM_TREASURE then
        mod:trySpawnTreasure(room)
    end
end
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.onNewRoom)

function mod:trySpawnTreasure(room)
    if hasSpawnedTreasureItem then return end
    hasSpawnedTreasureItem = true

    -- Генерируем ID текущей комнаты
    local roomID = getCurrentRoomID()

    -- Проверяем, не спавнили ли мы уже предметы в этой комнате
    if SpawnedRooms[roomID] then
        -- Уже спавнили, выходим
        return
    end

    -- Иначе спавним
    local spawnPos = room:FindFreePickupSpawnPosition(room:GetCenterPos(), 0, true)
    for i = 1, settings.extraTreasureItems do
        Isaac.Spawn(EntityType.ENTITY_PICKUP,
                    PickupVariant.PICKUP_COLLECTIBLE,
                    0,
                    spawnPos,
                    Vector(0,0),
                    nil)
    end

    -- Отмечаем, что тут мы уже спавнили
    SpawnedRooms[roomID] = true
    saveData()
end

-----------------------------------
-- Логика спавна: Boss Room
-----------------------------------
local hasSpawnedBossItem = false

function mod:onBossDeath(npc)
    if not npc:IsBoss() then return end

    local room = game:GetRoom()
    if room:GetType() == RoomType.ROOM_BOSS then
        if hasSpawnedBossItem then return end
        hasSpawnedBossItem = true

        local roomID = getCurrentRoomID()
        if SpawnedRooms[roomID] then
            return
        end

        local spawnPos = room:FindFreePickupSpawnPosition(room:GetCenterPos(), 0, true)
        for i = 1, settings.extraBossItems do
            Isaac.Spawn(EntityType.ENTITY_PICKUP,
                        PickupVariant.PICKUP_COLLECTIBLE,
                        0,
                        spawnPos,
                        Vector(0,0),
                        nil)
        end

        SpawnedRooms[roomID] = true
        saveData()
    end
end
mod:AddCallback(ModCallbacks.MC_POST_NPC_DEATH, mod.onBossDeath)

-----------------------------------
-- Пример MCM (если нужно)
-----------------------------------
local function setupMCM()
    if not ModConfigMenu then return end

    local cat = "Double Rewards"
    ModConfigMenu.AddTitle(cat, nil, "Double Rewards with Fix")
    ModConfigMenu.AddText(cat, nil, "No double-spawning in same room!")

    ModConfigMenu.AddSetting(cat, nil, {
        Type = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return settings.extraTreasureItems end,
        Minimum = 0,
        Maximum = 5,
        Display = function() return "Extra Treasure Items: " .. tostring(settings.extraTreasureItems) end,
        OnChange = function(val)
            settings.extraTreasureItems = val
            saveData()
        end,
        Info = { "Additional pedestal items in Treasure Rooms." }
    })

    ModConfigMenu.AddSetting(cat, nil, {
        Type = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return settings.extraBossItems end,
        Minimum = 0,
        Maximum = 5,
        Display = function() return "Extra Boss Items: " .. tostring(settings.extraBossItems) end,
        OnChange = function(val)
            settings.extraBossItems = val
            saveData()
        end,
        Info = { "Additional pedestal items after Boss fights." }
    })
end

function mod:onPlayerInit()
    if mod._mcmInit then return end
    mod._mcmInit = true
    setupMCM()
end
mod:AddCallback(ModCallbacks.MC_POST_PLAYER_INIT, mod.onPlayerInit)
