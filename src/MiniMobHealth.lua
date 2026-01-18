local _, addon = ...
---@type MiniFramework
local mini = addon.Framework
local config = addon.Config
---@type HealthTracker
local tracker = addon.Tracker

local function SetRealHealth(textString, unit)
	local hp, max = tracker:GetHealth(unit)

	if not hp or not max then
		return
	end

	local text = string.format("%s/%s", hp, max)

	textString:SetText(text)
end

local function OnUpdateTextString(textString, unit)
	if not textString or not unit then
		return
	end

	SetRealHealth(textString, unit)
end

local function OnHealthBarUpdate(statusBar, unit)
	if not statusBar or not unit then
		return
	end

	if unit ~= "target" and unit ~= "focus" then
		return
	end

	if not statusBar.TextString then
		return
	end

	SetRealHealth(statusBar.TextString, unit)

	if not statusBar.MiniMobHealthHooked and statusBar.UpdateTextString then
		hooksecurefunc(statusBar, "UpdateTextString", function()
			OnUpdateTextString(statusBar.TextString, unit)
		end)

		statusBar.MiniMobHealthHooked = true
	end
end

local function OnAddonLoaded()
	config:Init()
	tracker:Init()
end

if UnitFrameHealthBar_Update then
	hooksecurefunc("UnitFrameHealthBar_Update", OnHealthBarUpdate)
else
	mini:Notify("Update to run on this client.")
end

mini:WaitForAddonLoad(OnAddonLoaded)
