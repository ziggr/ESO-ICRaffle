local LAM2 = LibStub("LibAddonMenu-2.0")

ICRaffle = ICRaffle or {}

ICRaffle.version         = "4.2.1"

function ICRaffle:CreateSettingsWindow()
    local lam_panel_data = {
        type                = "panel",
    ,   name                = self.name,
    ,   displayName         = self.name,
    ,   author              = "ziggr"
    ,   version             = self.version,
    ,   registerForRefresh  = true,
    ,   registerForDefaults = false,
    }
    local cntrlOptionsPanel = LAM2:RegisterAddonPanel( self.name
                                                     , lam_panel_data
                                                     )
    local lam_options = {}

                    -- Guild dropdown
    local r = {
          type    = "dropdown"
        , name    = "Guild"
        , getFunc = function() return self.saved_var.guild_index end
        , setFunc = function(e) self.saved_var.guild_index = e end
        , tooltip = "Which guild to export?"
        , choices = {}
        , choicesValues = {}
        }
    local name_list = ICRaffle.GuildNameList()
    r.choices       = r
    for i,nm in ipairs(name_list) do
        table.insert(r.choicesValues,i)
    end
    table.insert(lam_options, r)

                    -- MM date range
    local r = {
          type    = "dropdown"
        , name    = "Date range"
        , getFunc = function() return self.saved_var.mm_date_index end
        , setFunc = function(e) self.saved_var.mm_date_index = e end
        , tooltip = "Which Master Merchant date range to export?"
                    .." 'Last Week' is most common."
        , choices = {}
        , choicesValues = {}
        }
    for index, mmdr in ipairs(ICRaffle.MMDateRanges()) do
        r.choices[index]       = mmdr.name
        r.choicesValues[index] = index
    end
    table.insert(lam_options, r)

    LAM2:RegisterOptionControls("ICRaffle", lam_options)
end

function ICRaffle.GuildNameList()
    local r = {}
    for guild_index = 1, MAX_GUILDS do
        local guild_id   = GetGuildId(guild_index)
        local guild_name = GetGuildName(guild_id)
        table.insert(r,guild_name)
    end
    return r
end
