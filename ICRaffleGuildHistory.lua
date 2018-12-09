ICRaffle = ICRaffle or {}


-- Generic guild history fetcher ---------------------------------------------
--
-- Both Guild Roster and Guild Bank history live on the ESO server, and are
-- sent to the ESO client only on request, and only a page at a time. If you
-- want to iterate over history, you need to repeatedly call ZOS API
-- RequestGuidlHistoryCategoryOlder(), going further and further back in time,
-- until you've fetched enough for your needs.

ICRaffle.GuildHistoryFetcher = {}

local GuildHistoryFetcher   = ICRaffle.GuildHistoryFetcher
GuildHistoryFetcher.next_id = 1

function GuildHistoryFetcher:New(args)
    local o = {
          guild_id               = args.guild_id
        , guild_history_category = args.guild_history_category
        , old_enough_ts          = args.old_enough_ts
        , func_complete          = args.func_complete
        , progress_msg           = args.progress_msg
                                     or "fetching...  event_ct: %d  %s"
        , page_delay_ms          = args.page_delay_ms or 2 * 1000
        }
    o.id = ICRaffle.name .. "_ghf_" .. tostring(GuildHistoryFetcher.next_id)
    GuildHistoryFetcher.next_id = GuildHistoryFetcher.next_id + 1
    setmetatable(o,self)
    self.__index = self
    return o
end

function GuildHistoryFetcher:Start()
    EVENT_MANAGER:RegisterForEvent(
              self.id
            , EVENT_GUILD_HISTORY_RESPONSE_RECEIVED
            , function() self:OnGuildHistoryResponseReceived() end
            )

    self:FetchFirstPage()
end

function GuildHistoryFetcher:FetchFirstPage()
    local requested = RequestGuildHistoryCategoryNewest(
                              self.guild_id
                            , self.guild_history_category )
    ICRaffle.Debug("requested newest: %s",tostring(requested))
    if not requested then
        self:OnFetchComplete()
    end
end

function GuildHistoryFetcher:FetchNextPage()
    local requested = nil
    if not self:OldEnough() then
        requested = RequestGuildHistoryCategoryOlder(
                          self.guild_id
                        , self.guild_history_category )
        ICRaffle.Debug("requested older: %s", tostring(requested))
    end
    if not requested then
        self:OnFetchComplete()
    end
end

                        -- After each page of results comes back, ask for the
                        -- next page.
function GuildHistoryFetcher:OnGuildHistoryResponseReceived(event_code, guild_id, category)
    self:ReportProgress()

                        -- Wait 2 seconds between requests to give UI time to
                        -- breathe, and to avoid getting kicked from server for
                        -- too many requests. Could probably tighten this up to
                        -- 1 second or even less, but I'm in no hurry.
    zo_callLater(function() self:FetchNextPage() end, self.page_delay_ms)
end

function GuildHistoryFetcher:ReportProgress()
    local secs_ago, event_ct = self:Oldest()
    local time_ago = ""
    if secs_ago then
        time_ago = ICRaffle.SecsAgoToString(secs_ago)
    end
    ICRaffle.Info(self.progress_msg, event_ct, time_ago)
end

function GuildHistoryFetcher:OldEnough()
    if not self.old_enough_ts then return nil end
    local secs_ago, event_ct = self:Oldest()
    local event_ts = ICRaffle.SecsAgoToTS(secs_ago)
    return event_ts < self.old_enough_ts
end

function GuildHistoryFetcher:Oldest()
    local event_ct = GetNumGuildEvents(
                          self.guild_id
                        , self.guild_history_category )
    local event_code, secs_ago = GetGuildEventInfo(
                          self.guild_id
                        , self.guild_history_category
                        , event_ct
                        )
    return secs_ago, event_ct
end

function GuildHistoryFetcher:OnFetchComplete()
    ICRaffle.Debug("unregistered for guild history")
    EVENT_MANAGER:UnregisterForEvent(
              self.id
            , EVENT_GUILD_HISTORY_RESPONSE_RECEIVED )
    if self.func_complete then
        self.func_complete()
    end
end
