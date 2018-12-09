INFILE = "data/ICRaffle.lua"        -- aka SavedVariables/ICRaffle.lua

OUTFILE_ROSTER      = "data/roster.txt"
OUTFILE_SALES       = "data/sales.txt"
OUTFILE_DEPOSITS    = "data/deposits.txt"
OUTFILE_GUILD_RANKS = "data/guild_ranks.txt"

-- From http://lua-users.org/wiki/SplitJoin
function split2(str,sep)
    local ret={}
    local n=1
    local offset = 1
                        -- "true" here is arg "plain", which turns off
                        -- pattern expressions and uses just boring old
                        -- byte matching.
    local delim_begin, delim_end = str:find(sep, offset, true)
    while delim_begin do
        local sub = str:sub(offset, delim_begin - 1)
        table.insert(ret, sub)
        offset = delim_end + 1
        delim_begin, delim_end = str:find(sep, offset, true)
    end
    return ret
end

function Textify(schema, row_list, out_file_name)
    if not row_list then return 0 end

    local OUT_FILE = assert(io.open(out_file_name, "w"))
    if schema then
        OUT_FILE:write("# ")
        OUT_FILE:write(schema)
        OUT_FILE:write("\n")
    end
    for _,row in ipairs(row_list) do
        row = row:gsub("\n"," ")
        OUT_FILE:write(row)
        OUT_FILE:write("\n")
    end
    return 1
end

function GuildRank(guild_rank, out_file_name)
    if not guild_rank then return 0 end
    local OUT_FILE = assert(io.open(out_file_name, "w"))
    OUT_FILE:write("# index\trank\n")
    for index, rank in ipairs(guild_rank) do
        local row = string.format("%d\t%s\n", index, rank)
        OUT_FILE:write(row)
    end
end

function main()
                        -- Read input file.
                        --
                        -- Since it's a Lua file, let the Lua interpreter
                        -- parse it for us. Other languages will have to
                        -- include parsing code. Good luck with that.
    dofile(INFILE)

    local account_wide = nil
    for account_name,t in pairs(ICRaffleVars["Default"]) do
        account_wide = t["$AccountWide"]
        if account_wide then
            local got = 0
            got = got + Textify( account_wide.roster_schema
                               , account_wide.roster
                               , OUTFILE_ROSTER
                               )
            got = got + Textify( account_wide.sale_list_schema
                               , account_wide.sale_list
                               , OUTFILE_SALES
                               )
            got = got + Textify( account_wide.deposit_list_schema
                               , account_wide.deposit_list
                               , OUTFILE_DEPOSITS
                               )
            GuildRank(account_wide.guild_rank, OUTFILE_GUILD_RANKS)

                            -- Looks like this account had enough data.
                            -- If this wasn't the account you wanted,
                            -- don't enable ICRaffle on the other accounts.
            if 3 <= got then
                print(string.format("Found account %s", account_name))
                break
            end
        end
    end
end


main()
