local _, addon = ...

---@class UnitUtil
local M = {}
addon.UnitUtil = M

function M:IsUnitInMyGroup(unit)
	return UnitIsUnit(unit, "player") or UnitInParty(unit) or UnitInRaid(unit)
end

function M:IsPet(unit)
	if UnitIsUnit(unit, "pet") then
		return true
	end

	if UnitIsOtherPlayersPet(unit) then
		return true
	end

	return false
end

function M:IsPlayerGUID(guid)
	return type(guid) == "string" and guid:match("^Player%-")
end

---@param unit string
---@return number|nil
function M:GetUnitPercent(unit)
	if not UnitExists(unit) then
		return nil
	end

	local max = UnitHealthMax(unit)

	if not max or max <= 0 then
		return nil
	end

	local cur = UnitHealth(unit)

	if cur == nil or cur < 0 then
		return nil
	end

	return cur / max
end
