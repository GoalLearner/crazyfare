--!strict
-- Roblox analytics (Creator Hub > Analytics): thin wrappers over AnalyticsService for the new-player funnel, every
-- Gems earn and spend, level-ups and a few custom events. Names live in Config.Metrics. Server only; bots never log;
-- every call is pcall'd, because analytics must never break a match. In Studio each call also prints a line
-- (Config.Metrics.StudioLog) so a test shows what would be sent.

local AnalyticsService = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Racers = require(script.Parent.Racers)

local Metrics = {}

local cfg = Config.Metrics
local isStudio = RunService:IsStudio()

local function send(player: Player, label: string, call: () -> ())
	if Racers.IsBot(player) then
		return
	end
	local result = table.pack(pcall(call))
	local ok, err = result[1], result[2]
	if isStudio and cfg.StudioLog then
		print(string.format("[Metrics] %s %s%s", player.Name, label, if ok then "" else "  FAILED: " .. tostring(err)))
	end
end

-- A step of the one-time new-player funnel (Config.Metrics.Onboarding; 1 = joined).
function Metrics.Onboarding(player: Player, step: number, name: string)
	send(player, string.format("onboarding %d %s", step, name), function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name)
	end)
end

-- Gems in (`source` true) or out, with the balance after it, the Roblox transaction type (Config.Metrics.Kinds) and
-- what it was for (`sku`, e.g. "Car:GoKart", "Quest:daily1").
function Metrics.Gems(player: Player, source: boolean, amount: number, balance: number, kind: string, sku: string?)
	if amount <= 0 then
		return
	end
	local flow = if source then Enum.AnalyticsEconomyFlowType.Source else Enum.AnalyticsEconomyFlowType.Sink
	send(player, string.format("gems %s%d (%d) %s %s", if source then "+" else "-", amount, balance, kind, sku or ""), function()
		AnalyticsService:LogEconomyEvent(player, flow, cfg.Currency, amount, balance, kind, sku)
	end)
end

-- A level reached on a progression path (Config.Metrics.LevelPath).
function Metrics.Level(player: Player, level: number)
	send(player, string.format("level %d", level), function()
		AnalyticsService:LogProgressionCompleteEvent(player, cfg.LevelPath, level)
	end)
end

-- A custom event (Config.Metrics.Events), with an optional number.
function Metrics.Event(player: Player, name: string, value: number?)
	send(player, string.format("event %s %s", name, if value then tostring(value) else ""), function()
		AnalyticsService:LogCustomEvent(player, name, value)
	end)
end

return Metrics
