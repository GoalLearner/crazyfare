--!strict
-- Tiny helpers for building UI from code. No Studio-authored GUI assets anywhere in the project.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Money = require(Shared:WaitForChild("Money"))
local Config = require(Shared:WaitForChild("Config"))

local UI = {}

UI.Font = Enum.Font.GothamBlack
UI.FontMedium = Enum.Font.GothamBold
UI.White = Color3.fromRGB(255, 255, 255)
UI.Black = Color3.fromRGB(12, 12, 16)
UI.Panel = Color3.fromRGB(18, 18, 24)
UI.Muted = Color3.fromRGB(170, 170, 180)
UI.Cash = Color3.fromRGB(120, 240, 130)
UI.Danger = Color3.fromRGB(240, 70, 70)
UI.Warn = Color3.fromRGB(250, 210, 60)
UI.Accent = Color3.fromRGB(80, 230, 255)

function UI.New(className: string, props: { [string]: any }, parent: Instance?): Instance
	local inst = Instance.new(className)
	for key, value in props do
		(inst :: any)[key] = value
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- Phones: when the screen below Roblox's top bar is smaller than Config.Hud.FitSize every scaled ScreenGui shrinks to
-- fit. A UIScale on the ScreenGui keeps each piece pinned to its corner. Screen points (WorldToViewportPoint,
-- AbsolutePosition) divided by UI.FitScale() are offsets inside a scaled screen.
local fitScales: { UIScale } = {}
local fitListeners: { () -> () } = {}
local fitScale = 1
local fitWatching = false

-- Roblox's top bar height in px; it never scales.
local function topbar(): number
	return math.max(game:GetService("GuiService"):GetGuiInset().Y, Config.Hud.TopbarHeight) -- 0 before the bar loads
end

local function refit()
	local camera = workspace.CurrentCamera
	local fit = Config.Hud.FitSize
	local view = if camera then camera.ViewportSize else fit + Vector2.new(0, topbar())
	fitScale = math.clamp(math.min(view.X / fit.X, (view.Y - topbar()) / fit.Y), Config.Hud.FitMinScale, 1)
	for _, scale in fitScales do
		scale.Scale = fitScale
	end
	for _, listener in fitListeners do
		listener()
	end
end

local function watchFit()
	if fitWatching then
		return
	end
	fitWatching = true
	local function hook()
		local camera = workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(refit)
		end
		refit()
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hook)
	hook()
end

function UI.FitScale(): number
	return fitScale
end

-- Runs now and whenever the phone scale changes (for pieces placed by UI.BelowTopbar or UI.CenterBelowTopbar).
function UI.OnFit(listener: () -> ())
	table.insert(fitListeners, listener)
	listener()
end

-- A Y offset in a scaled screen that keeps a piece the same distance below Roblox's top bar at any scale (the bar
-- itself never shrinks). designY is the full-size layout, made for a bar Config.Hud.TopbarHeight tall.
function UI.BelowTopbar(designY: number): number
	return designY + topbar() / fitScale - Config.Hud.TopbarHeight
end

-- A centered panel (AnchorPoint 0.5, 0.5) centers in the space below the top bar, so a tall one never slides under it.
function UI.CenterBelowTopbar(panel: GuiObject)
	UI.OnFit(function()
		panel.Position = UDim2.new(0.5, 0, 0.5, topbar() / fitScale / 2)
	end)
end

-- `fixed` screens keep their size on phones (touch pads, full-screen effects).
function UI.Screen(name: string, displayOrder: number?, fixed: boolean?): ScreenGui
	local player = game:GetService("Players").LocalPlayer
	local gui = UI.New("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder or 0,
	}, player:WaitForChild("PlayerGui")) :: ScreenGui
	if not fixed then
		watchFit()
		local scale = UI.New("UIScale", { Name = "Fit", Scale = fitScale }, gui) :: UIScale
		table.insert(fitScales, scale)
	end
	return gui
end

function UI.Frame(props: { [string]: any }, parent: Instance?): Frame
	local base: { [string]: any } = {
		BackgroundColor3 = UI.Panel,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
	}
	for k, v in props do
		base[k] = v
	end
	return UI.New("Frame", base, parent) :: Frame
end

function UI.Label(props: { [string]: any }, parent: Instance?): TextLabel
	local base: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = UI.Font,
		TextColor3 = UI.White,
		TextScaled = true,
		TextStrokeTransparency = 0.5,
		TextStrokeColor3 = UI.Black,
		Text = "",
	}
	for k, v in props do
		base[k] = v
	end
	return UI.New("TextLabel", base, parent) :: TextLabel
end

function UI.Corner(radius: number, parent: Instance): UICorner
	return UI.New("UICorner", { CornerRadius = UDim.new(0, radius) }, parent) :: UICorner
end

function UI.Stroke(color: Color3, thickness: number, parent: Instance): UIStroke
	return UI.New("UIStroke", { Color = color, Thickness = thickness }, parent) :: UIStroke
end

export type Bar = { back: Frame, fill: Frame }

-- Horizontal bar; call UI.SetBar(bar, 0..1).
function UI.Bar(props: { [string]: any }, fillColor: Color3, parent: Instance?): Bar
	local back = UI.Frame(props, parent)
	back.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	back.BackgroundTransparency = 0.2
	back.ClipsDescendants = true
	UI.Corner(4, back)
	local fill = UI.Frame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = fillColor,
		BackgroundTransparency = 0,
	}, back)
	UI.Corner(4, fill)
	return { back = back, fill = fill }
end

function UI.SetBar(bar: Bar, fraction: number, color: Color3?)
	bar.fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	if color then
		bar.fill.BackgroundColor3 = color
	end
end

function UI.FormatTime(seconds: number): string
	local s = math.max(0, math.floor(seconds + 0.999))
	if s >= 3600 then
		return string.format("%d:%02d:%02d", s // 3600, s // 60 % 60, s % 60)
	end
	return string.format("%d:%02d", s // 60, s % 60)
end

-- Money arrives in cents from the server (see Shared/Money).
function UI.Money(cents: number): string
	return Money.Format(cents)
end

return UI
