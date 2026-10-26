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
local VehicleBuilder = require(ReplicatedStorage.Shared.VehicleBuilder)

local VehicleRig = {}

local function attachment(name: string, position: Vector3, parent: BasePart): Attachment
	local att = Instance.new("Attachment")
	att.Name = name
	att.Position = position
	att.Parent = parent
	return att
end

-- `targetLength` scales the mesh so its longest horizontal side matches the parts cab (11 studs) unless given.
function VehicleRig.Rig(imported: Instance?, vehicleId: string, targetLength: number?): Model
	assert(Config.Vehicles.Stats[vehicleId], "unknown vehicle id " .. vehicleId)
	assert(imported ~= nil, "nothing selected: click the imported model in the Explorer first")
	assert(imported:IsA("Model"), "select the imported MODEL (the top item, e.g. taxi), not a part or folder")
	assert(imported:IsDescendantOf(workspace), "select the model in the Workspace, not one already in VehicleTemplates")
	assert(not imported:FindFirstChild("Chassis"), "this model is already rigged; import a fresh copy")
	local mesh = imported :: Model
	local _, rawSize = mesh:GetBoundingBox()
	print(string.format("[VehicleRig] imported size %.1f x %.1f x %.1f studs", rawSize.X, rawSize.Y, rawSize.Z))

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
	-- Vehicles flagged TintMesh take their Config colour (and garage paint) on the body; wheels keep the imported look.
	if Config.Vehicles.Stats[vehicleId].TintMesh then
		for _, part in mesh:GetDescendants() do
			if part:IsA("BasePart") and part ~= chassis and part ~= silhouette and not string.find(string.lower(part.Name), "wheel", 1, true) then
				part:SetAttribute("Paintable", true)
				if part:IsA("MeshPart") and part.TextureID ~= "" and not part:FindFirstChildOfClass("SurfaceAppearance") then
					local appearance = Instance.new("SurfaceAppearance")
					appearance.ColorMap = part.TextureID
					appearance.Parent = part
				end
			end
		end
		VehicleBuilder.ApplyPaint(mesh, nil)
	end
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

-- Rig everything imported into the Workspace in one go, by file name. Items go to ReplicatedStorage.ItemModels.
-- Command bar:  require(game.ServerScriptService.Server.Studio.VehicleRig).RigAll()
local VEHICLE_BY_NAME: { [string]: string } = {
	taxi = "YellowCab",
	sedan = "NightCab",
	delivery = "IceCreamTruck",
	["kart-oozi"] = "GoKart",
	["kart-oobi"] = "GoKart",
	["kart-oodi"] = "GoKart",
	["kart-ooli"] = "GoKart",
	["kart-oopi"] = "GoKart",
}
local ITEM_BY_NAME: { [string]: string } = {
	banana = "Banana",
	tomato = "Tomato",
	lemon = "Lemon",
}

function VehicleRig.RigAll()
	local rigged = 0
	for _, inst in workspace:GetChildren() do
		if not inst:IsA("Model") or inst:FindFirstChild("Chassis") then
			continue
		end
		local key = string.lower(inst.Name)
		local vehicleId = VEHICLE_BY_NAME[key]
		local itemName = ITEM_BY_NAME[key]
		if vehicleId then
			local length = if vehicleId == "GoKart" then 8 else 11
			VehicleRig.Rig(inst, vehicleId, length)
			rigged += 1
		elseif itemName then
			local folder = ReplicatedStorage:FindFirstChild("ItemModels")
			if not folder then
				folder = Instance.new("Folder")
				folder.Name = "ItemModels"
				folder.Parent = ReplicatedStorage
			end
			local old = folder:FindFirstChild(itemName)
			if old then
				old:Destroy()
			end
			if not inst.PrimaryPart then
				for _, part in inst:GetDescendants() do
					if part:IsA("BasePart") then
						inst.PrimaryPart = part
						break
					end
				end
			end
			inst.Name = itemName
			inst.Parent = folder
			print("[VehicleRig] item model filed: " .. itemName)
			rigged += 1
		else
			print("[VehicleRig] skipped " .. inst.Name .. " (no mapping)")
		end
	end
	print(string.format("[VehicleRig] RigAll done: %d models placed", rigged))
end

return VehicleRig
