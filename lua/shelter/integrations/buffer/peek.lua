---@class ShelterPeek
---Peek functionality for cursor-based line reveal
local M = {}

local state = require("shelter.state")

-- Active peek state
local peek_augroup = nil
local peek_range = nil -- { bufnr, start_line, end_line }
local peek_revealed_lines = {} -- list of revealed line numbers

---Cleanup peek resources (remove autocmds, reset state)
function M.cleanup()
	if peek_augroup then
		pcall(vim.api.nvim_del_augroup_by_id, peek_augroup)
		peek_augroup = nil
	end
	peek_range = nil
	peek_revealed_lines = {}
	state.reset_revealed_lines()
end

---Hide all peeked lines and cleanup
---@param bufnr number Buffer number
---@param refresh_callback fun() Callback to refresh the buffer display
local function hide_peek(bufnr, refresh_callback)
	M.cleanup()
	if vim.api.nvim_buf_is_valid(bufnr) then
		refresh_callback()
	end
end

---Peek a line while cursor remains on the value's line range
---@param bufnr number Buffer number
---@param line_num number Line number to reveal
---@param refresh_callback fun() Callback to refresh the buffer display
---@param find_value_range fun(bufnr: number, line_num: number): number|nil, number|nil
function M.peek_line(bufnr, line_num, refresh_callback, find_value_range)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	-- Cleanup any previous peek
	M.cleanup()

	-- Find the value range for this line
	local start_line, end_line = find_value_range(bufnr, line_num)
	if not start_line or not end_line then
		return -- cursor is not on a value line
	end

	-- Store active peek range
	peek_range = { bufnr = bufnr, start_line = start_line, end_line = end_line }

	-- Reveal all lines in the range
	for ln = start_line, end_line do
		state.reveal_line(ln)
		peek_revealed_lines[#peek_revealed_lines + 1] = ln
	end
	refresh_callback()

	-- Create augroup for cursor tracking
	peek_augroup = vim.api.nvim_create_augroup("ShelterPeek", { clear = true })

	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
		group = peek_augroup,
		buffer = bufnr,
		callback = function()
			local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
			if cursor_line < start_line or cursor_line > end_line then
				hide_peek(bufnr, refresh_callback)
			end
		end,
	})

	vim.api.nvim_create_autocmd("BufLeave", {
		group = peek_augroup,
		buffer = bufnr,
		once = true,
		callback = function()
			hide_peek(bufnr, refresh_callback)
		end,
	})
end

---Toggle peek for a line
---@param bufnr number Buffer number
---@param line_num number Line number
---@param refresh_callback fun() Callback to refresh the buffer display
---@param find_value_range fun(bufnr: number, line_num: number): number|nil, number|nil
function M.toggle_peek(bufnr, line_num, refresh_callback, find_value_range)
	-- If currently peeking and cursor is within the active range, hide
	if
		peek_range
		and peek_range.bufnr == bufnr
		and line_num >= peek_range.start_line
		and line_num <= peek_range.end_line
	then
		hide_peek(bufnr, refresh_callback)
	else
		M.peek_line(bufnr, line_num, refresh_callback, find_value_range)
	end
end

return M
