
ICRaffle = ICRaffle or {}
                        -- Strings that appear in UI settings panel
ICRaffle.name            = "ICRaffle"
ICRaffle.saved_var_version = 1
ICRaffle.default = {
      mm_date_index = 4 -- "Last Week"
    , guild_index = 1
}

ICRaffle.max_guild_ct = MAX_GUILDS
ICRaffle.fetching = {}

ICRaffle.guild_name  = {} -- guild_name [guild_index] = "My Guild"
ICRaffle.guild_index = {} -- guild_index["My Guild" ] = 1
ICRaffle.guild_rank  = {} -- table of tables, gr[guild_index][rank]="Veteran"

                        -- When does the saved time range begin and end.
                        -- Seconds since the epoch.
                        -- Filled in at start of MMScan()
                        -- Either or both can be nil for "no limit".
ICRaffle.saved_begin_ts = 0
ICRaffle.saved_end_ts   = 0

                        -- key = user_id
                        -- value = UserRecord
ICRaffle.user_records = {}

                        -- retry_ct[guild_index] = how many retries after
                        -- distrusting "nah, no more history"
ICRaffle.retry_ct   = { 0, 0, 0, 0, 0 }
ICRaffle.max_retry_ct = 3
                        -- Filled in partially by MMDateRanges(), fully by FetchMMDateRanges()
ICRaffle.mm_date_ranges = nil

ICRaffle.color = {}
ICRaffle.color.dark  = "|c666666"
ICRaffle.color.grey  = "|c999999"
ICRaffle.color.red   = "|cFF6666"
ICRaffle.color.green = "|c66FF66"
ICRaffle.color.white = "|cFFFFFF"
function ICRaffle.Debug(msg, ...)
    d(ICRaffle.color.dark..ICRaffle.name..": "..string.format(msg, ...))
end
function ICRaffle.Info(msg, ...)
    d(ICRaffle.color.grey..ICRaffle.name..": "..string.format(msg, ...))
end
function ICRaffle.Error(msg, ...)
    d(ICRaffle.color.red ..ICRaffle.name..": "..string.format(msg, ...))
end

function ICRaffle.TodayTS()
                        -- Copied straight from MasterMerchant_Guild.lua
                        -- Returns the timestamp for 12 midnight that started
                        -- today.
      return GetTimeStamp() - GetSecondsSinceMidnight()
end

function ICRaffle.SecsAgoToTS(secs_ago)
    return GetTimeStamp() - secs_ago
end

function ICRaffle.SecsAgoToString(secs_ago)
    time_ago = FormatTimeSeconds(
              secs_ago
            , TIME_FORMAT_STYLE_SHOW_LARGEST_UNIT_DESCRIPTIVE
            )
    time_ago = time_ago .. " ago"
    return time_ago
end


function ICRaffle.TSCloseEnough(a,b)
                        -- There is JUST enough slop in timestamps, especially
                        -- when we're given "seconds ago" and then convert them
                        -- back to seconds-since-the-epoch, that "within 2
                        -- minutes" is close enough.
    return a and b and math.abs(a-b) < 120
end

function ICRaffle.Earlier(a, b)
    if not a then return b end
    if not b then return a end
    if a < b then return a end
    return b
end

function ICRaffle.Later(a, b)
    if not a then return b end
    if not b then return a end
    if a < b then return b end
    return a
end

function ICRaffle.Increment(a, incr_amount)
    if not a then return incr_amount or 1 end
    return a + (incr_amount or 1)
end

function ICRaffle.ReloadUIReminder()
    ICRaffle.Info("Will be written to SavedVariables next %s/reloadui|r %sor %s/logout|r."
             , ICRaffle.color.white
             , ICRaffle.color.grey
             , ICRaffle.color.white )
end

function ICRaffle.Reset()
    local field_names = {
                          "deposit_list"
                        , "deposit_list_schema"
                        , "guild_rank"
                        , "roster"
                        , "roster_last_scan_ts"
                        , "roster_schema"
                        , "sale_list"
                        , "sale_list_schema"
                        }
    for _,fn in ipairs(field_names) do
        ICRaffle.saved_var[fn] = nil
    end
    ICRaffle.Info("Data reset.")
end

-- Slash Commands ------------------------------------------------------------

function ICRaffle.RegisterSlashCommands()
                        -- Optional support for Sirinsidiator's most excellent
                        -- LibSlashCommander, which gives autocompletion and
                        -- command help strings.
    local lsc = LibStub:GetLibrary("LibSlashCommander", true)
    if lsc then
        local cmd = lsc:Register( "/icraffle"
                                , function(arg) ICRaffle.SlashCommand(arg) end
                                , "Record guild sales and bank deposit history")

        local sub_reset = cmd:RegisterSubCommand()
        sub_reset:AddAlias("reset")
        sub_reset:SetCallback(function() ICRaffle.SlashCommand("reset") end)
        sub_reset:SetDescription("Reset data. Mostly for debugging.")

        local sub_roster = cmd:RegisterSubCommand()
        sub_roster:AddAlias("roster")
        sub_roster:SetCallback(function() ICRaffle.SlashCommand("roster") end)
        sub_roster:SetDescription("Fetch guild roster. Mostly for debugging.")
    else
        SLASH_COMMANDS["/icraffle"] = ICRaffle.SlashCommand
    end
end

function ICRaffle.SlashCommand(arg)
    if arg == "reset" then
        ICRaffle.Reset()
    elseif arg == "roster" then
        ICRaffle.FetchRosterHistoryStart()
    else
        ICRaffle.StartTheBigScan()
    end
end

function ICRaffle.StartTheBigScan()
    if ICRaffle.GuildHistoryFetcher.ErrorIfBusy() then return end

                        -- Scan Master Merchant first, since it runs
                        -- synchronously and near-instantaneously.
    ICRaffle.MMScan()

                        -- Guild bank gold deposit scan is async and
                        -- might take a few seconds. Start it and walk away.
    ICRaffle.FetchBankHistoryStart()
end

-- Init ----------------------------------------------------------------------

function ICRaffle.OnAddOnLoaded(event, addonName)
    if addonName ~= ICRaffle.name then return end
    ICRaffle:Initialize()
end

function ICRaffle:Initialize()
    self.saved_var = ZO_SavedVars:NewAccountWide(
                              "ICRaffleVars"
                            , self.saved_var_version
                            , nil
                            , self.default
                            )
    self.SavedVarsToUserRecords()
    -- self:CreateSettingsWindow()

    self.RegisterSlashCommands()
end


-- Postamble -----------------------------------------------------------------

EVENT_MANAGER:RegisterForEvent( ICRaffle.name
                              , EVENT_ADD_ON_LOADED
                              , ICRaffle.OnAddOnLoaded
                              )

                        -- Need to call DailyRosterCheck() from a function()
                        -- wrapper here because DailyRosterCheck() is not
                        -- defined in this file or by the time we execute this
                        -- code at load time.
EVENT_MANAGER:RegisterForEvent( ICRaffle.name
                              , EVENT_PLAYER_ACTIVATED
                              , function() ICRaffle.DailyRosterCheck() end
                              )
