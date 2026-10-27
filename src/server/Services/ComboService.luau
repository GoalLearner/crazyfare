--!strict
-- Stunts and the chain. The client reports drift, airtime and near misses; the server rate-limits, type-checks and
-- speed-checks every report before it counts. An accepted stunt adds to the player's chain (x1 to Config.Stunts.ChainMax)
-- and fires OnStunt, which FareService turns into cash. A crash that hurts, a bail, a new round or
-- Config.Stunts.ChainIdleSeconds without a stunt breaks the chain.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Signal = require(ReplicatedStorage.Shared.Signal)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local VehicleService = require(script.Parent.VehicleService)

type ChainState = {
	chain: number, -- 0 = no chain running
	lastStuntAt: number,
	driftCarry: number, -- drift seconds not yet turned into a chain step
}

local ComboService = {}

local onDrift: Signal.Signal<Player, number> = Signal.new()
ComboService.OnDrift = onDrift -- (player, seconds) accepted drift time
local onStunt: Signal.Signal<Player, string, number, number> = Signal.new()
ComboService.OnStunt = onStunt -- (player, kind, units of pay, chain after this stunt)
local onChainBroken: Signal.Signal<Player, number, string> = Signal.new()
ComboService.OnChainBroken = onChainBroken -- (player, chain it reached, "crash" | "bail" | "idle")

local states: { [Player]: ChainState } = {}

local function getState(player: Player): ChainState
	local state = states[player]
	if not state then
		state = { chain = 0, lastStuntAt = 0, driftCarry = 0 }
		states[player] = state
	end
	return state
end

local function isFiniteNumber(x: any): boolean
	return typeof(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function addStunt(player: Player, kind: string, units: number, steps: number)
	local state = getState(player)
	state.chain = math.clamp(state.chain + steps, 1, Config.Stunts.ChainMax)
	state.lastStuntAt = os.clock()
	onStunt:Fire(player, kind, units, state.chain)
end

function ComboService.GetChain(player: Player): number
	local state = states[player]
	return if state then state.chain else 0
end

-- Ends the chain. A chain of 2 or more fires OnChainBroken with the reason.
function ComboService.Reset(player: Player, reason: string?)
	local state = states[player]
	if not state then
		return
	end
	local had = state.chain
	state.chain = 0
	state.driftCarry = 0
	if had >= 2 then
		onChainBroken:Fire(player, had, reason or "bail")
	end
end

-- New round: every chain ends quietly.
function ComboService.ResetAll()
	for _, state in states do
		state.chain = 0
		state.driftCarry = 0
	end
end

function ComboService.Remove(player: Player)
	states[player] = nil
end

function ComboService.Init()
	local cfg = Config.Stunts
	Remotes.Get("ComboEvent").OnServerEvent:Connect(function(player: Player, payload: any)
		if not RateLimiter.Allow(player, "ComboEvent", cfg.MaxEventsPerSecond) then
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
		if speed < cfg.MinSpeedForEvents then
			return
		end
		if kind == "Drift" then
			local seconds = math.clamp(value, 0, cfg.MaxDriftReport)
			if seconds <= 0 then
				return
			end
			local state = getState(player)
			state.driftCarry += seconds
			local steps = math.floor(state.driftCarry / cfg.DriftChainSeconds)
			state.driftCarry -= steps * cfg.DriftChainSeconds
			addStunt(player, "Drift", seconds / cfg.UnitSeconds, steps)
			onDrift:Fire(player, seconds)
		elseif kind == "Airtime" then
			local seconds = math.clamp(value, 0, cfg.MaxAirSeconds)
			if seconds > 0 then
				addStunt(player, "Airtime", seconds / cfg.UnitSeconds, 1)
			end
		elseif kind == "NearMiss" then
			if speed >= cfg.NearMissMinSpeed then
				addStunt(player, "NearMiss", 1, 1)
			end
		end
	end)

	-- A crash big enough to hurt a passenger breaks the chain, passenger or not.
	VehicleService.OnCrash:Connect(function(player: Player, lost: number)
		if VehicleService.CrashIntensity(player, lost) >= Config.Passenger.CrashMinIntensity then
			ComboService.Reset(player, "crash")
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		ComboService.Remove(player)
	end)
end

function ComboService.Start()
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for player, state in states do
			if state.chain > 0 and now - state.lastStuntAt >= Config.Stunts.ChainIdleSeconds then
				ComboService.Reset(player, "idle")
			end
		end
	end)
end

return ComboService
