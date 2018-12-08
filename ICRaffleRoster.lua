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
        --ICRaffle.Info("Guild roster already saved once today. Done.")
        return
    end

    self.Info("saving guild rosters...")
    self.FetchHistoryStart()
    -- local ct = self.RememberMembers()
    -- self.Info("saved %d guild members. Done.", ct)

    -- if not self.saved_var.roster then self.saved_var.roster = {} end
    -- self.saved_var.roster.last_scan_ts = self.TodayTS()
end

function ICRaffle.DailyRosterCheckNeeded()
    self = ICRaffle
    if not (    self.saved_var 
            and self.saved_var.roster
            and self.saved_var.roster.last_scan_ts) then return true end
    if not (self.TodayTS() <= self.saved_var.roster.last_scan_ts)  then return true end
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
    self.gh_category = GUILD_HISTORY_GENERAL
    self.guild_id    = GetGuildId(self.saved_var.guild_index)

    EVENT_MANAGER:RegisterForEvent(
              self.name
            , EVENT_GUILD_HISTORY_RESPONSE_RECEIVED
            , ICRaffle.OnGuildHistoryResponseReceived
            )

    self.FetchHistoryFirstPage()
end

function ICRaffle.FetchHistoryFirstPage()
    self = ICRaffle
    local requested = RequestGuildHistoryCategoryNewest(self.guild_id, self.gh_category)
    self.Debug("requested newest: %s",tostring(requested))
                        -- Returns false when there's no more to request.
    if not requested then
        self.OnFetchHistoryComplete()
    end
end

function ICRaffle.FetchHistoryNextPage()
    self = ICRaffle
    local requested = RequestGuildHistoryCategoryOlder(self.guild_id, self.gh_category)
    self.Debug("requested older: %s", tostring(requested))
                        -- Returns false when there's no more to request.
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
    local event_ct = GetNumGuildEvents(self.guild_id, self.gh_category)
    local event = { GetGuildEventInfo(self.guild_id, self.gh_category, event_ct) }
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

function ICRaffle.OnFetchHistoryComplete()
    self = ICRaffle
    self.ScanHistory()
    self.ScanRoster()
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
    local event_ct = GetNumGuildEvents(self.guild_id, self.gh_category)
    local join_ct  = 0
    self.Debug("event_ct:"..tostring(event_ct))
    for i = 1,event_ct do
        local x = { GetGuildEventInfo(self.guild_id, self.gh_category, i) }
        local j = self.RecordJoinEvent(x)
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
        return 1
    end
    return 0
end

function ICRaffle.ScanRoster()
    self = ICRaffle
    local roster = self.RosterList()
    -- ...
end

-- function ICRaffle:RememberMembers(guild_index)
--     local today_ts = self.TodayTS()
--     local prev     = {}
--     local new      = {}
--     if self.saved_var.roster and self.saved_var.roster[guild_index] then
--         prev = self.saved_var.roster[guild_index]
--     end

--     local curr = self.RosterList(guild_index)
--     for i, user_id in ipairs(curr) do
--                         -- Retain any survivors from before.
--                         -- or create new record for newbies.
--         new[user_id] = prev[user_id] or { first_seen_ts = today_ts }
--     end

--     if not self.saved_var.roster then self.saved_var.roster = {} end
--     self.saved_var.roster[guild_index] = new
--     return #curr
-- end

function ICRaffle.RosterList()
    self = ICRaffle
    local member_names = {}
    local guildId = GetGuildId(self.saved_var.guild_index)
    local ct      = GetNumGuildMembers(guildId)
    for i = 1, ct do
        local user_id = GetGuildMemberInfo(guildId, i)
        table.insert(member_names, user_id)
    end
    return member_names
end



-- function ICRaffle:RememberMembersAllEnabledGuilds()
--     self.saved_var.guild_name = self:GuildNameList()
--     local ct = 0
--     for guild_index = 1, self.max_guild_ct do
--         if self.saved_var.enable_guild[guild_index] then
--             ct = ct + self:RememberMembers(guild_index)
--         end
--     end
--     return ct
-- end

