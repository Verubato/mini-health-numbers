local _, addon = ...
---@class HealthTracker
local M = {}

addon.Tracker = M

local function IsUnitInMyGroup(unit)
	return UnitIsUnit(unit, "player") or UnitInParty(unit) or UnitInRaid(unit)
end

local function IsPet(unit)
	if UnitIsUnit(unit, "pet") then
		return true
	end

	if UnitIsOtherPlayersPet(unit) then
		return true
	end

	return false
end

function M:GetHealth(unit)
	if IsUnitInMyGroup(unit) then
		-- grouped units are reliablty calulcated
		local hp = UnitHealth(unit)
		local max = UnitHealthMax(unit)

		return hp, max
	end

	if not UnitIsPlayer(unit) and not IsPet(unit) then
		-- mobs are reliablty calulcated
		local hp = UnitHealth(unit)
		local max = UnitHealthMax(unit)

		return hp, max
	end

    -- TODO: calculate from combat logs
end

function M:Init() end
