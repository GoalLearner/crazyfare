--!strict
-- On foot (Passenger / Queued) and riding along. HAIL CAB shows while you stand near a curb during a round (CANCEL once
-- you've hailed); the server decides if it counts (WalkerService). Every client seats everyone riding along
-- (RidingWith = the cab owner's UserId) in that cab's passenger seat each frame, so nobody can step out until the ride
-- ends; your own character can't jump or walk meanwhile. Cars pass through people (collision groups), so a car about to
-- hit you plays a cartoon dodge instead. A bail tosses you out (EjectedAt). After a ride arrives, rate the driver:
-- five stars, Config.PlayerFare.RatingDefault if you don't tap in time.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Sidewalk = require(Shared:WaitForChild("Sidewalk"))
local Types = require(Shared:WaitForChild("Types"))
local VecUtil = require(Shared:WaitForChild("VecUtil"))
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI)

local WalkerController = {}

local localPlayer = Players.LocalPlayer
local hailButton: TextButton
local ratePanel: Frame
local rateTitle: TextLabel
local rateThanks: TextLabel
local rateBar: UI.Bar
local starButtons: { TextButton } = {}
local rateDeadline = 0
local rateOpenedAt = 0
local hailRemote: RemoteEvent
local rateRemote: RemoteEvent
local cabs: { [number]: BasePart } = {} -- cab chassis by owner UserId (grid cars only)
local dodgeReadyAt = 0
local savedJump: { power: number, height: number, walk: number }? = nil
local rng = Random.new()

local function onFoot(): boolean
	return (State.sessionState == "Passenger" or State.sessionState == "Queued") and State.rideDriverId == 0
end

local function myRoot(): (BasePart?, Humanoid?)
	local character = localPlayer.Character
	if not character then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return if root and root:IsA("BasePart") then root else nil, humanoid
end

local function blockout(): typeof(Config.Map.City.Blockout)
	local round = State.round
	return Sidewalk.Blockout(if round then round.map else nil)
end

local function indexCab(inst: Instance)
	if inst:IsA("Model") and inst:GetAttribute("Depot") ~= true then
		local owner = inst:GetAttribute("OwnerUserId")
		local chassis = inst.PrimaryPart
		if typeof(owner) == "number" and chassis then
			cabs[owner] = chassis
		end
	end
end

-- Everyone riding along sits in their cab. Your own character also can't walk or jump while it does.
local function seatRiders()
	for _, player in Players:GetPlayers() do
		local id = player:GetAttribute("RidingWith")
		local character = player.Character
		local chassis = if typeof(id) == "number" then cabs[id] else nil
		if not character or not chassis or not chassis:IsDescendantOf(workspace) then
			continue
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") then
			root.CFrame = chassis.CFrame * CFrame.new(Config.PlayerFare.SeatOffset)
			root.AssemblyLinearVelocity = chassis.AssemblyLinearVelocity
			root.AssemblyAngularVelocity = Vector3.zero
		end
		if player == localPlayer and humanoid then
			humanoid.Sit = true
		end
	end
end

-- Riding: no walking or jumping out. Back on foot: as you were.
local function onRideChanged()
	local _, humanoid = myRoot()
	if not humanoid then
		return
	end
	if State.rideDriverId ~= 0 and not savedJump then
		savedJump = { power = humanoid.JumpPower, height = humanoid.JumpHeight, walk = humanoid.WalkSpeed }
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid.WalkSpeed = 0
	elseif State.rideDriverId == 0 then
		local saved = savedJump
		if saved then
			savedJump = nil
			humanoid.JumpPower = saved.power
			humanoid.JumpHeight = saved.height
			humanoid.WalkSpeed = saved.walk
		end
		humanoid.Sit = false
	end
end

local function say(text: string)
	local character = localPlayer.Character
	local head = if character then character:FindFirstChild("Head") else nil
	if not head then
		return
	end
	local gui = UI.New("BillboardGui", { Size = UDim2.fromOffset(160, 34), StudsOffset = Vector3.new(0, 3, 0), AlwaysOnTop = true }, head) :: BillboardGui
	UI.Label({ Size = UDim2.fromScale(1, 1), Text = text, TextColor3 = UI.Warn }, gui)
	task.delay(Config.Walkers.DodgeCooldown, function()
		gui:Destroy()
	end)
end

-- A car about to run you over (they pass through people): dive out of its way.
local function dodge(root: BasePart, humanoid: Humanoid)
	local cfg = Config.Walkers
	if os.clock() < dodgeReadyAt then
		return
	end
	local me = VecUtil.Flat(root.Position)
	local function check(part: BasePart)
		local vel = VecUtil.Flat(part.AssemblyLinearVelocity)
		local speed = vel.Magnitude
		if speed < cfg.DodgeMinSpeed then
			return false
		end
		-- only a car whose path covers you, close ahead of it (one passing in its lane never makes you jump)
		local offset = me - VecUtil.Flat(part.Position)
		local dir = vel / speed
		local side = Vector3.new(-dir.Z, 0, dir.X)
		local along = offset:Dot(dir)
		local across = offset:Dot(side)
		local halfLength = math.max(part.Size.X, part.Size.Z) / 2
		local halfWidth = math.min(part.Size.X, part.Size.Z) / 2
		if along < 0 or along > halfLength + cfg.DodgeAhead or math.abs(across) > halfWidth + cfg.DodgeDistance then
			return false
		end
		local away = if across >= 0 then side else -side
		root.AssemblyLinearVelocity = away * cfg.DodgeShove + Vector3.new(0, cfg.DodgeJump, 0)
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		dodgeReadyAt = os.clock() + cfg.DodgeCooldown
		say(cfg.DodgeLines[rng:NextInteger(1, #cfg.DodgeLines)])
		return true
	end
	for _, chassis in cabs do
		if chassis:IsDescendantOf(workspace) and check(chassis) then
			return
		end
	end
	for _, inst in CollectionService:GetTagged(Config.Tags.Traffic) do
		if inst:IsA("BasePart") and check(inst) then
			return
		end
	end
end

local function refreshHail(root: BasePart?)
	local hailing = localPlayer:GetAttribute("Hailing") == true
	local show = false
	if onFoot() and root and State.GetPhase() == "Playing" then
		local curb = Sidewalk.CurbDistance(blockout(), root.Position)
		show = hailing or (curb ~= nil and curb <= Config.PlayerFare.HailCurbDistance)
	end
	hailButton.Visible = show and rateDeadline == 0 -- the rating prompt sits where the button does
	hailButton.Text = if hailing then Config.PlayerFare.CancelButton else Config.PlayerFare.HailButton
	hailButton.BackgroundColor3 = if hailing then Color3.fromRGB(110, 70, 30) else Config.PlayerFare.Color
	hailButton.TextColor3 = if hailing then UI.White else UI.Black
end

local function closeRating()
	ratePanel.Visible = false
	rateDeadline = 0
end

local function styleStars(lit: number)
	for i, star in starButtons do
		star.TextColor3 = if i <= lit then Config.PlayerFare.Color else UI.Muted
	end
end

local function openRating(payload: Types.FareEventPayload)
	rateTitle.Text = string.format("%s  ·  %s", Config.PlayerFare.RatePrompt, string.upper(payload.line or ""))
	rateThanks.Text = string.format(Config.PlayerFare.Thanks, payload.payout or 0)
	rateDeadline = payload.deadline or (workspace:GetServerTimeNow() + Config.PlayerFare.RatingSeconds)
	rateOpenedAt = workspace:GetServerTimeNow()
	styleStars(Config.PlayerFare.RatingDefault)
	ratePanel.Visible = true
end

local function build()
	local screen = UI.Screen("CrazyFareWalker", 12)
	hailButton = UI.New("TextButton", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.fromOffset(200, 60),
		BackgroundColor3 = Config.PlayerFare.Color,
		BorderSizePixel = 0,
		Font = UI.Font,
		TextSize = 24,
		TextColor3 = UI.Black,
		Text = Config.PlayerFare.HailButton,
		Visible = false,
	}, screen) :: TextButton
	UI.Corner(14, hailButton)
	hailButton.Activated:Connect(function()
		hailRemote:FireServer(localPlayer:GetAttribute("Hailing") ~= true)
	end)

	ratePanel = UI.Frame({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -110), Size = UDim2.fromOffset(340, 118), BackgroundTransparency = 0.08, Visible = false }, screen)
	UI.Corner(14, ratePanel)
	rateTitle = UI.Label({ Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 20), Text = "" }, ratePanel)
	local row = UI.Frame({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 32), Size = UDim2.fromOffset(5 * 52, 48), BackgroundTransparency = 1 }, ratePanel)
	UI.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Center }, row)
	for i = 1, 5 do
		local star = UI.New("TextButton", {
			Size = UDim2.fromOffset(48, 48),
			BackgroundTransparency = 1,
			Font = UI.Font,
			TextSize = 40,
			TextColor3 = UI.Muted,
			Text = "★",
			LayoutOrder = i,
		}, row) :: TextButton
		star.Activated:Connect(function()
			if rateDeadline > 0 then
				styleStars(i)
				rateRemote:FireServer(i)
				closeRating()
			end
		end)
		table.insert(starButtons, star)
	end
	rateThanks = UI.Label({ Position = UDim2.fromOffset(12, 84), Size = UDim2.new(1, -24, 0, 14), Text = "", TextColor3 = UI.Accent, Font = UI.FontMedium }, ratePanel)
	rateBar = UI.Bar({ Position = UDim2.new(0, 12, 1, -10), Size = UDim2.new(1, -24, 0, 4) }, Config.PlayerFare.Color, ratePanel)
end

function WalkerController.Init()
	hailRemote = Remotes.Get("HailCab")
	rateRemote = Remotes.Get("RateRide")
	build()
	for _, inst in CollectionService:GetTagged(Config.Tags.Vehicle) do
		indexCab(inst)
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.Vehicle):Connect(function(inst: Instance)
		indexCab(inst)
		inst:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
			indexCab(inst)
		end)
	end)
	State.RideChanged:Connect(onRideChanged)
	State.FareEvent:Connect(function(payload: Types.FareEventPayload)
		if payload.kind == "Rate" then
			openRating(payload)
		end
	end)
	-- Tossed out of a cab: a cartoon tumble (your client owns your character, so it plays it)
	localPlayer:GetAttributeChangedSignal("EjectedAt"):Connect(function()
		local root, humanoid = myRoot()
		if root and humanoid then
			local cfg = Config.PlayerFare
			root.AssemblyLinearVelocity = Vector3.new(0, cfg.EjectHop, 0) + VecUtil.FlatUnit(root.CFrame.RightVector) * cfg.EjectShove
			root.AssemblyAngularVelocity = Vector3.new(0, cfg.EjectSpin, 0)
			humanoid:ChangeState(Enum.HumanoidStateType.FallingDown)
		end
	end)
	localPlayer.CharacterAdded:Connect(function()
		savedJump = nil
	end)
end

function WalkerController.Start()
	-- seat riders before physics steps (your own) and before the frame draws (everyone's)
	RunService.Stepped:Connect(seatRiders)
	RunService.RenderStepped:Connect(function()
		seatRiders()
		local root, humanoid = myRoot()
		refreshHail(root)
		if onFoot() and root and humanoid and humanoid.Health > 0 then
			dodge(root, humanoid)
		end
		if rateDeadline > 0 then
			local now = workspace:GetServerTimeNow()
			if now >= rateDeadline then
				closeRating()
			else
				UI.SetBar(rateBar, (rateDeadline - now) / math.max(0.1, rateDeadline - rateOpenedAt))
			end
		end
	end)
end

return WalkerController
