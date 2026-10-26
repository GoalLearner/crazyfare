--!strict
-- Crazy Combo: a per-player multiplier built from client-reported drift / airtime / near-miss events.
-- The server rate-limits, type-checks and speed-checks every event before it counts.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local VehicleService = require(script.Parent.VehicleService)

type ComboState = {
	steps: number, -- fractional steps; multiplier = 1 + steps * Step
	lastEventAt: number,
	lastDecayAt: number,
}

local ComboService = {}

local states: { [Player]: ComboState } = {}
local maxSteps = (Config.Combo.Max - 1) / Config.Combo.Step

local function getState(player: Player): ComboState
	local state = states[player]
	if not state then
		state = { steps = 0, lastEventAt = 0, lastDecayAt = 0 }
		states[player] = state
	end
	return state
end

local function isFiniteNumber(x: any): boolean
	return typeof(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function addSteps(player: Player, amount: number)
	local state = getState(player)
	state.steps = math.min(maxSteps, state.steps + amount)
	state.lastEventAt = os.clock()
	state.lastDecayAt = state.lastEventAt
end

function ComboService.GetMultiplier(player: Player): number
	local state = states[player]
	if not state then
		return 1
	end
	return math.min(Config.Combo.Max, 1 + state.steps * Config.Combo.Step)
end

function ComboService.Reset(player: Player)
	local state = states[player]
	if state then
		state.steps = 0
	end
end

function ComboService.ResetAll()
	for _, state in states do
		state.steps = 0
	end
end

function ComboService.Remove(player: Player)
	states[player] = nil
end

function ComboService.Init()
	Remotes.Get("ComboEvent").OnServerEvent:Connect(function(player: Player, payload: any)
		if not RateLimiter.Allow(player, "ComboEvent", Config.Combo.MaxEventsPerSecond) then
			return
		end
		if typeof(payload) ~= "table" then
			return
		end
		local kind = payload.kind
		local value = payload.value
		if typeof(kind) ~= "string" or not isFiniteNumber(value) then
			return
		end
		local speed = VehicleService.GetSpeed(player)
		if speed < Config.Combo.MinSpeedForEvents then
			return
		end
		if kind == "Drift" then
			addSteps(player, math.clamp(value, 0, 1) / Config.Combo.DriftTickSeconds)
		elseif kind == "Airtime" then
			addSteps(player, math.clamp(value, 0, 3) / Config.Combo.AirtimeStepSeconds)
		elseif kind == "NearMiss" then
			if speed >= Config.Combo.NearMissMinSpeed then
				addSteps(player, 1)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		ComboService.Remove(player)
	end)
end

function ComboService.Start()
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for _, state in states do
			if state.steps > 0 and now - state.lastEventAt >= Config.Combo.IdleSeconds and now - state.lastDecayAt >= Config.Combo.DecayStepSeconds then
				state.steps = math.max(0, state.steps - 1)
				state.lastDecayAt = now
			end
		end
	end)
end

return ComboService
