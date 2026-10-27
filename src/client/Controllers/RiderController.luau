--!strict
-- Draws the passenger riding in every cab (yours and rivals'), from the attributes RiderService writes on each car:
-- head and shoulders out of the roof, sunroof style, in their kind's shirt (a black suit and a gold crown for the
-- Golden Fare), arms by pose, and their lines in a speech bubble. Local parts only: nothing here touches physics or
-- the server. Every number is Config.Rider.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local State = require(script.Parent.Parent.State)

local RiderController = {}

type Figure = {
	model: Model?, -- the drawn rider (nil when the car is empty)
	kind: string,
	golden: boolean,
	torsoC0: CFrame,
	arms: { Weld },
	pose: string,
	gui: BillboardGui?,
	label: TextLabel?,
	lineId: number, -- last RiderLineId shown (or seen when the car first appeared)
	lineToken: number,
}

local localPlayer = Players.LocalPlayer
local figures: { [Model]: Figure } = {}
local SKIN = Color3.fromRGB(230, 190, 160)
local BUBBLE_TEXT = Color3.fromRGB(20, 20, 24)
local SIDES = { -1, 1 }

local function part(name: string, size: Vector3, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Massless = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function weldTo(chassis: BasePart, p: BasePart, c0: CFrame): Weld
	p.CFrame = chassis.CFrame * c0
	local w = Instance.new("Weld")
	w.Part0 = chassis
	w.Part1 = p
	w.C0 = c0
	w.Parent = p
	return w
end

-- Arm offsets from the chassis for a pose: hanging at the sides, straight up (cheer), or flung out wide (panic).
local function armC0(figure: Figure, side: number, pose: string): CFrame
	local cfg = Config.Rider
	local shoulderX = cfg.TorsoSize.X / 2 + cfg.ArmSize.X / 2
	if pose == "cheer" then
		return figure.torsoC0 * CFrame.new(side * (shoulderX - 0.05), cfg.TorsoSize.Y * 0.5 + cfg.ArmSize.Y * 0.4, 0) * CFrame.Angles(0, 0, -side * 0.25)
	elseif pose == "panic" then
		return figure.torsoC0 * CFrame.new(side * (shoulderX + 0.4), cfg.TorsoSize.Y * 0.4, 0) * CFrame.Angles(0, 0, -side * 1.0)
	end
	return figure.torsoC0 * CFrame.new(side * shoulderX, 0, 0)
end

local function setPose(figure: Figure, pose: string)
	figure.pose = pose
	for i, side in SIDES do
		local arm = figure.arms[i]
		if arm then
			arm.C0 = armC0(figure, side, pose)
		end
	end
end

local function clear(figure: Figure)
	if figure.model then
		figure.model:Destroy()
	end
	figure.model = nil
	figure.arms = {}
	figure.gui = nil
	figure.label = nil
end

local function build(figure: Figure, car: Model, chassis: BasePart, kind: string, golden: boolean)
	clear(figure)
	figure.kind = kind
	figure.golden = golden
	local cfg = Config.Rider
	-- The car's Silhouette marks the seat; the top of the car (measured before the rider is added) sets the height.
	local silhouette = car:FindFirstChild("Silhouette")
	local seat = if silhouette and silhouette:IsA("BasePart") then chassis.CFrame:PointToObjectSpace(silhouette.Position) else Vector3.new(0, 0, chassis.Size.Z * 0.2)
	local boxCf, boxSize = car:GetBoundingBox()
	local top = chassis.CFrame:PointToObjectSpace(boxCf.Position).Y + boxSize.Y / 2
	figure.torsoC0 = CFrame.new(seat.X, top - cfg.Sink, seat.Z)

	local kindDef = Config.PassengerTypes.Kinds[kind] or Config.PassengerTypes.Kinds.Regular
	local shirt = if golden then Config.Golden.RiderSuit else kindDef.Shirt
	local model = Instance.new("Model")
	model.Name = "Rider"
	weldTo(chassis, part("RiderTorso", cfg.TorsoSize, shirt, model), figure.torsoC0)
	local head = part("RiderHead", Vector3.one * cfg.HeadSize, SKIN, model)
	head.Shape = Enum.PartType.Ball
	local headC0 = figure.torsoC0 * CFrame.new(0, cfg.TorsoSize.Y / 2 + cfg.HeadSize / 2 - 0.05, 0)
	weldTo(chassis, head, headC0)
	if golden then
		local crown = part("RiderCrown", Vector3.new(cfg.HeadSize * 0.45, cfg.HeadSize * 0.75, cfg.HeadSize * 0.75), Config.Golden.Color, model)
		crown.Shape = Enum.PartType.Cylinder
		crown.Material = Enum.Material.Neon
		weldTo(chassis, crown, headC0 * CFrame.new(0, cfg.HeadSize * 0.5, 0) * CFrame.Angles(0, 0, math.pi / 2))
	end
	for _, side in SIDES do
		table.insert(figure.arms, weldTo(chassis, part("RiderArm", cfg.ArmSize, shirt, model), armC0(figure, side, "rest")))
	end

	-- Speech bubble: white, rounded, black text, over the head
	local gui = Instance.new("BillboardGui")
	gui.Name = "RiderBubble"
	gui.Size = UDim2.fromOffset(170, 30)
	gui.StudsOffset = Vector3.new(0, cfg.HeadSize / 2 + 2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = cfg.BubbleDistance
	gui.LightInfluence = 0
	gui.Enabled = false
	gui.Parent = head
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.new(1, 1, 1)
	back.BackgroundTransparency = 0.15
	back.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = back
	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(10, 4)
	label.Size = UDim2.new(1, -20, 1, -8)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = BUBBLE_TEXT
	label.Text = ""
	label.Parent = back
	figure.gui = gui
	figure.label = label

	model.Parent = car
	figure.model = model
	setPose(figure, "rest")
end

local function showLine(figure: Figure, text: string)
	local gui, label = figure.gui, figure.label
	if not gui or not label then
		return
	end
	figure.lineToken += 1
	local token = figure.lineToken
	label.Text = text
	gui.Enabled = true
	task.delay(Config.Rider.LineSeconds, function()
		if figure.lineToken == token and gui.Parent then
			gui.Enabled = false
		end
	end)
end

local function update(car: Model)
	local figure = figures[car]
	local lineIdAttr = car:GetAttribute("RiderLineId")
	local lineId = if typeof(lineIdAttr) == "number" then lineIdAttr else 0
	if not figure then
		local made: Figure = { model = nil, kind = "", golden = false, torsoC0 = CFrame.new(), arms = {}, pose = "rest", gui = nil, label = nil, lineId = lineId, lineToken = 0 }
		figures[car] = made
		figure = made
	end
	local current = figure :: Figure
	local kindAttr = car:GetAttribute("RiderKind")
	local kind = if typeof(kindAttr) == "string" then kindAttr else ""
	local chassis = car.PrimaryPart
	if kind == "" or not chassis then
		if current.model then
			clear(current)
		end
		current.kind = ""
		return
	end
	local golden = car:GetAttribute("RiderGolden") == true
	if not current.model or current.kind ~= kind or current.golden ~= golden then
		build(current, car, chassis, kind, golden)
	end
	local poseAttr = car:GetAttribute("RiderPose")
	local pose = if typeof(poseAttr) == "string" then poseAttr else "rest"
	if pose ~= current.pose then
		setPose(current, pose)
	end
	if lineId ~= current.lineId then
		current.lineId = lineId
		local line = car:GetAttribute("RiderLine")
		if typeof(line) == "string" and car:GetAttribute("RiderLineHide") ~= localPlayer.UserId then
			if car:GetAttribute("OwnerUserId") == localPlayer.UserId then
				State.RiderSaid:Fire(line) -- your own passenger talks in the HUD's bubble: one bubble over your cab, never two
			else
				showLine(current, line)
			end
		end
	end
end

function RiderController.Init() end

function RiderController.Start()
	RunService.Heartbeat:Connect(function()
		local folder = workspace:FindFirstChild("Vehicles")
		local seen: { [Model]: boolean } = {}
		if folder then
			for _, child in folder:GetChildren() do
				if child:IsA("Model") then
					seen[child] = true
					update(child)
				end
			end
		end
		for car, figure in figures do
			if not seen[car] then
				clear(figure)
				figures[car] = nil
			end
		end
	end)
end

return RiderController
