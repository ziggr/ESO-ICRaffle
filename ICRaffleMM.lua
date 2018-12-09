ICRaffle = ICRaffle or {}


-- Master Merchant -----------------------------------------------------------

-- Scan through every single sale recorded in Master Merchant, and if it was
-- a sale through one of our requested guild stores, AND sometime during
-- "Last Week", then credit the seller and buyer with the gold amount.
--
-- Happens nearly instantaneously.
--
function ICRaffle.MMScan()
    self = ICRaffle
    self.MMCalcSavedTS()

    self.Info("Scanning Master Merchant...")

                        -- Reset all sales totals and records.
    self.ResetUserRecordFields("sold", "bought")
    self.saved_var.sale_list = {}

                        -- MM indexes by guild name, not index or id.
    local guild_id  = GetGuildId(self.saved_var.guild_index)
    self.guild_name = GetGuildName(guild_id)
                        -- O(n) table scan of all MM data.
                        -- Surprise! This completes nearly instantly.
    local sales_data = MasterMerchant.salesData
    local item_id_ct = 0
    local sale_ct    = 0
    local total_gold = 0
    for item_id,t in pairs(sales_data) do
        item_id_ct = item_id_ct + 1
        for item_index,tt in pairs(t) do
            local sales = tt["sales"]
            if sales then
                for i, mm_sales_record in ipairs(sales) do
                    local s = self.AddMMSale(mm_sales_record)
                    if s then
                        sale_ct = sale_ct + 1
                        total_gold = total_gold + mm_sales_record.price
                    end
                end
            end
        end
    end
    self.saved_var.sale_list_schema = self.MMSaleSchema()

    local gold_str = ZO_CurrencyControl_FormatCurrency(
                              total_gold
                            , true )
    self.Info( "Master Merchant scan complete. Sales:%s%d  %sGold:%s%s"
             , ICRaffle.color.white
             , sale_ct
             , ICRaffle.color.grey
             , ICRaffle.color.white
             , gold_str)
end

function ICRaffle.AddMMSale(mm_sales_record)


    self = ICRaffle
    local mm = mm_sales_record  -- for less typing

                        -- Track only sales within guilds we care about.
    if mm.guild ~= self.guild_name then return nil end

                        -- Track only sales within time range we care about.
    if self.saved_begin_ts and mm.timestamp < self.saved_begin_ts
        or self.saved_end_ts and self.saved_end_ts < mm.timestamp then
        return nil
    end
                        -- Add to buyer's and seller's totals.
    local ur_buyer  = self.User(mm.buyer)
    local ur_seller = self.User(mm.seller)
    ur_buyer:RecordPurchase(mm.price, mm.timestamp)
    ur_seller:RecordSale(mm.price, mm.timestamp)

                        -- Record event details in list of all sales.
    local sale_string = string.format("%d\t%d\t%s\t%s\t%d\t%s"
                        , mm.timestamp
                        , mm.price
                        , mm.seller
                        , mm.buyer
                        , mm.quant
                        , mm.itemLink or mm.itemName or ""
                        )
    table.insert(self.saved_var.sale_list, sale_string)
    return 1
end

function ICRaffle.MMSaleSchema()
    local r = { "timestamp"
              , "gold"
              , "seller"
              , "buyer"
              , "item_ct"
              , "item_link"
              }
    return table.concat(r,"\t")
end

-- MM date ranges ------------------------------------------------------------
--
-- Let Master Merchant tell us when "last week" begins and ends
--

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

