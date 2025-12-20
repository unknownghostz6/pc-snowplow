local QBCore = exports['qb-core']:GetCoreObject()
local function LoadModel(model)
    -- QBCore compatibility: newer qb-core provides QBCore.Functions.LoadModel, but keep a safe fallback.
    if QBCore.Functions and QBCore.Functions.LoadModel then
        QBCore.Functions.LoadModel(model)
        return
    end
    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(20)
    end
end

local function EnableAllVehicleExtras(veh)
    -- Enables all available extras on the vehicle (set to 0 = ON)
    for extra = 0, 20 do
        if DoesExtraExist(veh, extra) then
            SetVehicleExtra(veh, extra, 0)
        end
    end
end


local npcPed
local npcSpawned = false
local dutyCoords = vector3(Config.DutyLocation.x, Config.DutyLocation.y, Config.DutyLocation.z - 1)
local dutyHeading = Config.DutyLocation.w
local spawnCoords = vector3(Config.VehicleSpawnLocation.x, Config.VehicleSpawnLocation.y, Config.VehicleSpawnLocation.z)
local spawnHeading = Config.VehicleSpawnLocation.w
local doingJob = false
local jobSpot
local jobSize
local jobProgress = 0
local groupProgress = 1
local plowEntity
local blip

-- =========================================================
-- Immersion helpers (notifications + salt visuals)
-- =========================================================
local currentLocationName = nil

local function NotifyImm(msg, ntype, time)
    if not (Config.Immersion and Config.Immersion.Notify and Config.Immersion.Notify.enabled) then return end
    QBCore.Functions.Notify(msg, ntype or 'primary', time or 3500)
end

local function PickLocationName()
    local list = (Config.Immersion and Config.Immersion.LocationNames) or {}
    if #list == 0 then return 'your assigned location' end
    return list[math.random(1, #list)]
end

local function GetVehModelNameLower(veh)
    local model = GetEntityModel(veh)
    local name = GetDisplayNameFromVehicleModel(model)
    return string.lower(name or '')
end

local Salt = {
    enabled = false,
    lbs = 0,
    cap = 0,
    lastSync = 0,
    lastFx = 0,
    lastNotify = 0,
    lastEmergency = false,
}

local OtherSalt = {} -- [serverId] = { enabled=bool, lbs=int, cap=int }

-- Keep cached player data up to date (latest qb-core pattern)
local PlayerData = {}
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    PlayerData = QBCore.Functions.GetPlayerData()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    PlayerData = {}
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    PlayerData.job = job
end)

-- Create menu entries based on car list
local function CreateCarList(carList)
    local menuEntries = {}

    table.insert(menuEntries, {
        header = 'Plow options',
        icon = 'fas fa-snowplow',
        isMenuHeader = true,
    })

    table.insert(menuEntries, {
        header = 'Back',
        icon = 'fas fa-arrow-left',
        params = {
            event = 'pc-snowplow:client:OpenPlowMenu',
            args = {}
        }
    })

    for _,v in ipairs(carList) do
        local veh = QBCore.Shared and QBCore.Shared.Vehicles and QBCore.Shared.Vehicles[v]
        local vehicleName = veh and ((veh.brand or '')..' '..(veh.name or '')) or v

        table.insert(menuEntries, {
            header = vehicleName,
            icon = 'fas fa-snowflake',
            params = {
                event = 'pc-snowplow:client:TakeJob',
                args = { vehicle = v }
            }
        })
    end

    return menuEntries
end

-- Reset local progress trackers and handles
local function ClearInternals()
    doingJob = false
    jobSpot = nil
    jobSize = nil
    jobProgress = 0
    groupProgress = 1
    plowEntity = nil
end

-- Start/stop handling
AddEventHandler('onClientResourceStart', function(name)
    if name == GetCurrentResourceName() then
        -- Prepare config for use with draw functionality
        for k,v in ipairs({ Config.PlowLocationsSmall, Config.PlowLocationsMedium, Config.PlowLocationsLarge }) do -- Plow sizes
            for l,q in ipairs(v) do -- Job spots
                for m,r in ipairs(q) do -- Groups
                    r.Rads = r.Location.w / 180.00 * 3.14 -- Convert headings to radians, the preferred unit by trigonometry functions
                end
            end
        end

        -- Blip registration
        if Config.UseBlip then
            blip = AddBlipForCoord(Config.DutyLocation)
            SetBlipDisplay(blip, 2)
            SetBlipSprite(blip, Config.BlipSprite)
            SetBlipColour(blip, Config.BlipColor)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(Config.BlipTitle)
            EndTextCommandSetBlipName(blip)
        end
    end
end)

AddEventHandler('onClientResourceStop', function(name)
    if name == GetCurrentResourceName() then
        -- Blip deregistration
        if Config.UseBlip then
            RemoveBlip(blip)
        end
    end
end)

-- Job menus
RegisterNetEvent('pc-snowplow:client:OpenPlowMenu', function()
    local playerData = QBCore.Functions.GetPlayerData()

    if playerData.job and playerData.job.name == Config.JobName then
        exports[Config.MenuResource]:openMenu({
            {
                header = 'Snowplow Jobs',
                icon = 'fas fa-snowflake',
                isMenuHeader = true,
            },
            {
                header = 'Small',
                txt = 'A small plowing job',
                icon = 'fas fa-hammer',
                params = {
                    event = 'pc-snowplow:client:OpenJobsMenu',
                    args = { size = 'small' }
                }
            },
            {
                header = 'Medium',
                txt = 'A medium plowing job',
                icon = 'fas fa-truck-pickup',
                params = {
                    event = 'pc-snowplow:client:OpenJobsMenu',
                    args = { size = 'medium' }
                }
            },
            {
                header = 'Large',
                txt = 'A large plowing job',
                icon = 'fas fa-snowplow',
                params = {
                    event = 'pc-snowplow:client:OpenJobsMenu',
                    args = { size = 'large' }
                }
            },
        })
    end
end)

RegisterNetEvent('pc-snowplow:client:OpenJobsMenu', function(data)
    local playerData = QBCore.Functions.GetPlayerData()

    if playerData.job.name == Config.JobName then
        local menuEntries
        jobSize = data.size

        if jobSize == 'small' then
            menuEntries = CreateCarList(Config.SmallPlows, 'small')
        elseif jobSize == 'medium' then
            menuEntries = CreateCarList(Config.MediumPlows, 'medium')
        elseif jobSize == 'large' then
            menuEntries = CreateCarList(Config.LargePlows, 'large')
        end

        if menuEntries then
            exports[Config.MenuResource]:openMenu(menuEntries)
        end
    else
        exports[Config.MenuResource]:closeMenu()
        QBCore.Functions.Notify('You are not on duty', 'error')
        ClearInternals()
    end
end)

RegisterNetEvent('pc-snowplow:client:TakeJob', function(data)
    local playerData = QBCore.Functions.GetPlayerData()

    if playerData.job.name == Config.JobName then
        local vehicle = data.vehicle

        if doingJob then
            QBCore.Functions.Notify('Previous job was cancelled')
        end

        -- Spawn the job vehicle using qb-core helper (latest pattern)
        QBCore.Functions.SpawnVehicle(vehicle, function(veh)
            if not veh or veh == 0 then
                QBCore.Functions.Notify('Failed to spawn plow vehicle', 'error')
                return
            end

            plowEntity = veh
            SetEntityCoords(veh, spawnCoords.x, spawnCoords.y, spawnCoords.z, false, false, false, true)
            SetEntityHeading(veh, spawnHeading)

            local plate = "PLWG"..tostring(math.random(1000, 9999))
            SetVehicleNumberPlateText(veh, plate)

            -- EXTRAS FOR VEHICLES --
            -- Enable all extras by default for specific plow vehicles
            local _model = string.lower(vehicle or '')
            if _model == 'snowplow' or _model == 'snowatv' or _model == '18f350plow' then
                EnableAllVehicleExtras(veh)
            end

            -- Fix overlapping side plow on snowplow
            local model = string.lower(GetDisplayNameFromVehicleModel(GetEntityModel(veh)) or "")
            if model == "snowplow" then
            SetVehicleExtra(veh, 10, true) -- disable extra 10
            end

            -- qb-vehiclekeys support (original script expected this)
            -- Keep the original logic: the player should receive keys for the spawned plow.
            TriggerServerEvent('qb-vehiclekeys:server:AcquireVehicleKeys', plate)

            SetVehicleEngineOn(veh, true, true)
            TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)

            if Config.FuelResource and Config.FuelResource ~= '' and exports[Config.FuelResource] and exports[Config.FuelResource].SetFuel then
                exports[Config.FuelResource]:SetFuel(veh, 100)
            end

            TriggerEvent('pc-snowplow:client:SetNextJobSpot')
        end, vector3(spawnCoords.x, spawnCoords.y, spawnCoords.z), true)
    else
        QBCore.Functions.Notify('You are not on duty', 'error')
        ClearInternals()
    end

    exports[Config.MenuResource]:closeMenu()
end)

-- Fetch a new group spot
RegisterNetEvent('pc-snowplow:client:SetNextGroupSpot', function()
    local playerData = QBCore.Functions.GetPlayerData()

    if playerData.job.name == Config.JobName then
        jobProgress = 0
        groupProgress = groupProgress + 1

        if jobSpot[groupProgress] then
            SetNewWaypoint(jobSpot[groupProgress].Location.x, jobSpot[groupProgress].Location.y)
            if Config.Immersion and Config.Immersion.Notify and Config.Immersion.Notify.checkpoint then
                local every = Config.Immersion.Notify.cadenceCheckpoint or 0
                if every > 0 and (groupProgress % every == 0) then
                    local name = currentLocationName or 'your assigned location'
                    NotifyImm(('Progress: %d group(s) cleared. Continue at %s.'):format(groupProgress, name), 'primary', 3500)
                end
            end
        end
    else
        QBCore.Functions.Notify('You are not on duty', 'error')
        ClearInternals()
    end
end)

-- Fetch a new job spot
RegisterNetEvent('pc-snowplow:client:SetNextJobSpot', function()
    local playerData = QBCore.Functions.GetPlayerData()

    if playerData.job.name == Config.JobName then
        jobSpot = PickRandomJob(jobSize)
        jobProgress = 0
        groupProgress = 1
        doingJob = true

        currentLocationName = PickLocationName()
        if Config.Immersion and Config.Immersion.Notify and Config.Immersion.Notify.start then
            NotifyImm(('Dispatch: Head to %s and begin plowing.'):format(currentLocationName), 'success', 5500)
        end

        if jobSpot then
            SetNewWaypoint(jobSpot[groupProgress].Location.x, jobSpot[groupProgress].Location.y)
        else
            QBCore.Functions.Notify('No jobs are available', 'error')
        end
    else
        QBCore.Functions.Notify('You are not on duty', 'error')
        ClearInternals()
    end
end)

-- Return plow
RegisterNetEvent('pc-snowplow:client:ReturnPlow', function()
    local playerData = QBCore.Functions.GetPlayerData()

    if playerData.job.name == Config.JobName then
        local veh = GetVehiclePedIsIn(PlayerPedId(), false)
        local plate = GetVehicleNumberPlateText(veh)

        if string.sub(plate, 1, 4) == 'PLWG' then
            QBCore.Functions.DeleteVehicle(veh)
            QBCore.Functions.Notify('Plow has been returned')
            ClearInternals()
        end
    end
end)

-- NPC spawn thread
CreateThread(function()
    local coords

    while true do
        coords = GetEntityCoords(PlayerPedId())

        if #(dutyCoords - coords) < 100.00 and not npcSpawned then
            local hash = GetHashKey(Config.DutyPedModel)

            LoadModel(hash)
            npcPed = CreatePed(0, hash, dutyCoords, dutyHeading, false, false)

            if npcPed ~= 0 then
                npcSpawned = true

                SetModelAsNoLongerNeeded(hash)
                SetEntityInvincible(npcPed, true)
                SetBlockingOfNonTemporaryEvents(npcPed, true)
                FreezeEntityPosition(npcPed, true)
                TaskStartScenarioInPlace(npcPed, 'WORLD_HUMAN_CLIPBOARD', 0, true)

                -- NPC Targeting (supports newer qb-target APIs)
                local target = exports[Config.TargetResource]
                local opt = {
                    {
                        event = 'pc-snowplow:client:OpenPlowMenu',
                        icon = 'fas fa-snowplow',
                        label = 'Accept a job',
                        job = Config.JobName,
                    }
                }

                if target and target.AddTargetEntity then
                    target:AddTargetEntity(npcPed, {
                        options = opt,
                        distance = 3.0,
                    })
                else
                    -- Legacy qb-target
                    target:AddEntityZone('plowperson', npcPed, {
                        name = 'plowperson',
                        heading = dutyHeading,
                        debugPoly = false,
                        useZ = true
                    }, {
                        options = opt,
                        distance = 3.0
                    })
                end
            end
        elseif #(dutyCoords - coords) >= 100.00 and npcSpawned then
            DeleteEntity(npcPed)
            npcSpawned = false
            npcPed = nil
        end

        Wait(1000)
    end
end)

-- Plow return thread
CreateThread(function()
    local coords

    while true do
        local playerData = QBCore.Functions.GetPlayerData()

        if playerData.job and playerData.job.name == Config.JobName then
            coords = GetEntityCoords(PlayerPedId())

            if #(Config.ReturnLocation - coords) <= Config.ReturnRange then
                TriggerEvent('pc-snowplow:client:ReturnPlow')
            end

            Wait(1000)
        else
            Wait(5000)
        end
    end
end)

-- Plowing markers thread
CreateThread(function()
    local coords

    while true do
        local playerData = QBCore.Functions.GetPlayerData()

        if doingJob and jobSize and jobSpot and playerData.job.name == Config.JobName then
            coords = GetEntityCoords(PlayerPedId())

            local groupSpot = jobSpot[groupProgress]
            local groupLoc = groupSpot.Location
            local jobCoords = vector3(groupLoc.x, groupLoc.y, groupLoc.z)
            local markerPos = jobCoords

            if #(coords - markerPos) < (1.2 * math.sqrt(( groupSpot.Width ^ 2 ) + ( groupSpot.Height ^ 2 ))) then
                -- Draw marker
                local rads = groupSpot.Rads
                local coordShift = GetMarkerProportions(jobSize, jobProgress)

                coordShift.x = coordShift.x * groupSpot.Width
                coordShift.y = coordShift.y * groupSpot.Height
                coordShift.x, coordShift.y = ( coordShift.x * math.cos(rads) ) - ( coordShift.y * math.sin(rads) ), ( coordShift.x * math.sin(rads) ) + ( coordShift.y * math.cos(rads) )
                coordShift.z = jobCoords.z - 1
                markerPos = vector3(jobCoords.x + coordShift.x, jobCoords.y + coordShift.y, jobCoords.z)
                DrawMarker(
                    0,
                    markerPos.x,
                    markerPos.y,
                    markerPos.z,
                    0.0,
                    0.0,
                    0.0,
                    0.0,
                    0.0,
                    0.0,
                    3.0,
                    3.0,
                    3.0,
                    235,
                    134,
                    52,
                    255,
                    false,
                    true,
                    2,
                    nil,
                    nil,
                    false
                )

                -- Increment progress if checkpoint is hit
                if #(coords - markerPos) < 2 then
                    jobProgress = jobProgress + 1
                end

                -- Complete group
                if coordShift.resetProgress == jobProgress then
                    TriggerEvent('pc-snowplow:client:SetNextGroupSpot')

                    -- Complete job
                    if #jobSpot < groupProgress then
                        TriggerServerEvent('pc-snowplow:server:FinishJob', jobSize, #jobSpot)
                        if Config.Immersion and Config.Immersion.Notify and Config.Immersion.Notify.finish then
                            local name = currentLocationName or 'your assigned location'
                            NotifyImm(('Job complete at %s. Dispatch is assigning a new call...'):format(name), 'success', 5500)
                        end
                        -- reset named location for next call
                        currentLocationName = nil
                        TriggerEvent('pc-snowplow:client:SetNextJobSpot')
                    end
                end

                Wait(0)
            else
                Wait(1000)
            end
        else
            Wait(1000)
        end
    end
end)


-- =========================================================
-- Salt sync + visuals (added; immersion only)
-- =========================================================
RegisterNetEvent('pc-snowplow:client:SaltSync', function(serverId, data)
    if not serverId then return end
    if not data then
        OtherSalt[serverId] = nil
        return
    end
    OtherSalt[serverId] = data
end)

-- Optional manual command
if Config.Salt and Config.Salt.Enabled and Config.Salt.CommandEnabled then
    RegisterCommand(Config.Salt.Command or 'salt', function()
        if not doingJob then
            NotifyImm('You are not currently on a plow job.', 'error')
            return
        end

        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh == 0 then
            NotifyImm('Get in your plow vehicle to spread salt.', 'error')
            return
        end

        if Salt.cap <= 0 then
            local model = GetVehModelNameLower(veh)
            Salt.cap = (Config.Salt.CapacityLbs and Config.Salt.CapacityLbs[model]) or 0
            Salt.lbs = Salt.cap
        end

        if Salt.lbs <= 0 then
            NotifyImm('Salt hopper empty. Turn on beacons after refilling.', 'error', 4500)
            return
        end

        Salt.enabled = not Salt.enabled
        NotifyImm(Salt.enabled and 'Salt spreading ON' or 'Salt spreading OFF', Salt.enabled and 'success' or 'primary')
    end, false)
end

local function EnsurePtfx(asset)
    if not asset or asset == '' then return end
    if HasNamedPtfxAssetLoaded(asset) then return end
    RequestNamedPtfxAsset(asset)
    while not HasNamedPtfxAssetLoaded(asset) do
        Wait(0)
    end
end

local function EmitPtfxAtCoord(asset, name, coord, size)
    if not asset or not name or asset == '' or name == '' then return end
    EnsurePtfx(asset)
    UseParticleFxAssetNextCall(asset)
    StartNetworkedParticleFxNonLoopedAtCoord(
        name,
        coord.x, coord.y, coord.z,
        0.0, 0.0, 0.0,
        size or 0.7,
        false, false, false
    )
end

local function EmergencyOn(veh)
    -- Most vehicle packs map beacons/emergency lights to siren state toggle (Q)
    return IsVehicleSirenOn(veh)
end

CreateThread(function()
    if not (Config.Salt and Config.Salt.Enabled) then return end

    while true do
        Wait(200)

        if not doingJob then
            Salt.enabled = false
            Salt.lastEmergency = false
            goto continue
        end

        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh == 0 then goto continue end

        -- init capacity for this vehicle
        if Salt.cap <= 0 then
            local model = GetVehModelNameLower(veh)
            Salt.cap = (Config.Salt.CapacityLbs and Config.Salt.CapacityLbs[model]) or 0
            Salt.lbs = Salt.cap
        end

        -- Follow emergency lights/beacons (Q)
        if Config.Salt.FollowEmergencyLights then
            local em = EmergencyOn(veh)
            if em ~= Salt.lastEmergency then
                Salt.lastEmergency = em

                if em and Salt.lbs > 0 then
                    Salt.enabled = true
                    NotifyImm('Beacons ON — salt spreading ON', 'primary', 2500)
                else
                    Salt.enabled = false
                    NotifyImm('Beacons OFF — salt spreading OFF', 'primary', 2500)
                end
            end
        end

        -- Consume + emit visuals when salting and moving
        local now = GetGameTimer()
        local speedMph = GetEntitySpeed(veh) * 2.236936

        if Salt.enabled and speedMph >= (Config.Salt.MinSpeedMph or 6.0) then
            local model = GetVehModelNameLower(veh)
            local rate = (Config.Salt.ConsumeRate and Config.Salt.ConsumeRate[model]) or 0.0
            -- rate is lbs/sec; loop is 0.2s
            if rate > 0.0 then
                Salt.lbs = Salt.lbs - (rate * 0.2)
                if Salt.lbs < 0 then Salt.lbs = 0 end
            end

            -- salt visuals behind vehicle
            if Config.Salt.Visuals and Config.Salt.Visuals.enabled then
                if now - Salt.lastFx >= (Config.Salt.Visuals.spawnEveryMs or 180) then
                    Salt.lastFx = now
                    local behind = GetOffsetFromEntityInWorldCoords(
                        veh,
                        0.0,
                        -(Config.Salt.Visuals.behindDistance or 3.2),
                        -(Config.Salt.Visuals.downOffset or 0.6)
                    )
                    EmitPtfxAtCoord(Config.Salt.Visuals.particleAsset, Config.Salt.Visuals.particleName, behind, Config.Salt.Visuals.size or 0.7)
                end
            end

            -- optional plow spray
            if Config.PlowSpray and Config.PlowSpray.enabled then
                if now % (Config.PlowSpray.spawnEveryMs or 260) < 200 then
                    local left = GetOffsetFromEntityInWorldCoords(
                        veh,
                        -(Config.PlowSpray.sideOffset or 1.3),
                        (Config.PlowSpray.forwardOffset or 1.2),
                        -(Config.PlowSpray.downOffset or 0.6)
                    )
                    local right = GetOffsetFromEntityInWorldCoords(
                        veh,
                        (Config.PlowSpray.sideOffset or 1.3),
                        (Config.PlowSpray.forwardOffset or 1.2),
                        -(Config.PlowSpray.downOffset or 0.6)
                    )
                    EmitPtfxAtCoord(Config.PlowSpray.particleAsset, Config.PlowSpray.particleName, left, Config.PlowSpray.size or 0.6)
                    EmitPtfxAtCoord(Config.PlowSpray.particleAsset, Config.PlowSpray.particleName, right, Config.PlowSpray.size or 0.6)
                end
            end

            -- notify remaining salt occasionally
            if now - Salt.lastNotify >= 20000 then
                Salt.lastNotify = now
                if Salt.cap > 0 then
                    local pct = math.floor((Salt.lbs / Salt.cap) * 100.0)
                    NotifyImm(('Salt: %d%% (%d lbs)'):format(pct, math.floor(Salt.lbs)), 'primary', 2500)
                end
            end

            if Salt.lbs <= 0 then
                Salt.enabled = false
                NotifyImm('Salt hopper empty. Beacons will stop spreading until refilled.', 'error', 4500)
            end
        end

        -- Sync to all players (for shared visuals)
        if now - Salt.lastSync >= (Config.Salt.SyncEveryMs or 1200) then
            Salt.lastSync = now
            TriggerServerEvent('pc-snowplow:server:SaltUpdate', Salt.enabled, math.floor(Salt.lbs), Salt.cap)
        end

        ::continue::
    end
end)

-- Render other players' salt visuals (client-side only)
CreateThread(function()
    if not (Config.Salt and Config.Salt.Enabled and Config.Salt.Visuals and Config.Salt.Visuals.enabled) then return end

    while true do
        Wait(200)
        local now = GetGameTimer()

        for serverId, st in pairs(OtherSalt) do
            if st and st.enabled then
                local ply = GetPlayerFromServerId(serverId)
                if ply and ply ~= -1 then
                    local ped = GetPlayerPed(ply)
                    if ped ~= 0 then
                        local veh = GetVehiclePedIsIn(ped, false)
                        if veh ~= 0 then
                            local speedMph = GetEntitySpeed(veh) * 2.236936
                            if speedMph >= (Config.Salt.MinSpeedMph or 6.0) then
                                local behind = GetOffsetFromEntityInWorldCoords(
                                    veh,
                                    0.0,
                                    -(Config.Salt.Visuals.behindDistance or 3.2),
                                    -(Config.Salt.Visuals.downOffset or 0.6)
                                )
                                EmitPtfxAtCoord(Config.Salt.Visuals.particleAsset, Config.Salt.Visuals.particleName, behind, Config.Salt.Visuals.size or 0.7)
                            end
                        end
                    end
                end
            end
        end
    end
end)
