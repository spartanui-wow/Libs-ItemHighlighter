local addonName, root = ... --[[@type string, table]]
local addon = root.Core
local Log = root.Log

---@class BagnonIntegration
local BagnonIntegration = {
	name = 'Bagnon',
}

-- Store item button widgets that we've created
local itemButtonWidgets = {}

-- Check if Bagnon is available
function BagnonIntegration:IsAvailable()
	local available = Bagnon ~= nil and Bagnon.NewModule ~= nil
	Log('Bagnon availability check: ' .. tostring(available))
	return available
end

-- Helper function to check if Bagnon frames are visible
function BagnonIntegration:AreBagsVisible()
	if not Bagnon then
		return false
	end

	-- Check for visible Bagnon frames using common patterns
	local framePatterns = {
		'BagnonFrameinventory',
		'BagnonFramebank',
		'BagnonFrameguild',
		'BagnonFramekeys',
		'BagnonFramevoid',
		'BagnonFramereagent',
	}

	for _, frameName in ipairs(framePatterns) do
		local frame = _G[frameName]
		if frame and frame:IsVisible() then
			Log('Found visible Bagnon frame: ' .. frameName, 'debug')
			return true
		end
	end

	-- Also check Bagnon's frame management system if available
	if Bagnon.Frames and Bagnon.Frames.frames then
		for frameId, frame in pairs(Bagnon.Frames.frames) do
			if frame and frame:IsVisible() then
				Log('Found visible Bagnon frame via Frames system: ' .. tostring(frameId), 'debug')
				return true
			end
		end
	end

	-- If we're processing items and getting updates, bags are probably visible
	-- This is a fallback since Bagnon only calls our updater when frames are active
	if Bagnon.Item then
		Log('No visible frames found but Bagnon.Item exists - assuming bags are visible', 'debug')
		return true
	end

	Log('No visible Bagnon frames found', 'debug')
	return false
end

-- Function to create our highlight widget on an item button
local function CreateHighlightWidget(itemButton)
	if not itemButton or itemButtonWidgets[itemButton] then
		return itemButtonWidgets[itemButton]
	end

	local widget = root.Animation.CreateIndicatorFrame(itemButton)
	itemButtonWidgets[itemButton] = widget
	Log('Created highlight widget for Bagnon item button', 'debug')
	return widget
end

-- Main updater function called by Bagnon for each item button
-- This follows the exact pattern from Bagnon_BoE and other Bagnon plugins
local function BagnonItemUpdater(itemButton)
	-- Early exit if all highlighting features are disabled
	if not addon.DB.ShowGlow and not addon.DB.ShowIndicator then
		-- Hide any existing widget
		local widget = itemButtonWidgets[itemButton]
		if widget then
			widget:Hide()
		end
		return
	end

	-- Handle empty slots - hide any existing widget
	if not itemButton.hasItem then
		local widget = itemButtonWidgets[itemButton]
		if widget then
			widget:Hide()
		end
		return
	end

	-- Get item information from Bagnon's item button structure
	local bagID = itemButton:GetBag()
	local slotID = itemButton:GetID()
	local itemLink = itemButton.info and itemButton.info.hyperlink

	-- Fallback to WoW API if hyperlink not available in button
	if not itemLink and bagID and slotID then
		itemLink = C_Container.GetContainerItemLink(bagID, slotID)
	end

	-- Check if this item is openable BEFORE creating any widgets
	if itemLink then
		local itemDetails = {
			itemLink = itemLink,
			bagID = bagID,
			slotID = slotID,
		}

		-- Use our core checking function to determine if item is openable
		local isOpenable = root.CheckItem(itemDetails)

		if isOpenable then
			-- Item is openable - get or create widget
			local widget = itemButtonWidgets[itemButton]
			if not widget then
				widget = CreateHighlightWidget(itemButton)
			end

			Log('Updating Bagnon highlight for openable item: ' .. itemLink, 'debug')
			root.Animation.UpdateIndicatorFrame(widget, itemDetails)

			-- Ensure animation timer is running when we have openable items
			root.Animation.StartGlobalTimer()
		else
			-- Item is not openable - hide any existing widget
			local widget = itemButtonWidgets[itemButton]
			if widget then
				widget:Hide()
			end
		end
	else
		-- No item link available, hide any existing widget
		local widget = itemButtonWidgets[itemButton]
		if widget then
			widget:Hide()
		end
	end
end

-- Function to refresh all widgets after settings changes
local function RefreshAllWidgets()
	addon:ScheduleTimer(function()
		Log('Refreshing all Bagnon widgets due to settings change')

		-- Clear existing widgets
		for itemButton, widget in pairs(itemButtonWidgets) do
			if widget then
				widget:Hide()
			end
		end
		wipe(itemButtonWidgets)

		-- The Bagnon module system will automatically call our updater
		-- for all visible item buttons when they refresh
		addon:SendMessage('BAG_UPDATE_DELAYED')
	end, 0.1)
end

function BagnonIntegration:OnEnable()
	if not self:IsAvailable() then
		Log('Bagnon not available during OnEnable', 'warning')
		return
	end

	Log('Bagnon integration enabled')

	-- Hook into Bagnon's item update system
	-- This is how Bagnon_BoE and other plugins actually work
	if Bagnon.Item then
		-- Find the correct update method to hook
		local method = Bagnon.Item.UpdateSecondary and 'UpdateSecondary' or Bagnon.Item.UpdatePrimary and 'UpdatePrimary' or Bagnon.Item.Update and 'Update'

		if method then
			hooksecurefunc(Bagnon.Item, method, BagnonItemUpdater)
			Log('Hooked Bagnon.Item.' .. method .. ' successfully')
		else
			Log('Could not find Bagnon.Item update method to hook', 'error')
			return
		end
	else
		Log('Bagnon.Item not found', 'error')
		return
	end

	-- Hook into bag visibility events for animation timer management
	addon:RegisterMessage('BAG_UPDATE_DELAYED', function()
		if self:AreBagsVisible() then
			Log('Bagnon bags visible - starting animation timer', 'debug')
			root.Animation.StartGlobalTimer()
		else
			Log('Bagnon bags hidden - stopping animation timer', 'debug')
			root.Animation.StopGlobalTimer()
		end
	end)

	-- Hook bag toggle functions to detect when bags are opened/closed
	local function OnBagToggle()
		addon:ScheduleTimer(function()
			if self:AreBagsVisible() then
				root.Animation.StartGlobalTimer()
			else
				root.Animation.StopGlobalTimer()
			end
		end, 0.1)
	end

	hooksecurefunc('ToggleBackpack', OnBagToggle)
	hooksecurefunc('ToggleBag', OnBagToggle)
	hooksecurefunc('ToggleAllBags', OnBagToggle)

	-- Hook Bagnon-specific frame toggle if available
	if Bagnon.Frames and Bagnon.Frames.Toggle then
		hooksecurefunc(Bagnon.Frames, 'Toggle', OnBagToggle)
	end
end

function BagnonIntegration:OnDisable()
	Log('Bagnon integration disabling')
	root.Animation.StopGlobalTimer()

	-- Clean up all widgets
	for itemButton, widget in pairs(itemButtonWidgets) do
		if widget then
			widget:Hide()
		end
	end
	wipe(itemButtonWidgets)
end

-- Store refresh function for options
BagnonIntegration.RefreshAllWidgets = RefreshAllWidgets

-- Register this bag system
addon:RegisterBagSystem('bagnon', BagnonIntegration)
