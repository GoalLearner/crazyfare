--!strict
-- The passenger in your cab, server side: who rides, how they pose and what they shout. Everything is written as
-- attributes on the car model and drawn by RiderController on every client, so no parts are ever welded to a cab here
-- (welding to a car from the server hands its physics back to the server and the driver loses control).
-- Lines: cheers or screams on stunts (ComboService.OnStunt), yelps on crashes and item hits (PassengerService.OnDamaged),
-- "HURRY UP!" when the fare runs low, a Thrill Seeker's "BORING!" when nothing happens. Every number is Config.Rider.
--
-- Car attributes: RiderKind (Config.PassengerTypes.Kinds key, "" when empty), RiderGolden, RiderPose ("rest" | "cheer"
-- | "panic"), RiderLine, RiderLineId (bumps on every line, so the same words can repeat), RiderLineHide (UserId kept
-- from seeing the line, 0 for nobody).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local MapService = require(script.Parent.MapService)
local VehicleService = require(script.Parent.VehicleService)
local PassengerService = require(script.Parent.PassengerService)
local ComboService = require(script.Parent.ComboService)
local FareService = require(script.Parent.FareService)

local RiderService = {}

type Rider = {
	player: Player,
	npc: PassengerService.Npc,
	vehicle: Model?, -- the car the attributes are on; a respawned car gets them again
	lineAt: number, -- os.clock() of the last line
	pose: string,
	poseUntil: number,
	saidHurry: boolean,
	saidBored: boolean,
}

local riders: { [Player]: Rider } = {}
local lineIds: { [Player]: number } = {} -- keeps counting across rides, so a new line always reads as new
local rng = Random.new()

local function clearCar(model: Model?)
	if model and model.Parent then
		model:SetAttribute("RiderKind", "")
		model:SetAttribute("RiderPose", "rest")
	end
end

-- Puts the rider on the player's current car (first time, or after the car was respawned).
local function seat(rider: Rider)
	local entry = VehicleService.GetEntry(rider.player)
	local model = if entry then entry.model else nil
	rider.vehicle = model
	if not model then
		return
	end
	model:SetAttribute("RiderGolden", rider.npc.golden)
	model:SetAttribute("RiderPose", rider.pose)
	model:SetAttribute("RiderKind", rider.npc.kind)
	model:SetAttribute("RiderCount", rider.npc.riders)
end

local function setPose(rider: Rider, pose: string)
	rider.pose = pose
	rider.poseUntil = os.clock() + Config.Rider.PoseSeconds
	local model = rider.vehicle
	if model then
		model:SetAttribute("RiderPose", pose)
	end
end

local function canSpeak(rider: Rider): boolean
	return os.clock() - rider.lineAt >= Config.Rider.LineCooldown
end

-- A line over the rider's head for everyone; `hideFrom` keeps it off one player's screen (the driver already has the
-- HUD's own "TAKE ME TO" bubble).
local function say(rider: Rider, text: string, hideFrom: Player?)
	local model = rider.vehicle
	if not model then
		return
	end
	rider.lineAt = os.clock()
	local id = (lineIds[rider.player] or 0) + 1
	lineIds[rider.player] = id
	model:SetAttribute("RiderLine", text)
	model:SetAttribute("RiderLineHide", if hideFrom then hideFrom.UserId else 0)
	model:SetAttribute("RiderLineId", id)
end

local function pick(lines: { string }): string
	return lines[rng:NextInteger(1, #lines)]
end

-- A per-kind line list (Config.Rider.Lines.Stunt.ThrillSeeker), falling back to the Regular list.
local function kindLines(category: string, kind: string): { string }
	local byKind = Config.Rider.Lines[category]
	return (byKind[kind] or byKind.Regular) :: { string }
end

local function onBoarded(player: Player, npc: PassengerService.Npc)
	local rider: Rider = {
		player = player,
		npc = npc,
		vehicle = nil,
		lineAt = 0,
		pose = "rest",
		poseUntil = 0,
		saidHurry = false,
		saidBored = false,
	}
	riders[player] = rider
	seat(rider)
	-- Rivals hear where they're headed (the fare starts right after boarding); a Golden passenger brags after that.
	task.defer(function()
		local fare = FareService.GetFare(player)
		local point = if fare then MapService.GetDropoff(fare.destinationIndex) else nil
		if riders[player] == rider and point and point.name ~= "" then
			say(rider, "TAKE ME TO " .. point.name .. "!", player)
		end
	end)
	if npc.golden then
		task.delay(Config.Hud.ShoutSeconds, function()
			if riders[player] == rider then
				say(rider, pick(Config.Rider.Lines.Golden))
			end
		end)
	end
end

local function onUnloaded(player: Player)
	local rider = riders[player]
	riders[player] = nil
	if rider then
		clearCar(rider.vehicle)
	end
end

local function onStunt(player: Player)
	local rider = riders[player]
	if not rider then
		return
	end
	setPose(rider, if rider.npc.kind == "Nervous" then "panic" else "cheer")
	if canSpeak(rider) and rng:NextNumber() < Config.Rider.StuntLineChance then
		say(rider, pick(kindLines("Stunt", rider.npc.kind)))
	end
end

local function onDamaged(player: Player, _amount: number, source: string)
	local rider = riders[player]
	if not rider or source == "self" then
		return
	end
	setPose(rider, "panic")
	-- A crash always gets a yelp; item hits share the line cooldown.
	if source == "crash" or source == "pedestrian" or source == "ram" or source == "debug" then
		say(rider, pick(kindLines("Crash", rider.npc.kind)))
	elseif canSpeak(rider) then
		say(rider, pick(kindLines("Hit", rider.npc.kind)))
	end
end

local function step()
	local now = workspace:GetServerTimeNow()
	local clock = os.clock()
	local cfg = Config.Rider
	for player, rider in riders do
		local entry = VehicleService.GetEntry(player)
		if entry and entry.model ~= rider.vehicle then
			seat(rider) -- the car was respawned: the passenger climbs into the new one
		end
		local vehicle = rider.vehicle
		if vehicle and vehicle:GetAttribute("RiderCount") ~= rider.npc.riders then
			vehicle:SetAttribute("RiderCount", rider.npc.riders) -- a carpool stop let one out
		end
		if rider.pose ~= "rest" and clock >= rider.poseUntil then
			setPose(rider, "rest")
		end
		local fare = FareService.GetFare(player)
		if not fare then
			continue
		end
		local left = fare.deadline - now
		if not rider.saidHurry and left > 0 and left <= cfg.HurryAt then
			rider.saidHurry = true
			say(rider, pick(cfg.Lines.Hurry))
		elseif rider.npc.kind == "ThrillSeeker" and not rider.saidBored and fare.stuntTips <= 0 then
			local elapsed = (now - fare.startedAt) / math.max(0.01, fare.deadline - fare.startedAt)
			if elapsed >= cfg.BoredAt and canSpeak(rider) then
				rider.saidBored = true
				say(rider, pick(cfg.Lines.Bored))
			end
		end
	end
end

function RiderService.Init()
	PassengerService.OnBoarded:Connect(onBoarded)
	PassengerService.OnUnloaded:Connect(onUnloaded)
	PassengerService.OnDamaged:Connect(onDamaged)
	ComboService.OnStunt:Connect(onStunt)
	game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
		lineIds[player] = nil
	end)
end

function RiderService.Start()
	RunService.Heartbeat:Connect(step)
end

return RiderService
