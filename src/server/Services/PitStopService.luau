--!strict
-- Pit Stop: between rounds every player gets CardsOffered random boost cards priced by round (last place gets a
-- pity discount), buys them with round cash, and the boosts apply to the next round only.
-- Boosts are exposed as player attributes "Pit_<CardId>" = Card.Value so both server systems and the owning client
-- can read them without another remote. StartItem is granted directly.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local Types = require(ReplicatedStorage.Shared.Types)
local FareService = require(script.Parent.FareService)
local ItemService = require(script.Parent.ItemService)
local MonetizationService = require(script.Parent.MonetizationService)

local PitStopService = {}

local offers: { [Player]: { Types.PitStopCard } } = {}
local endsAt = 0
local open = false
local rng = Random.new()
local offerEvent: RemoteEvent

local function cardIds(): { string }
	local ids: { string } = {}
	for id in Config.PitStop.Cards do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

local function boughtCount(cards: { Types.PitStopCard }): number
	local n = 0
	for _, card in cards do
		if card.bought then
			n += 1
		end
	end
	return n
end

local function sendOffer(player: Player)
	local cards = offers[player]
	if not cards then
		return
	end
	local payload: Types.PitStopOfferPayload = {
		cards = cards,
		cash = FareService.GetCash(player),
		endsAt = endsAt,
		buysLeft = Config.PitStop.MaxBuys - boughtCount(cards),
	}
	offerEvent:FireClient(player, payload)
end

-- Open the shop for everyone. `roundIndex` is the round that just ended.
function PitStopService.Open(roundIndex: number, closesAt: number)
	open = true
	endsAt = closesAt
	table.clear(offers)
	local scales = Config.PitStop.PriceScale
	local scale = scales[math.min(roundIndex, #scales)] or 1
	local ranks = FareService.GetRanks()
	local playerCount = #Players:GetPlayers()
	for _, player in Players:GetPlayers() do
		local ids = cardIds()
		for i = #ids, 2, -1 do
			local j = rng:NextInteger(1, i)
			ids[i], ids[j] = ids[j], ids[i]
		end
		local isLast = playerCount > 1 and ranks[player] == playerCount
		local discount = if isLast then 1 - Config.PitStop.PityDiscount else 1
		local cards: { Types.PitStopCard } = {}
		local offered = if MonetizationService.HasPitStopPlus(player) then Config.Monetization.PitStopPlusCards else Config.PitStop.CardsOffered
		for i = 1, math.min(offered, #ids) do
			local id = ids[i]
			local def = Config.PitStop.Cards[id]
			table.insert(cards, {
				id = id,
				name = def.Name,
				effect = def.Effect,
				price = math.max(1, math.round(def.Price * scale * discount)),
				bought = false,
			})
		end
		offers[player] = cards
		sendOffer(player)
	end
end

function PitStopService.Close()
	open = false
end

local function buy(player: Player, cardId: string)
	if not open then
		return
	end
	local cards = offers[player]
	if not cards then
		return
	end
	if boughtCount(cards) >= Config.PitStop.MaxBuys then
		return
	end
	for _, card in cards do
		if card.id == cardId then
			if card.bought then
				return
			end
			if FareService.GetCash(player) < card.price then
				return
			end
			FareService.AddCash(player, -card.price)
			card.bought = true
			sendOffer(player)
			return
		end
	end
end

-- Called at the start of the next round, after items were cleared: grant StartItem, set the boost attributes.
function PitStopService.ApplyBoosts()
	for player, cards in offers do
		if not player.Parent then
			continue
		end
		for _, card in cards do
			if not card.bought then
				continue
			end
			local def = Config.PitStop.Cards[card.id]
			if card.id == "StartItem" then
				local pool: { string } = {}
				for id in Config.Items.Pool do
					table.insert(pool, id)
				end
				table.sort(pool)
				ItemService.Give(player, pool[rng:NextInteger(1, #pool)])
			elseif def then
				player:SetAttribute("Pit_" .. card.id, def.Value)
			end
		end
	end
	table.clear(offers)
end

-- Called at round end: boosts were for that round only.
function PitStopService.ClearBoosts()
	for _, player in Players:GetPlayers() do
		for id in Config.PitStop.Cards do
			player:SetAttribute("Pit_" .. id, nil)
		end
	end
end

-- Server-side helper for systems that scale by a card: returns Card.Value or 1.
function PitStopService.Boost(player: Player, cardId: string): number
	local value = player:GetAttribute("Pit_" .. cardId)
	return if typeof(value) == "number" then value else 1
end

function PitStopService.Init()
	offerEvent = Remotes.Get("PitStopOffer")
	Remotes.Get("PitStopBuy").OnServerEvent:Connect(function(player: Player, cardId: any)
		if not RateLimiter.Allow(player, "PitStopBuy", Config.Net.RateLimits.PitStopBuy) then
			return
		end
		if typeof(cardId) == "string" then
			buy(player, cardId)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		offers[player] = nil
	end)
end

function PitStopService.Start() end

return PitStopService
