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

    self.FetchRosterHistoryStart()
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


-- Async guild history fetch and record --------------------------------------
--
-- Request history pages from server until there are no more to request. Then
-- scan through results.

function ICRaffle.FetchRosterHistoryStart()
    self = ICRaffle
    self.Info("Fetching guild roster history...")
    self.guild_history_category = GUILD_HISTORY_GENERAL
    self.guild_id               = GetGuildId(self.saved_var.guild_index)

    EVENT_MANAGER:RegisterForEvent(
              self.name .. "_roster"
            , EVENT_GUILD_HISTORY_RESPONSE_RECEIVED
            , ICRaffle.OnGuildRosterHistoryResponseReceived
            )

    self.FetchRosterHistoryFirstPage()
end

function ICRaffle.FetchRosterHistoryFirstPage()
    self = ICRaffle
    local requested = RequestGuildHistoryCategoryNewest(
                              self.guild_id
                            , self.guild_history_category )
    -- self.Debug("requested newest: %s",tostring(requested))
                        -- Returns false when there's no more to request.
    if not requested then
        self.OnFetchRosterHistoryComplete()
    end
end

function ICRaffle.FetchRosterHistoryNextPage()
    self = ICRaffle
    local requested = nil
    if not self.GuildRosterHistoryOldEnough() then
                        -- Returns false when there's no more to request.
        requested = RequestGuildHistoryCategoryOlder(
                          self.guild_id
                        , self.guild_history_category )
        -- self.Debug("requested older: %s", tostring(requested))
    end
    if not requested then
        self.OnFetchRosterHistoryComplete()
    end
end

                        -- After each page of results comes back, ask for the
                        -- next page.
function ICRaffle.OnGuildRosterHistoryResponseReceived(event_code, guild_id, category)
    local self = ICRaffle
    self.ReportRosterHistoryStatus()

                        -- Wait 2 seconds between requests to give UI time  to
                        -- breathe, and to avoid getting kicked from server for
                        -- too many requests. Could probably tighten this up to
                        -- 1 second or even less, but I'm in no hurry.
    zo_callLater(function() ICRaffle.FetchRosterHistoryNextPage() end, 2*1000)
end

function ICRaffle.ReportRosterHistoryStatus()
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
        time_ago = self.SecsAgoToString(secs_ago)
    end
    self.Debug("response received, event_ct: %d  %s",event_ct, time_ago)
end

function ICRaffle.GuildRosterHistoryOldEnough()
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

function ICRaffle.OnFetchRosterHistoryComplete()
    self = ICRaffle
    EVENT_MANAGER:UnregisterForEvent(
              self.name .. "_roster"
            , EVENT_GUILD_HISTORY_RESPONSE_RECEIVED )
    self.ScanRosterHistory()
    self.ScanRoster()
    self.ScanRanks() -- could move this out to "only at explicit save" time.
end

local function earlier(a,b)
    if not a then return b end
    if not b then return a end
    if a < b then return a end
    return b
end

function ICRaffle.ScanRosterHistory()
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
        if j == 0 then
            self.RecordLeaveEvent(event)
        end
    end
    self.saved_var.history = r
    self.Debug("Roster history scan complete, event_ct:%d join_ct:%d"
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
                        -- Did we already record this join?
        if user.invitor == invitor
                and self.TSCloseEnough(user.join_ts, join_ts) then
            return 0
        end

        user.join_ts = join_ts
        user.invitor = invitor or user.invitor
        self.oldest_join_ts = earlier(self.oldest_join_ts, join_ts)
        local ago_string = self.SecsAgoToString(event[2])
        self.Debug("invitee:%s  invitor:%s %s"
                  , invitee, invitor, ago_string )
        return 1
    end
    return 0
end

-- 12 GUILD_EVENT_GUILD_KICKED  name name
--  8 GUILD_EVENT_GUILD_LEAVE   name

function ICRaffle.RecordLeaveEvent(event)
    self = ICRaffle
    if not event then return 0 end
    if event[1] == GUILD_EVENT_GUILD_LEAVE then
        local leave_ts = self.SecsAgoToTS(event[2])
        local leaver   = event[3]
        local user     = self.User(leaver)
                        -- Did we already record this leave?
        if self.TSCloseEnough(user.leave_ts, leave_ts) then
            return 0
        end

        user.leave_ts = leave_ts

        local ago_string = self.SecsAgoToString(event[2])
        self.Debug("left:%s   %s"
                  , leaver, ago_string )
        return 1
    elseif event[1] == GUILD_EVENT_GUILD_KICKED then
        local leave_ts = self.SecsAgoToTS(event[2])
        local leaver   = event[3]
        local kicker   = event[4]
        local user     = self.User(leaver)
                        -- Did we already record this leave?
        if self.TSCloseEnough(user.leave_ts, leave_ts) then
            return 0
        end

        user.leave_ts = leave_ts
        user.kicker   = kicker

        local ago_string = self.SecsAgoToString(event[2])
        self.Debug("kicked:%s by %s  %s"
                  , leaver, kicker, ago_string )
        return 1
    end
    return 0
end

function ICRaffle.ScanRoster()
    self = ICRaffle

                            -- Unless we see you in the roster right now,
                            -- you're not a member.
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
