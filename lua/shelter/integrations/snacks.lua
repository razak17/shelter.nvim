---@class ShelterSnacksIntegration
---Snacks.nvim previewer integration for shelter.nvim
local M = {}

local state = require("shelter.state")
local env_file = require("shelter.utils.env_file")

---Setup Snacks previewer integration
function M.setup()
	-- Check if snacks.nvim picker preview is available
	local ok, preview = pcall(require, "snacks.picker.preview")
	if not ok then
		return
	end

	state.set_initial("snacks_previewer", true)

	-- Store original function if not already stored
	if not state.get_original("snacks_preview") then
		state.set_original("snacks_preview", preview.file)
	end

	-- Wrap the preview.file function
	preview.file = function(ctx)
		local original = state.get_original("snacks_preview")

		-- Call original preview function first
		if original then
			original(ctx)
		end

		-- Apply masking if enabled - detect filetype from filename
		if state.is_enabled("snacks_previewer") then
			vim.schedule(function()
				if ctx.buf and vim.api.nvim_buf_is_valid(ctx.buf) then
					local filepath = ctx.item and ctx.item.file
					local filename = filepath and vim.fn.fnamemodify(filepath, ":t")
					-- Detect filetype from filename since preview buffers have their own filetype
					local filetype = filepath and vim.filetype.match({ filename = filepath })
					if filetype and env_file.is_env_filetype(filetype) then
						local buffer = require("shelter.integrations.buffer")
						buffer.shelter_preview_buffer(ctx.buf, filename, filetype)
					end
				end
			end)
		end
	end
end

---Cleanup Snacks integration
function M.cleanup()
	local ok, preview = pcall(require, "snacks.picker.preview")
	if not ok then
		return
	end

	local original = state.get_original("snacks_preview")
	if original then
		preview.file = original
		state.clear_original("snacks_preview")
	end
end

return M
