local LAM2 = LibStub("LibAddonMenu-2.0")

ICRaffle = ICRaffle or {}

ICRaffle.version         = "4.2.1"

function ICRaffle.CreateSettingsWindow()
    local self = ICRaffle

    local lam_addon_id = "ICRaffle_LAM"
    local lam_panel_data = {
        type                = "panel"
    ,   name                = self.name
    ,   displayName         = self.name
    ,   author              = "ziggr"
    ,   version             = self.version
    ,   registerForRefresh  = true
    ,   registerForDefaults = false
    }
    local cntrlOptionsPanel = LAM2:RegisterAddonPanel( lam_addon_id
                                                     , lam_panel_data
                                                     )
    local lam_options = {}

                    -- Guild dropdown
    local g = {
          type    = "dropdown"
        , name    = "Guild"
        , getFunc = function() return self.saved_var.guild_index end
        , setFunc = function(e)
                        if e ~= self.saved_var.guild_index then
                            self.saved_var.guild_index = e
                            self.Reset()
                        end
                    end
        , tooltip = "Which guild to export?"
        , choices = {}
        , choicesValues = {}
        }
    local name_list = ICRaffle.GuildNameList()
    for index,name in ipairs(name_list) do
        g.choices[index]       = name
        g.choicesValues[index] = index
    end
    table.insert(lam_options, g)

                    -- MM date range
    local r = {
          type    = "dropdown"
        , name    = "Date range"
        , getFunc = function() return self.saved_var.mm_date_index end
        , setFunc = function(e)
                        if e ~= self.saved_var.mm_date_index then
                            self.saved_var.mm_date_index = e
                            self.Reset()
                        end
                    end
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

                        -- Scan Now button
    local b = {
          type      = "button"
        , name      = "Scan Now"
        , tooltip   = "Record guild sales and bank deposit history."
        , func      = function() ICRaffle.StartTheBigScan() end
        }
    table.insert(lam_options, b)

    LAM2:RegisterOptionControls(lam_addon_id, lam_options)
end
