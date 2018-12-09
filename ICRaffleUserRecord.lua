ICRaffle = ICRaffle or {}

ICRaffle.user_records = ICRaffle.user_records or {}

local UserRecord = {}

function UserRecord:New()
    local o = {
        user_id     = nil   -- "@Alice"
    ,   is_member   = nil   -- true if member of guild, nil if not
    ,   rank_index  = nil   -- peon, guild master, which rank?
    ,   guild_note  = nil   -- "Top seller!" or whatever
    ,   invitor     = nil   -- "@OtherGuildie"
    ,   kicker      = nil   -- "@SomeGMLikeUser"
    ,   join_ts     = nil   -- seconds since 1970-01-01
    ,   leave_ts    = nil   -- "

                            -- event totals/summaries:
                            -- { event_ct, total, earliest_ts, latest_ts }
    ,   gold        = nil   -- guild bank gold deposits
    ,   sold        = nil   -- guild trader sales
    ,   bought      = nil   -- guild trader purchases
    }
    setmetatable(o,self)
    self.__index = self
    return o
end

-- To/From SavedVariables ----------------------------------------------------
--
-- ToSaved()/FromSaved():  I will probably end up compressing each user record
-- down to a single  string for easier storage and parsing. But for now, I'll
-- leave them as tables of key/value pairs for easier debugging.

                        -- Flat/exportable fields written to SavedVariables
UserRecord.FIELD_LIST = {
        "user_id"
    ,   "is_member"
    ,   "rank_index"
    ,   "guild_note"
    ,   "invitor"
    ,   "kicker"
    ,   "join_ts"
    ,   "leave_ts"
    ,   "gold"
    ,   "sold"
    ,   "bought"
}

function UserRecord:ToSaved()
                        -- Stringify field values to something compact.
    local function f(f)
        if f == nil   then return ""  end
        if f == false then return "0" end
        if f == true  then return "1" end
        return tostring(f)
    end

    r = {
       f( self.user_id                            )
    ,  f( self.is_member                          )
    ,  f( self.rank_index                         )
    ,  f( self.invitor                            )
    ,  f( self.kicker                             )
    ,  f( self.join_ts                            )
    ,  f( self.leave_ts                           )

    ,  f( self.gold and self.gold.total           )
    ,  f( self.gold and self.gold.event_ct        )
    ,  f( self.gold and self.gold.earliest_ts     )
    ,  f( self.gold and self.gold.latest_ts       )

    ,  f( self.sold and self.sold.total           )
    ,  f( self.sold and self.sold.event_ct        )
    ,  f( self.sold and self.sold.earliest_ts     )
    ,  f( self.sold and self.sold.latest_ts       )

    ,  f( self.bought and self.bought.total       )
    ,  f( self.bought and self.bought.event_ct    )
    ,  f( self.bought and self.bought.earliest_ts )
    ,  f( self.bought and self.bought.latest_ts   )

    ,  f( self.guild_note                         )
    }

    return table.concat(r,"\t")
    -- for _,fn in ipairs(UserRecord.FIELD_LIST) do
    --     r[fn] = self[fn]
    -- end
    -- return r
end

function UserRecord:FromSaved(s)
    local r = { zo_strsplit("\t", s) }

    local function bool(txt)
        if txt == "" then return nil end
        if txt == "0" then return nil end
        return true
    end
    local function num(txt)
        return tonumber(txt)
    end
    local function str(txt)
        if txt == "" then return nil end
        return txt
    end

    local ur = UserRecord:New()

    ur.user_id            = str( r[ 1])
    ur.is_member          = bool(r[ 2])
    ur.rank_index         = num( r[ 3])
    ur.invitor            = str( r[ 4])
    ur.kicker             = str( r[ 5])
    ur.join_ts            = num( r[ 6])
    ur.leave_ts           = num( r[ 7])

    ur.gold = {}
    ur.gold.total         = num( r[ 8])
    ur.gold.event_ct      = num( r[ 9])
    ur.gold.earliest_ts   = num( r[10])
    ur.gold.latest_ts     = num( r[11])

    ur.sold = {}
    ur.sold.total         = num( r[12])
    ur.sold.event_ct      = num( r[13])
    ur.sold.earliest_ts   = num( r[14])
    ur.sold.latest_ts     = num( r[15])

    ur.bought = {}
    ur.bought.total       = num( r[16])
    ur.bought.event_ct    = num( r[17])
    ur.bought.earliest_ts = num( r[18])
    ur.bought.latest_ts   = num( r[19])

    ur.guild_note         = str( r[20])

    return ur
end

function ICRaffle.User(user_id)
    local self = ICRaffle
    if not self.user_records[user_id] then
        local ur = UserRecord:New()
        ur.user_id = user_id
        self.user_records[user_id] = ur
    end
    return self.user_records[user_id]
end

function ICRaffle.SavedVarsToUserRecords()
    local self = ICRaffle
    self.user_records = self.user_records or {}

    local roster = self.saved_var.roster
    if not roster then return end
    for _,u in pairs(roster) do
        local ur = UserRecord:FromSaved(u)
        self.user_records[ur.user_id] = ur
    end
end

local function sorted_keys(t)
    local keys = {}
    for k,_ in pairs(t) do table.insert(keys,k) end
    table.sort(keys)
    local i = 0
    local function next()
        i = i + 1
        if #keys < i then return nil end
        return keys[i]
    end
    return next
end

function ICRaffle.UserRecordsToSavedVars()
    local roster = {}
    for user_id in sorted_keys(self.user_records) do
        local ur = self.user_records[user_id]
        local sv = ur:ToSaved()
        table.insert(roster, sv)
    end
    self.saved_var.roster = roster
    self.ReloadUIReminder()
end


-- Absorbing data from events ------------------------------------------------

function UserRecord.RecordEvent(field, gold_ct, ts)
    local r = field or {}
-- if type(r) ~= "table" then r = {} end  -- temp reset from previous data
    r.event_ct    = ICRaffle.Increment(r.event_ct   )
    r.total       = ICRaffle.Increment(r.total      , gold_ct)
    r.earliest_ts = ICRaffle.Earlier  (r.earliest_ts, ts)
    r.latest_ts   = ICRaffle.Later    (r.latest_ts  , ts)
    return r
end

function UserRecord:RecordGoldDeposit(gold_ct, ts)
    self.gold = self.RecordEvent(self.gold, gold_ct, ts)
end

function UserRecord:RecordPurchase(gold_ct, ts)
    self.bought = self.RecordEvent(self.bought, gold_ct, ts)
end

function UserRecord:RecordSale(gold_ct, ts)
    self.sold = self.RecordEvent(self.sold, gold_ct, ts)
end


-- Resetting before accumulating new totals ----------------------------------

function ICRaffle.ResetUserRecordFields(field_name, ...)
    local self = ICRaffle
    for user_id, user_record in pairs(self.user_records) do
        user_record[field_name] = nil
        for _,fn in ipairs({...}) do
            user_record[fn] = nil
        end
    end
end
