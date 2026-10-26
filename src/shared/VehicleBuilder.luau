--!strict
-- Parts-built vehicle models. The chassis is the only part with mass; everything else is welded, massless and non-colliding.
-- Contract every vehicle model must satisfy (Studio-made ones too):
--   PrimaryPart "Chassis" (the collider), attachments WheelFL/WheelFR/WheelRL/WheelRR, DropPoint, Muzzle,
--   wheel parts named Wheel* each with a Weld named "WheelWeld" (Part0 = Chassis), a "Silhouette" part,
--   attributes VehicleId and WheelType.
-- Models are built at the origin facing -Z; the caller PivotTo()s them into place.

local Config = require(script.Parent.Config)

local VehicleBuilder = {}

local function makePart(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Weld b to a so that b keeps its current offset from a.
local function weld(a: BasePart, b: BasePart, name: string?): Weld
	local w = Instance.new("Weld")
	w.Name = name or "Weld"
	w.Part0 = a
	w.Part1 = b
	w.C0 = a.CFrame:ToObjectSpace(b.CFrame)
	w.Parent = b
	return w
end

local function attachment(name: string, position: Vector3, parent: BasePart): Attachment
	local att = Instance.new("Attachment")
	att.Name = name
	att.Position = position
	att.Parent = parent
	return att
end

function VehicleBuilder.Build(vehicleId: string): Model
	local stats = Config.Vehicles.Stats[vehicleId] or Config.Vehicles.Stats[Config.Vehicles.Default]
	local chassisCfg = Config.Chassis
	local bodyColor = stats.Color
	local glass = Color3.fromRGB(170, 215, 240)
	local dark = Color3.fromRGB(35, 35, 40)

	local model = Instance.new("Model")
	model.Name = vehicleId
	model:SetAttribute("VehicleId", vehicleId)
	model:SetAttribute("WheelType", stats.WheelType)

	-- Collider / mass carrier. 6 wide, 1.6 tall, 11 long. Front is -Z.
	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(6, 1.6, 11)
	chassis.CFrame = CFrame.new()
	chassis.Color = bodyColor
	chassis.Material = Enum.Material.SmoothPlastic
	chassis.TopSurface = Enum.SurfaceType.Smooth
	chassis.BottomSurface = Enum.SurfaceType.Smooth
	chassis.CanCollide = true
	chassis.Anchored = true -- the server unanchors at GO
	chassis.CustomPhysicalProperties = PhysicalProperties.new(1, 0.3, 0.1, 1, 1)
	chassis.Parent = model
	model.PrimaryPart = chassis

	local cabin = makePart("Cabin", Vector3.new(5, 1.8, 5.5), CFrame.new(0, 1.6, 0.3), bodyColor, model)
	weld(chassis, cabin)

	local windshield = makePart("Windshield", Vector3.new(4.8, 1.3, 0.3), CFrame.new(0, 1.65, -2.6), glass, model)
	windshield.Transparency = 0.35
	windshield.Material = Enum.Material.Glass
	weld(chassis, windshield)

	local rearWindow = makePart("RearWindow", Vector3.new(4.8, 1.3, 0.3), CFrame.new(0, 1.65, 3.2), glass, model)
	rearWindow.Transparency = 0.35
	rearWindow.Material = Enum.Material.Glass
	weld(chassis, rearWindow)

	-- Passenger silhouette: visible through the rear window while loaded (server toggles Transparency).
	local silhouette = makePart("Silhouette", Vector3.new(1.4, 1.3, 0.5), CFrame.new(0, 1.6, 2.6), Color3.fromRGB(10, 10, 12), model)
	silhouette.Transparency = 1
	weld(chassis, silhouette)

	local roofSign = makePart("RoofSign", Vector3.new(2.2, 0.5, 0.9), CFrame.new(0, 2.75, 0.3), Color3.fromRGB(255, 140, 30), model)
	roofSign.Material = Enum.Material.Neon
	weld(chassis, roofSign)

	for _, side in { -1, 1 } do
		local head = makePart("Headlight", Vector3.new(0.9, 0.5, 0.3), CFrame.new(2.1 * side, 0.2, -5.55), Color3.fromRGB(255, 250, 220), model)
		head.Material = Enum.Material.Neon
		weld(chassis, head)
		local tail = makePart("Taillight", Vector3.new(0.9, 0.5, 0.3), CFrame.new(2.1 * side, 0.2, 5.55), Color3.fromRGB(255, 40, 40), model)
		tail.Material = Enum.Material.Neon
		weld(chassis, tail)
	end

	-- Wheels: cylinder axis is X, which is the axle direction.
	local wheelDiameter = chassisCfg.WheelRadius * 2
	local restDrop = chassisCfg.SuspensionRest * 0.6 -- approximate visual rest position before the client takes over
	local wheelSpecs = {
		{ name = "FL", x = -2.6, z = -3.8 },
		{ name = "FR", x = 2.6, z = -3.8 },
		{ name = "RL", x = -2.6, z = 3.8 },
		{ name = "RR", x = 2.6, z = 3.8 },
	}
	for _, spec in wheelSpecs do
		attachment("Wheel" .. spec.name, Vector3.new(spec.x, -0.4, spec.z), chassis)
		local wheel = makePart(
			"Wheel" .. spec.name,
			Vector3.new(1, wheelDiameter, wheelDiameter),
			CFrame.new(spec.x, -0.4 - restDrop, spec.z),
			dark,
			model
		)
		wheel.Shape = Enum.PartType.Cylinder
		weld(chassis, wheel, "WheelWeld")
	end

	attachment("DropPoint", Vector3.new(0, -0.4, 7.5), chassis)
	attachment("Muzzle", Vector3.new(0, 1, -6.5), chassis)

	return model
end

return VehicleBuilder
