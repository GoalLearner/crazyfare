--!strict
-- People on foot (SessionService "Passenger" and "Queued"): a Roblox character on a sidewalk near a pickup point, in the
-- Walkers collision group (cars, traffic and bots pass straight through; the client plays a cartoon dodge). Someone who
-- stands in a traffic lane for Config.Walkers.LanePushSeconds is put back on the sidewalk. At a curb, HAIL CAB makes
-- them a player fare (PassengerService.SpawnPlayerFare); walking off (HailLeash) calls it off. Riding along, their
-- avatar is seated by every client (RidingWith); the server never moves them until the ride ends.
-- Drivers and the depot have no character.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local Sidewalk = require(ReplicatedStorage.Shared.Sidewalk)
local VecUtil = require(ReplicatedStorage.Shared.VecUtil)
local MapService = require(script.Parent.MapService)
local SessionService = require(script.Parent.SessionService)
local PassengerService = require(script.Parent.PassengerService)
local FareService = require(script.Parent.FareService)

local WalkerService = {}

local inLaneFor: { [Player]: number } = {}
local lastHailAt: { [Player]: number } = {}
local rng = Random.new()
local checkAccumulator = 0

local function isWalker(player: Player): boolean
	local state = SessionService.GetState(player)
	return state == "Passenger" or state == "Queued"
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function setGroup(part: Instance)
	if part:IsA("BasePart") then
		part.CollisionGroup = Config.CollisionGroups.Walkers
	end
end

-- A sidewalk spot beside a random pickup point, facing the road.
local function spawnCFrame(): CFrame
	local pickups = MapService.GetPickups()
	if #pickups == 0 then
		return CFrame.new(MapService.GetCenter() + Vector3.new(0, 5, 0))
	end
	local point = pickups[rng:NextInteger(1, #pickups)]
	local look = VecUtil.FlatUnit(point.cframe.LookVector)
	local along = Vector3.new(-look.Z, 0, look.X) * Config.Walkers.SpawnOffset * (if rng:NextNumber() < 0.5 then -1 else 1)
	local at = point.position + along
	local y = MapService.GroundY(at, at.Y)
	local pos = Vector3.new(at.X, y + 3, at.Z)
	return CFrame.lookAt(pos, pos + look)
end

local function place(player: Player)
	local character = player.Character
	if character then
		character:PivotTo(spawnCFrame())
	end
end

local function loadCharacter(player: Player)
	task.spawn(function()
		local ok, err = pcall(function()
			player:LoadCharacter()
		end)
		if not ok then
			warn("[WalkerService] LoadCharacter failed for " .. player.Name .. ": " .. tostring(err))
		end
	end)
end

local function removeCharacter(player: Player)
	PassengerService.CancelHail(player, "cancelled")
	player:SetAttribute("Hailing", nil)
	local character = player.Character
	if character then
		player.Character = nil
		character:Destroy()
	end
	inLaneFor[player] = nil
end

local function onCharacter(player: Player, character: Model)
	for _, part in character:GetDescendants() do
		setGroup(part)
	end
	character.DescendantAdded:Connect(setGroup)
	-- after the spawn location has had its say
	task.defer(function()
		if player.Character == character and isWalker(player) then
			place(player)
		end
	end)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(function()
			PassengerService.CancelHail(player, "cancelled")
			task.delay(Config.Walkers.RespawnSeconds, function()
				if player.Parent and player.Character == character and isWalker(player) then
					loadCharacter(player)
				end
			end)
		end)
	end
end

-- Lanes and leashes: a few times a second.
local function check()
	local B = MapService.GetBlockout()
	for _, player in Players:GetPlayers() do
		if not isWalker(player) or player:GetAttribute("RidingWith") ~= nil then
			inLaneFor[player] = nil
			continue
		end
		local root = rootOf(player)
		if not root then
			continue
		end
		local pos = root.Position
		-- Hailing and walked off: the hail is off
		local fare = PassengerService.GetRiderFare(player)
		if fare and fare.state == 0 and VecUtil.FlatDistance(pos, fare.position) > Config.PlayerFare.HailLeash then
			PassengerService.CancelHail(player, "cancelled")
			lastHailAt[player] = os.clock()
		end
		if Sidewalk.InRoad(B, pos) then
			local t = (inLaneFor[player] or 0) + Config.Walkers.CheckSeconds
			inLaneFor[player] = t
			if t >= Config.Walkers.LanePushSeconds then
				inLaneFor[player] = nil
				local back = Sidewalk.Nearest(B, pos, Config.Walkers.SidewalkInset)
				local y = MapService.GroundY(back, pos.Y)
				local at = Vector3.new(back.X, y + 3, back.Z)
				root.AssemblyLinearVelocity = Vector3.zero
				local character = player.Character
				if character then
					character:PivotTo(CFrame.lookAt(at, at + VecUtil.FlatUnit(root.CFrame.LookVector)))
				end
			end
		else
			inLaneFor[player] = nil
		end
	end
end

-- HailCab(true): at a curb, during a round, become a player fare. HailCab(false): call it off.
local function onHail(player: Player, hail: any)
	if not RateLimiter.Allow(player, "HailCab", Config.Net.RateLimits.HailCab) then
		return
	end
	if typeof(hail) ~= "boolean" or not isWalker(player) or player:GetAttribute("RidingWith") ~= nil then
		return
	end
	if not hail then
		PassengerService.CancelHail(player, "cancelled")
		lastHailAt[player] = os.clock()
		return
	end
	local cfg = Config.PlayerFare
	local root = rootOf(player)
	if not root or not FareService.IsEnabled() or os.clock() - (lastHailAt[player] or -math.huge) < cfg.HailCooldown then
		return
	end
	local B = MapService.GetBlockout()
	local curb = Sidewalk.CurbDistance(B, root.Position)
	if not curb or curb > cfg.HailCurbDistance then
		return
	end
	local spot, out = Sidewalk.CurbSpot(B, root.Position, cfg.CurbInset)
	if not spot or not out then
		return
	end
	local npc = PassengerService.SpawnPlayerFare(player, spot, out)
	if not npc then
		SessionService.OnNotice:Fire(player, cfg.Busy)
		return
	end
	lastHailAt[player] = os.clock()
	player:SetAttribute("Hailing", true)
end

function WalkerService.Init()
	local groups = Config.CollisionGroups
	if not PhysicsService:IsCollisionGroupRegistered(groups.Walkers) then
		PhysicsService:RegisterCollisionGroup(groups.Walkers)
	end
	for _, other in { groups.Vehicles, groups.Traffic, groups.Bots } do
		if not PhysicsService:IsCollisionGroupRegistered(other) then
			PhysicsService:RegisterCollisionGroup(other)
		end
		PhysicsService:CollisionGroupSetCollidable(groups.Walkers, other, false)
	end

	SessionService.OnStateChanged:Connect(function(player: Player, _old: string, new: string)
		if new == "Passenger" or new == "Queued" then
			if player.Character then
				if not player:GetAttribute("RidingWith") then
					place(player)
				end
			else
				loadCharacter(player)
			end
		else
			removeCharacter(player)
		end
	end)
	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterAdded:Connect(function(character: Model)
			onCharacter(player, character)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		inLaneFor[player] = nil
		lastHailAt[player] = nil
	end)
	-- Picked up: no longer hailing. Freed (any way): no longer hailing or riding.
	PassengerService.OnBoarded:Connect(function(_driver: Player, npc: PassengerService.Npc)
		local rider = npc.rider
		if rider then
			rider:SetAttribute("Hailing", nil)
		end
	end)
	PassengerService.OnRiderFreed:Connect(function(rider: Player)
		if rider.Parent then
			rider:SetAttribute("Hailing", nil)
		end
	end)
	-- A new map under everyone's feet: walkers back onto its sidewalks.
	MapService.OnMapLoaded:Connect(function()
		for _, player in Players:GetPlayers() do
			if isWalker(player) and not player:GetAttribute("RidingWith") then
				place(player)
			end
		end
	end)
	Remotes.Get("HailCab").OnServerEvent:Connect(onHail)
end

function WalkerService.Start()
	RunService.Heartbeat:Connect(function(dt: number)
		checkAccumulator += dt
		if checkAccumulator >= Config.Walkers.CheckSeconds then
			checkAccumulator = 0
			check()
		end
	end)
end

return WalkerService
