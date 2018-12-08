ICRaffle = ICRaffle or {}


-- Daily Roster Check --------------------------------------------------------
--
-- Once per day, scan the guild roster and history, record any new names.
-- Usually the history scan for GUILD_EVENT_GUILD_JOIN will catch all new
-- members. But the first time you run this add-on, there are usually
-- long-time members whose GUILD_EVENT_GUILD_JOIN event has fallen off the end
-- of history. So we have to scan the roster to get a complete roster.

function ICRaffle.DailyRosterCheck()
    self = ICRaffle
                        -- NOP if already checked once today.
    if not ICRaffle.DailyRosterCheckNeeded() then
        ICRaffle.Debug("Guild roster already saved once today. Done.")
        return
    end

    self.FetchHistoryStart()
end

function ICRaffle.DailyRosterCheckNeeded()
    self = ICRaffle
    if not (    self.saved_var 
            and self.saved_var.roster_last_scan_ts) then return true end
    if not (self.TodayTS() <= self.saved_var.roster_last_scan_ts) then
        return true
    end
    return false
end

function ICRaffle.TodayTS()
                        -- Copied straight from MasterMerchant_Guild.lua
                        -- Returns the timestamp for 12 midnight that started
                        -- today.
      return GetTimeStamp() - GetSecondsSinceMidnight()
end

-- Async guild history fetch and record --------------------------------------
--
-- Request history pages from server until there are no more to request. Then
-- scan through results.

function ICRaffle.FetchHistoryStart()
    self = ICRaffle
    self.Info("Fetching guild roster history...")
    self.guild_history_category = GUILD_HISTORY_GENERAL
    self.guild_id               = GetGuildId(self.saved_var.guild_index)

    EVENT_MANAGER:RegisterForEvent(
              self.name
            , EVENT_GUILD_HISTORY_RESPONSE_RECEIVED
            , ICRaffle.OnGuildHistoryResponseReceived
            )

    self.FetchHistoryFirstPage()
end

function ICRaffle.FetchHistoryFirstPage()
    self = ICRaffle
    local requested = RequestGuildHistoryCategoryNewest(    
                              self.guild_id
                            , self.guild_history_category )
    -- self.Debug("requested newest: %s",tostring(requested))
                        -- Returns false when there's no more to request.
    if not requested then
        self.OnFetchHistoryComplete()
    end
end

function ICRaffle.FetchHistoryNextPage()
    self = ICRaffle
    local requested = nil
    if not self.GuildHistoryOldEnough() then
                        -- Returns false when there's no more to request.
        requested = RequestGuildHistoryCategoryOlder(
                          self.guild_id
                        , self.guild_history_category )
        -- self.Debug("requested older: %s", tostring(requested))
    end
    if not requested then
        self.OnFetchHistoryComplete()
    end
end

                        -- After each page of results comes back, ask for the
                        -- next page.
function ICRaffle.OnGuildHistoryResponseReceived(event_code, guild_id, category)
    local self = ICRaffle
    self.ReportGuildHistoryStatus()   

                        -- Wait 2 seconds between requests to give UI time  to
                        -- breathe, and to avoid getting kicked from server for
                        -- too many requests. Could probably tighten this up to
                        -- 1 second or even less, but I'm in no hurry.
    zo_callLater(function() ICRaffle.FetchHistoryNextPage() end, 2*1000)
end

function ICRaffle.ReportGuildHistoryStatus()
    local event_ct = GetNumGuildEvents( 
                          self.guild_id
                        , self.guild_history_category )
    local event = { GetGuildEventInfo(
                          self.guild_id
                        , self.guild_history_category
                        , event_ct
                        ) }
    local secs_ago = (event and event[2])
    local time_ago = ""
    if secs_ago then
        time_ago = FormatTimeSeconds(
                  secs_ago
                , TIME_FORMAT_STYLE_SHOW_LARGEST_UNIT_DESCRIPTIVE
                )
        time_ago = time_ago .. " ago"
    end
    self.Debug("response received, event_ct: %d  %s",event_ct, time_ago)
end

function ICRaffle.GuildHistoryOldEnough()
    local self = ICRaffle
    if not self.saved_var.roster_last_scan_ts then return nil end
    local event_ct = GetNumGuildEvents(
                          self.guild_id
                        , self.guild_history_category )
    local event    = { GetGuildEventInfo(
                          self.guild_id
                        , self.guild_history_category
                        , event_ct
                        ) }
    local secs_ago = (event and event[2])
    local event_ts = ICRaffle.SecsAgoToTS(secs_ago)
    return event_ts < self.saved_var.roster_last_scan_ts
end

function ICRaffle.OnFetchHistoryComplete()
    self = ICRaffle
    EVENT_MANAGER:UnregisterForEvent(
              self.name
            , EVENT_GUILD_HISTORY_RESPONSE_RECEIVED )
    self.ScanHistory()
    self.ScanRoster()
    self.ScanRanks() -- could move this out to "only at explicit save" time.
end

local function earlier(a,b)
    if not a then return b end
    if not b then return a end
    if a < b then return a end
    return b
end

function ICRaffle.ScanHistory()
    self = ICRaffle
    self.oldest_join_ts = nil
    local event_ct = GetNumGuildEvents(
                          self.guild_id
                        , self.guild_history_category )
    local join_ct  = 0
    self.Debug("event_ct:"..tostring(event_ct))
    for i = 1,event_ct do
        local event = { GetGuildEventInfo(
                          self.guild_id
                        , self.guild_history_category, i ) }
        local j = self.RecordJoinEvent(event)
        join_ct = join_ct + j
    end
    self.saved_var.history = r
    self.Debug("guild history scan complete, event_ct:%d join_ct:%d"
            , event_ct, join_ct)
end

-- 1 GUILD_EVENT_GUILD_INVITE (eventType, secsAgo, invitor, invitee)
-- 7 GUILD_EVENT_GUILD_JOIN   (eventType, secsAgo, joiner,  invitor_optional)

function ICRaffle.RecordJoinEvent(event)
    self = ICRaffle
    if not event then return 0 end
    if event[1] == GUILD_EVENT_GUILD_JOIN then
        local join_ts = self.SecsAgoToTS(event[2])
        local invitee = event[3]
        local invitor = event[4] -- can be nil!
        local user    = self.User(invitee)
        user.join_ts = join_ts
        user.invitor = invitor or user.invitor
        self.oldest_join_ts = earlier(self.oldest_join_ts, join_ts)
        -- self.Debug("invitee:%s  invitor:%s join_ts:%d"
        --           , invitee, invitor, join_ts )
        return 1
    end
    return 0
end

function ICRaffle.ScanRoster()
    self = ICRaffle

                            -- Mark the unworthy for a later purge.
    self.user_records = self.user_records or {}                        
    for _,ur in pairs(self.user_records) do
        ur.is_member = nil
    end

                            -- Fetch complete, current, guild member list
    local guild_id = GetGuildId(self.saved_var.guild_index)
    local ct = GetNumGuildMembers(guild_id)
    for i = 1, ct do
        local user_id, note, rank_index = GetGuildMemberInfo(guild_id, i)
        local ur = self.User(user_id)
        ur.is_member  = true
        ur.rank_index = rank_index
        ur.guild_note = note
    end

                        -- Purge the unworthy
    local delete_list = {}
    for user_id,ur in pairs(self.user_records) do
        if not ur.is_member then
            table.insert(delete_list,user_id)
        end
    end
    for _,user_id in ipairs(delete_list) do
        self.user_records[user_id] = nil
    end
                        -- Record the survivors to saved variables.
    self.user_records = self.user_records or {}
    self.saved_var.roster_last_scan_ts = self.TodayTS()
    self.UserRecordsToSavedVars()
    self.Info("Guild roster saved. Member count: %d.", ct)
    self.Info("Will be written to SavedVariables next %s/reloadui|r %sor %s/logout|r."
             , ICRaffle.color.white
             , ICRaffle.color.grey
             , ICRaffle.color.white )
end

function ICRaffle.ScanRanks()
    self = ICRaffle
    local guild_rank = {}
    local guild_id   = GetGuildId(self.saved_var.guild_index)
    local rank_ct    = GetNumGuildRanks(guild_id)
    for rank_index = 1,rank_ct do
        local rank_name = GetGuildRankCustomName(guild_id, rank_index)
                        -- Kudos to Ayantir's GMen for pointing me to
                        -- GetFinalGuildRankName()
        if rank_name == "" then
            rank_name = GetFinalGuildRankName(guild_id, rank_index)
        end
        guild_rank[rank_index] = rank_name
    end
    self.saved_var.guild_rank = guild_rank
end
