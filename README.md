# ICRaffle

an Elder Scrolls Online add-on for collecting guild sales and deposit history.

- [ ] guild sales for the last week, from Master Merchant
- [x] guild bank deposits for same time period
    - [x] as totals per-user
    - [x] as a flat list of individual deposits
- [x] guild rank
- [x] invited by which guild member, when

The weekly cutoff for "last week" is defined within Master Merchant as the Sunday trader flip time: 8pm EST or 9 pm EDT.

## Guild Sales Records from Master Merchant

You _must_ run `/mm missing` right before running this add-on. Master Merchant (and the Guild Trader API it calls) has a known problem with dropped sales records.

Before I learned to always run `/mm missing` each Sunday night, I would get several guildies complaining that they did not get credit for all their sales that week. The guildies were correct.

## Guild Bank Deposits

Guild bank history only goes back 10 days. You need to run this add-on within 10 days of the start of the raffle window if you don't want to lose deposit information.

This became a problem once or twice per year in my other guild, when we'd skip the occasional raffle. We would run the add-on and save a copy of the exported ticket deposits, then hand-merge that data into the spreadsheet that drove the raffle tickets.

## Guild Roster

Guild roster history goes back 6 months or more, so just about everybody except long-timers will get their actual join date and invitor.

The first time you scan guild roster history, it can take several minutes. The scan is intentionally throttled to avoid getting kicked for too many server requests. Later scans take seconds or less.

The add-on automatically scans the guild roster once per day on login.

