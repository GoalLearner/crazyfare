--!strict
-- Ticking fares (Config.Chaos.Ticking): what the fare is worth as the clock runs, and the alarm clock the passenger
-- holds. The server (payout, Hunter Bonus, the snapshot) and the client (the FARE meter) share the math; the curb
-- passenger and the rider in the cab share the clock.

local Config = require(script.Parent.Config)

local Ticking = {}

-- StartMult at pickup, one step down every TickSeconds, FloorMult at the deadline.
function Ticking.Mult(startedAt: number, deadline: number, now: number): number
	local cfg = Config.Chaos.Ticking
	local total = math.max(0.01, deadline - startedAt)
	local elapsed = math.floor(math.max(0, now - startedAt) / cfg.TickSeconds) * cfg.TickSeconds
	local frac = math.clamp(1 - elapsed / total, 0, 1)
	return cfg.FloorMult + (cfg.StartMult - cfg.FloorMult) * frac
end

-- The fare itself (no tip, no stunt cash) at `now`, in cents.
function Ticking.Value(base: number, startedAt: number, deadline: number, now: number): number
	return math.round(base * Ticking.Mult(startedAt, deadline, now))
end

local function piece(name: string, shape: Enum.PartType, size: Vector3, color: Color3, cframe: CFrame, root: BasePart, model: Model): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.CFrame = cframe
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	local w = Instance.new("Weld")
	w.Part0 = root
	w.Part1 = p
	w.C0 = root.CFrame:ToObjectSpace(cframe)
	w.Parent = p
	p.Parent = model
	return p
end

-- A cartoon alarm clock `size` studs across with its face toward +Z, every piece welded to an invisible PrimaryPart
-- at its center: pivot it into place and weld the PrimaryPart.
function Ticking.Clock(size: number): Model
	local cfg = Config.Chaos.Ticking
	local model = Instance.new("Model")
	model.Name = "TickingClock"
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.one * 0.2
	root.CFrame = CFrame.new()
	root.Transparency = 1
	root.Anchored = false
	root.Massless = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Parent = model
	model.PrimaryPart = root
	local faceOn = CFrame.Angles(0, math.pi / 2, 0) -- a cylinder's axis is X; turn it to Z
	local depth = size * 0.35
	piece("Rim", Enum.PartType.Cylinder, Vector3.new(depth, size, size), cfg.Color, faceOn, root, model)
	piece("Face", Enum.PartType.Cylinder, Vector3.new(depth + 0.1, size * 0.8, size * 0.8), cfg.FaceColor, faceOn, root, model)
	for _, side in { -1, 1 } do
		piece("Bell", Enum.PartType.Ball, Vector3.one * size * 0.32, cfg.Color, CFrame.new(side * size * 0.3, size * 0.48, 0), root, model)
	end
	-- the hands at ten past ten, the way every clock is drawn
	local front = CFrame.new(0, 0, depth / 2 + 0.08)
	for _, hand in { { angle = math.rad(60), length = size * 0.24 }, { angle = math.rad(-60), length = size * 0.33 } } do
		local cf = front * CFrame.Angles(0, 0, hand.angle) * CFrame.new(0, hand.length / 2, 0)
		piece("Hand", Enum.PartType.Block, Vector3.new(size * 0.07, hand.length, 0.05), cfg.HandColor, cf, root, model)
	end
	return model
end

return Ticking
