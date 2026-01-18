local _, addon = ...
addon.DebugMode = true
---@type MiniFramework
local mini = addon.Framework
local config = addon.Config
---@type HealthTracker
local tracker = addon.Tracker
local eventsFrame
-- classic era doesn't have STATUS_TEXT_DISPLAY_MODE
local percentMode = STATUS_TEXT_DISPLAY_MODE and STATUS_TEXT_DISPLAY_MODE.PERCENT or "PERCENT"
local numericMode = STATUS_TEXT_DISPLAY_MODE and STATUS_TEXT_DISPLAY_MODE.NUMERIC or "NUMERIC"
local bothMode = STATUS_TEXT_DISPLAY_MODE and STATUS_TEXT_DISPLAY_MODE.BOTH or "BOTH"
---@type { string: WatchEntry }
local watching = {}

local function ClassicShims(statusBar)
	-- classic era doesn't have any text strings on the target frame, so let's create them
	-- blizzard is mucking around with our texts when we create them as TextString/LeftText/RightText
	-- so don't use those fields when we shim
	local font = "GameFontHighlightSmall"
	local left = statusBar.LeftText or statusBar.MhnLeftText
	local center = statusBar.TextString or statusBar.MhnTextString
	local right = statusBar.RightText or statusBar.MhnRightText

	if not left then
		local fs = statusBar:CreateFontString(nil, "OVERLAY")
		statusBar.MhnLeftText = fs

		fs:SetFontObject(font)
		fs:SetJustifyH("LEFT")
		fs:SetPoint("LEFT", statusBar, "LEFT", 6, 0)
		fs:Hide()
	end

	if not center then
		local fs = statusBar:CreateFontString(nil, "OVERLAY")
		statusBar.MhnTextString = fs

		fs:SetFontObject(font)
		fs:SetJustifyH("CENTER")
		fs:SetJustifyV("MIDDLE")
		fs:SetPoint("CENTER", statusBar, "CENTER", 0, 0)
		fs:Hide()
	end

	if not right then
		local fs = statusBar:CreateFontString(nil, "OVERLAY")
		statusBar.MhnRightText = fs

		fs:SetFontObject(font)
		fs:SetJustifyH("RIGHT")
		fs:SetPoint("RIGHT", statusBar, "RIGHT", -6, 0)
		fs:Hide()
	end
end

local function CleanStatusBar(statusBar)
	local left = statusBar.LeftText or statusBar.MhnLeftText
	local center = statusBar.TextString or statusBar.MhnTextString
	local right = statusBar.RightText or statusBar.MhnRightText

	local frames = {
		left,
		center,
		right,
	}

	for _, frame in pairs(frames) do
		frame:SetText("")
		frame:Hide()
	end
end

local function SetRealHealth(statusBar, unit)
	local hp, max = tracker:GetHealth(unit)

	if not hp or not max then
		return false
	end

	addon:DebugPrint("Tracker %s/%s, Blizzard %s/%s", hp, max, UnitHealth(unit), UnitHealthMax(unit))

	if hp == 0 then
		-- blizzard sets a "dead" text
		return false
	end

	local displayMode = GetCVar("statusTextDisplay")

	if not displayMode then
		return false
	end

	ClassicShims(statusBar)

	local left = statusBar.LeftText or statusBar.MhnLeftText
	local center = statusBar.TextString or statusBar.MhnTextString
	local right = statusBar.RightText or statusBar.MhnRightText

	if displayMode == percentMode or displayMode == numericMode then
		-- it doesn't make much sense with percent mode and this addon
		-- so just use real values to avoid bug reports
		if center then
			local text = string.format("%s/%s", hp, max)
			center:SetText(text)
			center:Show()
		end
	elseif displayMode == bothMode then
		if left then
			-- left one contains percentage
			local percentage = math.floor((hp / max) * 100)
			left:SetText(tostring(percentage) .. "%")
			left:Show()
		end

		if right then
			-- right one contains the real values
			right:SetText(tostring(hp))
			right:Show()
		end

		if center then
			center:Hide()
		end
	end

	return true
end

local function OnUpdateTextString(statusBar, unit)
	if not statusBar or not unit then
		return
	end

	SetRealHealth(statusBar, unit)
end

local function OnHealthBarUpdate(statusBar, unit)
	if not statusBar or not unit then
		return
	end

	if statusBar.IsForbidden and statusBar:IsForbidden() then
		return
	end

	if unit ~= "target" and unit ~= "focus" then
		return
	end

	local updated = SetRealHealth(statusBar, unit)

	if statusBar.UpdateTextString then
		-- this exists on TBC
		if not statusBar.MiniHealthNumbersHooked then
			hooksecurefunc(statusBar, "UpdateTextString", function()
				OnUpdateTextString(statusBar, unit)
			end)

			statusBar.MiniHealthNumbersHooked = true
		end
	else
		-- classic fallback
		watching[unit] = {
			StatusBar = statusBar,
			UnitGuid = UnitGUID(unit),
		}

		if not updated then
			-- clean up previous values
			CleanStatusBar(statusBar)
		end
	end
end

local function OnEvent()
	for unit, entry in pairs(watching) do
		local isSameUnit = entry.UnitGuid == UnitGUID(unit)

		addon:DebugPrint("Manually updating status bar for unit %s, same unit %s.", unit, tostring(isSameUnit))

		if isSameUnit and entry.StatusBar:IsVisible() then
			OnHealthBarUpdate(entry.StatusBar, unit)
		else
			-- they may have changed target, clean up previous values
			CleanStatusBar(entry.StatusBar)
			-- the bar no longer exists or the target has changed
			watching[unit] = nil
		end
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

eventsFrame = CreateFrame("Frame")
eventsFrame:RegisterEvent("UNIT_HEALTH")
eventsFrame:SetScript("OnEvent", OnEvent)

mini:WaitForAddonLoad(OnAddonLoaded)

---@class WatchEntry
---@field StatusBar table
---@field UnitGuid string
