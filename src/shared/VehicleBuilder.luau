--!strict
-- Parts-built vehicle models. The chassis is the only part with mass; everything else is welded, massless and non-colliding.
-- Contract every vehicle model must satisfy (Studio-made ones too):
--   PrimaryPart "Chassis" (the collider), attachments WheelFL/WheelFR/WheelRL/WheelRR, DropPoint, Muzzle,
--   wheel parts named Wheel* each with a Weld named "WheelWeld" (Part0 = Chassis), a "Silhouette" part,
--   attributes VehicleId and WheelType. Parts tagged with attribute Paintable = true take the player's paint.
-- Models are built at the origin facing -Z; the caller PivotTo()s them into place.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)

local VehicleBuilder = {}

local GLASS = Color3.fromRGB(170, 215, 240)
local DARK = Color3.fromRGB(35, 35, 40)

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

local function paintable(part: Part): Part
	part:SetAttribute("Paintable", true)
	return part
end

local function glassPart(name: string, size: Vector3, cf: CFrame, chassis: Part, model: Model): Part
	local p = makePart(name, size, cf, GLASS, model)
	p.Transparency = 0.35
	p.Material = Enum.Material.Glass
	weld(chassis, p)
	return p
end

local function neon(name: string, size: Vector3, cf: CFrame, color: Color3, chassis: Part, model: Model): Part
	local p = makePart(name, size, cf, color, model)
	p.Material = Enum.Material.Neon
	weld(chassis, p)
	return p
end

local function makeChassis(model: Model, size: Vector3, color: Color3): Part
	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = size
	chassis.CFrame = CFrame.new()
	chassis.Color = color
	chassis.Material = Enum.Material.SmoothPlastic
	chassis.TopSurface = Enum.SurfaceType.Smooth
	chassis.BottomSurface = Enum.SurfaceType.Smooth
	chassis.CanCollide = true
	chassis.Anchored = true -- the server unanchors at GO
	chassis.CustomPhysicalProperties = PhysicalProperties.new(1, 0.3, 0.1, 1, 1)
	chassis:SetAttribute("Paintable", true)
	chassis.Parent = model
	model.PrimaryPart = chassis
	return chassis
end

-- Wheel attachments at the corners plus the visual wheels (or legs) welded on.
local function makeWheels(model: Model, chassis: Part, halfWidth: number, halfLength: number, legs: boolean, legColor: Color3)
	local diameter = Config.Chassis.WheelRadius * 2
	local restDrop = Config.Chassis.SuspensionRest * 0.6
	local specs = {
		{ name = "FL", x = -halfWidth, z = -halfLength },
		{ name = "FR", x = halfWidth, z = -halfLength },
		{ name = "RL", x = -halfWidth, z = halfLength },
		{ name = "RR", x = halfWidth, z = halfLength },
	}
	for _, spec in specs do
		attachment("Wheel" .. spec.name, Vector3.new(spec.x, -0.4, spec.z), chassis)
		local visual: Part
		if legs then
			visual = makePart("Wheel" .. spec.name, Vector3.new(0.8, diameter, 0.8), CFrame.new(spec.x, -0.4 - restDrop, spec.z), legColor, model)
		else
			visual = makePart("Wheel" .. spec.name, Vector3.new(1, diameter, diameter), CFrame.new(spec.x, -0.4 - restDrop, spec.z), DARK, model)
			visual.Shape = Enum.PartType.Cylinder
		end
		weld(chassis, visual, "WheelWeld")
	end
end

local function finish(model: Model, chassis: Part, front: number, back: number)
	attachment("DropPoint", Vector3.new(0, -0.4, back + 2), chassis)
	attachment("Muzzle", Vector3.new(0, 1, front - 1), chassis)
	local silhouette = makePart("Silhouette", Vector3.new(1.4, 1.3, 0.5), CFrame.new(0, 1.6, 2.6), Color3.fromRGB(10, 10, 12), model)
	silhouette.Transparency = 1
	weld(chassis, silhouette)
end

local function lights(model: Model, chassis: Part, x: number, front: number, back: number)
	for _, side in { -1, 1 } do
		neon("Headlight", Vector3.new(0.9, 0.5, 0.3), CFrame.new(x * side, 0.2, front), Color3.fromRGB(255, 250, 220), chassis, model)
		neon("Taillight", Vector3.new(0.9, 0.5, 0.3), CFrame.new(x * side, 0.2, back), Color3.fromRGB(255, 40, 40), chassis, model)
	end
end

-- Classic sedan silhouette shared by YellowCab and NightCab.
local function buildCab(model: Model, color: Color3, signColor: Color3)
	local chassis = makeChassis(model, Vector3.new(6, 1.6, 11), color)
	local cabin = paintable(makePart("Cabin", Vector3.new(5, 1.8, 5.5), CFrame.new(0, 1.6, 0.3), color, model))
	weld(chassis, cabin)
	glassPart("Windshield", Vector3.new(4.8, 1.3, 0.3), CFrame.new(0, 1.65, -2.6), chassis, model)
	glassPart("RearWindow", Vector3.new(4.8, 1.3, 0.3), CFrame.new(0, 1.65, 3.2), chassis, model)
	neon("RoofSign", Vector3.new(2.2, 0.5, 0.9), CFrame.new(0, 2.75, 0.3), signColor, chassis, model)
	lights(model, chassis, 2.1, -5.55, 5.55)
	makeWheels(model, chassis, 2.6, 3.8, false, DARK)
	finish(model, chassis, -5.5, 5.5)
end

local function buildGoKart(model: Model, color: Color3)
	local chassis = makeChassis(model, Vector3.new(5, 1.2, 8), color)
	local seat = makePart("Seat", Vector3.new(2.2, 1.6, 1.6), CFrame.new(0, 1.2, 1.2), DARK, model)
	weld(chassis, seat)
	local seatBack = makePart("SeatBack", Vector3.new(2.2, 1.8, 0.5), CFrame.new(0, 1.8, 2.1), DARK, model)
	weld(chassis, seatBack)
	local wheelCol = paintable(makePart("Nose", Vector3.new(3, 0.8, 1.6), CFrame.new(0, 0.9, -3.2), color, model))
	weld(chassis, wheelCol)
	local wing = paintable(makePart("Wing", Vector3.new(5.4, 0.3, 1.4), CFrame.new(0, 2.4, 3.4), color, model))
	weld(chassis, wing)
	lights(model, chassis, 1.6, -4.05, 4.05)
	makeWheels(model, chassis, 2.4, 2.8, false, DARK)
	finish(model, chassis, -4, 4)
end

local function buildShoppingCart(model: Model, color: Color3)
	local chassis = makeChassis(model, Vector3.new(5, 1.6, 8), color)
	local rim = Color3.fromRGB(200, 205, 215)
	-- Open basket: four thin walls.
	for _, spec in {
		{ name = "WallL", size = Vector3.new(0.25, 2.6, 7.6), cf = CFrame.new(-2.4, 2.1, 0) },
		{ name = "WallR", size = Vector3.new(0.25, 2.6, 7.6), cf = CFrame.new(2.4, 2.1, 0) },
		{ name = "WallF", size = Vector3.new(5, 2.6, 0.25), cf = CFrame.new(0, 2.1, -3.8) },
		{ name = "WallB", size = Vector3.new(5, 2.6, 0.25), cf = CFrame.new(0, 2.1, 3.8) },
	} do
		local wall = paintable(makePart(spec.name, spec.size, spec.cf, color, model))
		wall.Transparency = 0.25
		weld(chassis, wall)
	end
	local handle = makePart("Handle", Vector3.new(5.4, 0.4, 0.4), CFrame.new(0, 3.9, 4.6), rim, model)
	weld(chassis, handle)
	for _, side in { -1, 1 } do
		local post = makePart("Post", Vector3.new(0.3, 2.4, 0.3), CFrame.new(2.5 * side, 2.8, 4.4) * CFrame.Angles(math.rad(-20), 0, 0), rim, model)
		weld(chassis, post)
	end
	lights(model, chassis, 1.6, -4.05, 4.05)
	makeWheels(model, chassis, 2.4, 2.8, false, DARK)
	finish(model, chassis, -4, 4)
end

local function buildHorse(model: Model, color: Color3)
	local chassis = makeChassis(model, Vector3.new(3.6, 1.6, 8), color)
	local mane = Color3.fromRGB(60, 40, 25)
	local neck = paintable(makePart("Neck", Vector3.new(1.6, 3, 1.6), CFrame.new(0, 1.8, -3.4) * CFrame.Angles(math.rad(25), 0, 0), color, model))
	weld(chassis, neck)
	local head = paintable(makePart("Head", Vector3.new(1.5, 1.4, 2.8), CFrame.new(0, 3.3, -4.9), color, model))
	weld(chassis, head)
	for _, side in { -1, 1 } do
		local ear = makePart("Ear", Vector3.new(0.4, 0.8, 0.4), CFrame.new(0.5 * side, 4.2, -4.2), mane, model)
		weld(chassis, ear)
	end
	local maneStrip = makePart("Mane", Vector3.new(0.5, 3.2, 0.6), CFrame.new(0, 2.1, -2.8) * CFrame.Angles(math.rad(25), 0, 0), mane, model)
	weld(chassis, maneStrip)
	local tail = makePart("Tail", Vector3.new(0.5, 2.4, 0.5), CFrame.new(0, 0.4, 4.3) * CFrame.Angles(math.rad(-30), 0, 0), mane, model)
	weld(chassis, tail)
	local saddle = makePart("Saddle", Vector3.new(2.4, 0.6, 2.4), CFrame.new(0, 1.1, 0.6), DARK, model)
	weld(chassis, saddle)
	makeWheels(model, chassis, 1.4, 2.8, true, color)
	finish(model, chassis, -4, 4)
end

local function buildIceCreamTruck(model: Model, color: Color3)
	local chassis = makeChassis(model, Vector3.new(6, 1.6, 11), color)
	local box = paintable(makePart("Box", Vector3.new(6, 4, 7.5), CFrame.new(0, 2.7, 1.5), color, model))
	weld(chassis, box)
	local cabin = paintable(makePart("Cabin", Vector3.new(5.4, 2.2, 3), CFrame.new(0, 1.8, -3.9), color, model))
	weld(chassis, cabin)
	glassPart("Windshield", Vector3.new(5, 1.4, 0.3), CFrame.new(0, 2, -5.3), chassis, model)
	local stripe = makePart("Stripe", Vector3.new(6.2, 0.6, 7.7), CFrame.new(0, 2.7, 1.5), Color3.fromRGB(240, 120, 170), model)
	weld(chassis, stripe)
	local cone = makePart("Cone", Vector3.new(1.4, 2.2, 1.4), CFrame.new(0, 5.8, 1.5), Color3.fromRGB(220, 170, 110), model)
	weld(chassis, cone)
	local scoop = makePart("Scoop", Vector3.new(2, 2, 2), CFrame.new(0, 7.3, 1.5), Color3.fromRGB(255, 170, 200), model)
	scoop.Shape = Enum.PartType.Ball
	weld(chassis, scoop)
	lights(model, chassis, 2.1, -5.55, 5.55)
	makeWheels(model, chassis, 2.6, 3.8, false, DARK)
	finish(model, chassis, -5.5, 5.5)
end

-- Rocket Cab (Robux only): a low cab with twin rocket boosters, glowing nozzles and a tail fin.
local function buildRocketCab(model: Model, color: Color3)
	local chassis = makeChassis(model, Vector3.new(6, 1.4, 11.5), color)
	local cabin = paintable(makePart("Cabin", Vector3.new(4.6, 1.5, 4.6), CFrame.new(0, 1.4, 0.6), color, model))
	weld(chassis, cabin)
	glassPart("Windshield", Vector3.new(4.4, 1.1, 0.3), CFrame.new(0, 1.45, -1.8), chassis, model)
	local nose = paintable(makePart("Nose", Vector3.new(5, 0.7, 2.2), CFrame.new(0, 0.95, -4.6), color, model))
	weld(chassis, nose)
	for _, side in { -1, 1 } do
		local booster = makePart("Booster", Vector3.new(3.4, 1.2, 1.2), CFrame.new(1.9 * side, 1.5, 4.4) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(200, 200, 210), model)
		booster.Shape = Enum.PartType.Cylinder
		weld(chassis, booster)
		neon("Nozzle", Vector3.new(0.9, 0.9, 0.4), CFrame.new(1.9 * side, 1.5, 6.15), Color3.fromRGB(255, 150, 40), chassis, model)
	end
	local fin = paintable(makePart("Fin", Vector3.new(0.3, 1.6, 2), CFrame.new(0, 2.6, 3.6), color, model))
	weld(chassis, fin)
	lights(model, chassis, 2.1, -5.8, 5.8)
	makeWheels(model, chassis, 2.6, 3.9, false, DARK)
	finish(model, chassis, -5.75, 5.75)
end

-- Armored Limo (Robux only): long and black, tinted glass all round, a gold trim line.
local function buildArmoredLimo(model: Model, color: Color3)
	local chassis = makeChassis(model, Vector3.new(6, 1.7, 14), color)
	local cabin = paintable(makePart("Cabin", Vector3.new(5.2, 1.9, 9), CFrame.new(0, 1.75, 0.6), color, model))
	weld(chassis, cabin)
	for _, z in { -2.4, 0.6, 3.6 } do
		for _, side in { -1, 1 } do
			local window = glassPart("Window", Vector3.new(0.2, 1.1, 2.4), CFrame.new(2.62 * side, 1.9, z), chassis, model)
			window.Color = Color3.fromRGB(40, 50, 60)
		end
	end
	glassPart("Windshield", Vector3.new(5, 1.3, 0.3), CFrame.new(0, 1.8, -3.95), chassis, model)
	for _, side in { -1, 1 } do
		local trim = makePart("Trim", Vector3.new(0.15, 0.3, 13.6), CFrame.new(3.02 * side, 0.4, 0), Color3.fromRGB(230, 185, 60), model)
		weld(chassis, trim)
	end
	neon("RoofLight", Vector3.new(1.6, 0.35, 0.8), CFrame.new(0, 2.85, -1), Color3.fromRGB(255, 210, 80), chassis, model)
	lights(model, chassis, 2.1, -7.05, 7.05)
	makeWheels(model, chassis, 2.6, 5, false, DARK)
	finish(model, chassis, -7, 7)
end

function VehicleBuilder.Build(vehicleId: string): Model
	local stats = Config.Vehicles.Stats[vehicleId]
	if not stats then
		vehicleId = Config.Vehicles.Default
		stats = Config.Vehicles.Stats[vehicleId]
	end
	local model = Instance.new("Model")
	model.Name = vehicleId
	model:SetAttribute("VehicleId", vehicleId)
	model:SetAttribute("WheelType", stats.WheelType)

	if vehicleId == "GoKart" then
		buildGoKart(model, stats.Color)
	elseif vehicleId == "ShoppingCart" then
		buildShoppingCart(model, stats.Color)
	elseif vehicleId == "Horse" then
		buildHorse(model, stats.Color)
	elseif vehicleId == "IceCreamTruck" then
		buildIceCreamTruck(model, stats.Color)
	elseif vehicleId == "NightCab" then
		buildCab(model, stats.Color, Color3.fromRGB(170, 60, 255))
	elseif vehicleId == "RocketCab" then
		buildRocketCab(model, stats.Color)
	elseif vehicleId == "ArmoredLimo" then
		buildArmoredLimo(model, stats.Color)
	else
		buildCab(model, stats.Color, Color3.fromRGB(255, 140, 30))
	end
	return model
end

-- Recolour every Paintable part (nil restores the vehicle's own colour).
function VehicleBuilder.ApplyPaint(model: Model, color: Color3?)
	local vehicleId = model:GetAttribute("VehicleId")
	local stats = if typeof(vehicleId) == "string" then Config.Vehicles.Stats[vehicleId] else nil
	local target = color or (if stats then stats.Color else nil)
	if not target then
		return
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("Paintable") == true then
			part.Color = target
			-- Imported meshes carry their texture on a SurfaceAppearance; its Color is what tints them.
			local appearance = part:FindFirstChildOfClass("SurfaceAppearance")
			if appearance then
				appearance.Color = target
			end
		end
	end
end

-- Ambient traffic (TrafficService): a sedan, a van or a bus (Config.Traffic.Kinds). "Body" is the only collider and
-- carries the mass; built at the origin facing -Z like the rest, so the caller pivots it into place and sets its
-- collision group.
local function trafficWheels(model: Model, body: Part, size: Vector3, diameter: number, inset: number)
	local halfX, halfY, halfZ = size.X / 2, size.Y / 2, size.Z / 2
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			local wheel = makePart("Wheel", Vector3.new(1, diameter, diameter), CFrame.new(x * (halfX - 0.3), -halfY + 0.05, z * (halfZ - inset)), DARK, model)
			wheel.Shape = Enum.PartType.Cylinder
			weld(body, wheel)
		end
	end
end

local function buildSedanBody(model: Model, body: Part, size: Vector3, color: Color3)
	local halfX, halfY, halfZ = size.X / 2, size.Y / 2, size.Z / 2
	local cabin = makePart("Cabin", Vector3.new(size.X - 1, 1.8, size.Z * 0.48), CFrame.new(0, halfY + 0.9, 0.4), color, model)
	weld(body, cabin)
	glassPart("Windshield", Vector3.new(size.X - 1.2, 1.3, 0.3), CFrame.new(0, halfY + 0.95, 0.4 - size.Z * 0.24), body, model)
	glassPart("RearWindow", Vector3.new(size.X - 1.2, 1.3, 0.3), CFrame.new(0, halfY + 0.95, 0.4 + size.Z * 0.24), body, model)
	lights(model, body, halfX - 0.9, -halfZ - 0.05, halfZ + 0.05)
	trafficWheels(model, body, size, 1.8, 2.2)
end

-- A tall box with a big windshield and a window strip up front.
local function buildVanBody(model: Model, body: Part, size: Vector3)
	local halfX, halfY, halfZ = size.X / 2, size.Y / 2, size.Z / 2
	glassPart("Windshield", Vector3.new(size.X - 0.8, 1.6, 0.3), CFrame.new(0, halfY - 1.2, -halfZ - 0.05), body, model)
	for _, side in { -1, 1 } do
		glassPart("SideWindow", Vector3.new(0.3, 1.4, 3.2), CFrame.new(side * (halfX + 0.05), halfY - 1.2, -halfZ + 2.4), body, model)
		glassPart("RearWindow", Vector3.new(size.X * 0.36, 1.4, 0.3), CFrame.new(side * size.X * 0.22, halfY - 1.2, halfZ + 0.05), body, model)
	end
	local bumper = makePart("Bumper", Vector3.new(size.X + 0.2, 0.7, 0.5), CFrame.new(0, -halfY + 0.6, -halfZ - 0.2), DARK, model)
	weld(body, bumper)
	lights(model, body, halfX - 0.9, -halfZ - 0.05, halfZ + 0.05)
	trafficWheels(model, body, size, 2, 2.4)
end

-- A long city bus: window bands down both sides, a lit route board up front, a pale stripe low on the sides.
local function buildBusBody(model: Model, body: Part, size: Vector3)
	local halfX, halfY, halfZ = size.X / 2, size.Y / 2, size.Z / 2
	glassPart("Windshield", Vector3.new(size.X - 0.8, 2.6, 0.3), CFrame.new(0, halfY - 2.3, -halfZ - 0.05), body, model)
	neon("RouteBoard", Vector3.new(size.X - 2, 0.7, 0.3), CFrame.new(0, halfY - 0.5, -halfZ - 0.05), Color3.fromRGB(255, 170, 40), body, model)
	glassPart("RearWindow", Vector3.new(size.X - 2, 1.8, 0.3), CFrame.new(0, halfY - 1.8, halfZ + 0.05), body, model)
	for _, side in { -1, 1 } do
		glassPart("WindowBand", Vector3.new(0.3, 2.2, size.Z - 5), CFrame.new(side * (halfX + 0.05), halfY - 2.1, 0.8), body, model)
		local stripe = makePart("Stripe", Vector3.new(0.3, 0.6, size.Z - 1), CFrame.new(side * (halfX + 0.05), -halfY + 1.6, 0), Color3.fromRGB(240, 240, 235), model)
		weld(body, stripe)
	end
	local bumper = makePart("Bumper", Vector3.new(size.X + 0.2, 0.8, 0.5), CFrame.new(0, -halfY + 0.7, -halfZ - 0.2), DARK, model)
	weld(body, bumper)
	lights(model, body, halfX - 1, -halfZ - 0.05, halfZ + 0.05)
	trafficWheels(model, body, size, 2.6, 4)
end

-- Imported car art (Config.Art; ReplicatedStorage.MapModels.Cars): a clone welded to `anchor`, `length` long (no wider
-- than `maxWidth`), facing -Z like every vehicle here, the bottom of its wheels `drop` below the anchor's center. Looks
-- only: massless, no collision, queries or touches. Nil when that model isn't imported.
function VehicleBuilder.AttachArt(model: Model, anchor: BasePart, artName: string, length: number, maxWidth: number, drop: number): Model?
	local art = ReplicatedStorage:FindFirstChild("MapModels")
	local cars = if art then art:FindFirstChild("Cars") else nil
	local template = if cars then cars:FindFirstChild(artName) else nil
	if not template or not template:IsA("Model") then
		return nil
	end
	local clone = template:Clone()
	local _, size = clone:GetBoundingBox()
	clone:ScaleTo(clone:GetScale() * math.min(length / size.Z, maxWidth / size.X))
	local box, scaled = clone:GetBoundingBox()
	local pivotFromBox = box:ToObjectSpace(clone:GetPivot())
	clone:PivotTo(anchor.CFrame * CFrame.new(0, scaled.Y / 2 - drop, 0) * CFrame.Angles(0, math.rad(Config.Art.CarYaw), 0) * pivotFromBox)
	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.Massless = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			local w = Instance.new("WeldConstraint")
			w.Part0 = anchor
			w.Part1 = part
			w.Parent = part
		end
	end
	clone.Name = "Art"
	clone.Parent = model
	return clone
end

-- A bot's cab in Kenney clothes (Config.Art.BotCars): the parts cab stays (the chassis still collides and drives) but
-- hides, a Kenney car rides on the chassis and a glowing roof sign in the bot's color sits on its roof. False when the
-- model isn't imported (the bot keeps its painted parts cab).
function VehicleBuilder.DressBot(model: Model, artName: string, signColor: Color3): boolean
	local chassis = model.PrimaryPart
	if not chassis then
		return false
	end
	local art = VehicleBuilder.AttachArt(model, chassis, artName, chassis.Size.Z, chassis.Size.X * Config.Art.CarWidthSlack, Config.Bots.RideHeight)
	if not art then
		return false
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and not part:IsDescendantOf(art) then
			part.Transparency = 1
		end
	end
	local box, size = art:GetBoundingBox()
	local roof = chassis.CFrame:PointToObjectSpace(box.Position).Y + size.Y / 2
	local sign = makePart("BotSign", Config.Art.BotSignSize, chassis.CFrame * CFrame.new(0, roof + Config.Art.BotSignSize.Y / 2, 0), signColor, model)
	sign.Material = Enum.Material.Neon
	sign.Anchored = false
	sign.Massless = true
	sign.CanCollide = false
	sign.CanQuery = false
	sign.CanTouch = false
	local w = Instance.new("WeldConstraint")
	w.Part0 = chassis
	w.Part1 = sign
	w.Parent = sign
	return true
end

-- `pick` chooses the car among the kind's Config.Art.TrafficCars (wrapping); with none imported, the parts body.
function VehicleBuilder.BuildTraffic(kind: string, color: Color3, pick: number?): (Model, Part)
	local cfg = Config.Traffic
	local kindCfg = cfg.Kinds[kind] or cfg.Kinds.Sedan
	local size = kindCfg.Size
	local model = Instance.new("Model")
	model.Name = "Traffic" .. kind
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = size
	body.CFrame = CFrame.new()
	body.Color = color
	body.Material = Enum.Material.SmoothPlastic
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.CanCollide = true
	body.CustomPhysicalProperties = PhysicalProperties.new(kindCfg.Density, 0.3, 0.1, 1, 1)
	body.Parent = model
	model.PrimaryPart = body
	local cars = Config.Art.TrafficCars[kind]
	if cars and #cars > 0 then
		local artName = cars[((pick or 1) - 1) % #cars + 1]
		if VehicleBuilder.AttachArt(model, body, artName, size.Z, size.X * Config.Art.CarWidthSlack, size.Y / 2 + Config.Traffic.RideHeight) then
			body.Transparency = 1
			return model, body
		end
	end
	if kind == "Bus" then
		buildBusBody(model, body, size)
	elseif kind == "Van" then
		buildVanBody(model, body, size)
	else
		buildSedanBody(model, body, size, color)
	end
	return model, body
end

return VehicleBuilder
