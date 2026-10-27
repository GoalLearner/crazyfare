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

local DebugService = {}

local commands: { [string]: (player: Player, arg: any) -> () } = {
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
	-- The nearest waiting passenger climbs in, wherever they are.
	ClaimNearest = function(player)
		FareService.DebugClaimNearest(player)
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
			DataService.AddGems(player, Config.Vehicles.Stats[nextId].GemPrice)
			DataService.BuyVehicle(player, nextId)
		end
		DataService.SelectVehicle(player, nextId)
		VehicleService.Spawn(player)
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
