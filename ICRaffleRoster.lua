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
    self.roster_fetcher = ICRaffle.GuildHistoryFetcher:New(
        { guild_id      = GetGuildId(self.saved_var.guild_index)
        , guild_history_category = GUILD_HISTORY_GENERAL
        , old_enough_ts = self.saved_var.roster_last_scan_ts
        , func_complete = ICRaffle.OnFetchRosterHistoryComplete
        })
    self.roster_fetcher:Start()
end


function ICRaffle.OnFetchRosterHistoryComplete()
    self = ICRaffle
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
    local guild_id = GetGuildId(self.saved_var.guild_index)
    local event_ct = GetNumGuildEvents(
                          guild_id
                        , GUILD_HISTORY_GENERAL )
    local join_ct  = 0
    self.Debug("event_ct:"..tostring(event_ct))
    for i = 1,event_ct do
        local event = { GetGuildEventInfo(
                          guild_id
                        , GUILD_HISTORY_GENERAL
                        , i ) }
        local j = self.RecordJoinEvent(event)
        join_ct = join_ct + (j or 0)
        if not j then
            self.RecordLeaveEvent(event)
        end
    end
    self.Debug("Roster history scan complete, event_ct:%d join_ct:%d"
            , event_ct, join_ct)
end

-- 1 GUILD_EVENT_GUILD_INVITE (eventType, secsAgo, invitor, invitee)
-- 7 GUILD_EVENT_GUILD_JOIN   (eventType, secsAgo, joiner,  invitor_optional)

function ICRaffle.RecordJoinEvent(event)
    self = ICRaffle
    if not event then return nil end
    if event[1] == GUILD_EVENT_GUILD_JOIN then
        local join_ts = self.SecsAgoToTS(event[2])
        local invitee = event[3]
        local invitor = event[4] -- can be nil!
        local user    = self.User(invitee)
                        -- Did we already record this join?
        if user.invitor == invitor
                and self.TSCloseEnough(user.join_ts, join_ts) then
            return nil
        end

        user.join_ts = join_ts
        user.invitor = invitor or user.invitor
        self.oldest_join_ts = earlier(self.oldest_join_ts, join_ts)
        local ago_string = self.SecsAgoToString(event[2])
        self.Debug("invitee:%s  invitor:%s %s"
                  , invitee, invitor, ago_string )
        return 1
    end
    return nil
end

-- 12 GUILD_EVENT_GUILD_KICKED  name name
--  8 GUILD_EVENT_GUILD_LEAVE   name

function ICRaffle.RecordLeaveEvent(event)
    self = ICRaffle
    if not event then return nil end
    if event[1] == GUILD_EVENT_GUILD_LEAVE then
        local leave_ts = self.SecsAgoToTS(event[2])
        local leaver   = event[3]
        local user     = self.User(leaver)
                        -- Did we already record this leave?
        if self.TSCloseEnough(user.leave_ts, leave_ts) then
            return nil
        end

        user.leave_ts = leave_ts

        local ago_string = self.SecsAgoToString(event[2])
        self.Debug("left:%s   %s"
                  , leaver, ago_string )
        return 1
    elseif event[1] == GUILD_EVENT_GUILD_KICKED then
        local leave_ts = self.SecsAgoToTS(event[2])
        local kicker   = event[3]
        local leaver   = event[4]
        local user     = self.User(leaver)
                        -- Did we already record this leave?
        if self.TSCloseEnough(user.leave_ts, leave_ts) then
            return nil
        end

        user.leave_ts = leave_ts
        user.kicker   = kicker

        local ago_string = self.SecsAgoToString(event[2])
        self.Debug("kicked:%s by %s  %s"
                  , leaver, kicker, ago_string )
        return 1
    end
    return nil
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
