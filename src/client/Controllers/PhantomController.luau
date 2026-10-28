--!strict
-- The Phantom's built-in shield, drawn on every screen: a see-through bubble around each car whose stats have
-- BuiltInShield while its driver's shield is charged (the server's ready time is the player attribute
-- Config.Vehicles.Phantom.ShieldAttribute; 0 or past = charged). Client-only parts, never welded to the car.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local PhantomController = {}

local PHANTOM = Config.Vehicles.Phantom
local bubbles: { [Model]: BasePart } = {}

local function makeBubble(model: Model): BasePart
	local size = model:GetExtentsSize()
	local diameter = math.max(size.X, size.Y, size.Z) + PHANTOM.BubblePadding * 2
	local bubble = Instance.new("Part")
	bubble.Name = "PhantomShield"
	bubble.Shape = Enum.PartType.Ball
	bubble.Size = Vector3.new(diameter, diameter, diameter)
	bubble.Material = Enum.Material.ForceField
	bubble.Color = PHANTOM.BubbleColor
	bubble.Transparency = PHANTOM.BubbleTransparency
	bubble.Anchored = true
	bubble.CanCollide = false
	bubble.CanQuery = false
	bubble.CanTouch = false
	bubble.CastShadow = false
	bubble.Parent = workspace.CurrentCamera
	return bubble
end

local function charged(model: Model): boolean
	local owner = model:GetAttribute("OwnerUserId")
	local player = if typeof(owner) == "number" then Players:GetPlayerByUserId(owner) else nil
	if not player then
		return false
	end
	local readyAt = player:GetAttribute(PHANTOM.ShieldAttribute)
	return typeof(readyAt) ~= "number" or readyAt <= workspace:GetServerTimeNow()
end

local function update()
	for _, inst in CollectionService:GetTagged(Config.Tags.Vehicle) do
		if not inst:IsA("Model") or not inst:IsDescendantOf(workspace) then
			continue
		end
		local vehicleId = inst:GetAttribute("VehicleId")
		local stats = if typeof(vehicleId) == "string" then Config.Vehicles.Stats[vehicleId] else nil
		local chassis = inst.PrimaryPart
		local existing = bubbles[inst]
		if not stats or not stats.BuiltInShield or not chassis then
			continue
		end
		local bubble = existing or makeBubble(inst)
		bubbles[inst] = bubble
		local on = charged(inst)
		bubble.Transparency = if on then PHANTOM.BubbleTransparency else 1
		if on then
			bubble.CFrame = chassis.CFrame
		end
	end
	-- cars that left (or changed into something else)
	for model, bubble in bubbles do
		local vehicleId = model:GetAttribute("VehicleId")
		local stats = if typeof(vehicleId) == "string" then Config.Vehicles.Stats[vehicleId] else nil
		if not model:IsDescendantOf(workspace) or not stats or not stats.BuiltInShield then
			bubble:Destroy()
			bubbles[model] = nil
		end
	end
end

function PhantomController.Init() end

function PhantomController.Start()
	RunService.RenderStepped:Connect(update)
end

return PhantomController
