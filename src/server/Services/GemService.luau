--!strict
-- Gems: the persistent currency. Phase 3 keeps session totals in memory; Phase 4 swaps the store for ProfileStore.
-- Awarded only at match end (placement + fares delivered). Never spendable mid-match.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

local GemService = {}

local totals: { [Player]: number } = {}

function GemService.GetTotal(player: Player): number
	return totals[player] or 0
end

function GemService.Add(player: Player, amount: number)
	totals[player] = (totals[player] or 0) + amount
end

-- Pays every entry by placement and fares, writes the award into the entry, returns the entries.
function GemService.AwardMatch(results: { Types.PodiumEntry }): { Types.PodiumEntry }
	local placement = Config.Gems.Placement
	for i, entry in results do
		local byPlace = placement[math.min(i, #placement)] or 0
		local gems = byPlace + entry.fares * Config.Gems.PerFare
		entry.gems = gems
		local player = Players:GetPlayerByUserId(entry.id)
		if player then
			GemService.Add(player, gems)
		end
	end
	return results
end

function GemService.Init()
	Players.PlayerRemoving:Connect(function(player: Player)
		totals[player] = nil
	end)
end

function GemService.Start() end

return GemService
