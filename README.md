# ICRaffle

an Elder Scrolls Online add-on for collecting guild sales and deposit history.

- guild sales for the last week, from Master Merchant
    - as totals per-user
    - as a flat list of individual sales
- guild bank deposits for same time period
    - as totals per-user
    - as a flat list of individual deposits
- guild rank
    - rank index for each guild member
    - separate table of rank names to join by index
- invited by which guild member, when
    - also includes ex-guild members who left, or were kicked, when and by whom.

## GitHub Repo

https://github.com/ziggr/ESO-ICRaffle

## Results

The results can look something like [this Google sheet](https://docs.google.com/spreadsheets/d/1ofkL5vWvT8bQUExRvYW_5k5wnVyS0qRvdiJUEkQnwUs/edit?usp=sharing)

![out_roster](doc/img/out_roster.jpg)

To produce the exact output format that you need, write your own text file converter to read `SavedVariables/ICRaffle.lua`:

![saved_vars](doc/img/saved_vars.jpg)

## Operating Instructions

1. Install `ICRaffle` addon.
2. Also install and enable `Master Merchant` and `LibAddOnMenu-2.0` addons: both are required. You probably already have them.
3. Log into the game.
   ICRaffle fetches guild roster history. The first time this runs, it can take a few minutes. Later fetches will only take a second or two. The scan is intentionally throttled to avoid being kicked from server for too many API requests.
   ![chat_1_invites_in_progress](doc/img/chat_1_invites_in_progress.jpg)
4. Wait until ICRaffle finishes.<br />
   ![chat_2_invites_done](doc/img/chat_2_invites_done.jpg)

   You do not have to `/reloadui` or `/logout` right away. You can wait until after the next steps. Or not. Your call.
5. Run `/icraffle` to fetch guild sales and donation history:
   ![chat_3_icraffle_entry](doc/img/chat_3_icraffle_entry.jpg)

   This also can take a few seconds to complete:<br />
   ![chat_4_icraffle_done](doc/img/chat_4_icraffle_done.jpg)

6. `/reloadui` to write all data to `SavedVariables/ICRaffle.lua`

At this point you now have a SavedVariables text file. Process it into whatever spreadsheet or external programming you need.

### Settings

In `Settings/Addons/ICRaffle`, choose which guild to export, and which date range:
​    ![settings](doc/img/settings.jpg)

Changing either will reset all data: next time you `/reloadui` it will re-scan the guild invite history.

The `Scan Now` button is the same as typing `/icraffle` in the chat window.

The weekly cutoff for "last week" is defined within Master Merchant as the Sunday trader flip time: 8pm EST or 9 pm EDT.

## Guild Sales Records from Master Merchant

<font color="red">You _must_ run `/mm missing` right before running this add-on.</font>

Master Merchant has a known bug that causes it to omit some sales records.

Before I learned to always run `/mm missing` each Sunday night, I would get several guildies complaining that they did not get credit for all their sales that week. The guildies were correct. Once I started running `/mm missing` every Sunday before running guild quotas, the sales were all correctly recorded and guildies were much happier.

## Guild Bank Deposits

<font color="red">You _must_ collect guild bank depost data every 10 days or sooner.</font>

Guild bank history only goes back 10 days. You need to run this add-on within 10 days of the start of the raffle window if you don't want to lose deposit information.

This became a problem once or twice per year in my other guild, when we'd skip the occasional raffle. We would run the add-on and save a copy of the exported ticket deposits, then hand-merge that data into the spreadsheet that drove the raffle tickets.

## Guild Roster

Guild roster history goes back 6 months or more, so just about everybody except long-timers will get their actual join date and invitor.

The first time you scan guild roster history, it can take several minutes. The scan is intentionally throttled to avoid getting kicked for too many server requests. Later scans take seconds or less.

The add-on automatically scans the guild roster once per day on login. It records that it did its daily scan, and then goes quiet for the rest of the day.

# Data

`SavedVariables/ICRaffle.lua` contains four tables:

- roster
- sale_list
- deposit_list
- guild_rank

### Timestamps: seconds since the epoch

All timestamps are integer seconds since 1970-01-01.

Use your favorite date/time library to convert that to something human-readable:

```bash
$ date --date='@1534530705'
Fri Aug 17 11:31:45 PDT 2018

$ date --date='@1534530705' --iso-8601=seconds
2018-08-17T11:31:45-07:00
```

## roster: one row per user

Includes ex-guild-members.

Includes non-guild-members as buyers, in case your guild sends thank you gives or recruiting prizes to big purchasers.

### Schema

- **user_id**: "@Geddy"  the account name
- **is_member**: 1 or 0. Was this user a member at the time you ran `/icraffle`?
  Note that "at the time you ran `/icraffle` is always _after_ the time range of the exported sales/donations. If you want to know if this user was a member during the time range, you'll have to check the join/leave timestamps and do some comparisons yourself.
- **rank_index**: Index into `guild_rank` , if this user is a guild member.
- **invitor**: Who invited this user to the guild? Blank if user joined further in the past than guild history remembers.
- **kicker**: Who kicked this user out of the guild?
- **join_ts**: When did this user join?
- **leave_ts**: When did this user leave, either voluntarily or by kick?
- **guild_note**: Guild member note from guild roster screen. Stuck at the end of the schema because these notes tend to be long and free-form and clutter up the display.

Gold: sum of gold deposits to guild bank during the period. Total of applicable rows from **deposit_list** table.

- **gold.total**: How much gold did this user deposit into the guild bank during the time period?
- **gold.event_ct**: How many separate gold deposits did this user make?
- **gold.earliest_ts**:  When did the first gold deposit occur during the time period.
- **gold.latest_ts**: When last gold deposit?

Sold: sum of sales through guild store during the time period. Total of applicable rows from **sale_list** table.

- **sold.total**: Total gold value sold through guild store during the time period.
- **sold.event_ct**: Number of individual sales during the time period.
- **sold.earliest_ts**: First sale during the time period.
- **sold.latest_ts**: Last sale.

Bought: sum of purchases through guild store. Tends to pick up a lot of non-guild-member rows. Total of applicable rows from **sale_list** table.

- **bought.total**: Total gold value purchased through guild store during the time period.
- **bought.event_ct**: Number of individual purchases.
- **bought.earliest_ts**: First purchase.
- **bought.latest_ts**: Last purchase.

### Sample data

![sample_roster](doc/img/sample_roster.jpg)

Looks like @TheLowkeyLoki has been around longer than the six months: no invite in six months of retained history. Also lots of guild bank deposits: 5 deposits totaling 131,000 gold. That rank 2 "Radiant Apex" might be related to all those deposits.

Also looks like @emiliana_eso has had enough of @Abe_13, kicking them five months ago on 2018-07-01 (`1530493355`).

## deposit_list: gold deposits to guild bank

Each individual gold deposit to the guild bank shows up here, just like in the Guild History screen, Bank.

### Schema

- timestamp
- user
- gold

### Sample data

![out_deposits](doc/img/out_deposits.jpg)

## sale_list

Each individual sale. What shows up in Master Merchant if you view by item, show all data.

### Schema

- timestamp
- gold: this is the total gold paid for this sale, not per-item
- seller
- buyer
- item_ct: if this was a stack of 2 or more materials or whatever
- item_link

### Sample data

![out_sales](doc/img/out_sales.jpg)

## guild_rank

A tiny table that you will probably join to `roster.rank_index`.

### Schema

- index
- rank

### Sample data

 ![out_guild_ranks](doc/img/out_guild_ranks.jpg)



