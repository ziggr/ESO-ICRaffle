
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

--[[
-- UserGuildTotals -----------------------------------------------------------
-- sub-element of UserRecord
--
-- One user's membership and buy/sell totals for one guild.
--
local UserGuildTotals = {
--    is_member      = false        -- latch true during GetGuildMember loops
--  , bought         = 0            -- gold totals for this user in this guild's store
--  , sold           = 0
--  , joined_ts      = 1469247161   -- when this user joined this guild
--  , rank_index     = 1            -- player's rank within this guild, nil if not is_member

                                    -- Audit trail: what are the first and last
                                    -- MM records that counted in the "sold" total?
--  , sold_first_mm  = mm_sales_record
--  , sold_last_mm   = mm_sales_record
--  , sold_ct_mm     = 0
}

local function MMEarlier(mm_a, mm_b)
    if not mm_b then return mm_a end
    if not mm_a then return mm_b end
    if mm_a.timestamp <= mm_b.timestamp then return mm_a end
    return mm_b
end

local function MMLater(mm_a, mm_b)
    if not mm_b then return mm_a end
    if not mm_a then return mm_b end
    if mm_a.timestamp <= mm_b.timestamp then return mm_b end
    return mm_a
end

local function MaxRank(a, b)
    if not a then return b end
    if not b then return a end
    return math.max(a, b)
end

function UserGuildTotals:Add(b)
    if not b then return end
    self.is_member      = self.is_member or b.is_member
    self.bought         = self.bought         + b.bought
    self.sold           = self.sold           + b.sold
    self.rank_index     = MaxRank(self.rank_index, b.rank_index)

    self.sold_first_mm = MMEarlier(self.sold_first_mm, b.sold_first_mm)
    self.sold_last_mm  = MMLater(self.sold_last_mm,    b.sold_last_mm )
    self.sold_ct_mm    = self.sold_ct_mm             + b.sold_ct_mm
end

local function MMToString(mm)
    if not mm then return "nil nil nil" end
    return        tostring(mm.timestamp)
        .. " " .. tostring(mm.buyer)
        .. " " .. tostring(mm.price)
end

function UserGuildTotals:ToString()
    return            tostring(  self.is_member     )
            .. " " .. tostring(  self.rank_index    )
            .. " " .. tostring(  self.bought        )
            .. " " .. tostring(  self.sold          )
            .. " " .. tostring(  self.joined_ts     )
            .. " " .. tostring(  self.sold_ct_mm    )
            .. " " .. MMToString(self.sold_first_mm )
            .. " " .. MMToString(self.sold_last_mm  )
end

function UserGuildTotals:New()
    local o = { is_member      = false
              , bought         = 0
              , sold           = 0
              , joined_ts      = nil
              , sold_first_mm  = nil
              , sold_last_mm   = nil
              , sold_ct_mm     = 0
              }
    setmetatable(o, self)
    self.__index = self
    return o
end

-- UserRecord ----------------------------------------------------------------
-- One row in our saved_var history
--
-- One user's membership and buy/sell totals for each guild.
--
-- Knows how to add a sale/purchase to a specific guild by index
local UserRecord = {
--    user_id = nil     -- @account string
--
--                      -- UserGuildTotals struct, one per guild with any of
--                      -- guild membership, sale, or purchase.
--  , g       = { nil, nil, nil, nil, nil }
}

-- For summary reports
function UserRecord:Sum()
    local r = UserGuildTotals:New()
    for _, ugt in pairs(self.g) do
        r:Add(ugt)
    end
    return r
end

function UserRecord:SetIsGuildMember(guild_index, is_member)
    local ugt = self:UGT(guild_index)
    local v = true            -- default to true if left nil.
    if is_member == false then v = false end
    ugt.is_member = v
end

function UserRecord:SetGuildNote(guild_index, note)
    local ugt = self:UGT(guild_index)
    ugt.note = note
end

function UserRecord:SetRankIndex(guild_index, rank_index)
    local ugt = self:UGT(guild_index)
    ugt.rank_index = rank_index
end

-- Lazy-create list elements upon demand.
function UserRecord:UGT(guild_index)
    if not self.g[guild_index] then
        self.g[guild_index] = UserGuildTotals:New()
        self.g[guild_index].joined_ts = self:CalcTimeJoinedGuild(guild_index)
    end
    return self.g[guild_index]
end

function UserRecord:AddSold(guild_index, mm_sales_record)
    local ugt = self:UGT(guild_index)
    ugt.sold = ugt.sold + mm_sales_record.price

    ugt.sold_first_mm = MMEarlier(ugt.sold_first_mm, mm_sales_record)
    ugt.sold_last_mm  = MMLater(ugt.sold_last_mm, mm_sales_record)
    ugt.sold_ct_mm    = ugt.sold_ct_mm + 1
end

function UserRecord:AddBought(guild_index, amount)
    local ugt = self:UGT(guild_index)
    ugt.bought = ugt.bought + amount
end

function UserRecord:FromUserID(user_id)
    local o = { user_id = user_id
              , g       = { nil, nil, nil, nil, nil }
              }
    setmetatable(o, self)
    self.__index = self
    return o
end

function UserRecord:ToString()
    local s = self.user_id
    for guild_index = 1, ICRaffle.max_guild_ct do
        local ugt = self.g[guild_index]
        if ugt then
            s = s .. "\t" .. ugt:ToString()
        else
            s = s .. "\t"
        end
    end
    return s
end

-- When was the first time we saw this user_id in this guild?
function UserRecord:CalcTimeJoinedGuild(guild_index)
    if not (ICRaffle.saved_var
            and ICRaffle.saved_var.roster
            and ICRaffle.saved_var.roster[guild_index]
            and ICRaffle.saved_var.roster[guild_index][self.user_id]
           ) then return 0 end
    return ICRaffle.saved_var.roster[guild_index][self.user_id].first_seen_ts
end

-- Lazy-create UserRecord instances on demand.
function ICRaffle:UR(user_id)
    if not self.user_records[user_id] then
        self.user_records[user_id] = UserRecord:FromUserID(user_id)
    end
    return self.user_records[user_id]
end

-- Return a more compact list-of-strings representation
function ICRaffle:CompressedUserRecords()
    local line_list = {}
    for _, ur in pairs(self.user_records) do
        table.insert(line_list, ur:ToString())
    end
    return line_list
end

function ICRaffle:UserNotes()
    local u_g_note = {}
    for _, ur in pairs(self.user_records) do
        local g_note   = {}
        local have_one = false
        for guild_index,ugt in pairs(ur.g) do
            if ugt and ugt.note and ugt.note ~= "" then
                g_note[guild_index] = ugt.note
                have_one = true
            end
        end
        if have_one then
            u_g_note[ur.user_id] = g_note
        end
    end
    return u_g_note
end
--]]


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
end

--[[
-- Fetch Guild Data from the server and Master Merchant ----------------------
--
-- Fetch _all_ events for each guild. Server holds no more than 10 days, no
-- more than 500 events.
--
-- Defer per-event iteration until fetch is complete. This might help reduce
-- the clock skew caused by the items using relative time, but relative
-- to _what_?

function ICRaffle:SaveNow()
    self.fetched_str_list = {}
    self.saved_var.guild_name = self:GuildNameList()

    for guild_index = 1, self.max_guild_ct do
        if self.saved_var.enable_guild[guild_index] then
            self:SaveGuildIndex(guild_index)
        else
            self:SkipGuildIndex(guild_index)
        end
    end
    if not self.user_records then
        d("No guild members to report. Nothing to do.")
        return
    end

    self.saved_var.guild_rank = self.guild_rank

    self:MMScan()
    self:Done()
end

-- When the async guild bank history scan is done, print summary to chat.
function ICRaffle:Done()
    self.saved_var.user_records       = self:CompressedUserRecords()
    self.saved_var.user_notes         = self:UserNotes()

                        -- Tell CSV what time range we saved.
                        -- These timestamps aren't set until MMScan, so
                        -- don't write them until after MMScan.
    self.saved_var.saved_begin_ts = self.saved_begin_ts
    self.saved_var.saved_end_ts   = self.saved_end_ts

                        -- Write a summary and "gotta relog!" to chat window.
    local r = self:SummaryCount()
    d(self.name .. ": saved " ..tostring(r.user_ct).. " user record(s)." )
    d(self.name .. ": " .. tostring(r.seller_ct) .. " seller(s), "
                        .. tostring(r.buyer_ct) .. " buyer(s)." )
    d(self.name .. ": Reload UI, log out, or quit to write file.")
end

-- User doesn't want this guild. Respond with "okay, skipping"
function ICRaffle:SkipGuildIndex(guild_index)
    self:SetStatus(guild_index, "skipped")
end

-- Download one guild's roster
-- Happens nearly instantaneously.
function ICRaffle:SaveGuildIndex(guild_index)
    local guildId = GetGuildId(guild_index)
    self.fetching[guild_index] = true

                        -- Fetch guild rank index/name list
    local rank_ct = GetNumGuildRanks(guildId)
    self.guild_rank[guild_index] = {}
    for rank_index = 1,rank_ct do
        local rank_name = GetGuildRankCustomName(guildId, rank_index)
                        -- Kudos to Ayantir's GMen for pointing me to
                        -- GetFinalGuildRankName()
        if rank_name == "" then
            rank_name = GetFinalGuildRankName(guildId, rank_index)
        end
        self.guild_rank[guild_index][rank_index] = rank_name
    end

                        -- Fetch complete guild member list
    local ct = GetNumGuildMembers(guildId)
    self:SetStatus(guild_index, "downloading " .. ct .. " member names...")
    for i = 1, ct do
        local user_id, note, rank_index = GetGuildMemberInfo(guildId, i)
        local ur = self:UR(user_id)
        ur:SetIsGuildMember(guild_index)
        ur:SetRankIndex(guild_index, rank_index)
        ur:SetGuildNote(guild_index, note)
    end
    self:SetStatus(guild_index, ct .. " members")
end

-- Master Merchant -----------------------------------------------------------

-- Scan through every single sale recorded in Master Merchant, and if it was
-- a sale through one of our requested guild stores, AND sometime during
-- "Last Week", then credit the seller and buyer with the gold amount.
--
-- Happens nearly instantaneously.
--
function ICRaffle:MMScan()
    self:CalcSavedTS()

    -- d("MMScan start")
                        -- O(n) table scan of all MM data.
                        --- This will take a while...
    local salesData = MasterMerchant.salesData
    local itemID_ct = 0
    local sale_ct = 0
    for itemID,t in pairs(salesData) do
        itemID_ct = itemID_ct + 1
        for itemIndex,tt in pairs(t) do
            local sales = tt["sales"]
            if sales then
                for i, mm_sales_record in ipairs(sales) do
                    local s = self:AddMMSale(mm_sales_record)
                    if s then
                        sale_ct = sale_ct + 1
                    end
                end
            end
        end
    end

    -- d("MMScan done  itemID_ct=" .. itemID_ct .. " sale_ct=" .. sale_ct)

end

-- Fill in begin/end timestamps for "Last Week"
function ICRaffle:CalcSavedTS()
                        -- Use the start/end timestamps chosen from
                        -- the UI dropdown.
    local r = ICRaffle.FetchMMDateRanges()
    self.saved_begin_ts = r[self.saved_var.mm_date_index].start_ts
    self.saved_end_ts   = r[self.saved_var.mm_date_index].end_ts
end

function ICRaffle:AddMMSale(mm_sales_record)
    local mm = mm_sales_record  -- for less typing

                        -- Track only sales within guilds we care about.
    local guild_index = self.guild_index[mm.guild]
    if not guild_index then return 0 end
    if not self.saved_var.enable_guild[guild_index] then return 0 end

                        -- Track only sales within time range we care about.
    if self.saved_begin_ts and mm.timestamp < self.saved_begin_ts
        or self.saved_end_ts and self.saved_end_ts < mm.timestamp then
        return 0
    end

    -- d("# buyer " .. mm.buyer .. "  seller " .. mm.seller)
    self:UR(mm.buyer ):AddBought(guild_index, mm.price)
    self:UR(mm.seller):AddSold  (guild_index, mm)
    return 1
end

function ICRaffle:SummaryCount()
    local r = { user_ct   = 0
              , buyer_ct  = 0
              , seller_ct = 0
              , member_ct = 0
              , bought    = 0
              , sold      = 0
              }
    for _, ur in pairs(self.user_records) do
        r.user_ct = r.user_ct + 1
        ugt_sum = ur:Sum()
        if ugt_sum.is_member   then r.member_ct = r.member_ct + 1 end
        if ugt_sum.bought > 0  then r.buyer_ct  = r.buyer_ct  + 1 end
        if ugt_sum.sold   > 0  then r.seller_ct = r.seller_ct + 1 end
        r.bought = r.bought + ugt_sum.bought
        r.sold   = r.sold   + ugt_sum.sold
    end
    return r
end
--]]

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
