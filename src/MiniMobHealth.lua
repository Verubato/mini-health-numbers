local _, addon = ...
---@type MiniFramework
local mini = addon.Framework
local config = addon.Config
local eventsFrame

local function SetRealHealth(textString, unit)
	if UnitIsPlayer(unit) then
		-- TODO: In classic/tbc UnitHealth returns percentage for players
		-- so we'd need to calculate it from combat log events
		return
	end

	local hp = UnitHealth(unit)
	local max = UnitHealthMax(unit)
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

	eventsFrame = CreateFrame("Frame")
	eventsFrame:SetScript("OnEvent", OnEvent)
	eventsFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
end

if UnitFrameHealthBar_Update then
	hooksecurefunc("UnitFrameHealthBar_Update", OnHealthBarUpdate)
else
	mini:Notify("Update to run on this client.")
end

mini:WaitForAddonLoad(OnAddonLoaded)
