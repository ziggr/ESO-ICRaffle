ICRaffle = ICRaffle or {}

-- Guild Bank Scan -----------------------------------------------------------
--
-- Async call chain to scan all of guild bank history

function ICRaffle.FetchBankHistoryStart()
    if ICRaffle.GuildHistoryFetcher.ErrorIfBusy() then return end

    self = ICRaffle
    self.MMCalcSavedTS()

    self.bank_fetcher = ICRaffle.GuildHistoryFetcher:New(
        { guild_id      = GetGuildId(self.saved_var.guild_index)
        , guild_history_category = GUILD_HISTORY_BANK
        , old_enough_ts = self.saved_begin_ts
        , func_complete = ICRaffle.OnFetchBankHistoryComplete
        , progress_msg  = "Fetching guild bank deposits... events:%d  %s"
        })
    self.bank_fetcher:Start()
end

function ICRaffle.OnFetchBankHistoryComplete()
    self = ICRaffle
    self.ClearBankHistory()
    self.ScanBankHistory()
    self.ScanRanks()
    self.UserRecordsToSavedVars()
end

function ICRaffle.ClearBankHistory()
    self.ResetUserRecordFields("gold")
end

function ICRaffle.ScanBankHistory()
    self = ICRaffle

    local deposit_list = {}

    local function in_time(ts)
        return self.saved_begin_ts < ts and ts <= self.saved_end_ts
    end

    local guild_id = GetGuildId(self.saved_var.guild_index)
    local event_ct = GetNumGuildEvents(
                          guild_id
                        , GUILD_HISTORY_BANK )
    self.Debug("event_ct:"..tostring(event_ct))
    local deposit_ct = 0
    local total_gold = 0
    for i = 1,event_ct do
        local event = { GetGuildEventInfo(
                          guild_id
                        , GUILD_HISTORY_BANK
                        , i ) }

        local deposit = self.ToDeposit(event)
        if deposit and in_time(deposit.ts) then
            local j = self.RecordDeposit(deposit)
            table.insert(deposit_list, self.DepositToString(deposit))
            deposit_ct = deposit_ct + 1
            total_gold = total_gold + deposit.gold_ct
        end
    end
    self.saved_var.deposit_list = deposit_list

    local gold_str = ZO_CurrencyControl_FormatCurrency(
                              total_gold
                            , true )

    self.Info( "Guild bank history scan complete. Deposits:%s%d  %sGold:%s%s"
             , ICRaffle.color.white
             , deposit_ct
             , ICRaffle.color.grey
             , ICRaffle.color.white
             , gold_str
             )
end

function ICRaffle.ToDeposit(event)
    local self = ICRaffle
    local event_type = event[1]
    if event_type ~= GUILD_EVENT_BANKGOLD_ADDED then return nil end

    local secs_ago   = event[2]
    local ts         = self.SecsAgoToTS(secs_ago)
    local user_id    = event[3]
    local gold_ct    = event[4]
    return { user_id = user_id
           , gold_ct = gold_ct
           , ts      = ts
           }
end

function ICRaffle.RecordDeposit(deposit)
    local self = ICRaffle
    local ur = self.User(deposit.user_id)
    ur:RecordGoldDeposit(deposit.gold_ct, deposit.ts)
end

function ICRaffle.DepositToString(deposit)
    return string.format( "%d\t%s\t%d"
                        , deposit.ts
                        , deposit.user_id
                        , deposit.gold_ct
                        )
end
