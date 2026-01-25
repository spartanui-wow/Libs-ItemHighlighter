local addonName, root = ... --[[@type string, table]]
local addon = root.Core
local Log = root.Log

-- Simple global animation system - just replace individual timers with one master timer
local globalAnimationTimer = nil
local animatingFrames = {}

-- Global widget tracking to prevent duplicates across multiple bag systems
local globalWidgetRegistry = {} -- [itemButton] = {widgetFrame, bagSystem, itemKey}

function RGBToHex(rgbTable)
	local r = math.floor(rgbTable.r * 255 + 0.5)
	local g = math.floor(rgbTable.g * 255 + 0.5)
	local b = math.floor(rgbTable.b * 255 + 0.5)
	return string.format('|cFF%02X%02X%02X', r, g, b)
end

-- Global animation update function - runs all frame animations
local function GlobalAnimationUpdate()
	-- Check if ANY active bag system has visible bags
	local anyBagsVisible = false
	local availableSystems = addon:GetAllAvailableBagSystems()

	for _, systemData in ipairs(availableSystems) do
		local integration = systemData.integration
		if integration.AreBagsVisible and integration:AreBagsVisible() then
			anyBagsVisible = true
			Log('Found visible bags in system: ' .. systemData.name, 'debug')
			break
		end
	end

	if not anyBagsVisible then
		Log('No bags visible in any system, stopping animation timer to save resources', 'debug')
		if globalAnimationTimer then
			addon:CancelTimer(globalAnimationTimer)
			globalAnimationTimer = nil
		end
		return
	end

	for frame in pairs(animatingFrames) do
		local visible = frame:IsVisible()
		if not visible then
			-- Skip animation but don't remove frame - bags are still open, item might come back
			Log('Frame not visible, skipping animation update', 'debug')
		else
			-- Frame is visible, run its animation
			if frame.updateFunction then
				frame.updateFunction()
			end
		end
	end
end

-- Start global timer if not running
local function StartGlobalTimer()
	if not globalAnimationTimer then
		-- Before starting, clean up any frames that might be in inconsistent state
		-- This prevents frozen animations when bags are rapidly opened/closed
		for frame in pairs(animatingFrames) do
			if frame.pauseTimer then
				addon:CancelTimer(frame.pauseTimer)
				frame.pauseTimer = nil
				Log('Canceled orphaned pause timer on animation restart', 'debug')
			end
			-- Reset to initial state to ensure clean animation
			if frame.animationState then
				frame.animationState = 1 -- Reset to blue visible state
			end
		end

		globalAnimationTimer = addon:ScheduleRepeatingTimer(GlobalAnimationUpdate, addon.DB.AnimationUpdateInterval)
		local count = 0
		for _ in pairs(animatingFrames) do
			count = count + 1
		end
		Log('Started global animation timer for ' .. count .. ' frames')
	end
end

-- Stop global timer if no frames
local function StopGlobalTimer()
	if globalAnimationTimer then
		addon:CancelTimer(globalAnimationTimer)
		globalAnimationTimer = nil

		-- Clean up any orphaned pause timers when stopping
		for frame in pairs(animatingFrames) do
			if frame.pauseTimer then
				addon:CancelTimer(frame.pauseTimer)
				frame.pauseTimer = nil
			end
		end

		Log('Stopped global animation timer')
	end
end

-- Animation function for corner widget with pause states
local function AnimateTextures(frame)
	-- Store state on frame so it persists across timer restarts
	if not frame.animationState then
		frame.animationState = 1 -- 1 = blue visible, 2 = fading to green, 3 = green visible, 4 = fading to blue
	end
	local currentState = frame.animationState
	local elapsedTime = 0

	local function SetTextureState(alpha1, alpha2)
		if frame.texture1 then
			frame.texture1:SetAlpha(alpha1)
		end
		if frame.texture2 then
			frame.texture2:SetAlpha(alpha2)
		end
	end

	local function StartPause(nextState, alpha1, alpha2)
		-- Set final alpha values and update persistent state
		SetTextureState(alpha1, alpha2)
		frame.animationState = nextState

		-- Start pause timer (individual timer for pauses)
		frame.pauseTimer = addon:ScheduleTimer(function()
			AnimateTextures(frame) -- Restart animation for next phase
		end, addon.DB.TimeBetweenCycles)

		Log('Started pause timer for ' .. addon.DB.TimeBetweenCycles .. ' seconds, next state: ' .. nextState, 'debug')
	end

	local function UpdateAnimation()
		elapsedTime = elapsedTime + addon.DB.AnimationUpdateInterval
		local progress = elapsedTime / addon.DB.AnimationCycleTime

		if currentState == 1 then -- Blue visible, start fading to green
			currentState = 2
			frame.animationState = 2
			elapsedTime = 0
			Log('Starting fade: blue to green', 'debug')
		elseif currentState == 2 then -- Fading blue to green
			if progress >= 1 then
				-- Remove from global animation during pause
				animatingFrames[frame] = nil
				local count = 0
				for _ in pairs(animatingFrames) do
					count = count + 1
				end
				if count == 0 then
					StopGlobalTimer()
				end

				StartPause(3, 0, 1) -- Pause at green
				return
			end
			SetTextureState(1 - progress, progress)
		elseif currentState == 3 then -- Green visible, start fading to blue
			currentState = 4
			frame.animationState = 4
			elapsedTime = 0
			Log('Starting fade: green to blue', 'debug')
		elseif currentState == 4 then -- Fading green to blue
			if progress >= 1 then
				-- Remove from global animation during pause
				animatingFrames[frame] = nil
				local count = 0
				for _ in pairs(animatingFrames) do
					count = count + 1
				end
				if count == 0 then
					StopGlobalTimer()
				end

				StartPause(1, 1, 0) -- Pause at blue
				return
			end
			SetTextureState(progress, 1 - progress)
		end
	end

	-- Add this frame to global animation
	frame.updateFunction = UpdateAnimation
	animatingFrames[frame] = true
	StartGlobalTimer()

	-- Set initial state based on current animation state
	if currentState == 1 or currentState == 2 then
		SetTextureState(1, 0) -- Start with blue visible
		Log('Started animation cycle at blue', 'debug')
	elseif currentState == 3 or currentState == 4 then
		SetTextureState(0, 1) -- Start with green visible
		Log('Started animation cycle at green', 'debug')
	end
end

-- Cleanup function to stop animation timers
local function CleanupAnimation(cornerFrame)
	-- Remove from global animation
	if animatingFrames[cornerFrame] then
		animatingFrames[cornerFrame] = nil
		local count = 0
		for _ in pairs(animatingFrames) do
			count = count + 1
		end
		if count == 0 then
			StopGlobalTimer()
		end
		Log('Removed frame from global animation, ' .. count .. ' frames remaining', 'debug')
	end

	-- Cancel pause timer if running
	if cornerFrame.pauseTimer then
		addon:CancelTimer(cornerFrame.pauseTimer)
		cornerFrame.pauseTimer = nil
		Log('Canceled pause timer')
	end

	-- Reset state
	cornerFrame.animationState = nil
	cornerFrame.updateFunction = nil
end

---Create a standard openable indicator frame
---@param parent Frame The parent frame (item button)
---@return Frame frame The indicator frame
local count = 0
local function CreateIndicatorFrame(parent)
	-- Check if we already have a widget for this parent to prevent duplicates
	if globalWidgetRegistry[parent] then
		Log('Reusing existing widget for item button (multi-bag system active)', 'debug')
		return globalWidgetRegistry[parent].widgetFrame
	end

	local frame = CreateFrame('Frame', 'LibsIH_IndicatorFrame' .. count, parent)
	count = count + 1

	-- Register this widget in the global registry
	globalWidgetRegistry[parent] = {
		widgetFrame = frame,
		bagSystem = 'unknown', -- Will be updated by caller
		itemKey = nil, -- Will be updated by caller
	}

	-- Get parent size and use it for perfect alignment
	local width = parent:GetWidth()
	local height = parent:GetHeight()
	frame:SetSize(width, height)

	-- Anchor the frame to completely cover the parent item button
	frame:SetAllPoints(parent)

	-- Create two textures for crossfading glow animation
	local texture1 = frame:CreateTexture(nil, 'OVERLAY')
	texture1:SetAllPoints(frame)
	texture1:SetAtlas('bags-glow-blue')
	texture1:SetAlpha(1) -- Start fully visible for animation
	texture1:Hide() -- Initially hidden, shown when glow is enabled

	local texture2 = frame:CreateTexture(nil, 'OVERLAY')
	texture2:SetAllPoints(frame)
	texture2:SetAtlas('bags-glow-green')
	texture2:SetAlpha(0) -- Start invisible for animation
	texture2:Hide() -- Initially hidden, shown when glow is enabled

	-- Static indicator icon texture
	local texture3 = frame:CreateTexture(nil, 'OVERLAY')
	texture3:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, 0)
	texture3:SetAtlas('ShipMissionIcon-Treasure-Map')
	texture3:SetSize(20, 20)
	texture3:SetAlpha(1) -- Always full alpha when visible
	texture3:Hide() -- Initially hidden, shown when indicator is enabled

	-- Store all textures
	frame.texture1 = texture1
	frame.texture2 = texture2
	frame.texture3 = texture3
	frame.texture = texture3 -- For compatibility, use static texture

	return frame
end

---Update indicator frame for an item
---@param frame Frame The indicator frame
---@param itemDetails table Item details
---@return boolean visible True if indicator should be visible
local function UpdateIndicatorFrame(frame, itemDetails)
	-- Check if any indicator features are enabled
	if not addon.DB.ShowGlow and not addon.DB.ShowIndicator then
		Log('All indicator features disabled, hiding widget')
		CleanupAnimation(frame)
		frame:Hide()
		return false
	end

	if not itemDetails or not itemDetails.itemLink then
		Log('No itemDetails or itemLink provided')
		CleanupAnimation(frame)
		return false
	end

	Log('Checking item: ' .. (itemDetails.itemLink or 'unknown'), 'debug')
	local isOpenable = root.CheckItem(itemDetails)
	if isOpenable then
		Log('Item is openable, configuring display elements', 'debug')

		-- Always show frame if any feature is enabled for openable items
		frame:Show()

		-- Handle glow animation (texture1 and texture2)
		if addon.DB.ShowGlow then
			Log('Showing glow animation', 'debug')
			-- Show glow textures
			if frame.texture1 then
				frame.texture1:Show()
			end
			if frame.texture2 then
				frame.texture2:Show()
			end

			-- Ensure animation is running for glow effect
			if not animatingFrames[frame] then
				local success, errorMsg = pcall(AnimateTextures, frame)
				if not success then
					Log('ERROR starting glow animation: ' .. tostring(errorMsg))
				end
			else
				-- Frame is already in animation table, but ensure it's actually animating
				if not frame.updateFunction then
					Log('Glow animation function missing, restarting animation')
					CleanupAnimation(frame)
					local success, errorMsg = pcall(AnimateTextures, frame)
					if not success then
						Log('ERROR restarting glow animation: ' .. tostring(errorMsg))
					end
				end
			end
		else
			-- Hide glow textures if glow is disabled
			if frame.texture1 then
				frame.texture1:Hide()
			end
			if frame.texture2 then
				frame.texture2:Hide()
			end
			CleanupAnimation(frame)
		end

		-- Handle indicator icon (texture3)
		if frame.texture3 then
			if addon.DB.ShowIndicator then
				Log('Showing indicator icon', 'debug')
				frame.texture3:Show()
			else
				Log('Hiding indicator icon', 'debug')
				frame.texture3:Hide()
			end
		end

		return true
	else
		-- Stop animation timer and hide frame for non-openable items
		CleanupAnimation(frame)
		frame:Hide()
		Log('Item is not openable, hiding widget', 'debug')
	end

	return false
end

-- Cleanup all widgets (used when disabling addon)
local function CleanupAllWidgets()
	local count = 0
	for parent, entry in pairs(globalWidgetRegistry) do
		if entry.widgetFrame then
			CleanupAnimation(entry.widgetFrame)
			entry.widgetFrame:Hide()
		end
		count = count + 1
	end
	globalWidgetRegistry = {}
	Log('Cleaned up ' .. count .. ' widgets from global registry')
end

-- Export animation functions
root.Animation = {
	CreateIndicatorFrame = CreateIndicatorFrame,
	UpdateIndicatorFrame = UpdateIndicatorFrame,
	CleanupAnimation = CleanupAnimation,
	CleanupAllWidgets = CleanupAllWidgets,
	StartGlobalTimer = StartGlobalTimer,
	StopGlobalTimer = StopGlobalTimer,
}
