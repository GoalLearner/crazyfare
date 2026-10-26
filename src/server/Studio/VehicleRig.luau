--!strict
-- Studio helper: turns an imported mesh model into a vehicle that satisfies the VehicleBuilder contract.
-- Select the imported model in the Explorer, then in the command bar:
--   require(game.ServerScriptService.Server.Studio.VehicleRig).Rig(game.Selection:Get()[1], "YellowCab")
-- It builds an invisible Chassis collider around the mesh, welds the mesh to it, adds the four wheel attachments,
-- the DropPoint and Muzzle, a Silhouette, the attributes, and files it under ReplicatedStorage.VehicleTemplates.
-- VehicleService prefers a template there over the parts build. Wheel visuals stay part of the mesh (no spin).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.Config)

local VehicleRig = {}

local function attachment(name: string, position: Vector3, parent: BasePart): Attachment
	local att = Instance.new("Attachment")
	att.Name = name
	att.Position = position
	att.Parent = parent
	return att
end

-- `targetLength` scales the mesh so its longest horizontal side matches the parts cab (11 studs) unless given.
function VehicleRig.Rig(imported: Instance, vehicleId: string, targetLength: number?): Model
	assert(Config.Vehicles.Stats[vehicleId], "unknown vehicle id " .. vehicleId)
	local model = if imported:IsA("Model") then imported else nil
	if not model then
		model = Instance.new("Model")
		imported.Parent = model
	end
	local mesh = model :: Model

	-- Scale to size and sit it at the origin facing -Z (Kenney cars face +Z; rotate 180 if the nose points at you).
	local cf, size = mesh:GetBoundingBox()
	local longest = math.max(size.X, size.Z)
	local scale = (targetLength or 11) / math.max(longest, 0.01)
	mesh:ScaleTo(mesh:GetScale() * scale)
	cf, size = mesh:GetBoundingBox()

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(size.X * 0.9, math.max(1.2, size.Y * 0.45), size.Z * 0.95)
	chassis.CFrame = CFrame.new(cf.Position.X, cf.Position.Y - size.Y * 0.2, cf.Position.Z)
	chassis.Transparency = 1
	chassis.CanCollide = true
	chassis.Anchored = true
	chassis.CustomPhysicalProperties = PhysicalProperties.new(1, 0.3, 0.1, 1, 1)
	chassis.Parent = mesh
	mesh.PrimaryPart = chassis

	for _, part in mesh:GetDescendants() do
		if part:IsA("BasePart") and part ~= chassis then
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = chassis
			weld.Part1 = part
			weld.Parent = part
		end
	end

	local halfW = chassis.Size.X / 2 - 0.4
	local halfL = chassis.Size.Z / 2 - 1.2
	local y = -chassis.Size.Y / 2 + 0.4
	attachment("WheelFL", Vector3.new(-halfW, y, -halfL), chassis)
	attachment("WheelFR", Vector3.new(halfW, y, -halfL), chassis)
	attachment("WheelRL", Vector3.new(-halfW, y, halfL), chassis)
	attachment("WheelRR", Vector3.new(halfW, y, halfL), chassis)
	attachment("DropPoint", Vector3.new(0, y, chassis.Size.Z / 2 + 2), chassis)
	attachment("Muzzle", Vector3.new(0, 1, -chassis.Size.Z / 2 - 1), chassis)

	local silhouette = Instance.new("Part")
	silhouette.Name = "Silhouette"
	silhouette.Size = Vector3.new(1.4, 1.3, 0.5)
	silhouette.CFrame = chassis.CFrame * CFrame.new(0, chassis.Size.Y / 2 + 1, chassis.Size.Z * 0.2)
	silhouette.Color = Color3.fromRGB(10, 10, 12)
	silhouette.Transparency = 1
	silhouette.CanCollide = false
	silhouette.CanQuery = false
	silhouette.Massless = true
	silhouette.Parent = mesh
	local sWeld = Instance.new("WeldConstraint")
	sWeld.Part0 = chassis
	sWeld.Part1 = silhouette
	sWeld.Parent = silhouette

	mesh.Name = vehicleId
	mesh:SetAttribute("VehicleId", vehicleId)
	mesh:SetAttribute("WheelType", Config.Vehicles.Stats[vehicleId].WheelType)
	CollectionService:AddTag(mesh, Config.Tags.VehicleTemplate)
	mesh:PivotTo(CFrame.new())

	local templates = ReplicatedStorage:FindFirstChild("VehicleTemplates")
	if not templates then
		templates = Instance.new("Folder")
		templates.Name = "VehicleTemplates"
		templates.Parent = ReplicatedStorage
	end
	local old = templates:FindFirstChild(vehicleId)
	if old then
		old:Destroy()
	end
	mesh.Parent = templates
	print(string.format("[VehicleRig] %s rigged: chassis %.1f x %.1f x %.1f", vehicleId, chassis.Size.X, chassis.Size.Y, chassis.Size.Z))
	return mesh
end

return VehicleRig
