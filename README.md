# CrazyFare

Multiplayer free-for-all taxi game for Roblox. Read `CLAUDE.md` for conventions, `docs/DESIGN.md` for the game, `docs/PLAN.md` for phases, `docs/SCALING.md` for when to grow past one place.

**Server size:** the place's Max Players (Creator Hub > Creations > CrazyFare > Configure > Places > the place) must equal `Config.Server.MaxPlayers` (10): 6 race (`MaxDrivers`), the rest ride along on foot until a seat opens.

```
rokit install
wally install
rojo plugin install
rojo serve
```
