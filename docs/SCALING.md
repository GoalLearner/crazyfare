# CrazyFare — Scaling the server and lobby flow

_Written 2026-10-27 with lobby flow v1. Numbers here are starting points; check them against live analytics._

## Today: one place does everything

Every server is self-contained: up to `Config.Server.MaxPlayers` (10) people, `MaxDrivers` (6) racing, the rest riding along on foot, bots filling the grid to `BotFillTo` (4). The Taxi Depot is the lobby; matches chain by themselves. Roblox's own server fill does the matchmaking (it puts joiners into partly full servers and follows friends in).

This is the right shape while the game is small: no teleports (they cost 10-20 s and lose some players every time), friends stay together, and an empty server still plays (bots).

## When to upgrade

Move to a lobby place plus match servers when any of these holds for a week:

| Signal | Threshold | Why it matters |
|---|---|---|
| Time on foot | People spend more than one round in three as passengers (or depot "STAY" taps outnumber joins) | Servers are too full of people who want to drive; a queue would seat them sooner |
| Concurrent players | More than ~500 CCU sustained | Enough players to fill 6-driver matches in seconds, so bots should drop out of most matches |
| Party play | Players ask for (or analytics show) groups of 3+ friends arriving together | One-place servers split parties when a server is nearly full; a lobby can queue a party as one ticket |
| Skill gap | Win rate of the top 10% of players above ~60% against the rest | Matchmaking by skill needs a pool bigger than one server |
| Modes | A second permanent mode (ranked, team, private matches) | Each wants its own queue |

Below those, improve the one-place flow instead (seat rotation, depot fun, bots).

## The planned lobby/queue architecture (10 lines)

1. **Lobby place** (new): the Taxi Depot, garage, shop, quests and a PLAY button with party support; no city, no traffic.
2. **Queue**: PLAY adds a ticket (a party's UserIds, skill bucket, time joined) to a MemoryStoreService sorted map.
3. **Matchmaker**: one lobby server at a time holds a MemoryStore lock and every 2 s pops up to 6 seats of tickets, best skill fit first, never splitting a party.
4. **Hand-off**: it reserves a match server (`TeleportService:ReserveServer`) and teleports the group with TeleportData `{ roster = { userIds }, map, mode }`; a group still short after 20 s goes anyway and bots fill.
5. **Match place** = today's place: `SessionService` already reads `roster` into the seat order, and `MatchController.MatchStart(roster, options)` starts the match once the roster has arrived (or after a timeout).
6. Late arrivals and extra friends still work as today: Passenger / Queued states, seats by priority.
7. **Match end**: `MatchController.MatchEnd(results)` awards as today, then offers REMATCH (the same roster re-queues as one ticket) or LOBBY.
8. Returning players teleport back to a lobby server carrying their streak (as the Arcade return already does).
9. Player data stays in ProfileStore (session locking covers the hops); the Arcade reserved-server path is the template for the teleports.
10. Rollout: ship the lobby behind a flag, send 10% of joins through it, compare day-1 retention and time-to-first-match before moving everyone.
