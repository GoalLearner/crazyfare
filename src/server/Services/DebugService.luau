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
