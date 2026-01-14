---@class ShelterSnacksIntegration
---Snacks.nvim previewer integration for shelter.nvim
local M = {}

local preview_base = require("shelter.integrations.preview_base")

---Setup Snacks previewer integration
function M.setup()
	preview_base.setup_integration(
		"snacks_previewer",
		"snacks_preview",
		function()
			local ok, preview = pcall(require, "snacks.picker.preview")
			return ok and preview or nil
		end,
		function(preview)
			return preview.file
		end,
		function(preview)
			preview.file = function(ctx)
				local original = preview_base.get_original("snacks_preview")

				-- Call original preview function first
				if original then
					original(ctx)
				end

				-- Apply masking if enabled
				if preview_base.is_enabled("snacks_previewer") then
					vim.schedule(function()
						if ctx.buf and vim.api.nvim_buf_is_valid(ctx.buf) then
							-- Skip terminal buffers (e.g., lazygit)
							local buftype = vim.bo[ctx.buf].buftype
							if buftype == "terminal" then
								return
							end

							local filepath = ctx.item and ctx.item.file
							preview_base.apply_masking_if_env(ctx.buf, filepath)
						end
					end)
				end
			end
		end
	)
end

---Cleanup Snacks integration
function M.cleanup()
	preview_base.cleanup_integration("snacks_preview", function()
		local ok, preview = pcall(require, "snacks.picker.preview")
		return ok and preview or nil
	end, function(preview, original)
		preview.file = original
	end)
end

return M
