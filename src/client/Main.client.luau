--!strict
-- Client boot: Init() every controller, Start() every controller, then tell the server we are ready.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Config = require(Shared:WaitForChild("Config"))

-- Drivers have no character and walkers are respawned by the server, so the reset button stays off.
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
	require(Controllers.BountyController),
	require(Controllers.PhantomController),
	require(Controllers.WeirdoController),
	require(Controllers.EffectsController),
	require(Controllers.FruitStandController),
	require(Controllers.WeatherController),
	require(Controllers.SpeedFxController),
	require(Controllers.RiderController),
	require(Controllers.CoachController),
	require(Controllers.ArcadeController),
	require(Controllers.InviteController),
	require(Controllers.WalkerController),
	require(Controllers.DepotController),
	require(Controllers.CollectionController),
	require(Controllers.EventController),
	require(Controllers.PitStopController),
	require(Controllers.GarageController),
	require(Controllers.ProgressController),
	require(Controllers.ShopController),
	require(Controllers.RadarController),
	require(Controllers.DropController),
	require(Controllers.MapVoteController),
	require(Controllers.CalendarController),
	require(Controllers.OptionsController),
	require(Controllers.CreditsController),
	require(Controllers.TitleController),
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
-- the loading screen (ReplicatedFirst) waits for this before handing over to the title screen
game:GetService("Players").LocalPlayer:SetAttribute(Config.Title.BootedAttribute, true)
print("[CrazyFare] client ready")
