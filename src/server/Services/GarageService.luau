--!strict
-- Garage actions from the client: select or buy a vehicle, buy an upgrade level, buy paint, equip a trail or horn
-- won in a drop. Validation lives in
-- DataService; this only rate-limits and routes. Nothing here can touch a match in progress.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local DataService = require(script.Parent.DataService)

local GarageService = {}

function GarageService.Init()
	Remotes.Get("GarageAction").OnServerEvent:Connect(function(player: Player, action: any, id: any)
		if not RateLimiter.Allow(player, "GarageAction", Config.Net.RateLimits.GarageAction) then
			return
		end
		if typeof(action) ~= "string" or typeof(id) ~= "string" then
			return
		end
		if action == "Select" then
			DataService.SelectVehicle(player, id)
		elseif action == "Buy" then
			DataService.BuyVehicle(player, id)
		elseif action == "Upgrade" then
			DataService.BuyUpgrade(player, id)
		elseif action == "Paint" then
			DataService.BuyPaint(player, id)
		elseif action == "Trail" or action == "Horn" then
			DataService.Equip(player, action, id)
		end
	end)
end

function GarageService.Start() end

return GarageService
