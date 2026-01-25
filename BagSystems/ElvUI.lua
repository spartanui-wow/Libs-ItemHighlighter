local addonName, root = ... --[[@type string, table]]
local addon = root.Core
local Log = root.Log

---@class ElvUIIntegration
local ElvUIIntegration = {
	name = 'ElvUI',
}

-- Check if ElvUI is available
function ElvUIIntegration:IsAvailable()
	return ElvUI ~= nil and ElvUI[1] ~= nil and ElvUI[1].GetModule ~= nil
end

-- Helper function to check if ElvUI bag frames are visible
function ElvUIIntegration:AreBagsVisible()
	if not ElvUI then
		return false
	end

	local E = unpack(ElvUI)
	if not E then
		return false
	end

	local B = E:GetModule('Bags', true)
	if not B then
		return false
	end

	-- Check ElvUI bag frames
	local frames = {
		B.BagFrame,
		B.BankFrame,
	}

	for _, frame in ipairs(frames) do
		if frame and frame:IsVisible() then
			return true
		end
	end

	return false
end

-- Store item button widgets that we've created
local itemButtonWidgets = {}

-- Function to create our highlight widget on an item button
local function CreateHighlightWidget(itemButton)
	if not itemButton or itemButtonWidgets[itemButton] then
		return itemButtonWidgets[itemButton]
	end

	local widget = root.Animation.CreateIndicatorFrame(itemButton)
	itemButtonWidgets[itemButton] = widget
	return widget
end

-- Function to update highlight widget based on item details
local function UpdateHighlightWidget(itemButton)
	if not itemButton or (not addon.DB.ShowGlow and not addon.DB.ShowIndicator) then
		return
	end

	local widget = itemButtonWidgets[itemButton]
	if not widget then
		widget = CreateHighlightWidget(itemButton)
	end

	-- Get item details from the ElvUI button
	local bagID = itemButton.bagID or itemButton.bag
	local slotID = itemButton.slotID or itemButton:GetID()
	local itemLink = itemButton.itemLink

	-- Try to get item link if not available directly
	if not itemLink and bagID and slotID then
		itemLink = C_Container.GetContainerItemLink(bagID, slotID)
	end

	if itemLink then
		local itemDetails = {
			itemLink = itemLink,
			bagID = bagID,
			slotID = slotID,
		}

		root.Animation.UpdateIndicatorFrame(widget, itemDetails)
	else
		-- Hide widget if no item
		if widget then
			widget:Hide()
		end
	end
end

-- Function to hook into ElvUI bag system
local function HookElvUIBagSystem()
	if not ElvUI then
		return
	end

	local E = unpack(ElvUI)
	if not E then
		return
	end

	local B = E:GetModule('Bags', true)
	if not B then
		Log('ElvUI Bags module not found', 'warning')
		return
	end

	Log('Setting up ElvUI Bags hooks')

	-- Hook the UpdateSlot function which updates individual item buttons
	if B.UpdateSlot then
		hooksecurefunc(B, 'UpdateSlot', function(self, frame, bagID, slotID)
			if frame and frame.Bags then
				local slot = frame.Bags[bagID] and frame.Bags[bagID][slotID]
				if slot and slot.itemLink then
					-- Add our slot data for easier access
					slot.bagID = bagID
					slot.slotID = slotID
					UpdateHighlightWidget(slot)
				end
			end
		end)
		Log('Hooked ElvUI B:UpdateSlot')
	end

	-- Hook slot updates when bags are refreshed
	if B.UpdateBagSlots then
		hooksecurefunc(B, 'UpdateBagSlots', function(self, frame, bagID)
			local success, result = pcall(function()
				if frame and frame.Bags and frame.Bags[bagID] then
					for slotID, slot in pairs(frame.Bags[bagID]) do
						-- Check if slot is a frame object with GetBagID/GetID methods (ElvUI pattern)
						if slot and type(slot) == 'table' and slot.GetBagID and slot.GetID then
							local bagId = slot:GetBagID()
							local slotId = slot:GetID()
							local itemLink = C_Container.GetContainerItemLink(bagId, slotId)

							if itemLink then
								local itemData = {
									bagID = bagId,
									slotID = slotId,
									itemLink = itemLink,
								}
								UpdateHighlightWidget(slot, itemData)
							end
						elseif slot and type(slot) == 'table' and slot.itemLink then
							-- Fallback for table-based slots
							slot.bagID = bagID
							slot.slotID = slotID
							UpdateHighlightWidget(slot)
						end
					end
				end
			end)
			if not success then
				Log('ElvUI UpdateBagSlots hook error (non-critical): ' .. tostring(result), 'debug')
			end
		end)
		Log('Hooked ElvUI B:UpdateBagSlots')
	end

	-- Hook the broader UpdateAllSlots function
	if B.UpdateAllSlots then
		hooksecurefunc(B, 'UpdateAllSlots', function(self, frame)
			local success, result = pcall(function()
				if not frame or not frame.Bags then
					return
				end

				for bagID, bag in pairs(frame.Bags) do
					if bag then
						for slotID, slot in pairs(bag) do
							-- Check if slot is a frame object with GetBagID/GetID methods (ElvUI pattern)
							if slot and type(slot) == 'table' and slot.GetBagID and slot.GetID then
								local bagId = slot:GetBagID()
								local slotId = slot:GetID()
								local itemLink = C_Container.GetContainerItemLink(bagId, slotId)

								if itemLink then
									local itemData = {
										bagID = bagId,
										slotID = slotId,
										itemLink = itemLink,
									}
									UpdateHighlightWidget(slot, itemData)
								end
							elseif slot and type(slot) == 'table' and slot.itemLink then
								-- Fallback for table-based slots
								slot.bagID = bagID
								slot.slotID = slotID
								UpdateHighlightWidget(slot)
							end
						end
					end
				end
			end)
			if not success then
				Log('ElvUI UpdateAllSlots hook error (non-critical): ' .. tostring(result), 'debug')
			end
		end)
		Log('Hooked ElvUI B:UpdateAllSlots')
	end

	-- Hook bag frame updates
	if B.UpdateBagFrame then
		hooksecurefunc(B, 'UpdateBagFrame', function(self, frame)
			-- Schedule slot updates after the frame update
			addon:ScheduleTimer(function()
				if frame and frame.Bags then
					for bagID, bag in pairs(frame.Bags) do
						if bag then
							for slotID, slot in pairs(bag) do
								if slot and slot.itemLink then
									slot.bagID = bagID
									slot.slotID = slotID
									UpdateHighlightWidget(slot)
								end
							end
						end
					end
				end
			end, 0.05)
		end)
		Log('Hooked ElvUI B:UpdateBagFrame')
	end
end

-- Function to refresh all widgets after settings changes
local function RefreshAllWidgets()
	addon:ScheduleTimer(function()
		if not ElvUI then
			Log('ElvUI not available, skipping refresh')
			return
		end

		Log('Refreshing all ElvUI widgets due to settings change')

		-- Clear existing widgets
		for itemButton, widget in pairs(itemButtonWidgets) do
			if widget and widget:IsShown() then
				widget:Hide()
			end
		end
		wipe(itemButtonWidgets)

		-- Force ElvUI to refresh
		local E = unpack(ElvUI)
		if E then
			local B = E:GetModule('Bags', true)
			if B then
				-- Update both bag and bank frames
				if B.BagFrame then
					B:UpdateAllSlots(B.BagFrame)
				end
				if B.BankFrame then
					B:UpdateAllSlots(B.BankFrame)
				end
				Log('Refreshed ElvUI bag frames')
			end
		end

		-- Also trigger a general bag update
		addon:ScheduleTimer(function()
			addon:SendMessage('BAG_UPDATE_DELAYED')
		end, 0.1)
	end, 0.1)
end

function ElvUIIntegration:OnEnable()
	if not self:IsAvailable() then
		Log('ElvUI not available during OnEnable', 'warning')
		return
	end

	Log('ElvUI integration enabled')

	-- Set up hooks for ElvUI bag system
	HookElvUIBagSystem()

	-- Hook into bag events for visibility changes
	addon:RegisterMessage('BAG_UPDATE_DELAYED', function()
		if self:AreBagsVisible() then
			Log('Bags are visible - starting timer')
			root.Animation.StartGlobalTimer()
		else
			Log('Bags are hidden - stopping timer')
			root.Animation.StopGlobalTimer()
		end
	end)

	-- Hook Blizzard bag functions that might open ElvUI bags
	local function OnBagToggle()
		Log('Blizzard bag function called - checking bag state after delay')
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

	-- Hook the same functions that might trigger ElvUI bags
	hooksecurefunc('ToggleBackpack', OnBagToggle)
	hooksecurefunc('ToggleBag', OnBagToggle)
	hooksecurefunc('ToggleAllBags', OnBagToggle)

	-- Hook ElvUI specific bag toggle if available
	local E = unpack(ElvUI)
	if E then
		local B = E:GetModule('Bags', true)
		if B and B.ToggleBags then
			hooksecurefunc(B, 'ToggleBags', OnBagToggle)
		end
	end
end

function ElvUIIntegration:OnDisable()
	Log('ElvUI integration disabling')
	root.Animation.StopGlobalTimer()

	-- Clear widgets
	for itemButton, widget in pairs(itemButtonWidgets) do
		if widget then
			widget:Hide()
		end
	end
	wipe(itemButtonWidgets)
end

-- Store refresh function for options
ElvUIIntegration.RefreshAllWidgets = RefreshAllWidgets

-- Register this bag system
addon:RegisterBagSystem('elvui', ElvUIIntegration)
