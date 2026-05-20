--[[
    CDECAD Sync - Server Commands for vRP
    Admin and player commands for CAD integration
]]

local Proxy = module('vrp', 'lib/Proxy')
local vRP = Proxy.getInterface('vRP')

-- Load VehicleUtils module directly (shared_script globals not accessible in async callbacks)
local VehicleUtils = load(LoadResourceFile(GetCurrentResourceName(), 'shared/vehicles.lua'))()

local function GetUserId(source)
    if not source or source == 0 then return nil end
    return vRP.getUserId({ source })
end

local function GetIdentity(user_id)
    if not user_id then return nil end
    return vRP.getUserIdentity({ user_id })
end

-- =============================================================================
-- PLAYER COMMANDS
-- =============================================================================

-- 911 Emergency Call
if Config.Calls.Enabled then
    RegisterCommand(Config.Calls.Command, function(source, args)
        if source == 0 then return end

        local message = table.concat(args, ' ')
        if message == '' then
            TriggerClientEvent('cdecad-sync:client:notify', source, 'error', Config.Locale['911_invalid'])
            return
        end

        TriggerClientEvent('cdecad-sync:client:prepare911', source, message, false)
    end, false)

    if Config.Calls.AlternateCommand then
        RegisterCommand(Config.Calls.AlternateCommand, function(source, args)
            if source == 0 then return end

            local message = table.concat(args, ' ')
            if message == '' then
                TriggerClientEvent('cdecad-sync:client:notify', source, 'error', Config.Locale['911_invalid'])
                return
            end

            TriggerClientEvent('cdecad-sync:client:prepare911', source, message, false)
        end, false)
    end

    if Config.Calls.AllowAnonymous then
        RegisterCommand(Config.Calls.AnonymousCommand, function(source, args)
            if source == 0 then return end

            local message = table.concat(args, ' ')
            if message == '' then
                TriggerClientEvent('cdecad-sync:client:notify', source, 'error', Config.Locale['911_invalid'])
                return
            end

            TriggerClientEvent('cdecad-sync:client:prepare911', source, message, true)
        end, false)
    end
end

-- Report stolen vehicle
RegisterCommand('reportstolen', function(source, args)
    if source == 0 then return end

    local user_id = GetUserId(source)
    if not user_id then return end

    local description = table.concat(args, ' ')
    TriggerClientEvent('cdecad-sync:client:reportStolenVehicle', source, description)
end, false)

-- =============================================================================
-- ADMIN COMMANDS
-- =============================================================================

-- Force sync a player's character (target by source ID)
RegisterCommand('cadsync', function(source, args)
    local targetSource = source

    if args[1] then
        targetSource = tonumber(args[1])
    end

    if not targetSource or targetSource == 0 then
        print('[CDECAD-SYNC] Cannot sync console')
        return
    end

    local user_id = GetUserId(targetSource)
    if not user_id then
        if source > 0 then
            TriggerClientEvent('cdecad-sync:client:notify', source, 'error', 'Player not found')
        else
            print('[CDECAD-SYNC] Player not found: ' .. tostring(targetSource))
        end
        return
    end

    exports[GetCurrentResourceName()]:ForceSync(targetSource)

    if source > 0 then
        TriggerClientEvent('cdecad-sync:client:notify', source, 'success', 'Syncing player to CAD...')
    else
        print('[CDECAD-SYNC] Syncing player ' .. targetSource .. ' (user_id=' ..
            tostring(user_id) .. ') to CAD')
    end
end, true)

-- Check CAD connection status
RegisterCommand('cadstatus', function(source, args)
    CDECAD_API.HealthCheck(function(online, statusCode)
        local message = online
            and 'CAD is online (Status: ' .. tostring(statusCode) .. ')'
            or 'CAD is offline (Status: ' .. tostring(statusCode) .. ')'

        if source > 0 then
            TriggerClientEvent('cdecad-sync:client:notify', source, online and 'success' or 'error', message)
        else
            print('[CDECAD-SYNC] ' .. message)
        end
    end)
end, true)

-- Lookup civilian or vehicle in CAD
RegisterCommand('cadlookup', function(source, args)
    if not args[1] then
        if source > 0 then
            TriggerClientEvent('cdecad-sync:client:notify', source, 'error', 'Usage: /cadlookup [identifier or plate]')
        else
            print('[CDECAD-SYNC] Usage: /cadlookup [identifier or plate]')
        end
        return
    end

    local searchTerm = args[1]:upper()

    if #searchTerm <= 8 then
        CDECAD_API.GetVehicle(searchTerm, function(success, data)
            if success and data then
                local info = string.format('Vehicle: %s %s %s | Owner: %s | Stolen: %s',
                    data.year or '?',
                    data.color or '?',
                    data.model or '?',
                    data.owner or 'Unknown',
                    data.stolen and 'YES' or 'No'
                )

                if source > 0 then
                    TriggerClientEvent('cdecad-sync:client:notify', source, 'info', info)
                else
                    print('[CDECAD-SYNC] ' .. info)
                end
            else
                CDECAD_API.GetCivilianBySSN(searchTerm, function(civSuccess, civData)
                    if civSuccess and civData then
                        local info = string.format('Civilian: %s | DOB: %s | Phone: %s',
                            civData.name or 'Unknown',
                            civData.dob or '?',
                            civData.phone or '?'
                        )

                        if source > 0 then
                            TriggerClientEvent('cdecad-sync:client:notify', source, 'info', info)
                        else
                            print('[CDECAD-SYNC] ' .. info)
                        end
                    else
                        if source > 0 then
                            TriggerClientEvent('cdecad-sync:client:notify', source, 'error', 'No records found')
                        else
                            print('[CDECAD-SYNC] No records found for: ' .. searchTerm)
                        end
                    end
                end)
            end
        end)
    end
end, true)

-- Sync ALL characters from vRP database to CAD (not just online players)
RegisterCommand('cadsyncall', function(source, args)
    local msg = 'Querying all characters from database...'
    if source > 0 then
        TriggerClientEvent('cdecad-sync:client:notify', source, 'info', msg)
    else
        print('[CDECAD-SYNC] ' .. msg)
    end

    -- Build a lookup of online players' Discord IDs by user_id
    local onlineDiscordIds = {}
    local users = vRP.getUsers({}) or {}
    for user_id, src in pairs(users) do
        local srcNum = tonumber(src) or src
        if srcNum and srcNum > 0 then
            local identifiers = GetPlayerIdentifiers(srcNum)
            for _, id in ipairs(identifiers) do
                if string.find(id, 'discord:') then
                    onlineDiscordIds[tonumber(user_id) or user_id] = id:gsub('discord:', '')
                    break
                end
            end
        end
    end

    local table_name = Config.vRP.IdentityTable or 'vrp_user_identities'
    local query = ('SELECT user_id, registration, phone, firstname, name, age FROM %s'):format(table_name)

    exports.oxmysql:execute(query, {}, function(rows)
        if not rows or #rows == 0 then
            local errMsg = 'No characters found in database'
            if source > 0 then
                TriggerClientEvent('cdecad-sync:client:notify', source, 'error', errMsg)
            else
                print('[CDECAD-SYNC] ' .. errMsg)
            end
            return
        end

        local characterList = {}
        for _, row in ipairs(rows) do
            if row.user_id then
                local ssn = (Config.vRP.UseRegistrationAsSSN and row.registration) or tostring(row.user_id)
                local dob = nil
                if Config.vRP.DeriveDateOfBirth then
                    dob = Utils.DateOfBirthFromAge(row.age)
                end

                table.insert(characterList, {
                    firstName = row.firstname or 'Unknown',
                    lastName = row.name or '',
                    dateOfBirth = dob,
                    gender = 'Unknown',
                    nationality = 'American',
                    phone = Utils.FormatPhone(row.phone),
                    ssn = ssn,
                    discordId = onlineDiscordIds[row.user_id]
                })
            end
        end

        local infoMsg = 'Found ' .. #characterList .. ' characters. Syncing to CAD...'
        if source > 0 then
            TriggerClientEvent('cdecad-sync:client:notify', source, 'info', infoMsg)
        else
            print('[CDECAD-SYNC] ' .. infoMsg)
        end

        CDECAD_API.ForceSyncAllCharacters(characterList, function(success, data)
            local resultMsg
            if success then
                local stats = ''
                if data then
                    stats = string.format(' (Created: %s, Updated: %s, Skipped: %s)',
                        tostring(data.created or 0),
                        tostring(data.updated or 0),
                        tostring(data.skipped or 0)
                    )
                end
                resultMsg = 'Character sync complete!' .. stats
            else
                resultMsg = 'Character sync failed. Check server console.'
            end

            if source > 0 then
                TriggerClientEvent('cdecad-sync:client:notify', source, success and 'success' or 'error', resultMsg)
            else
                print('[CDECAD-SYNC] ' .. resultMsg)
            end
        end)
    end)
end, true)

-- Force sync ALL vehicles from vRP database to CAD
RegisterCommand('cadforcesyncvehicles', function(source, args)
    local message = 'Querying all player vehicles from database...'
    if source > 0 then
        TriggerClientEvent('cdecad-sync:client:notify', source, 'info', message)
    else
        print('[CDECAD-SYNC] ' .. message)
    end

    local vehicles_table = Config.vRP.VehiclesTable or 'vrp_user_vehicles'
    local identity_table = Config.vRP.IdentityTable or 'vrp_user_identities'

    local query = ([[
        SELECT v.user_id, v.vehicle, i.registration
        FROM %s v
        LEFT JOIN %s i ON i.user_id = v.user_id
    ]]):format(vehicles_table, identity_table)

    exports.oxmysql:execute(query, {}, function(vehicles)
        if not vehicles or #vehicles == 0 then
            local msg = 'No vehicles found in database'
            if source > 0 then
                TriggerClientEvent('cdecad-sync:client:notify', source, 'error', msg)
            else
                print('[CDECAD-SYNC] ' .. msg)
            end
            return
        end

        local vehicleList = {}
        for _, v in ipairs(vehicles) do
            local spawnName = v.vehicle or 'Unknown'
            local make, model = VehicleUtils.ResolveMakeModel(spawnName)
            local plate = v.registration or ('USER' .. tostring(v.user_id))
            local ownerSSN = (Config.vRP.UseRegistrationAsSSN and v.registration) or tostring(v.user_id)

            table.insert(vehicleList, {
                citizenid = ownerSSN,
                plate = plate,
                model = model,
                make = make,
                color = 'Unknown',
                year = os.date('%Y')
            })
        end

        local msg = 'Found ' .. #vehicleList .. ' vehicles. Syncing to CAD...'
        if source > 0 then
            TriggerClientEvent('cdecad-sync:client:notify', source, 'info', msg)
        else
            print('[CDECAD-SYNC] ' .. msg)
        end

        CDECAD_API.ForceSyncAllVehicles(vehicleList, function(success, data)
            local resultMsg
            if success then
                local stats = ''
                if data then
                    stats = string.format(' (Created: %s, Updated: %s, Skipped: %s)',
                        tostring(data.created or 0),
                        tostring(data.updated or 0),
                        tostring(data.skipped or 0)
                    )
                end
                resultMsg = 'Vehicle force sync complete!' .. stats
            else
                resultMsg = 'Vehicle force sync failed. Check server console.'
            end

            if source > 0 then
                TriggerClientEvent('cdecad-sync:client:notify', source, success and 'success' or 'error', resultMsg)
            else
                print('[CDECAD-SYNC] ' .. resultMsg)
            end
        end)
    end)
end, true)

-- Clear Discord role cache
RegisterCommand('cadclearcache', function(source, args)
    CDECAD_Discord.ClearAllCache()

    local message = 'Discord role cache cleared'

    if source > 0 then
        TriggerClientEvent('cdecad-sync:client:notify', source, 'success', message)
    else
        print('[CDECAD-SYNC] ' .. message)
    end
end, true)

-- =============================================================================
-- SUGGESTIONS (Tab completion)
-- =============================================================================

if Config.Calls.Enabled then
    TriggerEvent('chat:addSuggestion', '/' .. Config.Calls.Command, '911 Emergency Call', {
        { name = 'message', help = 'Describe your emergency' }
    })

    if Config.Calls.AllowAnonymous then
        TriggerEvent('chat:addSuggestion', '/' .. Config.Calls.AnonymousCommand, 'Anonymous 911 Call', {
            { name = 'message', help = 'Describe your emergency (anonymous)' }
        })
    end
end

TriggerEvent('chat:addSuggestion', '/reportstolen', 'Report your vehicle as stolen', {
    { name = 'description', help = 'Where/when was it stolen?' }
})

TriggerEvent('chat:addSuggestion', '/cadforcesyncvehicles', 'Force sync all vRP vehicles to CAD (Admin)', {})

print('[CDECAD-SYNC] Commands registered (vRP)')
