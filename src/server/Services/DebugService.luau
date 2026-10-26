--!strict
-- Studio-only commands from the client DebugPanel. Refuses everything outside Studio.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local PassengerService = require(script.Parent.PassengerService)
local FareService = require(script.Parent.FareService)
local ItemService = require(script.Parent.ItemService)
local DataService = require(script.Parent.DataService)

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
			FareService.AddCash(player, math.round(arg))
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
	AddGems = function(player, arg)
		if typeof(arg) == "number" then
			DataService.AddGems(player, math.round(arg))
		end
	end,
	Bail = function(player)
		PassengerService.Bail(player, "hp")
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
