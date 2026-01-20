---@type string, Addon
local _, addon = ...
local tracker = addon.Tracker
---@class Api
local M = {}
local v1 = {}
M.v1 = v1

MiniHealthNumbersApi = M

---Returns the current and max health for the specified unit token.
---@param unit string
---@return number|nil hp
---@return number|nil max
function v1:GetHealth(unit)
	if type(unit) ~= "string" then
		return nil, nil
	end

	return tracker:GetHealth(unit)
end

---Returns the current and max health for the specified unit token.
function v1:GetHealthByGuid(guid)
	if type(guid) ~= "string" then
		return nil, nil
	end

	return tracker:GetHealthByGuid(guid)
end

---Puts the addon in passive mode where it doesn't update any text strings.
---This is so it just sits quietly in the background and you can use the API for your own addon to handle the display.
---@param addonName string the name of the addon who is putting us into passive mode
function v1:PassiveMode(addonName)
	if type(addonName) ~= "string" then
		return false
	end

	addon.PassiveModeOwner = addonName
	addon.PassiveMode = true
	return true
end

---Puts the addon into active mode where it updates text strings.
function v1:ActiveMode()
	addon.PassiveMode = false
end
