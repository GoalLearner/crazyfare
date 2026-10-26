--!strict
-- Small vector helpers shared by server and client.

local VecUtil = {}

function VecUtil.Flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function VecUtil.FlatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Unit vector in the XZ plane; falls back to -Z (north) when the input has no horizontal component.
function VecUtil.FlatUnit(v: Vector3, fallback: Vector3?): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-4 then
		return fallback or Vector3.new(0, 0, -1)
	end
	return f.Unit
end

-- Heading around Y: 0 when facing -Z (north), positive clockwise seen from above. Matches GUI Rotation when converted to degrees.
function VecUtil.Yaw(look: Vector3): number
	return math.atan2(look.X, -look.Z)
end

function VecUtil.Clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

-- Frame-rate independent smoothing factor for "move toward target at this rate".
function VecUtil.ExpAlpha(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

return VecUtil
