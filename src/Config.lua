local addonName, addon = ...
---@type MiniFramework
local mini = addon.Framework

---@type Db
local db

---@class Db
local dbDefaults = {}

local M = {
	DbDefaults = dbDefaults,
}

addon.Config = M

function M:Init()
	db = mini:GetSavedVars(dbDefaults)

	local panel = CreateFrame("Frame")
	panel.name = addonName

	local category = mini:AddCategory(panel)

	if not category then
		return
	end

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 0, -16)
	title:SetText(addonName)

	local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontWhite")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	subtitle:SetText("This addon does some things.")

	SLASH_MINITEMPLATE1 = "/minitemplate"
	SLASH_MINITEMPLATE2 = "/minit"

	mini:RegisterSlashCommand(category, panel)
end
