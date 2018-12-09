ICRaffle = ICRaffle or {}

MM = MasterMerchant

                        -- Return a partially initialized date range table.
                        -- Names are there, but start/end timestamps not yet:
                        -- those don't get filled in until SaveNow() calls
                        -- FetchMMDateRanges().
function ICRaffle.MMDateRanges()
    if ICRaffle.mm_date_ranges then
        return ICRaffle.mm_date_ranges
    end

    local r   = {}
    r[1] = { name = "Today"        }
    r[2] = { name = "Yesterday"    }
    r[3] = { name = "This Week"    }
    r[4] = { name = "Last Week"    }
    r[5] = { name = "Prior Week"   }
    r[6] = { name = "Last 10 Days" }
    r[7] = { name = "Last 30 Days" }
    r[8] = { name = "Last 7 Days"  }
    r[9] = { name = "All History" }
    ICRaffle.mm_date_ranges = r
    return ICRaffle.mm_date_ranges
end

                        -- Lazy fetch timestamps for M.M. date ranges.
function ICRaffle.FetchMMDateRanges()
    local mmg = MMGuild:new("_not_really_a_guild")
    local r   = ICRaffle.MMDateRanges()
    r[1].start_ts = mmg.oneStart        -- Today
    r[1].end_ts   = nil
    r[2].start_ts = mmg.twoStart        -- Yesterday
    r[2].end_ts   = mmg.oneStart
    r[3].start_ts = mmg.threeStart      -- This Week
    r[3].end_ts   = nil
    r[4].start_ts = mmg.fourStart       -- Last Week
    r[4].end_ts   = mmg.fourEnd
    r[5].start_ts = mmg.fiveStart       -- Prior Week
    r[5].end_ts   = mmg.fiveEnd
    r[6].start_ts = mmg.sixStart        -- Last 10 Days
    r[6].end_ts   = nil
    r[7].start_ts = mmg.sevenStart      -- Last 30 Days
    r[7].end_ts   = nil
    r[8].start_ts = mmg.eightStart      -- Last 7 Days
    r[8].end_ts   = nil
                        -- Replace MM's "custom" date range with "All".
                        -- (Not worth the effort: I would have to dynamically
                        -- reload each time I updated UI or ran a scan)
    r[9].start_ts = nil
    r[9].end_ts   = nil
    ICRaffle.mm_date_ranges = r
    return ICRaffle.mm_date_ranges
end

                        -- Fill in begin/end timestamps for "Last Week"
function ICRaffle.MMCalcSavedTS()
    local self = ICRaffle
                        -- Use the start/end timestamps chosen from
                        -- the UI dropdown.
    local i = self.saved_var.mm_date_index
    local r = self.FetchMMDateRanges()
    self.saved_begin_ts = r[i].start_ts
    self.saved_end_ts   = r[i].end_ts
end

