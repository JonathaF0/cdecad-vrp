local function getConvar(name, default)
    local value = GetConvar(name, '')
    if value == nil or value == '' then return default end
    return value
end

local baseUrl = getConvar('CDE_CAD_API_URL', '')
if baseUrl ~= '' and not baseUrl:find('/api$') then
    Config.API_URL = baseUrl:gsub('/$', '') .. '/api'
else
    Config.API_URL = baseUrl:gsub('/$', '')
end

Config.API_KEY      = getConvar('CDE_CAD_API_KEY', '')
Config.COMMUNITY_ID = getConvar('CDE_CAD_COMMUNITY_ID', '')

if Config.API_KEY == '' then
    print('^1[CDECAD-SYNC-VRP] CDE_CAD_API_KEY convar is not set. CAD requests will fail. Add to server.cfg: set CDE_CAD_API_KEY "fvm_..."^0')
end
if Config.COMMUNITY_ID == '' then
    print('^1[CDECAD-SYNC-VRP] CDE_CAD_COMMUNITY_ID convar is not set. Add to server.cfg: set CDE_CAD_COMMUNITY_ID "..."^0')
end
