---@type string, Addon
local _, addon = ...
addon.DebugMode = false
addon.PassiveMode = false

local mini = addon.Framework
local config = addon.Config
local tracker = addon.Tracker
local numerics = addon.Numerics
local eventsFrame
-- classic era doesn't have STATUS_TEXT_DISPLAY_MODE
local percentMode = STATUS_TEXT_DISPLAY_MODE and STATUS_TEXT_DISPLAY_MODE.PERCENT or "PERCENT"
local numericMode = STATUS_TEXT_DISPLAY_MODE and STATUS_TEXT_DISPLAY_MODE.NUMERIC or "NUMERIC"
local bothMode = STATUS_TEXT_DISPLAY_MODE and STATUS_TEXT_DISPLAY_MODE.BOTH or "BOTH"
---@type { string: WatchEntry }
local watching = {}
---@type Db
local db

local function IsClassic()
	return LE_EXPANSION_LEVEL_CURRENT ~= nil
		and LE_EXPANSION_CLASSIC ~= nil
		and LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_CLASSIC
end

local function ClassicShims(statusBar)
	-- classic era doesn't have any text strings on the target frame, so let's create them
	-- blizzard is mucking around with our texts when we create them as TextString/LeftText/RightText
	-- so don't use those fields when we shim
	local font = "TextStatusBarText"
	local left = statusBar.MhnLeftText
	local center = statusBar.MhnTextString
	local right = statusBar.MhnRightText
	-- in classic the target frame health bar strata is too low
	-- so we make an overlay to fix that
	local overlay = statusBar.MhnOverlay

	if not overlay then
		overlay = CreateFrame("Frame", nil, statusBar)
		overlay:SetFrameLevel(statusBar:GetParent():GetFrameLevel() + 1)
		statusBar.MhnOverlay = overlay
	end

	if not left then
		local fs = overlay:CreateFontString(nil, "OVERLAY")
		statusBar.MhnLeftText = fs

		fs:SetFontObject(font)
		fs:SetJustifyH("LEFT")
		fs:SetPoint("LEFT", statusBar, "LEFT", 0, 0)
		fs:Hide()
	end

	if not center then
		local fs = overlay:CreateFontString(nil, "OVERLAY")
		statusBar.MhnTextString = fs

		fs:SetFontObject(font)
		fs:SetJustifyH("CENTER")
		fs:SetJustifyV("MIDDLE")
		fs:SetPoint("CENTER", statusBar, "CENTER", 0, 0)
		fs:Hide()
	end

	if not right then
		local fs = overlay:CreateFontString(nil, "OVERLAY")
		statusBar.MhnRightText = fs

		fs:SetFontObject(font)
		fs:SetJustifyH("RIGHT")
		fs:SetPoint("RIGHT", statusBar, "RIGHT", -6, 0)
		fs:Hide()
	end
end

local function CleanTextShims(statusBar)
	local left = statusBar.MhnLeftText
	local center = statusBar.MhnTextString
	local right = statusBar.MhnRightText

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

	addon:DebugPrint("Addon %s/%s, Blizzard %s/%s", hp or "nil", max or "nil", UnitHealth(unit), UnitHealthMax(unit))

	if not hp or not max then
		return false
	end

	if hp == 0 then
		if IsClassic() then
			CleanTextShims(statusBar)
		end

		-- blizzard sets a "dead" text
		return false
	end

	local hpAbbreviated = numerics:Abbreviate(hp)
	local maxAbbreviated = numerics:Abbreviate(max)

	local displayMode = GetCVar("statusTextDisplay")

	if not displayMode then
		return false
	end

	if IsClassic() then
		ClassicShims(statusBar)
	end

	local left = statusBar.LeftText or statusBar.MhnLeftText
	local center = statusBar.TextString or statusBar.MhnTextString
	local right = statusBar.RightText or statusBar.MhnRightText

	if displayMode == percentMode or displayMode == numericMode then
		-- it doesn't make much sense with percent mode and this addon
		-- so just use real values to avoid bug reports
		if center then
			local text

			if db.ExcludeMax then
				text = tostring(hpAbbreviated)
			else
				text = string.format("%s / %s", hpAbbreviated, maxAbbreviated)
			end

			center:SetText(text)
			center:Show()
		end

		return true
	elseif displayMode == bothMode then
		if left then
			-- left one contains percentage
			local percentage = math.floor((hp / max) * 100)
			left:SetText(tostring(percentage) .. "%")
			left:Show()
		end

		if right then
			-- right one contains the real values
			right:SetText(hpAbbreviated)
			right:Show()
		end

		if center then
			center:Hide()
		end

		return true
	end

	return false
end

local function OnUpdateTextString(statusBar)
	if addon.PassiveMode then
		return
	end

	if not statusBar or not statusBar.unit then
		return
	end

	if statusBar.IsForbidden and statusBar:IsForbidden() then
		return
	end

	local unit = statusBar.unit

	if unit ~= "target" and unit ~= "focus" then
		return
	end

	SetRealHealth(statusBar, unit)
end

local function OnHealthBarUpdate(statusBar, unit)
	if addon.PassiveMode then
		return
	end

	if not statusBar or not unit then
		return
	end

	if statusBar.IsForbidden and statusBar:IsForbidden() then
		return
	end

	-- prepare our hooks/watcher
	if statusBar.UpdateTextString then
		-- this exists on TBC
		if not statusBar.MiniHealthNumbersHooked then
			hooksecurefunc(statusBar, "UpdateTextString", OnUpdateTextString)

			statusBar.MiniHealthNumbersHooked = true
		end
	elseif IsClassic() then
		-- classic fallback
		watching[unit] = {
			StatusBar = statusBar,
			UnitGuid = UnitGUID(unit),
		}
	else
		addon:DebugPrint("Unsupported client.")
		return
	end

	-- only update target and focus
	if statusBar.unit ~= unit or (unit ~= "target" and unit ~= "focus") then
		return
	end

	if not SetRealHealth(statusBar, unit) and IsClassic() then
		-- clean up previous values
		CleanTextShims(statusBar)
	end
end

local function OnEvent()
	if addon.PassiveMode then
		return
	end

	for unit, entry in pairs(watching) do
		local isSameUnit = entry.UnitGuid == UnitGUID(unit)

		if isSameUnit and entry.StatusBar:IsVisible() then
			OnHealthBarUpdate(entry.StatusBar, entry.StatusBar.unit)
		else
			-- they may have changed target, clean up previous values
			CleanTextShims(entry.StatusBar)
			-- the bar no longer exists or the target has changed
			watching[unit] = nil
		end
	end
end

local function OnAddonLoaded()
	config:Init()
	tracker:Init()

	db = mini:GetSavedVars()

	if IsClassic() and TargetFrame and TargetFrame.healthbar then
		ClassicShims(TargetFrame.healthbar)
	end
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

if IsClassic() then
	eventsFrame = CreateFrame("Frame")
	eventsFrame:RegisterEvent("UNIT_HEALTH")
	eventsFrame:SetScript("OnEvent", OnEvent)
end

mini:WaitForAddonLoad(OnAddonLoaded)

---@class Addon
---@field PassiveMode boolean
---@field PassiveModeOwner string
---@field DebugMode boolean
---@field Framework MiniFramework
---@field Tracker HealthTracker
---@field UnitUtil UnitUtil
---@field Numerics Numerics
---@field CombatLogParser CombatLogParser
---@field Config Config
---@field DebugPrint fun(self: table, msg: string, ...)

---@class WatchEntry
---@field StatusBar table
---@field UnitGuid string
