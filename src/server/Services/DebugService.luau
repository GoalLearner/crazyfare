--!strict
-- Studio-only commands from the client DebugPanel. Refuses everything outside Studio.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Money = require(ReplicatedStorage.Shared.Money)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local PassengerService = require(script.Parent.PassengerService)
local FareService = require(script.Parent.FareService)
local ItemService = require(script.Parent.ItemService)
local DataService = require(script.Parent.DataService)
local VehicleService = require(script.Parent.VehicleService)
local MapService = require(script.Parent.MapService)
local WeatherService = require(script.Parent.WeatherService)
local SessionService = require(script.Parent.SessionService)
local MonetizationService = require(script.Parent.MonetizationService)
local DropService = require(script.Parent.DropService)

local DebugService = {}

local commands: { [string]: (player: Player, arg: any) -> () } = {
	-- a post-match crate right now: a rarity ("Common" ... "Mythic") or "Phantom"
	ForceDrop = function(player, arg)
		if typeof(arg) == "string" then
			DropService.DebugDrop(player, arg)
		end
	end,
	-- that many crates in a row (only the last one revealed): the pity shows in the Output
	DropBurst = function(player, arg)
		if typeof(arg) == "number" then
			DropService.DebugBurst(player, math.clamp(math.floor(arg), 1, Config.Drops.PityEpic * 2))
		end
	end,
	-- the pity counter (PityEpic - 1 makes the next natural drop an Epic or better)
	Pity = function(player, arg)
		if typeof(arg) == "number" then
			DropService.DebugSetPity(player, arg)
		end
	end,
	-- the shop's TEST buttons (ids still 0): as if this pass or product was just bought
	Grant = function(player, arg)
		if typeof(arg) == "string" then
			MonetizationService.DebugGrant(player, arg)
		end
	end,
	GiveItem = function(player, arg)
		if typeof(arg) == "string" then
			ItemService.Give(player, arg)
		end
	end,
	SetHp = function(player, arg)
		if typeof(arg) == "number" then
			PassengerService.SetHp(player, arg)
		end
	end,
	Damage = function(player, arg)
		if typeof(arg) == "number" then
			PassengerService.ApplyDamage(player, arg, "debug")
		end
	end,
	AddCash = function(player, arg)
		if typeof(arg) == "number" then
			FareService.AddCash(player, Money.Cents(arg)) -- the button sends dollars
		end
	end,
	ForceEnd = function()
		-- RoundService requires us indirectly, so resolve it late to avoid a cycle.
		local RoundService = require(script.Parent.RoundService) :: any
		RoundService.ForceEnd()
	end,
	SpawnNpc = function()
		PassengerService.SpawnWeighted()
	end,
	SpawnGolden = function()
		PassengerService.SpawnGolden()
	end,
	AddGems = function(player, arg)
		if typeof(arg) == "number" then
			DataService.AddGems(player, math.round(arg))
		end
	end,
	Bail = function(player)
		PassengerService.Bail(player, "hp")
	end,
	-- Your car at the west end of the long north road, facing east: a straight run for testing.
	Runway = function(player)
		local entry = VehicleService.GetEntry(player)
		if not entry or entry.chassis.Anchored then
			return
		end
		local roads = MapService.GetBlockout().RoadCoords
		local x, z = roads[1] + 20, roads[1]
		local pos = Vector3.new(x, MapService.GroundY(Vector3.new(x, 0, z), 0) + Config.Chassis.ResetLift, z)
		VehicleService.Teleport(entry, CFrame.lookAt(pos, pos + Vector3.xAxis))
	end,
	-- The first bot parked broadside 40 studs ahead with a passenger (ram it), or charging back at you (get rammed).
	BotStage = function(player, arg)
		local BotService = require(script.Parent.BotService) :: any
		BotService.DebugStage(player, if arg == "charge" then "charge" else "park")
	end,
	-- Dollars for the first bot (to make it the leader).
	BotCash = function(_player, arg)
		local Racers = require(script.Parent.Parent.Racers) :: any
		local bot = Racers.Bots()[1]
		if bot and typeof(arg) == "number" then
			FareService.AddCash(bot, Money.Cents(arg))
		end
	end,
	-- The first bot's passenger at this HP (to see a ram or a hit make them bail).
	BotHp = function(_player, arg)
		local Racers = require(script.Parent.Parent.Racers) :: any
		local bot = Racers.Bots()[1]
		if bot and typeof(arg) == "number" then
			PassengerService.SetHp(bot, arg)
		end
	end,
	-- Your car parked on your passenger's drop-off (the delivery happens on the next tick).
	ToDropoff = function(player)
		local fare = FareService.GetFare(player)
		local entry = VehicleService.GetEntry(player)
		if not fare or not entry or entry.chassis.Anchored then
			return
		end
		local d = fare.destination
		local pos = Vector3.new(d.X, MapService.GroundY(d, d.Y) + Config.Chassis.ResetLift, d.Z)
		VehicleService.Teleport(entry, CFrame.lookAt(pos, pos + entry.chassis.CFrame.LookVector * Vector3.new(1, 0, 1)))
	end,
	-- The next passenger you pick up asks for this request (arg: its Config.Chaos.Requests.List Id).
	Request = function(player, arg)
		if typeof(arg) == "string" then
			FareService.DebugForceRequest(player, arg)
		end
	end,
	-- A full carpool appears and climbs in.
	Carpool = function(player)
		FareService.DebugCarpool(player)
	end,
	-- Park facing the nearest waiting passenger, a special one (ticking, carpool, golden) first: to look at curbs.
	ToCurb = function(player)
		local entry = VehicleService.GetEntry(player)
		if not entry or entry.chassis.Anchored then
			return
		end
		local from = entry.chassis.Position
		local best: PassengerService.Npc? = nil
		local bestRank, bestDist = 0, math.huge
		for _, npc in PassengerService.GetAll() do
			if npc.state == 0 then
				-- a person hailing first, then the special fares, then the nearest
				local rank = if npc.rider then 2 elseif npc.ticking or npc.riders > 1 or npc.golden then 1 else 0
				local dist = (npc.position - from).Magnitude
				if rank > bestRank or (rank == bestRank and dist < bestDist) then
					best, bestRank, bestDist = npc, rank, dist
				end
			end
		end
		if not best then
			return
		end
		local stand = best.torso.CFrame
		-- a person: close enough that the cab claims them as it stops; an NPC: roll forward a little first
		local distance = if best.rider then Config.PlayerFare.DebugCurbDistance else Config.Fares.DebugCurbDistance
		local p = (stand * CFrame.new(0, 0, -distance)).Position
		local pos = Vector3.new(p.X, MapService.GroundY(p, p.Y) + Config.Chassis.ResetLift, p.Z)
		VehicleService.Teleport(entry, CFrame.lookAt(pos, Vector3.new(stand.Position.X, pos.Y, stand.Position.Z)))
	end,
	-- Lined up in the curb lane before the nearest fruit stand still standing: drive straight on to smash it.
	ToStand = function(player)
		local entry = VehicleService.GetEntry(player)
		if not entry or entry.chassis.Anchored then
			return
		end
		local cfg = Config.Chaos.FruitStands
		local from = entry.chassis.Position
		local best: CFrame? = nil
		for _, pivot in ItemService.GetActiveStands() do
			if not best or (pivot.Position - from).Magnitude < (best.Position - from).Magnitude then
				best = pivot
			end
		end
		if not best then
			return
		end
		local along = best.RightVector
		local p = best.Position + best.LookVector * cfg.DebugLane - along * cfg.DebugRunUp
		local pos = Vector3.new(p.X, MapService.GroundY(p, p.Y) + Config.Chassis.ResetLift, p.Z)
		VehicleService.Teleport(entry, CFrame.lookAt(pos, pos + along))
	end,
	-- A ticking fare appears and climbs in.
	Ticking = function(player)
		FareService.DebugTicking(player)
	end,
	-- The nearest waiting passenger climbs in, wherever they are.
	ClaimNearest = function(player)
		FareService.DebugClaimNearest(player)
	end,
	-- A world event starts now (arg: its Config.Chaos.Events.List Id).
	Event = function(_player, arg)
		if typeof(arg) == "string" then
			local WorldEventService = require(script.Parent.WorldEventService) :: any
			WorldEventService.DebugStart(arg)
		end
	end,
	-- Your car where the running world event happens.
	ToEvent = function(player)
		local WorldEventService = require(script.Parent.WorldEventService) :: any
		WorldEventService.DebugTeleport(player)
	end,
	-- The round clock jumps to just before Frenzy (or to `arg` seconds left).
	Clock = function(_player, arg)
		local RoundService = require(script.Parent.RoundService) :: any
		RoundService.DebugSetClock(if typeof(arg) == "number" then arg else Config.Chaos.Frenzy.Seconds + 3)
	end,
	-- A walker on the road ahead of your car (arg "dive" / "clip" forces the outcome; nil rolls as usual).
	PedAhead = function(player, arg)
		local PedestrianService = require(script.Parent.PedestrianService) :: any
		PedestrianService.DebugPlaceAhead(player, if typeof(arg) == "string" then arg else nil)
	end,
	-- Pretend a bot's Banana just spun you, so a clip in the next seconds is credited to that bot.
	RivalSpin = function(player)
		local Racers = require(script.Parent.Parent.Racers) :: any
		local bot = Racers.Bots()[1]
		local entry = VehicleService.GetEntry(player)
		if not bot or not entry then
			return
		end
		local seconds = Config.Items.Banana.SpinSeconds * 2
		entry.lockedBy = bot
		entry.lockedUntil = workspace:GetServerTimeNow() + seconds
		print("[DebugService] steering locked by " .. bot.Name .. " for " .. tostring(seconds) .. " s")
	end,
	-- Cycles a pretend live event (none -> each kind -> none) so the event line and its multipliers can be seen today.
	NextEvent = function()
		local ids: { string } = {}
		for id in Config.Events.Kinds do
			table.insert(ids, id)
		end
		table.sort(ids)
		local current = workspace:GetAttribute(Config.Events.DebugAttribute)
		local index = if typeof(current) == "string" then table.find(ids, current) or 0 else 0
		workspace:SetAttribute(Config.Events.DebugAttribute, ids[index + 1]) -- past the last: nil, no event
	end,
	-- The next weather in Config.Chaos.Weather.List, right now (Clear after the last).
	NextWeather = function()
		WeatherService.DebugNext()
	end,
	-- Cycles the garage so every imported vehicle mesh can be checked in one test: grants the next car if needed, swaps now.
	NextVehicle = function(player)
		local ids: { string } = {}
		for id in Config.Vehicles.Stats do
			table.insert(ids, id)
		end
		table.sort(ids)
		local index = table.find(ids, DataService.GetSelectedVehicle(player)) or 0
		local nextId = ids[index % #ids + 1]
		if not DataService.Owns(player, nextId) then
			if Config.Vehicles.Stats[nextId].RobuxOnly then
				MonetizationService.DebugGrant(player, nextId) -- Studio: as if bought for Robux
			else
				DataService.AddGems(player, Config.Vehicles.Stats[nextId].GemPrice)
				DataService.BuyVehicle(player, nextId)
			end
		end
		DataService.SelectVehicle(player, nextId)
		if SessionService.IsDriver(player) then
			VehicleService.Spawn(player)
		end
	end,
	-- Grid seats cap (0 = Config.Server.MaxDrivers), to test a full server with two test players. Takes effect for the
	-- next seat decision (a join, the next match).
	Seats = function(_player, arg)
		if typeof(arg) == "number" then
			SessionService.DebugSetMaxDrivers(arg)
			print(string.format("[DebugService] grid seats: %d", SessionService.MaxDrivers()))
		end
	end,
}

function DebugService.Init()
	Remotes.Get("Debug").OnServerEvent:Connect(function(player: Player, command: any, arg: any)
		if not RunService:IsStudio() then
			return
		end
		if not RateLimiter.Allow(player, "Debug", Config.Net.RateLimits.Debug) then
			return
		end
		if typeof(command) ~= "string" then
			return
		end
		local handler = commands[command]
		if handler then
			handler(player, arg)
		end
	end)
end

function DebugService.Start() end

return DebugService
