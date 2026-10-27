--!strict
-- One batched Snapshot RemoteEvent at Config.Net.SnapshotHz. Minimap, world tags and rival HP bars read only this.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local VecUtil = require(ReplicatedStorage.Shared.VecUtil)
local VehicleService = require(script.Parent.VehicleService)
local PassengerService = require(script.Parent.PassengerService)
local FareService = require(script.Parent.FareService)
local ComboService = require(script.Parent.ComboService)
local ItemService = require(script.Parent.ItemService)
local GemService = require(script.Parent.GemService)

local ReplicationService = {}

local snapshotEvent: RemoteEvent
local accumulator = 0

local function round1(x: number): number
	return math.round(x * 10) / 10
end

local function levelOf(player: Player): number
	local level = player:GetAttribute("Level")
	return if typeof(level) == "number" then level else 1
end

local function buildSnapshot(): Types.Snapshot
	local ranks = FareService.GetRanks()
	local players: { Types.PlayerSnap } = {}
	for player, entry in VehicleService.GetAll() do
		local cf = entry.chassis.CFrame
		local fare = FareService.GetFare(player)
		local npc = PassengerService.GetLoaded(player)
		table.insert(players, {
			id = player.UserId,
			name = player.DisplayName,
			x = round1(cf.Position.X),
			z = round1(cf.Position.Z),
			yaw = round1(VecUtil.Yaw(cf.LookVector)),
			cash = FareService.GetRoundEarned(player), -- cents toward this round's quota
			fare = if fare then fare.base else 0,
			tier = (if fare then fare.tier else "") :: string,
			hp = if npc then math.round(npc.hp) else 0,
			maxHp = if npc then npc.maxHp else 0,
			combo = round1(ComboService.GetMultiplier(player)),
			rank = ranks[player] or 0,
			item = ItemService.GetHeld(player),
			gems = GemService.GetTotal(player),
			level = levelOf(player),
			vip = player:GetAttribute("VIP") == true,
		})
	end
	return {
		t = workspace:GetServerTimeNow(),
		players = players,
		npcs = PassengerService.Snapshot(),
	}
end

function ReplicationService.Init()
	snapshotEvent = Remotes.Get("Snapshot")
end

function ReplicationService.Start()
	local interval = 1 / Config.Net.SnapshotHz
	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator < interval then
			return
		end
		accumulator = 0
		snapshotEvent:FireAllClients(buildSnapshot())
	end)
end

return ReplicationService
