--!strict
-- The loading screen (Config.Title.Loading), in place of Roblox's own: the CRAZYFARE logo, a spinning tire and a line,
-- from the moment Config arrives until the client has started every controller and the server has placed you. Then it
-- fades away over the title screen.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local title = Config.Title
local L = title.Logo
local loading = title.Loading
local player = Players.LocalPlayer
local shownAt = os.clock()

local gui = Instance.new("ScreenGui")
gui.Name = "CrazyFareLoading"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui:SetAttribute(title.KeepAttribute, true) -- the title screen never hides it

local cover = Instance.new("CanvasGroup")
cover.Size = UDim2.fromScale(1, 1)
cover.BackgroundColor3 = loading.Background
cover.BorderSizePixel = 0
cover.Parent = gui

local word = Instance.new("TextLabel")
word.AnchorPoint = Vector2.new(0.5, 0.5)
word.Position = UDim2.fromScale(0.5, 0.4)
word.Size = UDim2.new(0.8, 0, 0.14, 0)
word.BackgroundTransparency = 1
word.Font = L.Font
word.Text = L.Text
word.TextScaled = true
word.TextColor3 = Color3.new(1, 1, 1)
word.Rotation = L.Tilt
word.Parent = cover
local gradient = Instance.new("UIGradient")
gradient.Rotation = 90
gradient.Color = ColorSequence.new(L.Top, L.Bottom)
gradient.Parent = word
local stroke = Instance.new("UIStroke")
stroke.Color = L.Outline
stroke.Thickness = L.OutlineThickness
stroke.Parent = word

-- a tire: dark rubber, a gold hub, two spokes; the whole thing turns
local tire = Instance.new("Frame")
tire.AnchorPoint = Vector2.new(0.5, 0.5)
tire.Position = UDim2.fromScale(0.5, 0.62)
tire.Size = UDim2.fromOffset(64, 64)
tire.BackgroundColor3 = Color3.fromRGB(34, 34, 40)
tire.BorderSizePixel = 0
tire.Parent = cover
local round = Instance.new("UICorner")
round.CornerRadius = UDim.new(0.5, 0)
round.Parent = tire
local rim = Instance.new("UIStroke")
rim.Color = Color3.fromRGB(10, 10, 12)
rim.Thickness = 5
rim.Parent = tire
for _, angle in { 0, 90 } do
	local spoke = Instance.new("Frame")
	spoke.AnchorPoint = Vector2.new(0.5, 0.5)
	spoke.Position = UDim2.fromScale(0.5, 0.5)
	spoke.Size = UDim2.new(0.8, 0, 0, 6)
	spoke.Rotation = angle
	spoke.BackgroundColor3 = L.Bottom
	spoke.BorderSizePixel = 0
	spoke.Parent = tire
end
local hub = Instance.new("Frame")
hub.AnchorPoint = Vector2.new(0.5, 0.5)
hub.Position = UDim2.fromScale(0.5, 0.5)
hub.Size = UDim2.fromScale(0.36, 0.36)
hub.BackgroundColor3 = L.Top
hub.BorderSizePixel = 0
hub.Parent = tire
local hubRound = Instance.new("UICorner")
hubRound.CornerRadius = UDim.new(0.5, 0)
hubRound.Parent = hub

local line = Instance.new("TextLabel")
line.AnchorPoint = Vector2.new(0.5, 0)
line.Position = UDim2.new(0.5, 0, 0.62, 48)
line.Size = UDim2.fromOffset(420, 24)
line.BackgroundTransparency = 1
line.Font = Enum.Font.GothamBold
line.Text = loading.Text
line.TextSize = 18
line.TextColor3 = Color3.fromRGB(220, 220, 230)
line.Parent = cover

gui.Parent = player:WaitForChild("PlayerGui")
ReplicatedFirst:RemoveDefaultLoadingScreen()

local spin = RunService.RenderStepped:Connect(function(dt: number)
	tire.Rotation = (tire.Rotation + 360 * dt / loading.SpinSeconds) % 360
end)

if not game:IsLoaded() then
	game.Loaded:Wait()
end
local giveUp = os.clock() + loading.MaxSeconds
while os.clock() < giveUp and not (player:GetAttribute(title.BootedAttribute) == true and player:GetAttribute("SessionState") ~= nil) do
	task.wait(loading.PollSeconds)
end
local rest = loading.MinSeconds - (os.clock() - shownAt)
if rest > 0 then
	task.wait(rest)
end

local fade = TweenService:Create(cover, TweenInfo.new(title.FadeSeconds), { GroupTransparency = 1 })
fade.Completed:Once(function()
	spin:Disconnect()
	gui:Destroy()
end)
fade:Play()
