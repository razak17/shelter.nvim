---@class ShelterEcologIntegration
---Integration with ecolog-plugin for environment variable masking
---
---Wraps LSP client request method to intercept ecolog-lsp responses and mask values
---before they reach completion plugins (blink.cmp, nvim-cmp) or hover UIs (lspsaga)
---
---This approach works because it intercepts at the client level via LspAttach,
---so even plugins that bypass vim.lsp.handlers are covered.
---
---@usage
---```lua
---require("shelter").setup({
---  modules = {
---    ecolog = {
---      cmp = true,     -- Mask in completion
---      peek = true,    -- Mask in hover
---    },
---  },
---})
---```
local M = {}

local state = require("shelter.state")
local config = require("shelter.config")
local masking = require("shelter.masking")

-- Internal state (encapsulated)
local internal = {
	is_setup = false,
	wrapped_clients = {}, -- Store wrapped clients to avoid double-wrapping
	augroup_id = nil, -- Autocmd group ID
	picker_hook_id = nil, -- Hook ID for ecolog picker hook
}

---Mask a value using shelter's masking engine (same as buffer masking)
---@param value string Value to mask
---@param key string|nil Variable name for pattern matching
---@return string masked value
local function mask_value(value, key)
	if not value or value == "" then
		return value
	end

	-- Use the same masking function as buffer integration for consistency
	return masking.mask_value(value, {
		key = key,
		source = nil, -- No source file context for LSP values
		line_number = 1,
		quote_type = 0, -- No quotes in LSP response values
		is_comment = false,
	})
end

---Mask hover content from ecolog-lsp
---Handles both single-line and multi-line values
---For multi-line: combines all lines, masks as one unit, preserves line structure
---Format: **Value**: `line1`\n`line2`\n`line3`\n\n**Source**: `source`
---@param contents string|table Hover contents
---@return string|table masked contents
function M._mask_hover_content(contents)
	if type(contents) == "string" then
		-- Find the Value section and Source section
		local value_start, value_end = contents:find("%*%*Value%*%*:")
		local source_start = contents:find("%*%*Source%*%*:")

		if value_start and source_start and source_start > value_end then
			-- Extract sections
			local before = contents:sub(1, value_end)
			local value_section = contents:sub(value_end + 1, source_start - 1)
			local after = contents:sub(source_start)

			-- Collect all lines and their lengths
			local lines = {}
			for val in value_section:gmatch("`([^`]*)`") do
				table.insert(lines, val)
			end

			if #lines > 0 then
				-- Combine all lines into one value (with newlines)
				local full_value = table.concat(lines, "\n")

				-- Mask the combined value as one unit
				local masked_full = mask_value(full_value, nil)

				-- Split masked value back into lines
				local masked_lines = {}
				for line in (masked_full .. "\n"):gmatch("([^\n]*)\n") do
					table.insert(masked_lines, line)
				end

				-- Rebuild the value section with masked lines
				local rebuilt = " "
				for i, masked_line in ipairs(masked_lines) do
					if i > 1 then
						rebuilt = rebuilt .. "\n"
					end
					rebuilt = rebuilt .. "`" .. masked_line .. "`"
				end
				rebuilt = rebuilt .. "\n\n"

				return before .. rebuilt .. after
			end
		end

		-- Fallback: mask any backtick-wrapped content after **Value**:
		local masked = contents:gsub("(%*%*Value%*%*:%s*`)([^`]+)(`)", function(pre, value, post)
			return pre .. mask_value(value, nil) .. post
		end)

		return masked
	elseif type(contents) == "table" then
		if contents.kind == "markdown" or contents.kind == "plaintext" then
			contents.value = M._mask_hover_content(contents.value)
		elseif contents.value then
			contents.value = M._mask_hover_content(contents.value)
		elseif vim.islist(contents) then
			for i, item in ipairs(contents) do
				contents[i] = M._mask_hover_content(item)
			end
		end
	end
	return contents
end

---Mask completion items from ecolog-lsp
---@param result table LSP completion result
---@return table masked result
function M._mask_completion_items(result)
	if not result then
		return result
	end

	local items = result.items or result

	if not vim.islist(items) then
		return result
	end

	for _, item in ipairs(items) do
		-- Mask the detail field (shows value preview)
		if item.detail then
			item.detail = mask_value(item.detail, item.label)
		end

		-- Mask documentation if it contains value
		if item.documentation then
			if type(item.documentation) == "string" then
				item.documentation = M._mask_hover_content(item.documentation)
			elseif type(item.documentation) == "table" and item.documentation.value then
				item.documentation.value = M._mask_hover_content(item.documentation.value)
			end
		end

		-- Mask labelDetails if present
		if item.labelDetails then
			if item.labelDetails.detail then
				item.labelDetails.detail = mask_value(item.labelDetails.detail, item.label)
			end
			if item.labelDetails.description then
				item.labelDetails.description = mask_value(item.labelDetails.description, item.label)
			end
		end
	end

	return result
end

---Mask hover result from ecolog-lsp
---@param result table LSP hover result
---@return table masked result
function M._mask_hover_result(result)
	if not result then
		return result
	end

	-- Debug: capture the raw content before masking
	if result.contents then
		if type(result.contents) == "string" then
			M._last_hover_content = result.contents
		elseif type(result.contents) == "table" and result.contents.value then
			M._last_hover_content = result.contents.value
		end
	end

	if result.contents then
		result.contents = M._mask_hover_content(result.contents)
	end

	return result
end

---Check if client is ecolog-lsp
---@param client table LSP client
---@return boolean
local function is_ecolog_client(client)
	return client and client.name and (client.name:find("ecolog") ~= nil)
end

---Wrap a client's request method to intercept ecolog-lsp responses
---@param client table LSP client
local function wrap_client_request(client)
	-- Skip if not ecolog-lsp
	if not is_ecolog_client(client) then
		return
	end

	-- Skip if already wrapped
	if internal.wrapped_clients[client.id] then
		return
	end

	-- Store original request method
	local original_request = client.request

	-- Wrap the request method
	-- Note: When called as client:request(...), self is passed as first arg
	client.request = function(self_or_method, method_or_params, params_or_handler, handler_or_bufnr, bufnr_arg)
		-- Handle both client:request() and client.request() call styles
		local method, params, handler, bufnr
		if type(self_or_method) == "table" then
			-- Called as client:request(method, params, handler, bufnr)
			-- self_or_method is actually `self` (the client)
			method = method_or_params
			params = params_or_handler
			handler = handler_or_bufnr
			bufnr = bufnr_arg
		else
			-- Called as client.request(method, params, handler, bufnr)
			method = self_or_method
			params = method_or_params
			handler = params_or_handler
			bufnr = handler_or_bufnr
		end

		-- Check if we should mask this method
		local should_mask_hover = method == "textDocument/hover" and state.is_enabled("ecolog_peek")
		local should_mask_completion = method == "textDocument/completion" and state.is_enabled("ecolog_cmp")

		if not (should_mask_hover or should_mask_completion) then
			return original_request(client, method, params, handler, bufnr)
		end

		-- Wrap the handler to intercept the response
		local wrapped_handler
		if handler then
			wrapped_handler = function(err, result, ctx, cfg)
				-- Mask the result before passing to the original handler
				if not err and result then
					if should_mask_hover then
						result = M._mask_hover_result(result)
					elseif should_mask_completion then
						result = M._mask_completion_items(result)
					end
				end
				return handler(err, result, ctx, cfg)
			end
		else
			-- No handler provided, use the global handler
			wrapped_handler = function(err, result, ctx, cfg)
				if not err and result then
					if should_mask_hover then
						result = M._mask_hover_result(result)
					elseif should_mask_completion then
						result = M._mask_completion_items(result)
					end
				end
				-- Call the appropriate global handler
				local global_handler = vim.lsp.handlers[method]
				if global_handler then
					return global_handler(err, result, ctx, cfg)
				end
			end
		end

		return original_request(client, method, params, wrapped_handler, bufnr)
	end

	-- Mark as wrapped
	internal.wrapped_clients[client.id] = {
		original_request = original_request,
	}
end

---Unwrap a client's request method
---@param client_id number LSP client ID
local function unwrap_client_request(client_id)
	local wrapped = internal.wrapped_clients[client_id]
	if not wrapped then
		return
	end

	local client = vim.lsp.get_client_by_id(client_id)
	if client and wrapped.original_request then
		client.request = wrapped.original_request
	end

	internal.wrapped_clients[client_id] = nil
end

---Setup LSP client wrapping via LspAttach autocmd
function M._setup_lsp_attach()
	-- Create autocmd group
	internal.augroup_id = vim.api.nvim_create_augroup("ShelterEcolog", { clear = true })

	-- Wrap clients on attach
	vim.api.nvim_create_autocmd("LspAttach", {
		group = internal.augroup_id,
		callback = function(args)
			local client = vim.lsp.get_client_by_id(args.data.client_id)
			if client then
				wrap_client_request(client)
			end
		end,
	})

	-- Note: We intentionally do NOT unwrap on LspDetach because:
	-- 1. LspDetach fires when a client detaches from a BUFFER, not when client stops
	-- 2. The client may still be attached to other buffers
	-- 3. Plugins like oil.nvim delete hidden buffers which triggers LspDetach
	-- The wrapping persists for the client's lifetime and is cleaned up in teardown()

	-- Wrap any already-running ecolog-lsp clients
	for _, client in ipairs(vim.lsp.get_clients()) do
		wrap_client_request(client)
	end
end

---Setup ecolog hooks for picker masking
function M._setup_ecolog_hooks()
	-- Prevent double registration
	if internal.picker_hook_id then
		return
	end

	local ok, ecolog = pcall(require, "ecolog")
	if not ok then
		return
	end

	local hooks_ok, hooks = pcall(ecolog.hooks)
	if not hooks_ok or not hooks then
		return
	end

	-- Register hook for picker entry masking
	local reg_ok1, id1 = pcall(function()
		return hooks.register("on_picker_entry", function(entry)
			if not entry or not state.is_enabled("ecolog_picker") then
				return entry
			end
			if entry.value and entry.value ~= "" then
				entry.value = mask_value(entry.value, entry.name)
			end
			return entry
		end, { id = "shelter_picker", priority = 200 })
	end)
	if reg_ok1 then
		internal.picker_hook_id = id1
	end

	-- Note: We only use on_picker_entry, not on_variables_list
	-- on_variables_list modifies values in place which could affect vim.env sync
	-- on_picker_entry is sufficient for picker display masking
end

---Setup the ecolog integration
---@param opts? table Options (cmp, peek booleans)
function M.setup(opts)
	if internal.is_setup then
		return
	end

	opts = opts or {}

	-- Get ecolog config from shelter config
	local cfg = config.get()
	local ecolog_config = cfg.modules and cfg.modules.ecolog or {}

	-- If ecolog_config is boolean true, use defaults
	if ecolog_config == true then
		ecolog_config = {}
	end

	-- Merge with opts
	if type(ecolog_config) == "table" then
		ecolog_config = vim.tbl_extend("force", ecolog_config, opts)
	else
		ecolog_config = opts
	end

	-- Set initial state for each context (default to true)
	state.set_initial("ecolog_cmp", ecolog_config.cmp ~= false)
	state.set_initial("ecolog_peek", ecolog_config.peek ~= false)
	state.set_initial("ecolog_picker", ecolog_config.picker ~= false)

	-- Setup LSP client wrapping via autocmd
	M._setup_lsp_attach()

	-- Setup ecolog hooks for picker masking
	M._setup_ecolog_hooks()

	internal.is_setup = true
end

---Toggle a context or all contexts
---@param context? string "cmp"|"peek"|"picker" or nil for all
---@return boolean new_state
function M.toggle(context)
	if context then
		local key = "ecolog_" .. context
		return state.toggle(key)
	else
		-- Toggle all based on any being enabled
		local any_enabled = M.is_enabled("cmp") or M.is_enabled("peek") or M.is_enabled("picker")
		state.set_enabled("ecolog_cmp", not any_enabled)
		state.set_enabled("ecolog_peek", not any_enabled)
		state.set_enabled("ecolog_picker", not any_enabled)
		return not any_enabled
	end
end

---Enable a context or all contexts
---@param context? string "cmp"|"peek"|"picker" or nil for all
function M.enable(context)
	if context then
		state.set_enabled("ecolog_" .. context, true)
	else
		state.set_enabled("ecolog_cmp", true)
		state.set_enabled("ecolog_peek", true)
		state.set_enabled("ecolog_picker", true)
	end
end

---Disable a context or all contexts
---@param context? string "cmp"|"peek"|"picker" or nil for all
function M.disable(context)
	if context then
		state.set_enabled("ecolog_" .. context, false)
	else
		state.set_enabled("ecolog_cmp", false)
		state.set_enabled("ecolog_peek", false)
		state.set_enabled("ecolog_picker", false)
	end
end

---Check if a context is enabled
---@param context string "cmp"|"peek"
---@return boolean
function M.is_enabled(context)
	return state.is_enabled("ecolog_" .. context)
end

---Check if setup has been done
---@return boolean
function M.is_setup()
	return internal.is_setup
end

---Debug: Get wrapped clients info
---@return table
function M.get_wrapped_clients()
	return internal.wrapped_clients
end

---Debug: Show last hover content (set by wrapper)
M._last_hover_content = nil

---Debug: Manually wrap ecolog client
function M.debug_wrap()
	local clients = vim.lsp.get_clients({ name = "ecolog" })
	for _, client in ipairs(clients) do
		vim.notify("Found ecolog client: " .. client.id .. " name: " .. client.name)
		if internal.wrapped_clients[client.id] then
			vim.notify("Already wrapped")
		else
			vim.notify("Wrapping now...")
			wrap_client_request(client)
			vim.notify("Wrapped: " .. tostring(internal.wrapped_clients[client.id] ~= nil))
		end
	end
end

---Teardown integration (restore original request methods)
function M.teardown()
	-- Remove autocmds
	if internal.augroup_id then
		vim.api.nvim_del_augroup_by_id(internal.augroup_id)
		internal.augroup_id = nil
	end

	-- Unwrap all clients
	for client_id, _ in pairs(internal.wrapped_clients) do
		unwrap_client_request(client_id)
	end

	-- Unregister ecolog hooks
	pcall(function()
		local ecolog = require("ecolog")
		local hooks = ecolog.hooks()
		if internal.picker_hook_id then
			pcall(hooks.unregister, "on_picker_entry", internal.picker_hook_id)
		end
	end)
	internal.picker_hook_id = nil

	internal.wrapped_clients = {}
	internal.is_setup = false
end

return M
