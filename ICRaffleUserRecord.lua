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
    ,   join_ts     = nil   -- seconds since 1970-01-01 
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
    ,   "join_ts"    
}
function UserRecord:ToSaved()
    local r = {}
    for _,fn in ipairs(UserRecord.FIELD_LIST) do
        r[fn] = self[fn]
    end
    return r
end

function UserRecord:FromSaved(u)
    local r = UserRecord:New()
    for _,fn in ipairs(UserRecord.FIELD_LIST) do
        r[fn] = u[fn]
    end
    return r
end

function ICRaffle.User(user_id)
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
end


