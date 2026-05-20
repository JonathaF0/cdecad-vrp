--[[
    CDECAD Sync - Main Server Script for vRP
    Handles vRP events and syncs data to CDECAD

    vRP API reference: https://vrp-framework.github.io/vRP/dev/index.html
]]

-- =============================================================================
-- vRP PROXY INTERFACE
-- =============================================================================

local Proxy = module('vrp', 'lib/Proxy')
local Tunnel = module('vrp', 'lib/Tunnel')

local vRP = Proxy.getInterface('vRP')
local vRPclient = Tunnel.getInterface('vRP')

-- Tunnel for our own client->server calls
local CDECADSync = {}
Tunnel.bindInterface('cdecad-sync', CDECADSync)
Proxy.addInterface('cdecad-sync', CDECADSync)

local CDECADclient = Tunnel.getInterface('cdecad-sync')

-- Load VehicleUtils module directly (shared_script globals not accessible in async callbacks)
local VehicleUtils = load(LoadResourceFile(GetCurrentResourceName(), 'shared/vehicles.lua'))()

-- Cache: user_id -> CAD civilian ID (and plate -> true for vehicles)
local syncedCivilians = {}
local syncedVehicles = {}

-- source -> user_id (so we can resolve quickly during events)
local sourceToUserId = {}

-- Forward declarations
local SyncPlayerVehicles

-- =============================================================================
-- vRP HELPER FUNCTIONS
-- =============================================================================

local function GetUserId(source)
    if not source or source == 0 then return nil end
    local cached = sourceToUserId[source]
    if cached then return cached end
    local user_id = vRP.getUserId({ source })
    if user_id then sourceToUserId[source] = user_id end
    return user_id
end

local function GetIdentity(user_id)
    if not user_id then return nil end
    return vRP.getUserIdentity({ user_id })
end

local function GetSource(user_id)
    if not user_id then return nil end
    return vRP.getUserSource({ user_id })
end

local function HasExcludedGroup(user_id)
    if not user_id or not Config.ExcludedGroups then return false end
    for _, group in ipairs(Config.ExcludedGroups) do
        if vRP.hasGroup({ user_id, group }) then
            return true
        end
    end
    return false
end

-- =============================================================================
-- CHARACTER SYNC FUNCTIONS
-- =============================================================================

local function BuildCivilianData(source, user_id, identity)
    identity = identity or GetIdentity(user_id) or {}

    -- Discord ID for CAD account linking
    local discordId = nil
    if source and source > 0 then
        local identifiers = GetPlayerIdentifiers(source)
        for _, id in ipairs(identifiers) do
            if string.find(id, 'discord:') then
                discordId = id:gsub('discord:', '')
                break
            end
        end
    end

    -- vRP stores firstname in `firstname` and last name in `name`
    local firstName = identity.firstname or 'Unknown'
    local lastName = identity.name or ''

    -- Derive DoB from age if configured
    local dateOfBirth = nil
    if Config.vRP.DeriveDateOfBirth then
        dateOfBirth = Utils.DateOfBirthFromAge(identity.age)
    end

    -- vRP doesn't store gender natively; some identity addons add `sex` or `gender`
    local rawGender = identity.sex or identity.gender
    local gender = rawGender and Utils.ConvertGender(rawGender) or 'Unknown'

    -- Use vRP registration as SSN if configured
    local ssn
    if Config.vRP.UseRegistrationAsSSN and identity.registration then
        ssn = identity.registration
    else
        ssn = tostring(user_id)
    end

    return {
        firstName = firstName,
        lastName = lastName,
        dateOfBirth = dateOfBirth,
        gender = gender,
        nationality = 'American',
        phone = Utils.FormatPhone(identity.phone),
        identifier = tostring(user_id),
        ssn = ssn,
        discordId = discordId,
        registration = identity.registration,
    }
end

local function SyncCharacter(source, user_id, isNew)
    if not user_id then
        print('[CDECAD-SYNC] ERROR: SyncCharacter called without user_id')
        return
    end

    print('[CDECAD-SYNC] SyncCharacter called for user_id: ' .. tostring(user_id))

    -- Skip excluded vRP groups (police, ems, etc.)
    if HasExcludedGroup(user_id) then
        print('[CDECAD-SYNC] User has excluded vRP group, skipping sync')
        return
    end

    -- Check Discord role eligibility
    if source and source > 0 and not CDECAD_Discord.ShouldSyncPlayer(source) then
        print('[CDECAD-SYNC] Player has excluded Discord role, skipping sync')
        return
    end

    local identity = GetIdentity(user_id)
    if not identity then
        print('[CDECAD-SYNC] ERROR: No vRP identity found for user_id: ' .. tostring(user_id))
        return
    end

    local civilianData = BuildCivilianData(source, user_id, identity)

    print('[CDECAD-SYNC] Syncing character: user_id=' ..
        tostring(user_id) .. ' name=' .. tostring(civilianData.firstName) ..
        ' ' .. tostring(civilianData.lastName))
    print('[CDECAD-SYNC] Discord ID: ' .. tostring(civilianData.discordId))

    if syncedCivilians[user_id] and not isNew then
        print('[CDECAD-SYNC] Character already synced, updating...')
        CDECAD_API.UpdateCivilian(civilianData.ssn, civilianData, function(success, data, statusCode)
            if success then
                print('[CDECAD-SYNC] Character updated successfully')
                if Config.Sync.OnCharacterUpdate and source and source > 0 then
                    TriggerClientEvent('cdecad-sync:client:notify', source, 'success', Config.Locale['sync_success'])
                end
            else
                print('[CDECAD-SYNC] Failed to update character: ' .. tostring(statusCode))
            end
        end)
    else
        print('[CDECAD-SYNC] Creating/syncing civilian in CAD...')
        CDECAD_API.CreateCivilian(civilianData, function(success, data, statusCode)
            print('[CDECAD-SYNC] CreateCivilian callback - success: ' .. tostring(success) ..
                ', statusCode: ' .. tostring(statusCode))

            if success and data then
                if data.civilian then
                    syncedCivilians[user_id] = data.civilian._id
                elseif data._id then
                    syncedCivilians[user_id] = data._id
                else
                    syncedCivilians[user_id] = true
                end

                local action = data.action or 'synced'
                print('[CDECAD-SYNC] Character ' .. action .. ' successfully')
                if source and source > 0 then
                    TriggerClientEvent('cdecad-sync:client:notify', source, 'success', Config.Locale['sync_success'])
                end

                if Config.Sync.SyncVehicles then
                    SyncPlayerVehicles(source, user_id)
                end
            else
                print('[CDECAD-SYNC] Failed to create character: ' .. tostring(statusCode))
                if source and source > 0 then
                    TriggerClientEvent('cdecad-sync:client:notify', source, 'error', Config.Locale['sync_failed'])
                end
            end
        end)
    end
end

-- Sync player's vehicles from vRP database
SyncPlayerVehicles = function(source, user_id)
    if not user_id then return end

    Utils.Debug('Syncing vehicles for user_id:', user_id)

    local identity = GetIdentity(user_id) or {}
    local ownerSSN = (Config.vRP.UseRegistrationAsSSN and identity.registration) or tostring(user_id)

    -- vRP stores owned vehicles in vrp_user_vehicles (user_id, vehicle).
    -- The `vehicle` column is the spawn name (model). Plate is generated
    -- at spawn time via vRP's plate system and isn't always persisted here,
    -- so we fall back to a vRP-style plate derived from the registration.
    local table_name = Config.vRP.VehiclesTable or 'vrp_user_vehicles'
    local query = ('SELECT vehicle FROM %s WHERE user_id = ?'):format(table_name)

    exports.oxmysql:execute(query, { user_id }, function(vehicles)
        if not vehicles or #vehicles == 0 then
            Utils.Debug('No vehicles found for user_id:', user_id)
            return
        end

        Utils.Debug('Found ' .. #vehicles .. ' vehicles for user_id:', user_id)

        local vehicleList = {}
        for _, v in ipairs(vehicles) do
            local spawnName = v.vehicle or 'Unknown'
            local make, model = VehicleUtils.ResolveMakeModel(spawnName)

            -- vRP doesn't store a per-vehicle plate in user_vehicles by default —
            -- it uses the user's registration as the plate. Servers that customize
            -- plates may store them elsewhere; use registration as a deterministic
            -- placeholder so CAD has something to match against scans.
            local plate = identity.registration or ('USER' .. tostring(user_id))

            table.insert(vehicleList, {
                citizenid = ownerSSN,
                plate = plate,
                model = model,
                make = make,
                color = 'Stock',
                -- year omitted; backend marks unknown so UI renders "—".
            })
        end

        CDECAD_API.BulkSyncVehicles(ownerSSN, vehicleList, function(success, data, statusCode)
            if success then
                Utils.Debug('Bulk vehicle sync successful for user_id:', user_id)
                for _, veh in ipairs(vehicleList) do
                    syncedVehicles[veh.plate] = true
                end
            else
                print('[CDECAD-SYNC] Bulk vehicle sync failed for user_id ' ..
                    tostring(user_id) .. ' (HTTP ' .. tostring(statusCode) .. ')')
                if data then
                    print('[CDECAD-SYNC] Vehicle sync error response: ' .. json.encode(data))
                end
            end
        end)
    end)
end

-- =============================================================================
-- vRP EVENT HANDLERS
-- =============================================================================

-- Player join (first connect — identity may not exist yet for brand-new players)
AddEventHandler('vRP:playerJoin', function(user_id, source, name, last_login)
    print('[CDECAD-SYNC] vRP:playerJoin user_id=' .. tostring(user_id) .. ' source=' .. tostring(source))
    sourceToUserId[source] = user_id
end)

-- Player spawn (character ready, identity available)
-- Signature: vRP:playerSpawn(user_id, source, first_spawn)
AddEventHandler('vRP:playerSpawn', function(user_id, source, first_spawn)
    print('[CDECAD-SYNC] vRP:playerSpawn user_id=' .. tostring(user_id) ..
        ' source=' .. tostring(source) .. ' first_spawn=' .. tostring(first_spawn))

    sourceToUserId[source] = user_id

    if not Config.Sync.OnCharacterLoad then return end

    local delay = (Config.vRP.SpawnSyncDelay or 2) * 1000
    SetTimeout(delay, function()
        SyncCharacter(source, user_id, first_spawn and Config.Sync.OnCharacterCreate)
    end)
end)

-- Player leave
AddEventHandler('vRP:playerLeave', function(user_id, source)
    Utils.Debug('vRP:playerLeave user_id=' .. tostring(user_id))
    sourceToUserId[source] = nil
    if source and source > 0 then
        CDECAD_Discord.ClearCache(source)
    end
end)

-- =============================================================================
-- MUGSHOT UPDATE
-- =============================================================================

RegisterNetEvent('cdecad-sync:server:updateMugshot', function(mugshotBase64)
    local source = source
    local user_id = GetUserId(source)
    if not user_id then return end

    local identity = GetIdentity(user_id) or {}
    local ssn = (Config.vRP.UseRegistrationAsSSN and identity.registration) or tostring(user_id)

    Utils.Debug('Updating mugshot for user_id:', user_id)

    CDECAD_API.UpdateCivilian(ssn, { mugshotUrl = mugshotBase64 }, function(success, data, statusCode)
        if success then
            Utils.Debug('Mugshot updated for user_id:', user_id)
        else
            Utils.Debug('Mugshot update failed:', statusCode)
        end
    end)
end)

-- =============================================================================
-- VEHICLE EVENT HANDLERS
-- =============================================================================

-- Vehicle purchased/registered (call from your vehicle shop)
RegisterNetEvent('cdecad-sync:server:registerVehicle', function(vehicleData)
    local source = source
    local user_id = GetUserId(source)

    if not user_id or not Config.Sync.SyncVehicles then return end

    local identity = GetIdentity(user_id) or {}
    local ownerSSN = (Config.vRP.UseRegistrationAsSSN and identity.registration) or tostring(user_id)

    Utils.Debug('Registering vehicle:', vehicleData.plate)

    local cadVehicleData = {
        plate = vehicleData.plate,
        ownerId = ownerSSN,
        make = vehicleData.make or vehicleData.brand,
        model = vehicleData.model,
        color = vehicleData.color,
        year = vehicleData.year, -- nil means unknown; backend handles
    }

    CDECAD_API.RegisterVehicle(cadVehicleData, function(success, data)
        if success then
            Utils.Debug('Vehicle registered in CAD')
            syncedVehicles[vehicleData.plate] = data and data.vehicleId or true
            TriggerClientEvent('cdecad-sync:client:notify', source, 'success', Config.Locale['vehicle_registered'])
        else
            Utils.Debug('Failed to register vehicle in CAD')
        end
    end)
end)

-- Vehicle reported stolen
RegisterNetEvent('cdecad-sync:server:reportStolen', function(plate, description)
    local source = source
    local user_id = GetUserId(source)

    if not user_id or not Config.Sync.SyncVehicleStatus then return end

    Utils.Debug('Reporting vehicle stolen:', plate)

    CDECAD_API.GetVehicle(plate, function(success, vehicleData)
        if success and vehicleData then
            CDECAD_API.ReportVehicleStolen(vehicleData.id, true, description, function(stealSuccess)
                if stealSuccess then
                    TriggerClientEvent('cdecad-sync:client:notify', source, 'success', Config.Locale['vehicle_reported_stolen'])
                end
            end)
        end
    end)
end)

-- =============================================================================
-- 911 CALL HANDLER
-- =============================================================================

RegisterNetEvent('cdecad-sync:server:911call', function(callData)
    local source = source
    local user_id = GetUserId(source)

    if not Config.Calls.Enabled then return end

    -- Rate limiting
    local canCall, remaining = Utils.CheckRateLimit('911_' .. source, Config.Calls.Cooldown)
    if not canCall then
        TriggerClientEvent('cdecad-sync:client:notify', source, 'error',
            (Config.Locale['911_cooldown'] or 'Cooldown'):gsub('{time}', tostring(remaining)))
        return
    end

    local callerName = 'Anonymous'
    if user_id and not callData.anonymous then
        local identity = GetIdentity(user_id)
        if identity then
            callerName = (identity.firstname or '') .. ' ' .. (identity.name or '')
            callerName = callerName:match('^%s*(.-)%s*$') -- trim
            if callerName == '' then callerName = 'Unknown' end
        end
    end

    local cadCallData = {
        callType = callData.callType or 'Emergency Call',
        location = callData.location or callData.street or 'Unknown',
        callerName = callerName,
        coords = callData.coords,
        x = callData.coords and callData.coords.x,
        y = callData.coords and callData.coords.y,
        z = callData.coords and callData.coords.z,
        postal = callData.postal,
        isAnonymous = callData.anonymous,
        isNPC = false,
        reportType = 'Player'
    }

    CDECAD_API.Send911Call(cadCallData, function(success, data)
        if success then
            Utils.Debug('911 call sent successfully')
            if Config.Calls.NotifyOnSuccess then
                TriggerClientEvent('cdecad-sync:client:notify', source, 'success', Config.Locale['911_sent'])
            end
        else
            Utils.Debug('Failed to send 911 call')
            TriggerClientEvent('cdecad-sync:client:notify', source, 'error', Config.Locale['cad_offline'])
        end
    end)
end)

-- =============================================================================
-- NPC REPORTS (Automated witness reports)
-- =============================================================================

RegisterNetEvent('cdecad-sync:server:npcReport', function(reportData)
    if not Config.NPCReports.Enabled then return end

    local locationKey = 'npc_' .. reportData.reportType .. '_' ..
        math.floor((reportData.coords.x or 0) / 100) .. '_' ..
        math.floor((reportData.coords.y or 0) / 100)

    local cooldown = Config.NPCReports[reportData.reportType] and
        Config.NPCReports[reportData.reportType].Cooldown or 60

    local canReport = Utils.CheckRateLimit(locationKey, cooldown)
    if not canReport then return end

    local cadCallData = {
        callType = reportData.callType or 'Suspicious Activity',
        location = reportData.location or reportData.street or 'Unknown',
        callerName = 'Anonymous Witness',
        coords = reportData.coords,
        x = reportData.coords.x,
        y = reportData.coords.y,
        z = reportData.coords.z,
        postal = reportData.postal,
        isAnonymous = true,
        isNPC = true,
        reportType = reportData.reportType or 'NPC'
    }

    CDECAD_API.Send911Call(cadCallData, function(success)
        if success then
            Utils.Debug('NPC report sent:', reportData.reportType)
        end
    end)
end)

-- =============================================================================
-- LOOKUP CALLBACKS
-- =============================================================================

lib.callback.register('cdecad-sync:server:lookupCivilian', function(source, identifier)
    local result = nil
    local completed = false

    CDECAD_API.GetCivilianBySSN(identifier, function(success, data)
        result = success and data or nil
        completed = true
    end)

    while not completed do Wait(10) end
    return result
end)

lib.callback.register('cdecad-sync:server:lookupVehicle', function(source, plate)
    local result = nil
    local completed = false

    CDECAD_API.GetVehicle(plate, function(success, data)
        result = success and data or nil
        completed = true
    end)

    while not completed do Wait(10) end
    return result
end)

-- =============================================================================
-- EXPORTS
-- =============================================================================

exports('SyncCharacter', function(source)
    local user_id = GetUserId(source)
    if user_id then
        SyncCharacter(source, user_id, false)
        return true
    end
    return false
end)

exports('Send911Call', function(callData)
    CDECAD_API.Send911Call(callData, function(success)
        Utils.Debug('Export 911 call result:', success)
    end)
end)

exports('GetSyncedCivilianId', function(identifier)
    -- Accept either a numeric user_id or a string registration; check both
    if syncedCivilians[identifier] then return syncedCivilians[identifier] end
    local n = tonumber(identifier)
    if n and syncedCivilians[n] then return syncedCivilians[n] end
    return nil
end)

exports('ForceSync', function(source)
    local user_id = GetUserId(source)
    if user_id then
        SyncCharacter(source, user_id, true)
        return true
    end
    return false
end)

-- =============================================================================
-- STARTUP
-- =============================================================================

CreateThread(function()
    Wait(5000)

    print('[CDECAD-SYNC] Using vRP framework')

    CDECAD_API.HealthCheck(function(online, statusCode)
        if online then
            print('[CDECAD-SYNC] Connected to CDECAD API')
        else
            print('[CDECAD-SYNC] WARNING: Unable to connect to CDECAD API (Status: ' ..
                tostring(statusCode) .. ')')
        end
    end)

    -- Sync any already-online players
    if Config.Sync.OnCharacterLoad then
        local users = vRP.getUsers({}) or {}
        for user_id, src in pairs(users) do
            local uid = tonumber(user_id) or user_id
            local srcNum = tonumber(src) or src
            sourceToUserId[srcNum] = uid
            SyncCharacter(srcNum, uid, false)
        end
    end
end)

print('[CDECAD-SYNC] Server script loaded (vRP)')
