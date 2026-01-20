local addonName, root = ... --[[@type string, table]]
local addon = root.Core
local Log = root.Log

---@class BetterBagsIntegration
local BetterBagsIntegration = {
	name = 'BetterBags'
}

-- Module references for BetterBags integration
local categoriesModule = nil
local configModule = nil

-- Check if BetterBags is available
function BetterBagsIntegration:IsAvailable()
	Log('BetterBags IsAvailable check starting', 'info')

	-- Check if LibStub is available first
	if not LibStub then
		Log('LibStub not found - cannot check for BetterBags', 'info')
		return false
	end

	-- Try to get BetterBags addon directly (same pattern as working BetterBags plugins)
	local success, betterBagsAddon = pcall(function()
		return LibStub('AceAddon-3.0'):GetAddon('BetterBags')
	end)

	if not success then
		Log('Failed to get BetterBags addon via LibStub: ' .. tostring(betterBagsAddon), 'info')
		return false
	end

	if not betterBagsAddon then
		Log('BetterBags addon object is nil', 'info')
		return false
	end

	Log('BetterBags addon object found successfully', 'info')

	-- Test if we can access the GetModule method (AceAddon pattern)
	local hasGetModule = betterBagsAddon.GetModule ~= nil
	Log('BetterBags GetModule availability: ' .. tostring(hasGetModule), 'info')

	-- Also check if we can access a known module to verify functionality
	if hasGetModule then
		local moduleSuccess, itemFrame = pcall(function()
			return betterBagsAddon:GetModule('ItemFrame')
		end)
		Log('BetterBags ItemFrame module test: ' .. tostring(moduleSuccess), 'info')

		if moduleSuccess and itemFrame then
			-- Also get Categories and Config modules for category system
			local catSuccess, categories = pcall(function()
				return betterBagsAddon:GetModule('Categories')
			end)
			if catSuccess and categories then
				categoriesModule = categories
				Log('BetterBags Categories module found', 'info')
			end

			local configSuccess, config = pcall(function()
				return betterBagsAddon:GetModule('Config')
			end)
			if configSuccess and config then
				configModule = config
				Log('BetterBags Config module found', 'info')
			end

			Log('BetterBags is available and ready for integration', 'info')
			return true
		else
			Log('BetterBags found but modules not accessible', 'info')
			return false
		end
	else
		Log('BetterBags found but GetModule method missing', 'info')
		return false
	end
end

-- Helper function to check if BetterBags frames are visible
function BetterBagsIntegration:AreBagsVisible()
	-- Try to access the main BetterBags addon to check bag visibility
	local success, betterBagsAddon = pcall(function()
		return LibStub('AceAddon-3.0'):GetAddon('BetterBags')
	end)

	if success and betterBagsAddon and betterBagsAddon.Bags then
		-- Check if Backpack bag is visible (calls IsShown() method)
		if betterBagsAddon.Bags.Backpack and type(betterBagsAddon.Bags.Backpack.IsShown) == "function" then
			local backpackVisible = betterBagsAddon.Bags.Backpack:IsShown()
			Log('BetterBags Backpack visibility: ' .. tostring(backpackVisible), 'info')
			if backpackVisible then
				return true
			end
		else
			Log('BetterBags Backpack not available or no IsShown method', 'info')
		end

		-- Check if Bank bag is visible (calls IsShown() method)
		if betterBagsAddon.Bags.Bank and type(betterBagsAddon.Bags.Bank.IsShown) == "function" then
			local bankVisible = betterBagsAddon.Bags.Bank:IsShown()
			Log('BetterBags Bank visibility: ' .. tostring(bankVisible), 'info')
			if bankVisible then
				return true
			end
		else
			Log('BetterBags Bank not available or no IsShown method', 'info')
		end
	end

	Log('No BetterBags frames visible', 'debug')
	return false
end

-- Store item button widgets that we've created
local itemButtonWidgets = {}

-- Helper function to generate category color prefix
local function GetCategoryPrefix()
	if not addon.DB or not addon.DB.BetterBags_CategoryColor then
		return '|cff2beefd'  -- Default cyan
	end
	local color = addon.DB.BetterBags_CategoryColor
	local r = math.floor(color.r * 255 + 0.5)
	local g = math.floor(color.g * 255 + 0.5)
	local b = math.floor(color.b * 255 + 0.5)
	return string.format('|cff%02x%02x%02x', r, g, b)
end

-- Category filter function for BetterBags integration
---@param data ItemData BetterBags item data
---@return string|nil categoryName The category name or nil
local function BetterBagsCategoryFilter(data)
	-- Check if category system is enabled
	if not addon.DB or not addon.DB.BetterBags_EnableCategories then
		return nil
	end

	-- Get item link
	local itemLink = C_Container.GetContainerItemLink(data.bagid, data.slotid)
	if not itemLink then
		return nil
	end

	-- Convert to our format
	local itemDetails = {
		itemLink = itemLink,
		bagID = data.bagid,
		slotID = data.slotid
	}

	-- Get category from enhanced CheckItem function
	local categoryType = root.CheckItemWithCategory(itemDetails)

	if categoryType then
		return GetCategoryPrefix() .. categoryType
	end

	return nil
end

-- Function to create our highlight widget on an item button
local function CreateHighlightWidget(itemButton)
	if not itemButton or itemButtonWidgets[itemButton] then
		return itemButtonWidgets[itemButton]
	end

	local widget = root.Animation.CreateIndicatorFrame(itemButton)
	itemButtonWidgets[itemButton] = widget
	return widget
end

-- Function to update highlight widget based on item data
local function UpdateHighlightWidget(itemButton, itemData)
	if not itemButton or not itemData then
		return
	end

	local widget = itemButtonWidgets[itemButton]
	if not widget then
		widget = CreateHighlightWidget(itemButton)
	end

	-- Convert BetterBags itemData to our expected format
	local itemDetails = {
		itemLink = itemData.itemLink,
		bagID = itemData.bagID or itemData.bagid,  -- Handle both cases
		slotID = itemData.slotID or itemData.slotid  -- Handle both cases
	}

	root.Animation.UpdateIndicatorFrame(widget, itemDetails)
end

-- Function to hook into BetterBags item button creation and updates
local function HookBetterBagsItemButtons()
	-- Try to hook the ItemFrame module that handles SetItem calls
	local success, ItemFrame = pcall(function()
		local betterBagsAddon = LibStub('AceAddon-3.0'):GetAddon('BetterBags')
		return betterBagsAddon:GetModule('ItemFrame')
	end)

	if success and ItemFrame and ItemFrame.itemProto then
		Log('Found BetterBags ItemFrame module')

		-- Hook the SetItem method which is called for all item button updates
		if ItemFrame.itemProto.SetItem then
			hooksecurefunc(ItemFrame.itemProto, 'SetItem', function(self, ctx, slotkey)
				if self and slotkey and (addon.DB.ShowGlow or addon.DB.ShowIndicator) then
					-- BetterBags uses underscore format: "bagID_slotID"
					local bagID, slotID = slotkey:match("^(%d+)_(%d+)$")
					if bagID and slotID then
						local numBagID = tonumber(bagID)
						local numSlotID = tonumber(slotID)
						local itemLink = C_Container.GetContainerItemLink(numBagID, numSlotID)

						-- Only process if we have an actual item (itemLink exists)
						if itemLink then
							local itemData = {
								bagID = numBagID,
								slotID = numSlotID,
								itemLink = itemLink
							}
							UpdateHighlightWidget(self.button or self.frame, itemData)
						end
					end
				end
			end)
			Log('Hooked BetterBags ItemFrame SetItem')
		end

		-- Also hook SetItemFromData for completeness
		if ItemFrame.itemProto.SetItemFromData then
			hooksecurefunc(ItemFrame.itemProto, 'SetItemFromData', function(self, ctx, data)
				if self and data and (addon.DB.ShowGlow or addon.DB.ShowIndicator) then
					-- Get itemLink from container if not provided in data
					local itemLink = data.itemLink
					if not itemLink and data.bagid and data.slotid then
						itemLink = C_Container.GetContainerItemLink(data.bagid, data.slotid)
					end

					-- Only process if we have an actual item
					if itemLink then
						local itemData = {
							bagID = data.bagid,
							slotID = data.slotid,
							itemLink = itemLink
						}
						UpdateHighlightWidget(self.button or self.frame, itemData)
					end
				end
			end)
			Log('Hooked BetterBags ItemFrame SetItemFromData')
		end
	else
		Log('Failed to find BetterBags ItemFrame module', 'warning')
	end
end

-- Function to refresh all widgets after settings changes
local function RefreshAllWidgets()
	addon:ScheduleTimer(function()
		if not BetterBags then
			Log('BetterBags not available, skipping refresh')
			return
		end

		Log('Refreshing all BetterBags widgets due to settings change')

		-- Clear existing widgets
		for itemButton, widget in pairs(itemButtonWidgets) do
			if widget and widget:IsShown() then
				widget:Hide()
			end
		end
		wipe(itemButtonWidgets)

		-- Force BetterBags to refresh by triggering bag updates
		local success, betterBagsAddon = pcall(function()
			return LibStub('AceAddon-3.0'):GetAddon('BetterBags')
		end)

		if success and betterBagsAddon and betterBagsAddon.Bags then
			-- Trigger a refresh on the visible bags
			if betterBagsAddon.Bags.Backpack and betterBagsAddon.Bags.Backpack.IsShown and betterBagsAddon.Bags.Backpack:IsShown() then
				-- Force a redraw by simulating bag updates
				local Events = betterBagsAddon:GetModule('Events')
				if Events and Events.SendMessage then
					local Context = betterBagsAddon:GetModule('Context')
					if Context then
						local ctx = Context:New('RefreshAllWidgets')
						Events:SendMessage(ctx, 'bags/FullRefreshAll')
					end
				end
			end
			Log('Triggered BetterBags bag refresh')
		end

		-- Also try to trigger a general bag update
		addon:ScheduleTimer(function()
			addon:SendMessage("BAG_UPDATE_DELAYED")
		end, 0.1)
	end, 0.1)
end

function BetterBagsIntegration:OnEnable()
	if not self:IsAvailable() then
		Log('BetterBags not available during OnEnable', 'warning')
		return
	end

	Log('BetterBags integration enabled')

	-- Register category function if modules are available
	if categoriesModule and addon.DB.BetterBags_EnableCategories then
		categoriesModule:RegisterCategoryFunction('libs-itemhighlighter', BetterBagsCategoryFilter)
		Log('Registered BetterBags category function', 'info')
	end

	-- Register plugin config if available
	if configModule then
		local pluginOptions = {
			name = "Lib's Item Highlighter",
			type = 'group',
			args = {
				description = {
					type = 'description',
					name = 'Category system is configured in the main Item Highlighter options (/libsih).\n\nYou can enable/disable the category system and customize category colors there.',
					order = 1
				}
			}
		}
		configModule:AddPluginConfig("Lib's Item Highlighter", pluginOptions)
		Log('Registered BetterBags plugin config', 'info')
	end

	-- Set up hooks for item button updates
	HookBetterBagsItemButtons()

	-- Hook Blizzard bag functions that might open BetterBags
	local function OnBagToggle(source)
		Log('Bag toggle called from: ' .. (source or 'unknown') .. ' - checking bag state after delay')
		addon:ScheduleTimer(function()
			if self:AreBagsVisible() then
				Log('Bags are visible after Blizzard toggle - starting timer')
				root.Animation.StartGlobalTimer()
			else
				Log('Bags are hidden after Blizzard toggle - stopping timer')
				root.Animation.StopGlobalTimer()
			end
		end, 0.1)
	end

	-- Hook into BetterBags events for bag visibility changes
	addon:RegisterMessage("BAG_UPDATE_DELAYED", function()
		if self:AreBagsVisible() then
			Log('Bags are visible - starting timer')
			root.Animation.StartGlobalTimer()
		else
			Log('Bags are hidden - stopping timer')
			root.Animation.StopGlobalTimer()
		end
	end)

	-- Try to hook BetterBags internal events for bag open/close
	local success, betterBagsAddon = pcall(function()
		return LibStub('AceAddon-3.0'):GetAddon('BetterBags')
	end)

	if success and betterBagsAddon then
		local Events = betterBagsAddon:GetModule('Events')
		if Events and Events.RegisterMessage then
			-- Hook bag show/hide events
			Events:RegisterMessage('bags/OpenClose', function()
				Log('BetterBags bags/OpenClose event fired')
				OnBagToggle('BetterBags-Event')
			end)
			Log('Registered for BetterBags bags/OpenClose events')
		end
	end

	-- Hook the same functions that might trigger BetterBags
	hooksecurefunc('ToggleBackpack', function() OnBagToggle('ToggleBackpack') end)
	hooksecurefunc('ToggleBag', function() OnBagToggle('ToggleBag') end)
	hooksecurefunc('ToggleAllBags', function() OnBagToggle('ToggleAllBags') end)

	-- Hook BetterBags specific functions (reuse existing betterBagsAddon)
	if success and betterBagsAddon then
		-- Hook the main BetterBags toggle method
		if betterBagsAddon.ToggleAllBags then
			hooksecurefunc(betterBagsAddon, 'ToggleAllBags', function() OnBagToggle('BetterBags-ToggleAllBags') end)
			Log('Hooked BetterBags ToggleAllBags method')
		end

		-- Hook global BetterBags toggle function if it exists
		if _G.BetterBags_ToggleBags then
			hooksecurefunc('BetterBags_ToggleBags', function() OnBagToggle('BetterBags_ToggleBags') end)
			Log('Hooked BetterBags_ToggleBags global function')
		end
	end
end

function BetterBagsIntegration:OnDisable()
	Log('BetterBags integration disabling')
	root.Animation.StopGlobalTimer()
end

-- Store refresh function for options
BetterBagsIntegration.RefreshAllWidgets = RefreshAllWidgets

-- Register this bag system
addon:RegisterBagSystem('betterbags', BetterBagsIntegration)