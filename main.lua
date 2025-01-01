-----------------------------
-- Double Rewards Mod with Offset Spawns
-----------------------------
local mod = RegisterMod("DoubleRewardsMod", 1)
local game = Game()

-----------------------------
-- Settings
-----------------------------
local settings = {
    extraTreasureItems = 2,  -- # of extra items in Treasure Rooms
    extraBossItems     = 2,  -- # of extra items after Boss fights
}

-----------------------------
-- Save/Load Helpers (Optional)
-----------------------------
local json = require("json")

local function saveSettings()
    local success, encoded = pcall(function()
        return json.encode(settings)
    end)

    if success then
        mod:SaveData(encoded)
    else
        Isaac.DebugString("DoubleRewardsMod: Failed to encode settings for saving!")
    end
end

local function loadSettings()
    if mod:HasData() then
        local success, decoded = pcall(function()
            return json.decode(mod:LoadData())
        end)
        if success and type(decoded) == "table" then
            for key, value in pairs(decoded) do
                if settings[key] ~= nil then
                    settings[key] = value
                end
            end
        else
            Isaac.DebugString("DoubleRewardsMod: Failed to decode settings data!")
        end
    end
end

-----------------------------
-- Initialization
-----------------------------
function mod:onGameStart(isContinued)
    loadSettings()
end
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.onGameStart)

local hasSpawnedTreasureItem = false
local hasSpawnedBossItem     = false

-----------------------------
-- On New Room
-----------------------------
function mod:onNewRoom()
    local room     = game:GetRoom()
    local roomType = room:GetType()

    -- Reset these flags each time we enter a new room
    hasSpawnedTreasureItem = false
    hasSpawnedBossItem     = false

    -- If it's a Treasure Room, spawn extra items immediately
    if roomType == RoomType.ROOM_TREASURE then
        mod:spawnExtraTreasure(room)
    end
end
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.onNewRoom)

-----------------------------
-- Spawn Extra Items in Treasure Rooms
-- NOW with slight position offsets in a circle
-----------------------------
function mod:spawnExtraTreasure(room)
    if not hasSpawnedTreasureItem then
        hasSpawnedTreasureItem = true

        -- We'll pick a radius for the circle
        local radius    = 60
        local centerPos = room:GetCenterPos()

        for i = 1, settings.extraTreasureItems do
            -- Angle in radians
            local angle = (2 * math.pi / settings.extraTreasureItems) * (i - 1)
            local offset = Vector(
                radius * math.cos(angle),
                radius * math.sin(angle)
            )

            -- Combine the offset with the center of the room
            local spawnPos = room:FindFreePickupSpawnPosition(centerPos + offset, 0, true)

            Isaac.Spawn(EntityType.ENTITY_PICKUP,
                        PickupVariant.PICKUP_COLLECTIBLE,
                        0,
                        spawnPos,
                        Vector(0,0),
                        nil)
        end
    end
end

-----------------------------
-- Boss Room: Spawn Extra Items
-- Also with offset positions
-----------------------------
function mod:onBossDeath(npc)
    local room = game:GetRoom()
    if npc:IsBoss() and room:GetType() == RoomType.ROOM_BOSS then
        if not hasSpawnedBossItem then
            hasSpawnedBossItem = true

            local radius    = 70
            local centerPos = room:GetCenterPos()

            for i = 1, settings.extraBossItems do
                local angle = (2 * math.pi / settings.extraBossItems) * (i - 1)
                local offset = Vector(
                    radius * math.cos(angle),
                    radius * math.sin(angle)
                )

                local spawnPos = room:FindFreePickupSpawnPosition(centerPos + offset, 0, true)

                Isaac.Spawn(EntityType.ENTITY_PICKUP,
                            PickupVariant.PICKUP_COLLECTIBLE,
                            0,
                            spawnPos,
                            Vector(0,0),
                            nil)
            end
        end
    end
end
mod:AddCallback(ModCallbacks.MC_POST_NPC_DEATH, mod.onBossDeath)

-----------------------------
-- Minimal MCM Setup (Optional)
-----------------------------
local function setupModConfigMenu()
    if not ModConfigMenu then return end

    local cat = "Double Rewards"
    ModConfigMenu.AddTitle(cat, nil, "Double Rewards Mod")
    ModConfigMenu.AddText(cat, nil, "Spawns items in a small circle")

    ModConfigMenu.AddSetting(cat, nil, {
        Type = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return settings.extraTreasureItems end,
        Minimum = 0,
        Maximum = 5,
        Display = function() return "Extra Treasure Items: " .. tostring(settings.extraTreasureItems) end,
        OnChange = function(val)
            settings.extraTreasureItems = val
            saveSettings()
        end,
        Info = {"Additional pedestal items in Treasure Rooms."}
    })

    ModConfigMenu.AddSetting(cat, nil, {
        Type = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return settings.extraBossItems end,
        Minimum = 0,
        Maximum = 5,
        Display = function() return "Extra Boss Items: " .. tostring(settings.extraBossItems) end,
        OnChange = function(val)
            settings.extraBossItems = val
            saveSettings()
        end,
        Info = {"Additional pedestal items after Boss fights."}
    })
end

function mod:postPlayerInit()
    if mod._mcmHasInit then return end
    mod._mcmHasInit = true
    setupModConfigMenu()
end
mod:AddCallback(ModCallbacks.MC_POST_PLAYER_INIT, mod.postPlayerInit)
