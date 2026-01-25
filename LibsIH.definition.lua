-- LibsIH (Lib's - Item Highlighter) Type Definitions
-- This file contains all type annotations for the addon
-- It is not packaged with the addon to keep runtime files clean

---@meta LibsIH

-- SpartanUI Logger Type Definitions
---@alias LogLevel
---| "debug"    # Detailed debugging information
---| "info"     # General informational messages
---| "warning"  # Warning conditions
---| "error"    # Error conditions
---| "critical" # Critical system failures

---Logger function returned by RegisterAddon
---@alias SimpleLogger fun(message: string, level?: LogLevel): nil

---Logger table returned by RegisterAddonCategory
---@alias ComplexLoggers table<string, SimpleLogger>

---@class LibAT.Logger
---@field RegisterAddon fun(addonName: string): SimpleLogger
---@field RegisterAddonCategory fun(addonName: string, subcategories: string[]): ComplexLoggers

-- Core Addon Classes
---@class LibsIHCore: AceAddon, AceTimer-3.0, AceHook-3.0, AceEvent-3.0
---@field DB LibsIH.DB.Profile The addon's profile database
---@field GlobalDB GlobalDB The addon's global database
---@field DataBase AceDB The AceDB instance
---@field RegisterBagSystem fun(self: LibsIHCore, name: string, integration: BagSystemIntegration): nil
---@field GetActiveBagSystem fun(self: LibsIHCore): BagSystemIntegration?
---@field SetupOptions fun(self: LibsIHCore): nil

-- Global Database
---@class GlobalDB
---@field itemCache ItemCache Cache for item openability results

---@class ItemCache
---@field openable table<number, boolean> itemID -> true for confirmed openable items
---@field notOpenable table<number, boolean> itemID -> true for confirmed non-openable items

-- Item Details (varies by bag system)
---@class ItemDetails
---@field itemLink string The item's link
---@field bagID number? The bag ID (if applicable)
---@field slotID number? The slot ID (if applicable)

-- Bag System Integration Interface
---@class BagSystemIntegration
---@field name string Name of the bag system
---@field IsAvailable fun(self: BagSystemIntegration): boolean Check if this bag system is available
---@field AreBagsVisible fun(self: BagSystemIntegration): boolean Check if bags are currently visible
---@field OnEnable fun(self: BagSystemIntegration): nil Enable the bag system integration
---@field OnDisable fun(self: BagSystemIntegration): nil Disable the bag system integration
---@field RefreshAllCornerWidgets fun(): nil Refresh all indicators/widgets

-- Animation System
---@class AnimationFrame: Frame
---@field texture1 Texture First texture for crossfading
---@field texture2 Texture Second texture for crossfading
---@field texture3 Texture Static texture
---@field texture Texture Compatibility texture reference
---@field animationState number? Current animation state (1-4)
---@field updateFunction fun()? Animation update function
---@field pauseTimer any? Timer for animation pauses

---@class AnimationSystem
---@field CreateIndicatorFrame fun(parent: Frame): AnimationFrame
---@field UpdateIndicatorFrame fun(frame: AnimationFrame, itemDetails: ItemDetails): boolean
---@field CleanupAnimation fun(frame: AnimationFrame): nil
---@field StartGlobalTimer fun(): nil
---@field StopGlobalTimer fun(): nil

-- Utility Functions
---@class LibsIHUtils
---@field Log fun(msg: string, level?: LogLevel): nil Logging function
---@field GetLocaleString fun(key: string): string Get localized string
---@field CheckItem fun(itemDetails: ItemDetails): boolean? Check if item is openable
---@field REP_USE_TEXT string Reputation use text pattern

-- Global Root Object
---@class LibsIHRoot
---@field Core LibsIHCore The main addon object
---@field Log fun(msg: string, level?: LogLevel): nil Logging function
---@field GetLocaleString fun(key: string): string Get localized string
---@field CheckItem fun(itemDetails: ItemDetails): boolean? Check if item is openable
---@field REP_USE_TEXT string Reputation use text pattern
---@field Animation AnimationSystem Animation system functions
