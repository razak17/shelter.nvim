---@class ShelterPreviewBase
---Shared utilities for preview integrations (telescope, fzf, snacks)
local M = {}

local state = require("shelter.state")
local env_file = require("shelter.utils.env_file")

---Apply masking to a buffer if it contains an env file
---@param bufnr number Buffer number
---@param filepath string File path being previewed
---@return boolean applied Whether masking was applied
function M.apply_masking_if_env(bufnr, filepath)
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end

	if not filepath or filepath == "" then
		return false
	end

	local basename = vim.fn.fnamemodify(filepath, ":t")
	local filetype = vim.filetype.match({ filename = filepath })

	if filetype and env_file.is_env_filetype(filetype) then
		local buffer = require("shelter.integrations.buffer")
		buffer.shelter_preview_buffer(bufnr, basename, filetype)
		return true
	end

	return false
end

---Setup a preview integration with standard state management
---@param feature_name string Feature name for state tracking (e.g., "telescope_previewer")
---@param original_key string Key to store original function under
---@param check_available function Function that checks if the integration is available, returns module or nil
---@param get_original function Function that gets the original function to wrap
---@param set_wrapper function Function that sets the wrapper function
---@return boolean success Whether setup succeeded
function M.setup_integration(feature_name, original_key, check_available, get_original, set_wrapper)
	local module = check_available()
	if not module then
		return false
	end

	state.set_initial(feature_name, true)

	-- Store original function if not already stored
	if not state.get_original(original_key) then
		local original = get_original(module)
		if original then
			state.set_original(original_key, original)
		end
	end

	-- Set the wrapper
	set_wrapper(module)

	return true
end

---Cleanup a preview integration
---@param original_key string Key where original function is stored
---@param check_available function Function that checks if the integration is available, returns module or nil
---@param restore_original function Function that restores the original function
function M.cleanup_integration(original_key, check_available, restore_original)
	local module = check_available()
	if not module then
		return
	end

	local original = state.get_original(original_key)
	if original then
		restore_original(module, original)
		state.clear_original(original_key)
	end
end

---Check if a preview feature is enabled
---@param feature_name string Feature name to check
---@return boolean enabled
function M.is_enabled(feature_name)
	return state.is_enabled(feature_name)
end

---Get the original function for a feature
---@param original_key string Key where original function is stored
---@return function|nil original
function M.get_original(original_key)
	return state.get_original(original_key)
end

return M
