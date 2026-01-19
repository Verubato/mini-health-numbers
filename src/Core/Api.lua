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
