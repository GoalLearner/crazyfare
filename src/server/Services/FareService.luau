--!strict
-- The money side of passengers: pickup contests, destinations, timers, delivery, tips, stunt cash, quota, rank.
-- All money here is integer cents (Config is in dollars; Money.Cents converts). Three ledgers per player:
--   wallet       spendable at the Pit Stop, carried across the match
--   roundEarned  progress toward this round's quota; each round starts at Config.PitStop.CarryFrac of the wallet
--   matchEarned  everything earned this match (spending doesn't reduce it): the final standings

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Money = require(ReplicatedStorage.Shared.Money)
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
local wallet: { [Player]: number } = {}
local roundEarned: { [Player]: number } = {}
local matchEarned: { [Player]: number } = {}
local delivered: { [Player]: number } = {}
local bestTip: { [Player]: number } = {}
local enabled = false
local quota = Money.Cents(Config.Round.Quotas[1])
local rng = Random.new()
local fareEvent: RemoteEvent

local function fire(player: Player, payload: Types.FareEventPayload)
	fareEvent:FireClient(player, payload)
end

-- Spendable cash, in cents.
function FareService.GetCash(player: Player): number
	return wallet[player] or 0
end

-- This round's progress toward the quota, in cents.
function FareService.GetRoundEarned(player: Player): number
	return roundEarned[player] or 0
end

-- Money earned (cents): banks it, counts toward this round's quota and toward the match total.
function FareService.AddCash(player: Player, amount: number)
	wallet[player] = (wallet[player] or 0) + amount
	roundEarned[player] = (roundEarned[player] or 0) + amount
	matchEarned[player] = (matchEarned[player] or 0) + amount
	if enabled and (roundEarned[player] or 0) >= quota then
		onQuotaReached:Fire(player)
	end
end

-- Pit Stop spending: only the wallet goes down. False (and nothing spent) when it can't be afforded.
function FareService.Spend(player: Player, amount: number): boolean
	local have = wallet[player] or 0
	if have < amount then
		return false
	end
	wallet[player] = have - amount
	return true
end

function FareService.GetFare(player: Player): Types.Fare?
	return fares[player]
end

-- This round's quota, in cents.
function FareService.GetQuota(): number
	return quota
end

-- `dollars` straight from Config.Round.Quotas.
function FareService.SetQuota(dollars: number)
	quota = Money.Cents(dollars)
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

-- Players sorted by this round's earnings (or the match total), then deliveries, then UserId for stability.
local function sortedPlayers(byMatch: boolean?): { Player }
	local score = if byMatch then matchEarned else roundEarned
	local list = Players:GetPlayers()
	table.sort(list, function(a, b)
		local ca, cb = score[a] or 0, score[b] or 0
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

-- Round podium (`byMatch` false: this round's earnings) or final standings (`byMatch` true: the match total).
function FareService.GetResults(byMatch: boolean?): { Types.PodiumEntry }
	local score = if byMatch then matchEarned else roundEarned
	local results: { Types.PodiumEntry } = {}
	for _, player in sortedPlayers(byMatch) do
		table.insert(results, {
			id = player.UserId,
			name = player.DisplayName,
			cash = score[player] or 0,
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
		wallet[player] = 0
		roundEarned[player] = 0
		matchEarned[player] = 0
		delivered[player] = 0
		bestTip[player] = 0
	end
end

-- New round inside a match: active fares drop; the quota count restarts at a head start of the unspent wallet.
function FareService.ResetRound()
	table.clear(fares)
	for _, player in Players:GetPlayers() do
		roundEarned[player] = math.floor((wallet[player] or 0) * Config.PitStop.CarryFrac)
	end
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
		base = Money.Cents(tierDef.Base),
		pickupIndex = npc.pickupIndex,
		destinationIndex = destination.index,
		destination = destination.position,
		startedAt = now,
		deadline = now + duration,
		distance = distance,
		stuntTips = 0,
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

-- The Tip Jar Pit Stop card multiplies tips, stunt cash included.
local function tipJarMult(player: Player): number
	local tipJar = player:GetAttribute("Pit_TipJar")
	return if typeof(tipJar) == "number" then tipJar else 1
end

-- An accepted stunt: cash into the current fare at once, more per chain step, capped per fare. The popup fires either
-- way, so a stunt with no passenger still shows its name.
local function onStunt(player: Player, kind: string, units: number, chain: number)
	local cfg = Config.Stunts
	local fare = fares[player]
	local amount = 0
	if enabled and fare and not fare.expired then
		local raw = Money.Cents(units * (cfg.Pay[kind] or 0)) * (1 + cfg.ChainBonus * (chain - 1)) * tipJarMult(player)
		local room = math.max(0, math.round(fare.base * cfg.MaxPerFareFrac) - fare.stuntTips)
		amount = math.min(room, math.round(raw))
		if amount > 0 then
			fare.stuntTips += amount
			if not cfg.HoldUntilDelivery then
				FareService.AddCash(player, amount)
			end
		end
	end
	fire(player, { kind = "Stunt", stunt = kind, amount = amount, chain = chain })
end

local function finishDelivery(player: Player, fare: Types.Fare, npc: PassengerService.Npc, now: number, allowTip: boolean)
	local total = math.max(0.01, fare.deadline - fare.startedAt)
	local timeFrac = VecUtil.Clamp01((fare.deadline - now) / total)
	local hpFrac = VecUtil.Clamp01(npc.hp / npc.maxHp)
	local tips = Config.Tips
	local speedy = VecUtil.Clamp01((timeFrac - tips.TimeFloor) / (tips.TimeCeil - tips.TimeFloor))
	local chill = VecUtil.Clamp01((hpFrac - tips.HpFloor) / (1 - tips.HpFloor))
	local tipRaw = if allowTip then fare.base * tips.MaxFrac * (tips.TimeWeight * speedy + tips.ChillWeight * chill) else 0
	tipRaw *= tipJarMult(player)
	local tipShown = math.round(tipRaw)
	-- Stunt cash rides in the fare (Config.Stunts.HoldUntilDelivery) and is lost with the tip on a late arrival.
	local stunts = if allowTip then fare.stuntTips else 0
	local held = if Config.Stunts.HoldUntilDelivery then stunts else 0
	local payout = fare.base + tipShown + held

	fares[player] = nil
	delivered[player] = (delivered[player] or 0) + 1
	bestTip[player] = math.max(bestTip[player] or 0, tipShown + stunts)
	PassengerService.Deliver(player)
	fire(player, {
		kind = "Delivered",
		tier = fare.tier,
		base = fare.base,
		payout = payout,
		tip = tipShown,
		stunts = stunts,
		line = if allowTip then nil else "LATE. NO TIP.",
	})
	FareService.AddCash(player, payout)
	onDelivered:Fire(player, fare.tier, tipShown + stunts)

	task.delay(Config.Fares.RespawnDelay, function()
		if enabled then
			PassengerService.EnsureCount(FareService.TargetNpcCount())
		end
	end)
end

local function handleBail(victim: Player, npc: PassengerService.Npc, reason: string, attacker: Player?)
	local fare = fares[victim]
	fares[victim] = nil
	ComboService.Reset(victim, "bail")
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
	ComboService.OnStunt:Connect(onStunt)
	ComboService.OnChainBroken:Connect(function(player: Player, chain: number, reason: string)
		fire(player, { kind = "ChainBroken", chain = chain, reason = reason })
	end)
	PassengerService.OnDamaged:Connect(function(player: Player, amount: number, source: string)
		local lines = Config.Passenger.CrashLines
		fire(player, {
			kind = "Hurt",
			amount = math.round(amount),
			source = source,
			line = if source == "crash" then lines[rng:NextInteger(1, #lines)] else nil,
		})
	end)
	Players.PlayerAdded:Connect(function(player: Player)
		wallet[player] = 0
		roundEarned[player] = 0
		matchEarned[player] = 0
		delivered[player] = 0
		bestTip[player] = 0
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		fares[player] = nil
		wallet[player] = nil
		roundEarned[player] = nil
		matchEarned[player] = nil
		delivered[player] = nil
		bestTip[player] = nil
	end)
end

function FareService.Start()
	RunService.Heartbeat:Connect(tick)
end

return FareService
