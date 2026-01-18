local _, addon = ...
addon.DebugMode = true
---@type MiniFramework
local mini = addon.Framework
local config = addon.Config
---@type HealthTracker
local tracker = addon.Tracker

local function SetRealHealth(statusBar, unit)
	local hp, max = tracker:GetHealth(unit)

	if not hp or not max then
		return
	end

	addon:DebugPrint("Tracker %s/%s, Blizzard %s/%s", hp, max, UnitHealth(unit), UnitHealthMax(unit))

	if hp == 0 then
		-- blizzard sets a "dead" text
		return
	end

	local displayMode = GetCVar("statusTextDisplay")

	if not displayMode or not STATUS_TEXT_DISPLAY_MODE then
		return
	end

	if displayMode == STATUS_TEXT_DISPLAY_MODE.PERCENT or displayMode == STATUS_TEXT_DISPLAY_MODE.NUMERIC then
		-- it doesn't make much sense with percent mode and this addon
		-- so just use real values to avoid bug reports
		if statusBar.TextString then
			local text = string.format("%s/%s", hp, max)
			statusBar.TextString:SetText(text)
			statusBar.TextString:Show()
		end
	elseif displayMode == STATUS_TEXT_DISPLAY_MODE.BOTH then
		if statusBar.LeftText then
			-- left one contains percentage
			local percentage = math.floor((hp / max) * 100)
			statusBar.LeftText:SetText(tostring(percentage) .. "%")
			statusBar.LeftText:Show()
		end

		if statusBar.RightText then
			-- right one contains the real values
			statusBar.RightText:SetText(tostring(hp))
			statusBar.RightText:Show()
		end

		if statusBar.TextString then
			statusBar.TextString:Hide()
		end
	end
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

	SetRealHealth(statusBar, unit)

	if not statusBar.MiniMobHealthHooked and statusBar.UpdateTextString then
		hooksecurefunc(statusBar, "UpdateTextString", function()
			OnUpdateTextString(statusBar, unit)
		end)

		statusBar.MiniMobHealthHooked = true
	end
end

local function OnAddonLoaded()
	config:Init()
	tracker:Init()
end

function addon:DebugPrint(msg, ...)
	if not addon.DebugMode then
		return
	end

	mini:Notify(msg, ...)
end

if UnitFrameHealthBar_Update then
	hooksecurefunc("UnitFrameHealthBar_Update", OnHealthBarUpdate)
else
	mini:Notify("Update to run on this client.")
end

mini:WaitForAddonLoad(OnAddonLoaded)
