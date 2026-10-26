--!strict
-- Client boot: Init() every controller, Start() every controller, then tell the server we are ready.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

-- No character, so the reset button has nothing to reset.
task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCore("ResetButtonCallback", false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
		end)
		if ok then
			return
		end
		task.wait(0.5)
	end
end)

type Controller = { Init: () -> (), Start: () -> () }

local Controllers = script.Parent.Controllers
local ordered: { Controller } = {
	require(Controllers.NetController),
	require(Controllers.InputController),
	require(Controllers.VehicleController),
	require(Controllers.CameraController),
	require(Controllers.HudController),
	require(Controllers.MinimapController),
	require(Controllers.WorldTagController),
	require(Controllers.EffectsController),
	require(Controllers.PitStopController),
	require(Controllers.GarageController),
	require(Controllers.ProgressController),
	require(Controllers.ShopController),
	require(Controllers.SoundController),
}
if RunService:IsStudio() then
	table.insert(ordered, require(Controllers.DebugPanel))
end

for _, controller in ordered do
	controller.Init()
end
for _, controller in ordered do
	controller.Start()
end

Remotes.Get("ClientReady"):FireServer()
print("[CrazyFare] client ready")
