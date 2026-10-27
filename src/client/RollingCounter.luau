--!strict
-- A slot-machine money counter. Every digit is a reel; the value rolls up toward its target like an odometer: the cents
-- reel spins, and each higher reel turns over while the reels below it wrap from 9 to 0. Cents always show ("$5.00").
-- Going down (a new round) snaps instead of rolling.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local UI = require(script.Parent.UI)

export type Counter = {
	root: Frame,
	scale: UIScale,
	strips: { Frame }, -- one per digit reel, index 1 = the lowest place (cents ones)
	glyphs: { TextLabel }, -- every label, recolored together
	height: number,
	color: Color3,
	dollarDigits: number, -- reels left of the decimal point in the current layout
	value: number, -- shown cents (fractional while rolling)
	target: number,
	rate: number, -- cents per second for the current roll
	holdUntil: number,
}

local RollingCounter = {}

local function glyph(counter: Counter, parent: Instance, text: string, x: number, y: number, width: number): TextLabel
	local label = UI.Label({
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(width, counter.height),
		TextScaled = false,
		TextSize = math.floor(counter.height * 0.9),
		TextColor3 = counter.color,
		Text = text,
	}, parent)
	table.insert(counter.glyphs, label)
	return label
end

-- A reel: a clipped window over a strip of 0-9 and a second 0, so turning past 9 shows the wrap.
local function reel(counter: Counter, x: number, width: number): Frame
	local window = UI.Frame({ Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(width, counter.height), BackgroundTransparency = 1, ClipsDescendants = true }, counter.root)
	local strip = UI.Frame({ Size = UDim2.fromOffset(width, counter.height * 11), BackgroundTransparency = 1 }, window)
	for i = 0, 10 do
		glyph(counter, strip, tostring(i % 10), 0, i * counter.height, width)
	end
	return strip
end

local function dollarDigitsFor(cents: number): number
	return #tostring(math.max(0, math.floor(cents / 100)))
end

-- Lays out "$", the dollar reels, ".", and the two cent reels for `digits` dollar places.
local function layout(counter: Counter, digits: number)
	for _, child in counter.root:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(counter.strips)
	table.clear(counter.glyphs)
	counter.dollarDigits = digits
	local h = counter.height
	local digitWidth = math.round(h * 0.6)
	local dotWidth = math.round(h * 0.3)
	local x = 0
	glyph(counter, counter.root, "$", x, 0, digitWidth)
	x += digitWidth
	local ordered: { Frame } = {}
	for _ = 1, digits do
		table.insert(ordered, reel(counter, x, digitWidth))
		x += digitWidth
	end
	glyph(counter, counter.root, ".", x, 0, dotWidth)
	x += dotWidth
	for _ = 1, 2 do
		table.insert(ordered, reel(counter, x, digitWidth))
		x += digitWidth
	end
	-- strips run lowest place first
	for i = #ordered, 1, -1 do
		table.insert(counter.strips, ordered[i])
	end
	counter.root.Size = UDim2.fromOffset(x, h)
end

-- Odometer position of the reel for place `p` (0 = cents ones): its digit, plus how far it has turned toward the next.
local function reelPosition(value: number, p: number): number
	if p == 0 then
		return value % 10
	end
	local unit = 10 ^ p
	local base = math.floor(value / unit) % 10
	local turning = math.clamp(value % unit - (unit - 1), 0, 1)
	return base + turning
end

local function render(counter: Counter)
	local digits = dollarDigitsFor(counter.value)
	if digits ~= counter.dollarDigits then
		layout(counter, digits)
	end
	for i, strip in counter.strips do
		strip.Position = UDim2.fromOffset(0, -reelPosition(counter.value, i - 1) * counter.height)
	end
end

-- `anchorX` 0 grows to the right of `position`, 1 grows to the left (right-aligned).
function RollingCounter.new(parent: Instance, height: number, color: Color3, position: UDim2, anchorX: number): Counter
	local root = UI.Frame({ AnchorPoint = Vector2.new(anchorX, 0), Position = position, BackgroundTransparency = 1 }, parent)
	local counter: Counter = {
		root = root,
		scale = UI.New("UIScale", {}, root) :: UIScale,
		strips = {},
		glyphs = {},
		height = height,
		color = color,
		dollarDigits = 0,
		value = 0,
		target = 0,
		rate = 0,
		holdUntil = 0,
	}
	render(counter)
	return counter
end

function RollingCounter.Snap(counter: Counter, cents: number)
	counter.value = cents
	counter.target = cents
	counter.holdUntil = 0
	render(counter)
end

-- Roll to `cents`, optionally after `hold` seconds. Lower than what is showing snaps.
function RollingCounter.SetTarget(counter: Counter, cents: number, hold: number?)
	if cents == counter.target then
		return
	end
	if cents < counter.value then
		RollingCounter.Snap(counter, cents)
		return
	end
	counter.target = cents
	counter.rate = math.max((cents - counter.value) / Config.Hud.CounterRollSeconds, Config.Hud.CounterMinRate)
	if hold and hold > 0 then
		RollingCounter.Hold(counter, hold)
	end
end

-- Keeps the counter still for `seconds` before it rolls on (coins still in the air).
function RollingCounter.Hold(counter: Counter, seconds: number)
	counter.holdUntil = math.max(counter.holdUntil, os.clock() + seconds)
end

-- Advances the roll. Returns (ticked: a dime boundary went by, landed: the roll just finished).
function RollingCounter.Step(counter: Counter, dt: number): (boolean, boolean)
	if counter.value >= counter.target or os.clock() < counter.holdUntil then
		return false, false
	end
	local before = math.floor(counter.value / 10)
	counter.value = math.min(counter.target, counter.value + counter.rate * dt)
	render(counter)
	local landed = counter.value >= counter.target
	if landed then
		counter.scale.Scale = 1.18
		TweenService:Create(counter.scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	return math.floor(counter.value / 10) ~= before, landed
end

function RollingCounter.GetValue(counter: Counter): number
	return counter.value
end

function RollingCounter.SetColor(counter: Counter, color: Color3)
	if color == counter.color then
		return
	end
	counter.color = color
	for _, label in counter.glyphs do
		label.TextColor3 = color
	end
end

-- Screen-space center of the counter (for coins to fly into).
function RollingCounter.GetCenter(counter: Counter): Vector2
	return counter.root.AbsolutePosition + counter.root.AbsoluteSize / 2
end

return RollingCounter
