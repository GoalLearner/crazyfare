--!strict
-- The raycast chassis. Runs only for the local player's taxi (which this client network-owns).
-- Every number comes from Config.Chassis and the vehicle's stats; the model only supplies attachments.
-- Reports drift / airtime / near-miss events and the drifting flag to the server; applies server-sent
-- spinouts and boosts by reading State.

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local State = require(script.Parent.Parent.State)
local InputController = require(script.Parent.InputController)

type Wheel = {
	attachment: Attachment,
	weld: Weld?,
	isFront: boolean,
	contactDistance: number,
	spin: number,
}

local VehicleController = {}

local C = Config.Chassis
local chassis: BasePart? = nil
local wheels: { Wheel } = {}
local raycastParams = RaycastParams.new()
local overlapParams = OverlapParams.new()

local airTime = 0
local flipTimer = 0
local driftAccumulator = 0
local lastDriftingSent: boolean? = nil
local lastDriveStateAt = 0
local nearMissCooldownUntil = 0
local nearMissCheckAt = 0
local recentNearMiss: { [BasePart]: number } = {}

local comboEvent: RemoteEvent
local driveState: RemoteEvent
local resetVehicle: RemoteEvent

local function refreshFilters(model: Model?)
	local map = workspace:FindFirstChild("Map")
	if map then
		raycastParams.FilterType = Enum.RaycastFilterType.Include
		raycastParams.FilterDescendantsInstances = { map }
		overlapParams.FilterType = Enum.RaycastFilterType.Include
		overlapParams.FilterDescendantsInstances = { map }
	else
		local exclude: { Instance } = {}
		for _, name in { "Vehicles", "NPCs", "Items" } do
			local folder = workspace:FindFirstChild(name)
			if folder then
				table.insert(exclude, folder)
			end
		end
		if model then
			table.insert(exclude, model)
		end
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = exclude
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude
		overlapParams.FilterDescendantsInstances = exclude
	end
end

local function attach(model: Model?)
	chassis = nil
	wheels = {}
	airTime = 0
	flipTimer = 0
	driftAccumulator = 0
	lastDriftingSent = nil
	State.boostTank = 0
	if not model then
		return
	end
	local primary = model.PrimaryPart
	if not primary then
		return
	end
	chassis = primary
	for _, name in { "WheelFL", "WheelFR", "WheelRL", "WheelRR" } do
		local att = primary:FindFirstChild(name)
		if att and att:IsA("Attachment") then
			local part = model:FindFirstChild(name)
			local weld = if part then part:FindFirstChild("WheelWeld") else nil
			table.insert(wheels, {
				attachment = att,
				weld = if weld and weld:IsA("Weld") then weld else nil,
				isFront = name == "WheelFL" or name == "WheelFR",
				contactDistance = C.SuspensionRest + C.WheelRadius,
				spin = 0,
			})
		end
	end
	refreshFilters(model)
end

local function reportCombo(kind: string, value: number)
	comboEvent:FireServer({ kind = kind, value = value })
end

local function isNearMissTarget(part: BasePart): boolean
	return CollectionService:HasTag(part, Config.Tags.Building)
		or CollectionService:HasTag(part, Config.Tags.Wall)
		or CollectionService:HasTag(part, Config.Tags.Prop)
end

-- A tagged obstacle inside the padded box but outside the tight box = a near miss.
local function checkNearMiss(ch: BasePart, now: number)
	local pad = C.NearMissPadding
	local loose = workspace:GetPartBoundsInBox(ch.CFrame, ch.Size + Vector3.new(pad * 2, 1, pad * 2), overlapParams)
	if #loose == 0 then
		return
	end
	local tight = workspace:GetPartBoundsInBox(ch.CFrame, ch.Size + Vector3.new(1, 1, 1), overlapParams)
	local touching: { [BasePart]: boolean } = {}
	for _, part in tight do
		touching[part] = true
	end
	for _, part in loose do
		if touching[part] or not isNearMissTarget(part) then
			continue
		end
		local last = recentNearMiss[part]
		if last and now - last < 2 then
			continue
		end
		recentNearMiss[part] = now
		nearMissCooldownUntil = now + C.NearMissCooldown
		State.boostTank = math.min(State.stats.BoostTank, State.boostTank + C.BoostFillPerNearMiss)
		reportCombo("NearMiss", 1)
		return
	end
end

local function updateWheelVisual(w: Wheel, steer: number, forwardSpeed: number, dt: number)
	local weld = w.weld
	if not weld then
		return
	end
	w.spin = (w.spin + forwardSpeed / C.WheelRadius * dt) % (math.pi * 2)
	local drop = math.clamp(w.contactDistance - C.WheelRadius, 0, C.SuspensionRest + 0.3)
	local localPos = w.attachment.Position - Vector3.new(0, drop, 0)
	weld.C0 = CFrame.new(localPos) * CFrame.Angles(0, if w.isFront then -steer else 0, 0) * CFrame.Angles(w.spin, 0, 0)
end

local function step(rawDt: number)
	-- A long hitch (breakpoint, window drag) must not become one giant impulse.
	local dt = math.min(rawDt, C.MaxStepSeconds)
	local ch = chassis
	if not ch or ch.Anchored or not ch:IsDescendantOf(workspace) then
		State.speed = 0
		State.forwardSpeed = 0
		State.drifting = false
		State.boosting = false
		return
	end
	local now = workspace:GetServerTimeNow()
	local stats = State.stats
	local mass = ch.AssemblyMass
	local cf = ch.CFrame
	local up, look = cf.UpVector, cf.LookVector
	local vel = ch.AssemblyLinearVelocity
	local speed = vel.Magnitude
	local forwardSpeed = vel:Dot(look)
	local g = workspace.Gravity

	-- Input and timed effects
	local spinning = now < State.spinUntil
	local nitro = now < State.nitroUntil
	local throttle = if spinning then 0 else InputController.GetThrottle()
	local steerInput = if spinning then 0 else InputController.GetSteer()
	local handbrake = InputController.IsDrifting() and not spinning
	local wantBoost = InputController.IsBoosting() and State.boostTank > 0 and not spinning

	local speedMult = 1
	local accelMult = 1
	if nitro then
		speedMult *= Config.Items.LemonNitro.SpeedMult
		accelMult *= Config.Items.LemonNitro.AccelMult
	end
	if wantBoost then
		speedMult *= C.BoostSpeedMult
		accelMult *= C.BoostAccelMult
		State.boostTank = math.max(0, State.boostTank - dt)
	end
	local topSpeed = stats.TopSpeed * speedMult
	local accel = stats.Accel * accelMult

	-- Steering: less at speed, more while drifting
	local speedFrac = math.clamp(math.abs(forwardSpeed) / stats.TopSpeed, 0, 1)
	local steerScale = 1 - C.SpeedSteerFalloff * speedFrac
	if handbrake then
		steerScale *= C.DriftSteerBonus
	end
	local steerAngle = math.rad(stats.SteerMax) * steerInput * steerScale

	-- Suspension + tires, one wheel at a time
	local rayLen = C.SuspensionRest + C.WheelRadius
	local restLength = C.SuspensionRest
	local omega = math.sqrt(C.SuspensionStiffness * g / restLength)
	local dampCoef = 2 * omega * C.SuspensionDampingRatio
	local groundedCount = 0
	local rearSide = 0
	local comPlane = ch.Position

	for _, w in wheels do
		local origin = w.attachment.WorldPosition
		local result = workspace:Raycast(origin, -up * rayLen, raycastParams)
		local wheelSteer = if w.isFront then steerAngle else 0
		local wheelLook = if wheelSteer ~= 0 then CFrame.fromAxisAngle(up, -wheelSteer):VectorToWorldSpace(look) else look
		local wheelRight = wheelLook:Cross(up)

		if result then
			groundedCount += 1
			local normal = result.Normal
			local compression = rayLen - result.Distance
			local pointVel = ch:GetVelocityAtPosition(origin)

			local springAccel = C.SuspensionStiffness * (g / 4) * (compression / restLength)
			local damperAccel = dampCoef * pointVel:Dot(up) / 4
			local susAccel = math.max(0, springAccel - damperAccel)
			ch:ApplyImpulseAtPosition(up * susAccel * mass * dt, origin)

			local fwdFlat = wheelLook - normal * wheelLook:Dot(normal)
			fwdFlat = if fwdFlat.Magnitude > 1e-3 then fwdFlat.Unit else wheelLook
			local rightFlat = wheelRight - normal * wheelRight:Dot(normal)
			rightFlat = if rightFlat.Magnitude > 1e-3 then rightFlat.Unit else wheelRight
			local sideVel = pointVel:Dot(rightFlat)
			local fwdVel = pointVel:Dot(fwdFlat)

			local gripRate = stats.Handling
			if handbrake and not w.isFront then
				gripRate *= stats.DriftGrip
			end
			if spinning then
				gripRate *= C.SpinGripMult
			end
			local gripAlpha = 1 - math.exp(-gripRate * dt)
			-- Apply tire forces at the wheel's XZ but at the center-of-mass height so grip does not roll the car.
			local applyPos = origin + up * (comPlane - origin):Dot(up)
			ch:ApplyImpulseAtPosition(-rightFlat * sideVel * gripAlpha * (mass / 4), applyPos)

			local driveAccel = 0
			if throttle > 0 then
				driveAccel = throttle * accel * (1 - math.clamp(fwdVel / topSpeed, 0, 1))
			elseif throttle < 0 then
				if fwdVel > 2 then
					driveAccel = C.BrakeAccel * throttle
				else
					driveAccel = throttle * accel * C.ReverseAccelMult * (1 - math.clamp(-fwdVel / C.ReverseTopSpeed, 0, 1))
				end
			else
				driveAccel = -fwdVel * C.RollingDrag
			end
			ch:ApplyImpulseAtPosition(fwdFlat * driveAccel * (mass / 4) * dt, applyPos)

			if not w.isFront then
				rearSide += math.abs(sideVel) / 2
			end
			w.contactDistance = result.Distance
		else
			w.contactDistance = rayLen
		end
		updateWheelVisual(w, wheelSteer, forwardSpeed, dt)
	end

	local grounded = groundedCount > 0

	-- Air: damp tumbling and level out so landings are drivable
	if not grounded then
		airTime += dt
		local av = ch.AssemblyAngularVelocity
		ch.AssemblyAngularVelocity = av * math.clamp(1 - C.AirAngularDamping * dt, 0, 1)
		local inertia = mass * (ch.Size.X * ch.Size.X + ch.Size.Z * ch.Size.Z) / 12
		local uprightAxis = up:Cross(Vector3.yAxis)
		ch:ApplyAngularImpulse(uprightAxis * inertia * C.AirUprightStrength * dt)
	else
		if airTime >= C.AirtimeMinSeconds then
			reportCombo("Airtime", airTime)
		end
		airTime = 0
	end

	-- Upside down and stuck: ask the server to stand us up
	if up.Y < -0.2 and speed < 10 then
		flipTimer += dt
		if flipTimer >= C.FlipResetSeconds then
			flipTimer = 0
			resetVehicle:FireServer()
		end
	else
		flipTimer = 0
	end

	-- Spinout: yaw spin driven directly
	if spinning then
		local av = ch.AssemblyAngularVelocity
		ch.AssemblyAngularVelocity = Vector3.new(av.X, C.SpinAngularSpeed * State.spinDirection, av.Z)
	end

	-- Horizontal cap (arcade feel; also what the server assumes for speed sanity).
	-- Bleeds excess speed at brake rate instead of snapping, so a boost ending never reads as a crash.
	if grounded then
		local cap = topSpeed * C.SpeedHardCapMult
		local flat = Vector3.new(vel.X, 0, vel.Z)
		local allowed = math.max(cap, flat.Magnitude - C.BrakeAccel * dt)
		if flat.Magnitude > allowed then
			ch.AssemblyLinearVelocity = flat.Unit * allowed + Vector3.new(0, vel.Y, 0)
		end
	end

	-- Drift detection, combo ticks, boost tank
	local drifting = grounded and handbrake and speed > C.DriftMinSpeed and rearSide > C.DriftMinSide
	if drifting then
		driftAccumulator += dt
		State.boostTank = math.min(stats.BoostTank, State.boostTank + C.BoostFillPerDriftSecond * dt)
		if driftAccumulator >= Config.Combo.DriftTickSeconds then
			reportCombo("Drift", driftAccumulator)
			driftAccumulator = 0
		end
	else
		if driftAccumulator > 0.15 then
			reportCombo("Drift", driftAccumulator)
		end
		driftAccumulator = 0
	end
	if drifting ~= lastDriftingSent and now - lastDriveStateAt > 0.1 then
		lastDriftingSent = drifting
		lastDriveStateAt = now
		driveState:FireServer(drifting)
	end

	-- Near misses, checked ten times a second
	if speed >= Config.Combo.NearMissMinSpeed and now >= nearMissCooldownUntil and now >= nearMissCheckAt then
		nearMissCheckAt = now + 0.1
		checkNearMiss(ch, now)
	end

	State.speed = speed
	State.forwardSpeed = forwardSpeed
	State.drifting = drifting
	State.boosting = wantBoost or nitro
	State.grounded = grounded
end

function VehicleController.Init()
	comboEvent = Remotes.Get("ComboEvent")
	driveState = Remotes.Get("DriveState")
	resetVehicle = Remotes.Get("ResetVehicle")
	State.VehicleChanged:Connect(attach)
	if State.vehicle then
		attach(State.vehicle)
	end
	InputController.OnReset:Connect(function()
		resetVehicle:FireServer()
	end)
	workspace.ChildAdded:Connect(function(child: Instance)
		if child.Name == "Map" then
			refreshFilters(State.vehicle)
		end
	end)
end

function VehicleController.Start()
	RunService.Heartbeat:Connect(step)
end

return VehicleController
