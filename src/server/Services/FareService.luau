--!strict
-- The money side of passengers: pickup contests, destinations, timers, delivery, tips, combo at payout, cash, quota, rank.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Types = require(ReplicatedStorage.Shared.Types)
local VecUtil = require(ReplicatedStorage.Shared.VecUtil)
local MapService = require(script.Parent.MapService)
local VehicleService = require(script.Parent.VehicleService)
local PassengerService = require(script.Parent.PassengerService)
local ComboService = require(script.Parent.ComboService)

local FareService = {}

local onQuotaReached: Signal.Signal<Player> = Signal.new()
FareService.OnQuotaReached = onQuotaReached
local onDelivered: Signal.Signal<Player, string, number> = Signal.new()
FareService.OnDelivered = onDelivered -- (player, tier, tip shown)

local fares: { [Player]: Types.Fare } = {}
local cash: { [Player]: number } = {}
local delivered: { [Player]: number } = {}
local bestTip: { [Player]: number } = {}
local enabled = false
local quota = Config.Round.Quotas[1]
local rng = Random.new()
local fareEvent: RemoteEvent

local function fire(player: Player, payload: Types.FareEventPayload)
	fareEvent:FireClient(player, payload)
end

function FareService.GetCash(player: Player): number
	return cash[player] or 0
end

function FareService.AddCash(player: Player, amount: number)
	cash[player] = (cash[player] or 0) + amount
	if enabled and (cash[player] or 0) >= quota then
		onQuotaReached:Fire(player)
	end
end

function FareService.GetFare(player: Player): Types.Fare?
	return fares[player]
end

function FareService.GetQuota(): number
	return quota
end

function FareService.SetQuota(value: number)
	quota = value
end

function FareService.SetEnabled(value: boolean)
	enabled = value
end

function FareService.TargetNpcCount(): number
	local players = #Players:GetPlayers()
	local want = players * Config.Fares.NpcsPerPlayer
	local maxCount = math.min(Config.Fares.MaxNpcs, #MapService.GetPickups())
	return math.clamp(want, math.min(Config.Fares.MinNpcs, maxCount), maxCount)
end

-- Players sorted by cash (desc), then deliveries (desc), then UserId for stability.
local function sortedPlayers(): { Player }
	local list = Players:GetPlayers()
	table.sort(list, function(a, b)
		local ca, cb = cash[a] or 0, cash[b] or 0
		if ca ~= cb then
			return ca > cb
		end
		local da, db = delivered[a] or 0, delivered[b] or 0
		if da ~= db then
			return da > db
		end
		return a.UserId < b.UserId
	end)
	return list
end

function FareService.GetRanks(): { [Player]: number }
	local ranks: { [Player]: number } = {}
	for i, player in sortedPlayers() do
		ranks[player] = i
	end
	return ranks
end

function FareService.GetRankBucket(player: Player): Types.RankBucket
	local list = sortedPlayers()
	if #list <= 1 then
		return "Mid"
	end
	local rank = table.find(list, player)
	if rank == 1 then
		return "Leader"
	elseif rank == #list then
		return "Last"
	end
	return "Mid"
end

function FareService.GetResults(): { Types.PodiumEntry }
	local results: { Types.PodiumEntry } = {}
	for _, player in sortedPlayers() do
		table.insert(results, {
			id = player.UserId,
			name = player.DisplayName,
			cash = cash[player] or 0,
			fares = delivered[player] or 0,
			bestTip = bestTip[player] or 0,
		})
	end
	return results
end

-- New match: everything to zero.
function FareService.ResetMatch()
	table.clear(fares)
	for _, player in Players:GetPlayers() do
		cash[player] = 0
		delivered[player] = 0
		bestTip[player] = 0
	end
end

-- New round inside a match: active fares drop, cash and stats carry forward.
function FareService.ResetRound()
	table.clear(fares)
end

local function pickDestination(npc: PassengerService.Npc): MapService.Point?
	local tierDef = Config.Fares.Tiers[npc.tier]
	local candidates: { MapService.Point } = {}
	local closestToBand: MapService.Point? = nil
	local closestGap = math.huge
	local mid = (tierDef.MinTrip + math.min(tierDef.MaxTrip, tierDef.MinTrip + 200)) / 2
	for _, point in MapService.GetDropoffs() do
		local d = VecUtil.FlatDistance(point.position, npc.position)
		if d >= tierDef.MinTrip and d < tierDef.MaxTrip then
			table.insert(candidates, point)
		end
		local gap = math.abs(d - mid)
		if gap < closestGap then
			closestGap = gap
			closestToBand = point
		end
	end
	if #candidates > 0 then
		return candidates[rng:NextInteger(1, #candidates)]
	end
	return closestToBand
end

local function claim(player: Player, npc: PassengerService.Npc)
	local destination: MapService.Point? = nil
	if npc.destinationIndex then
		destination = MapService.GetDropoff(npc.destinationIndex)
	end
	if not destination then
		destination = pickDestination(npc)
	end
	if not destination then
		return
	end
	npc.destinationIndex = destination.index
	local distance = VecUtil.FlatDistance(destination.position, npc.position)
	local now = workspace:GetServerTimeNow()
	local duration = Config.Fares.TimeBase + distance / Config.Fares.TimeSpeed
	local tierDef = Config.Fares.Tiers[npc.tier]
	local fare: Types.Fare = {
		npcId = npc.id,
		expired = false,
		tier = npc.tier,
		base = tierDef.Base,
		pickupIndex = npc.pickupIndex,
		destinationIndex = destination.index,
		destination = destination.position,
		startedAt = now,
		deadline = now + duration,
		distance = distance,
	}
	local npcPosition = npc.position
	PassengerService.Board(npc, player)
	fares[player] = fare
	fire(player, {
		kind = "Claimed",
		npcId = npc.id,
		tier = npc.tier,
		base = fare.base,
		destination = destination.position,
		destinationIndex = destination.index,
		startedAt = now,
		deadline = fare.deadline,
	})
	-- Everyone else nearby and empty sees TAKEN.
	for other, entry in VehicleService.GetAll() do
		if other ~= player and not fares[other] and VecUtil.FlatDistance(entry.chassis.Position, npcPosition) <= Config.Fares.TakenNoticeRadius then
			fire(other, { kind = "Taken", npcId = npc.id, position = npcPosition })
		end
	end
end

local function finishDelivery(player: Player, fare: Types.Fare, npc: PassengerService.Npc, now: number, allowTip: boolean)
	local total = math.max(0.01, fare.deadline - fare.startedAt)
	local timeFrac = VecUtil.Clamp01((fare.deadline - now) / total)
	local hpFrac = VecUtil.Clamp01(npc.hp / npc.maxHp)
	local tips = Config.Tips
	local speedy = VecUtil.Clamp01((timeFrac - tips.TimeFloor) / (tips.TimeCeil - tips.TimeFloor))
	local chill = VecUtil.Clamp01((hpFrac - tips.HpFloor) / (1 - tips.HpFloor))
	local tipRaw = if allowTip then fare.base * tips.MaxFrac * (tips.TimeWeight * speedy + tips.ChillWeight * chill) else 0
	local tipJar = player:GetAttribute("Pit_TipJar")
	if typeof(tipJar) == "number" then
		tipRaw *= tipJar
	end
	local combo = ComboService.GetMultiplier(player)
	local payout = math.round((fare.base + tipRaw) * combo)
	local tipShown = math.round(tipRaw * combo)

	fares[player] = nil
	delivered[player] = (delivered[player] or 0) + 1
	bestTip[player] = math.max(bestTip[player] or 0, tipShown)
	PassengerService.Deliver(player)
	fire(player, {
		kind = "Delivered",
		tier = fare.tier,
		base = fare.base,
		payout = payout,
		tip = tipShown,
		combo = combo,
		line = if allowTip then nil else "LATE. NO TIP.",
	})
	FareService.AddCash(player, payout)
	onDelivered:Fire(player, fare.tier, tipShown)

	task.delay(Config.Fares.RespawnDelay, function()
		if enabled then
			PassengerService.EnsureCount(FareService.TargetNpcCount())
		end
	end)
end

local function handleBail(victim: Player, npc: PassengerService.Npc, reason: string, attacker: Player?)
	local fare = fares[victim]
	fares[victim] = nil
	ComboService.Reset(victim)
	fire(victim, {
		kind = "Bailed",
		reason = reason,
		tier = npc.tier,
		base = if fare then fare.base else 0,
	})
	-- Hunter Bonus: the rival who made them bail gets a share of the lost fare.
	if attacker and fare and attacker ~= victim and attacker.Parent then
		local bonus = math.round(fare.base * Config.Items.HunterBonusFrac)
		if bonus > 0 then
			fire(attacker, { kind = "HunterBonus", payout = bonus, line = victim.DisplayName })
			FareService.AddCash(attacker, bonus)
		end
	end
end

local function tick()
	if not enabled then
		return
	end
	local now = workspace:GetServerTimeNow()
	local vehicles = VehicleService.GetAll()

	-- Pickup contest: every stopped, empty taxi near an available NPC bids; the closest bid per NPC wins this tick.
	local bids: { [number]: { player: Player, npc: PassengerService.Npc, dist: number } } = {}
	local losers: { Player } = {}
	for player, entry in vehicles do
		if fares[player] or entry.chassis.Anchored then
			continue
		end
		if entry.chassis.AssemblyLinearVelocity.Magnitude > Config.Fares.StopSpeed then
			continue
		end
		local npc, dist = PassengerService.GetAvailableNear(entry.chassis.Position, Config.Fares.PickupRadius)
		if npc then
			local current = bids[npc.id]
			if not current then
				bids[npc.id] = { player = player, npc = npc, dist = dist }
			elseif dist < current.dist then
				table.insert(losers, current.player)
				bids[npc.id] = { player = player, npc = npc, dist = dist }
			else
				table.insert(losers, player)
			end
		end
	end
	for _, bid in bids do
		claim(bid.player, bid.npc)
	end
	for _, loser in losers do
		fire(loser, { kind = "Taken" })
	end

	-- Deliveries and timeouts.
	for player, fare in fares do
		local entry = vehicles[player]
		local npc = PassengerService.GetLoaded(player)
		if not entry or not npc then
			fares[player] = nil
			continue
		end
		local pos = entry.chassis.Position
		local speed = entry.chassis.AssemblyLinearVelocity.Magnitude
		if VecUtil.FlatDistance(pos, fare.destination) <= Config.Fares.DeliverRadius and speed <= Config.Fares.StopSpeed then
			finishDelivery(player, fare, npc, now, not fare.expired)
		elseif now >= fare.deadline and not fare.expired then
			if Config.Fares.TimeoutBails then
				PassengerService.Bail(player, "timeout")
			else
				-- Tip is gone; the passenger still has to be delivered for the base fare.
				fare.expired = true
				fire(player, { kind = "Expired", tier = fare.tier, base = fare.base })
			end
		end
	end
end

function FareService.Init()
	fareEvent = Remotes.Get("FareEvent")
	PassengerService.OnBailed:Connect(handleBail)
	Players.PlayerAdded:Connect(function(player: Player)
		cash[player] = 0
		delivered[player] = 0
		bestTip[player] = 0
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		fares[player] = nil
		cash[player] = nil
		delivered[player] = nil
		bestTip[player] = nil
	end)
end

function FareService.Start()
	RunService.Heartbeat:Connect(tick)
end

return FareService
