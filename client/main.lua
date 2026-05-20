--[[
    CDECAD Sync - Main Client Script for vRP
    Handles client-side notifications and data gathering
]]

local Proxy = module('vrp', 'lib/Proxy')
local Tunnel = module('vrp', 'lib/Tunnel')

local vRP = Proxy.getInterface('vRP')
local vRPclient = Tunnel.getInterface('vRP')

-- Tunnel for inbound RPCs from server (e.g. mugshot trigger)
local CDECADclient = {}
Tunnel.bindInterface('cdecad-sync', CDECADclient)
Proxy.addInterface('cdecad-sync', CDECADclient)

local isSpawned = false

-- =============================================================================
-- MUGSHOT CAPTURE
-- =============================================================================

local function CaptureMugshot()
    if GetResourceState('MugShotBase64') ~= 'started' then
        Utils.Debug('MugShotBase64 not running, skipping mugshot capture')
        return
    end

    local ok, result = pcall(function()
        return exports['MugShotBase64']:GetMugShotBase64(PlayerPedId(), true)
    end)

    if ok and result and result ~= '' then
        Utils.Debug('Mugshot captured, sending to server')
        TriggerServerEvent('cdecad-sync:server:updateMugshot', result)
    else
        Utils.Debug('Mugshot capture failed or returned empty')
    end
end

-- =============================================================================
-- vRP CLIENT EVENT HOOK
-- =============================================================================

-- vRP doesn't expose a network-side "player loaded" event on the client by
-- default, so we hook the global `vRP:playerSpawn` (custom servers commonly
-- forward this with TriggerClientEvent) and also fall back to a polling
-- watchdog that detects when the local ped becomes valid.
RegisterNetEvent('vRP:playerSpawn', function()
    isSpawned = true
    Utils.Debug('Client: vRP:playerSpawn received')
    SetTimeout(6000, function()
        CaptureMugshot()
    end)
end)

-- Fallback watchdog: capture mugshot once the ped is alive for a few seconds
CreateThread(function()
    Wait(15000) -- give vRP time to do its own spawn
    if isSpawned then return end
    if GetResourceState('MugShotBase64') ~= 'started' then return end

    local ped = PlayerPedId()
    if DoesEntityExist(ped) and not IsEntityDead(ped) then
        Utils.Debug('Client: Fallback mugshot capture')
        CaptureMugshot()
        isSpawned = true
    end
end)

-- =============================================================================
-- NOTIFICATIONS
-- =============================================================================

RegisterNetEvent('cdecad-sync:client:notify', function(type, message)
    if Config.Notifications.UseOxLib then
        lib.notify({
            title = 'CDECAD',
            description = message,
            type = type,
            duration = Config.Notifications.Duration,
            position = Config.Notifications.Position
        })
    else
        -- vRP native notification fallback
        local ok = pcall(function()
            vRPclient._notify(message)
        end)
        if not ok then
            print('[CDECAD] ' .. tostring(message))
        end
    end
end)

-- =============================================================================
-- POSTAL CODE FUNCTIONS
-- =============================================================================

function GetPostalCode()
    if not Config.Postal or not Config.Postal.Enabled then
        return nil
    end

    local postal = nil
    local resource = Config.Postal.Resource or 'nearest-postal'

    if resource == 'nearest-postal' then
        local success, result = pcall(function()
            return exports['nearest-postal']:getPostal()
        end)
        if success and result then
            postal = result
        end
    elseif resource == 'npostal' then
        local success, result = pcall(function()
            return exports.npostal:npostal()
        end)
        if success and result then
            postal = result
        end
    elseif resource == 'custom' then
        local exportName = Config.Postal.CustomExport
        local funcName = Config.Postal.CustomFunction or 'getPostal'

        if exportName then
            local success, result = pcall(function()
                return exports[exportName][funcName]()
            end)
            if success and result then
                postal = result
            end
        end
    end

    if postal then
        Utils.Debug('Got postal code:', postal)
        return tostring(postal)
    else
        Utils.Debug('No postal code available')
        return Config.Postal.FallbackText
    end
end

-- =============================================================================
-- LOCATION HELPERS
-- =============================================================================

function GetCurrentStreetName()
    local coords = GetEntityCoords(PlayerPedId())
    local streetHash, crossingHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local streetName = GetStreetNameFromHashKey(streetHash)
    local crossingName = GetStreetNameFromHashKey(crossingHash)

    if crossingName and crossingName ~= '' then
        return streetName .. ' & ' .. crossingName
    end
    return streetName
end

function GetCurrentZoneName()
    local coords = GetEntityCoords(PlayerPedId())
    return GetLabelText(GetNameOfZone(coords.x, coords.y, coords.z))
end

function FormatLocationString(street, zone, postal)
    local format

    if postal and Config.Postal.IncludeInLocation then
        format = Config.Postal.LocationFormat or '{street}, {zone} (Postal: {postal})'
        format = format:gsub('{street}', street or 'Unknown')
        format = format:gsub('{zone}', zone or 'Unknown')
        format = format:gsub('{postal}', postal)
    else
        format = Config.Postal.LocationFormatNoPostal or '{street}, {zone}'
        format = format:gsub('{street}', street or 'Unknown')
        format = format:gsub('{zone}', zone or 'Unknown')
    end

    return format
end

function GetLocationInfo()
    local coords = GetEntityCoords(PlayerPedId())
    local street = GetCurrentStreetName()
    local zone = GetCurrentZoneName()
    local postal = GetPostalCode()

    local locationString = FormatLocationString(street, zone, postal)

    return {
        street = street,
        zone = zone,
        postal = postal,
        location = locationString,
        coords = coords,
        x = coords.x,
        y = coords.y,
        z = coords.z
    }
end

function GetCurrentVehicle()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle == 0 then
        return nil
    end

    local plate = GetVehicleNumberPlateText(vehicle)
    local model = GetEntityModel(vehicle)
    local displayName = GetDisplayNameFromVehicleModel(model)

    return {
        vehicle = vehicle,
        plate = plate:gsub('%s+', ''),
        model = displayName,
        class = GetVehicleClass(vehicle)
    }
end

-- =============================================================================
-- 911 CALL PREPARATION
-- =============================================================================

function Prepare911CallData(callType, anonymous)
    local location = GetLocationInfo()

    return {
        callType = callType,
        location = location.location,
        street = location.street,
        zone = location.zone,
        postal = location.postal,
        coords = location.coords,
        anonymous = anonymous or false
    }
end

-- Client-side trigger from server commands
RegisterNetEvent('cdecad-sync:client:prepare911', function(message, anonymous)
    local callData = Prepare911CallData(message, anonymous)
    callData.callType = message
    TriggerServerEvent('cdecad-sync:server:911call', callData)
end)

RegisterNetEvent('cdecad-sync:client:reportStolenVehicle', function(description)
    local vehicle = GetCurrentVehicle()
    if not vehicle then
        lib.notify({
            title = 'CDECAD',
            description = 'You must be in or near a vehicle to report it stolen.',
            type = 'error'
        })
        return
    end
    TriggerServerEvent('cdecad-sync:server:reportStolen', vehicle.plate, description)
end)

-- =============================================================================
-- EXPORTS
-- =============================================================================

exports('GetLocationInfo', GetLocationInfo)
exports('GetCurrentVehicle', GetCurrentVehicle)
exports('Prepare911CallData', Prepare911CallData)
exports('GetPostalCode', GetPostalCode)

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

CreateThread(function()
    -- Wait for vRP proxy to be available
    while not vRP do
        Wait(100)
    end

    if Config.Postal and Config.Postal.Enabled then
        Wait(2000)
        local testPostal = GetPostalCode()
        if testPostal then
            Utils.Debug('Postal integration working. Current postal:', testPostal)
        else
            Utils.Debug('Postal integration enabled but no postal returned. Check Config.Postal.Resource setting.')
        end
    end

    Utils.Debug('Client: Initialized (vRP)')
end)

print('[CDECAD-SYNC] Client script loaded (vRP)')
