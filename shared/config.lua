--[[
    CDECAD Sync Configuration for vRP
    Configure your CDECAD API connection and sync settings
]]

Config = {}

-- =============================================================================
-- API CONFIGURATION
-- =============================================================================
Config.API_URL = ''
Config.API_KEY = ''
Config.COMMUNITY_ID = ''

-- =============================================================================
-- POSTAL CODE SETTINGS
-- =============================================================================

Config.Postal = {
    -- Enable postal code integration
    Enabled = true,

    -- Which postal resource to use
    -- Options:
    --   'nearest-postal' - Uses exports['nearest-postal']:getPostal() (most common)
    --   'npostal'        - Uses exports.npostal:npostal()
    --   'custom'         - Use your own export (set CustomExport and CustomFunction below)
    Resource = 'nearest-postal',

    -- Custom export settings (only used if Resource = 'custom')
    CustomExport = 'your-postal-resource',
    CustomFunction = 'getPostal',

    -- Include postal in 911 call location string
    IncludeIn911 = true,

    -- Include postal in location updates
    IncludeInLocation = true,

    -- Format for displaying postal in location string
    -- Use {postal} as placeholder for the postal code
    -- Use {street} for street name, {zone} for zone name
    LocationFormat = '{street}, {zone} (Postal: {postal})',

    -- Format when postal is not available
    LocationFormatNoPostal = '{street}, {zone}',

    -- Fallback text when postal is unavailable
    FallbackText = nil  -- Set to nil to just omit postal, or 'Unknown' etc.
}

-- =============================================================================
-- SYNC SETTINGS
-- =============================================================================

Config.Sync = {
    -- Automatically sync character data when player spawns
    OnCharacterLoad = true,

    -- Automatically sync when character is first created (vRP:playerJoin first_login)
    OnCharacterCreate = true,

    -- Sync character updates (identity changes via vRP.updateUserIdentity)
    OnCharacterUpdate = true,

    -- Delete civilian from CAD when user is deleted via vRP admin
    OnCharacterDelete = true,

    -- Sync vehicles when purchased/registered
    SyncVehicles = true,

    -- Sync vehicle status changes (stolen, etc.)
    SyncVehicleStatus = true,

    -- How often to send location updates (in seconds, 0 to disable)
    LocationUpdateInterval = 30,

    -- Only send location for on-duty players
    LocationOnDutyOnly = true
}

-- =============================================================================
-- DISCORD ROLE INTEGRATION (Optional)
-- =============================================================================

Config.Discord = {
    -- Enable Discord role checking
    Enabled = true,

    -- Use Badger_Discord_API (recommended)
    UseBadgerAPI = true,

    -- If not using Badger API, set your Discord Bot Token here
    BotToken = '',

    -- Roles that should NOT be synced to civilian CAD
    -- (LEO, Fire, EMS characters are usually handled separately)
    ExcludedRoles = {
        'Police',
        'Sheriff',
        'State Police',
        'Fire',
        'EMS',
        'Dispatch'
    },

    -- Role IDs that should NOT be synced (add your actual role IDs)
    ExcludedRoleIds = {
        -- '1234567890123456789', -- Example Police Role ID
        -- '9876543210987654321', -- Example EMS Role ID
    },

    -- If player has any of these roles, they WILL be synced regardless
    -- Useful for "Civilian" role that LEO players might also have
    ForceSyncRoles = {
        'Civilian',
        'Member'
    }
}

-- =============================================================================
-- 911 CALL SETTINGS
-- =============================================================================

Config.Calls = {
    -- Enable 911 command
    Enabled = true,

    -- Command name for 911 calls
    Command = '911',

    -- Also register as /call911
    AlternateCommand = 'call911',

    -- Send player coordinates with 911 calls
    SendCoordinates = true,

    -- Send postal code (requires Config.Postal.Enabled = true)
    SendPostal = true,

    -- Cooldown between 911 calls (in seconds)
    Cooldown = 30,

    -- Allow anonymous 911 calls
    AllowAnonymous = true,

    -- Anonymous call command
    AnonymousCommand = '911anon',

    -- Notify player when call is received
    NotifyOnSuccess = true,

    -- Notify player when call is assigned to unit
    NotifyOnAssignment = true
}

-- =============================================================================
-- NPC REPORTS (Automated crime reports)
-- =============================================================================

Config.NPCReports = {
    -- Enable NPC witness reports
    Enabled = true,

    -- Report gunshots heard
    Gunshots = {
        Enabled = true,
        Cooldown = 60, -- Seconds between reports from same area
        Radius = 200.0 -- How close NPCs need to be to "hear" shots
    },

    -- Report vehicle theft
    VehicleTheft = {
        Enabled = true,
        Cooldown = 120
    },

    -- Report fights/assaults
    Fights = {
        Enabled = true,
        Cooldown = 60
    },

    -- Report speeding (requires speed camera setup)
    SpeedCamera = {
        Enabled = false,
        SpeedLimit = 80 -- mph over this triggers report
    }
}

-- =============================================================================
-- FIELD MAPPING
-- =============================================================================

-- Map vRP identity fields to CDECAD civilian fields
-- vRP stores character data in the vrp_user_identities table
Config.FieldMapping = {
    -- vRP user_identities table -> CDECAD Civilian
    firstName = 'firstname',      -- user_identities.firstname
    lastName = 'name',            -- user_identities.name (lastname in vRP)
    age = 'age',                  -- user_identities.age (numeric, used to derive DoB)
    phone = 'phone',              -- user_identities.phone
    registration = 'registration',-- user_identities.registration (unique plate/SSN)

    -- vRP doesn't natively store gender; this is optional metadata
    gender = 'sex'
}

-- Group/permission names that should be treated as "non-civilian" for sync
-- (LEO/EMS/Fire jobs handled outside the civilian CAD)
Config.ExcludedGroups = {
    'police',
    'sheriff',
    'ems',
    'fire',
    'dispatch'
}

-- Gender mapping (vRP has no native gender field — these are normalized
-- in case a custom identity addon provides one).
Config.GenderMapping = {
    ['m'] = 'Male',
    ['f'] = 'Female',
    ['male'] = 'Male',
    ['female'] = 'Female',
    [0] = 'Male',
    [1] = 'Female'
}

-- =============================================================================
-- vRP-SPECIFIC SETTINGS
-- =============================================================================

Config.vRP = {
    -- Whether to derive a date-of-birth from vRP's `age` field.
    -- vRP only stores age (integer). When true, dateOfBirth is set to
    -- (currentYear - age) - 01 - 01 so CAD has a usable DoB.
    DeriveDateOfBirth = true,

    -- Use the vRP `registration` field as the civilian SSN. This is the
    -- unique plate-style identifier vRP issues to each user.
    UseRegistrationAsSSN = true,

    -- vRP identity table name (default: vrp_user_identities).
    -- Override if your server uses a custom identity schema.
    IdentityTable = 'vrp_user_identities',

    -- vRP vehicles table name (default: vrp_user_vehicles).
    VehiclesTable = 'vrp_user_vehicles',

    -- Number of seconds to wait after playerSpawn before pulling identity
    -- (gives custom identity addons time to populate the row).
    SpawnSyncDelay = 2
}

-- =============================================================================
-- NOTIFICATIONS
-- =============================================================================

Config.Notifications = {
    -- Use ox_lib notifications
    UseOxLib = true,

    -- Notification duration (ms)
    Duration = 5000,

    -- Notification position
    Position = 'top-right'
}

-- =============================================================================
-- DEBUG SETTINGS
-- =============================================================================

Config.Debug = {
    -- Enable debug prints
    Enabled = false,

    -- Log all API requests
    LogRequests = false,

    -- Log all API responses
    LogResponses = false
}

-- =============================================================================
-- LOCALE / MESSAGES
-- =============================================================================

Config.Locale = {
    ['911_sent'] = '911 call sent! Units have been dispatched.',
    ['911_cooldown'] = 'Please wait before making another 911 call.',
    ['911_invalid'] = 'Usage: /911 [message]',
    ['sync_success'] = 'Character synced to CAD.',
    ['sync_failed'] = 'Failed to sync character to CAD.',
    ['vehicle_registered'] = 'Vehicle registered in CAD.',
    ['vehicle_reported_stolen'] = 'Vehicle reported as stolen.',
    ['not_authorized'] = 'You are not authorized for this action.',
    ['cad_offline'] = 'CAD system is currently offline.'
}
