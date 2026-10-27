--!strict
-- Fruit stands (Config.Chaos.FruitStands): when the server marks one smashed (Active false) its parts vanish, fruit
-- flies the way the smasher was going and bounces down the road with a splat; it reappears when it's Active again.
-- Everyone sees it.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local FruitStandController = {}

local rng = Random.new()
local down: { [Model]: boolean } = {}

local function setVisible(model: Model, visible: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = if visible then 0 else 1
		end
	end
end

local function splat(model: Model)
	local cfg = Config.Chaos.FruitStands
	local counter = model.PrimaryPart
	if not counter then
		return
	end
	local pivot = counter.CFrame
	local dirAttr = model:GetAttribute("SmashDir")
	local dir = if typeof(dirAttr) == "Vector3" and dirAttr.Magnitude > 0 then dirAttr.Unit else pivot.LookVector
	local side = dir:Cross(Vector3.yAxis)
	local half = counter.Size / 2
	for _ = 1, cfg.Pieces do
		local fruit = Instance.new("Part")
		fruit.Name = "Fruit"
		fruit.Shape = Enum.PartType.Ball
		fruit.Size = Vector3.one * rng:NextNumber(cfg.PieceSizeMin, cfg.PieceSizeMax)
		fruit.Color = cfg.FruitColors[rng:NextInteger(1, #cfg.FruitColors)]
		fruit.Material = Enum.Material.SmoothPlastic
		fruit.CanQuery = false
		fruit.CanTouch = false
		fruit.CastShadow = false
		-- nearly weightless: it bounces off the road and your car without pushing anything
		fruit.CustomPhysicalProperties = PhysicalProperties.new(0.05, 0.3, 0.5)
		fruit.CFrame = pivot * CFrame.new(rng:NextNumber(-half.X, half.X), half.Y + fruit.Size.Y, rng:NextNumber(-half.Z, half.Z))
		fruit.AssemblyLinearVelocity = dir * cfg.FlySpeed * rng:NextNumber(0.5, 1.1)
			+ side * cfg.FlySpeed * rng:NextNumber(-0.5, 0.5)
			+ Vector3.yAxis * cfg.FlyUp * rng:NextNumber(0.6, 1.2)
		fruit.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * cfg.Spin
		fruit.Parent = workspace
		Debris:AddItem(fruit, cfg.DebrisSeconds)
	end
	local id = Config.Sounds.Ids[cfg.Sound]
	if id and id ~= 0 then
		local sound = Instance.new("Sound")
		sound.SoundId = "rbxassetid://" .. id
		sound.Volume = Config.Sounds.Volume
		sound.PlaybackSpeed = cfg.SoundPitch
		sound.RollOffMaxDistance = cfg.SoundRange
		sound.Parent = counter
		sound:Play()
		Debris:AddItem(sound, cfg.DebrisSeconds)
	end
end

local function refresh(model: Model, animate: boolean)
	local isDown = model:GetAttribute("Active") == false
	if isDown == (down[model] == true) then
		return
	end
	down[model] = isDown
	setVisible(model, not isDown)
	if isDown and animate then
		splat(model)
	end
end

local function watch(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local model = inst :: Model
	refresh(model, false) -- already down when we got here: just hide it
	model:GetAttributeChangedSignal("Active"):Connect(function()
		refresh(model, true)
	end)
end

function FruitStandController.Init() end

function FruitStandController.Start()
	for _, inst in CollectionService:GetTagged(Config.Tags.FruitStand) do
		watch(inst)
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.FruitStand):Connect(watch)
	CollectionService:GetInstanceRemovedSignal(Config.Tags.FruitStand):Connect(function(inst: Instance)
		if inst:IsA("Model") then
			down[inst] = nil
		end
	end)
end

return FruitStandController
