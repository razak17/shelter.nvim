---@class ShelterOilIntegration
---Oil.nvim preview integration for shelter.nvim
---Wraps oil's scratch buffer creation to apply masking before display
local M = {}

local preview_base = require("shelter.integrations.preview_base")
local state = require("shelter.state")

---@type function|nil Original read_file_to_scratch_buffer
local original_fn = nil

---Setup oil.nvim integration
function M.setup()
	local ok, oil_util = pcall(require, "oil.util")
	if not ok or not oil_util.read_file_to_scratch_buffer then
		return
	end

	state.set_initial("oil_previewer", true)

	-- Store original function
	if not original_fn then
		original_fn = oil_util.read_file_to_scratch_buffer
	end

	-- Wrap to apply masking after scratch buffer creation
	oil_util.read_file_to_scratch_buffer = function(path, preview_method)
		local bufnr = original_fn(path, preview_method)
		if bufnr and state.is_enabled("oil_previewer") then
			preview_base.apply_masking_if_env(bufnr, path)
		end
		return bufnr
	end
end

---Cleanup oil.nvim integration
function M.cleanup()
	local ok, oil_util = pcall(require, "oil.util")
	if not ok then
		return
	end

	if original_fn then
		oil_util.read_file_to_scratch_buffer = original_fn
		original_fn = nil
	end
end

return M
