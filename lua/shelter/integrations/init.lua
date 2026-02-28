---@class ShelterIntegrations
---Integration registry for shelter.nvim
local M = {}

---@type table<string, table>
local integrations = {}

---Register an integration
---@param name string
---@param integration table
function M.register(name, integration)
	integrations[name] = integration
end

---Get an integration
---@param name string
---@return table|nil
function M.get(name)
	return integrations[name]
end

---Setup all enabled integrations
---@param modules table<string, boolean>
function M.setup_all(modules)
	-- Buffer integration (core) - includes peek functionality
	if modules.files ~= false and modules.files ~= nil then
		local buffer = require("shelter.integrations.buffer")
		buffer.setup()
		M.register("buffer", buffer)
	end

	-- Telescope previewer
	if modules.telescope_previewer then
		local ok, telescope = pcall(require, "shelter.integrations.telescope")
		if ok then
			telescope.setup()
			M.register("telescope", telescope)
		end
	end

	-- FZF previewer
	if modules.fzf_previewer then
		local ok, fzf = pcall(require, "shelter.integrations.fzf")
		if ok then
			fzf.setup()
			M.register("fzf", fzf)
		end
	end

	-- Snacks previewer
	if modules.snacks_previewer then
		local ok, snacks = pcall(require, "shelter.integrations.snacks")
		if ok then
			snacks.setup()
			M.register("snacks", snacks)
		end
	end

	-- Oil.nvim previewer
	if modules.oil_previewer then
		local ok, oil = pcall(require, "shelter.integrations.oil")
		if ok then
			oil.setup()
			M.register("oil", oil)
		end
	end

	-- Ecolog integration (for ecolog-plugin LSP masking)
	if modules.ecolog then
		local ok, ecolog = pcall(require, "shelter.integrations.ecolog")
		if ok then
			local ecolog_opts = type(modules.ecolog) == "table" and modules.ecolog or {}
			ecolog.setup(ecolog_opts)
			M.register("ecolog", ecolog)
		end
	end
end

return M
