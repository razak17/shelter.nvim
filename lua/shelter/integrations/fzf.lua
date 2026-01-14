---@class ShelterFzfIntegration
---FZF-lua previewer integration for shelter.nvim
local M = {}

local preview_base = require("shelter.integrations.preview_base")

---Setup FZF previewer integration
function M.setup()
	preview_base.setup_integration(
		"fzf_previewer",
		"fzf_preview_buf_post",
		function()
			local ok, builtin = pcall(require, "fzf-lua.previewer.builtin")
			return ok and builtin or nil
		end,
		function(builtin)
			return builtin.buffer_or_file.preview_buf_post
		end,
		function(builtin)
			builtin.buffer_or_file.preview_buf_post = function(self, entry, min_winopts)
				-- Call original first
				local original = preview_base.get_original("fzf_preview_buf_post")
				if original then
					original(self, entry, min_winopts)
				end

				-- Check if feature is enabled
				if not preview_base.is_enabled("fzf_previewer") then
					return
				end

				-- Get filename from entry and apply masking
				local filepath = entry.path or entry.filename or entry.name
				preview_base.apply_masking_if_env(self.preview_bufnr, filepath)
			end
		end
	)
end

---Cleanup FZF integration
function M.cleanup()
	preview_base.cleanup_integration("fzf_preview_buf_post", function()
		local ok, builtin = pcall(require, "fzf-lua.previewer.builtin")
		return ok and builtin or nil
	end, function(builtin, original)
		builtin.buffer_or_file.preview_buf_post = original
	end)
end

return M
