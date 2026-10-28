--!strict
-- The new-player funnel (Creator Hub > Analytics > Funnels): joined, pressed PLAY, drove, first pickup, first delivery,
-- finished a match. Each step is logged once per account (the highest one sent is saved in the profile as
-- OnboardingStep), so the funnel shows where new players stop. Also a custom event per finished match (value = place).
-- Gems flows are logged by DataService, level-ups by ProgressionService, drops by DropService (all through Metrics).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Metrics = require(script.Parent.Parent.Metrics)
local DataService = require(script.Parent.DataService)
local SessionService = require(script.Parent.SessionService)
local FareService = require(script.Parent.FareService)
local MatchController = require(script.Parent.MatchController)

local MetricsService = {}

local cfg = Config.Metrics

-- Log this funnel step if the account hasn't reached it before.
local function step(player: Player, name: string)
	local index = table.find(cfg.Onboarding, name)
	local d = DataService.Get(player)
	if not index or not d or index <= d.OnboardingStep then
		return
	end
	d.OnboardingStep = index
	Metrics.Onboarding(player, index, name)
end

function MetricsService.Init()
	DataService.OnLoaded:Connect(function(player: Player)
		step(player, "Joined")
	end)
	SessionService.OnStateChanged:Connect(function(player: Player, old: string, new: string)
		if old == "Title" and new ~= "Title" then
			step(player, "PressedPlay")
		end
		if new == "Driver" then
			step(player, "Drove")
		end
	end)
	FareService.OnClaimed:Connect(function(player: Player)
		step(player, "FirstPickup")
	end)
	FareService.OnDelivered:Connect(function(player: Player)
		step(player, "FirstDelivery")
	end)
	MatchController.OnMatchEnded:Connect(function(results: { Types.PodiumEntry })
		for place, entry in results do
			local player = Players:GetPlayerByUserId(entry.id)
			if player then
				step(player, "FinishedMatch")
				Metrics.Event(player, cfg.Events.MatchFinished, place)
			end
		end
	end)
end

function MetricsService.Start() end

return MetricsService
