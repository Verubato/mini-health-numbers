local _, addon = ...

---@class Numerics
local M = {}
addon.Numerics = M

---Clamps a value between the minimum and maximum value such that the return value is never less than min, and never greater than max.
---@param x number
---@param min number
---@param max number
---@return number
function M:Clamp(x, min, max)
	if x < min then
		return min
	end

	if x > max then
		return max
	end

	return x
end

---Returns 0 if the value is not a number, otherwise the number itself.
---@param x number
---@return number
function M:ToNumberOrZero(x)
	local n = tonumber(x)

	if not n then
		return 0
	end

	return n
end

---Returns 0 if the number is below 0, otherwise the number itself.
---@param x number
---@return number
function M:NonNegativeOrZero(x)
	local n = tonumber(x)

	if not n or n < 0 then
		return 0
	end

	return n
end

---Linear interpolation.
---@param current number
---@param target number
---@param speed number 0..1
---@return number
function M:Lerp(current, target, speed)
	return current + (target - current) * speed
end
