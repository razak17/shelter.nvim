-- Performance benchmark: shelter.nvim vs cloak.nvim vs camouflage.nvim vs Pure Lua
-- Run with: nvim --headless -u benchmarks/minimal_init.lua -l benchmarks/benchmark.lua
--
-- Output: JSON file (benchmark_results.json) with timing results
--
-- Benchmarks:
-- 1. Parsing: Raw parsing + mask generation (no buffer)
-- 2. Preview: Masking a preview buffer (Telescope scenario)
-- 3. Edit: Re-masking after text change (typing scenario)
--
-- "Pure Lua" baseline: simple Lua pattern matching + extmarks with full buffer
-- parsing on every change. Represents the best you can achieve without a
-- dedicated plugin, separate optimisations, or a native Rust binary.

local ITERATIONS = 10000
local SIZES = { 10, 50, 100, 500 }
local OUTPUT_FILE = "benchmark_results.json"

-- High resolution timer
local hrtime = vim.uv and vim.uv.hrtime or vim.loop.hrtime

---Generate synthetic .env content with N lines
---@param num_lines number
---@return string
local function generate_env_content(num_lines)
	local lines = {}
	for i = 1, num_lines do
		-- Realistic env line: VAR_0001=secret_value_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
		lines[i] = string.format("VAR_%04d=secret_value_%s", i, string.rep("x", 32))
	end
	return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- PARSING BENCHMARKS (raw engine performance)
--------------------------------------------------------------------------------

---Benchmark shelter.nvim masking engine (parsing only)
---@param content string
---@param iterations number
---@return number Average time in milliseconds
local function benchmark_shelter_parse(content, iterations)
	local engine = require("shelter.masking.engine")

	-- Warmup run (not timed)
	engine.clear_caches()
	engine.generate_masks(content, "test.env")

	-- Timed runs
	local total_time = 0
	for _ = 1, iterations do
		engine.clear_caches() -- Clear cache for fair comparison
		local start = hrtime()
		engine.generate_masks(content, "test.env")
		local elapsed = hrtime() - start
		total_time = total_time + elapsed
	end

	return (total_time / iterations) / 1e6 -- Convert ns to ms
end

---Benchmark cloak.nvim masking (parsing equivalent)
---@param content string
---@param iterations number
---@return number|nil Average time in milliseconds, or nil if cloak not available
local function benchmark_cloak_parse(content, iterations)
	local ok, cloak = pcall(require, "cloak")
	if not ok then
		return nil
	end

	-- Create a scratch buffer with env content
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content, "\n"))
	vim.api.nvim_set_current_buf(bufnr)
	vim.bo[bufnr].filetype = "dotenv"

	-- Get the pattern config cloak uses
	local pattern = cloak.opts.patterns[1]

	-- Warmup run (not timed)
	cloak.cloak(pattern)
	cloak.uncloak()

	-- Timed runs
	local total_time = 0
	for _ = 1, iterations do
		cloak.uncloak() -- Clear previous masking
		local start = hrtime()
		cloak.cloak(pattern)
		local elapsed = hrtime() - start
		total_time = total_time + elapsed
	end

	-- Cleanup
	vim.api.nvim_buf_delete(bufnr, { force = true })

	return (total_time / iterations) / 1e6 -- Convert ns to ms
end

---Benchmark camouflage.nvim masking (parsing equivalent)
---@param content string
---@param iterations number
---@return number|nil Average time in milliseconds, or nil if camouflage not available
local function benchmark_camouflage_parse(content, iterations)
	local ok, camo_core = pcall(require, "camouflage.core")
	if not ok then
		return nil
	end

	-- Create a scratch buffer with env content
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content, "\n"))
	vim.api.nvim_set_current_buf(bufnr)
	vim.api.nvim_buf_set_name(bufnr, "test.env")
	vim.bo[bufnr].filetype = "dotenv"

	-- Warmup run (not timed)
	camo_core.apply_decorations(bufnr, "test.env")
	camo_core.clear_decorations(bufnr)

	-- Timed runs
	local total_time = 0
	for _ = 1, iterations do
		camo_core.clear_decorations(bufnr)
		local start = hrtime()
		camo_core.apply_decorations(bufnr, "test.env")
		local elapsed = hrtime() - start
		total_time = total_time + elapsed
	end

	-- Cleanup
	vim.api.nvim_buf_delete(bufnr, { force = true })

	return (total_time / iterations) / 1e6 -- Convert ns to ms
end

---Benchmark Pure Lua approach (pattern matching + extmark overlay)
---This represents the DIY approach: Lua pattern matching + vim.api.nvim_buf_set_extmark
---@param content string
---@param iterations number
---@return number Average time in milliseconds
local function benchmark_pure_lua_parse(content, iterations)
	-- Create a scratch buffer with env content
	local bufnr = vim.api.nvim_create_buf(false, true)
	local buf_lines = vim.split(content, "\n")
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, buf_lines)
	vim.api.nvim_set_current_buf(bufnr)

	local ns = vim.api.nvim_create_namespace("pure_lua_bench")
	local pattern = "=()(.+)()"

	-- Warmup run (not timed)
	for lnum, line in ipairs(buf_lines) do
		local from, match, to = string.find(line, pattern)
		if from then
			local mask = string.rep("*", vim.fn.strchars(match))
			vim.api.nvim_buf_set_extmark(bufnr, ns, lnum - 1, from - 1, {
				virt_text = { { mask, "Comment" } },
				virt_text_pos = "overlay",
				end_col = to - 1,
				priority = 200,
			})
		end
	end
	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

	-- Timed runs
	local total_time = 0
	for _ = 1, iterations do
		vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
		local start = hrtime()
		for lnum, line in ipairs(buf_lines) do
			local from, match, to = string.find(line, pattern)
			if from then
				local mask = string.rep("*", vim.fn.strchars(match))
				vim.api.nvim_buf_set_extmark(bufnr, ns, lnum - 1, from - 1, {
					virt_text = { { mask, "Comment" } },
					virt_text_pos = "overlay",
					end_col = to - 1,
					priority = 200,
				})
			end
		end
		local elapsed = hrtime() - start
		total_time = total_time + elapsed
	end

	-- Cleanup
	vim.api.nvim_buf_delete(bufnr, { force = true })

	return (total_time / iterations) / 1e6 -- Convert ns to ms
end

--------------------------------------------------------------------------------
-- PREVIEW BENCHMARKS (Telescope preview scenario)
--------------------------------------------------------------------------------

---Benchmark shelter.nvim preview buffer masking
---@param content string
---@param iterations number
---@return number Average time in milliseconds
local function benchmark_shelter_preview(content, iterations)
	local buffer_mod = require("shelter.integrations.buffer")
	local extmarks = require("shelter.integrations.buffer.extmarks")

	-- Create a scratch buffer (simulates Telescope/FZF/Snacks preview buffer)
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content, "\n"))

	-- Warmup
	buffer_mod.shelter_preview_buffer(bufnr, "test.env", "dotenv")

	local total_time = 0
	for _ = 1, iterations do
		-- Clear extmarks before each run (simulates new preview)
		extmarks.clear(bufnr)
		local start = hrtime()
		buffer_mod.shelter_preview_buffer(bufnr, "test.env", "dotenv")
		local elapsed = hrtime() - start
		total_time = total_time + elapsed
	end

	vim.api.nvim_buf_delete(bufnr, { force = true })
	return (total_time / iterations) / 1e6
end

---Benchmark cloak.nvim preview (same as parse, cloak doesn't distinguish)
---@param content string
---@param iterations number
---@return number|nil Average time in milliseconds
local function benchmark_cloak_preview(content, iterations)
	-- cloak.nvim uses the same mechanism for preview
	return benchmark_cloak_parse(content, iterations)
end

---Benchmark camouflage.nvim preview (same as parse, camouflage doesn't distinguish)
---@param content string
---@param iterations number
---@return number|nil Average time in milliseconds
local function benchmark_camouflage_preview(content, iterations)
	-- camouflage.nvim uses the same mechanism for preview
	return benchmark_camouflage_parse(content, iterations)
end

---Benchmark Pure Lua preview (same as parse, no separate preview concept)
---@param content string
---@param iterations number
---@return number Average time in milliseconds
local function benchmark_pure_lua_preview(content, iterations)
	return benchmark_pure_lua_parse(content, iterations)
end

--------------------------------------------------------------------------------
-- EDIT BENCHMARKS (re-masking after text change)
--------------------------------------------------------------------------------

---Benchmark shelter.nvim re-masking after edit (incremental path)
---@param content string
---@param iterations number
---@return number Average time in milliseconds
local function benchmark_shelter_edit(content, iterations)
	local buffer_mod = require("shelter.integrations.buffer")
	local extmarks = require("shelter.integrations.buffer.extmarks")
	local masking = require("shelter.masking")

	-- Create buffer and set up
	local bufnr = vim.api.nvim_create_buf(false, true)
	local lines = vim.split(content, "\n")
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.bo[bufnr].filetype = "dotenv"
	vim.api.nvim_set_current_buf(bufnr)

	-- Initial mask to populate cache
	buffer_mod.shelter_buffer(bufnr, true)

	local total_time = 0
	for i = 1, iterations do
		-- Simulate edit (modify first line - like typing)
		local new_line = "MODIFIED_" .. i .. "=new_secret_value_xxxxx"
		lines[1] = new_line
		vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { new_line })

		-- Directly test incremental path (what on_lines callback does)
		-- Clear only the affected range
		extmarks.clear_range(bufnr, 0, 2)

		local start = hrtime()
		-- Call with line_range to test incremental path
		buffer_mod.shelter_buffer(bufnr, true, { min_line = 0, max_line = 1 })
		local elapsed = hrtime() - start
		total_time = total_time + elapsed
	end

	vim.api.nvim_buf_delete(bufnr, { force = true })
	return (total_time / iterations) / 1e6
end

---Benchmark cloak.nvim re-masking after edit
---@param content string
---@param iterations number
---@return number|nil Average time in milliseconds
local function benchmark_cloak_edit(content, iterations)
	local ok, cloak = pcall(require, "cloak")
	if not ok then
		return nil
	end

	-- Create buffer
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content, "\n"))
	vim.api.nvim_set_current_buf(bufnr)
	vim.bo[bufnr].filetype = "dotenv"

	local pattern = cloak.opts.patterns[1]

	-- Initial mask
	cloak.cloak(pattern)

	local total_time = 0
	for i = 1, iterations do
		-- Simulate edit
		vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { "MODIFIED_" .. i .. "=new_secret_value_xxxxx" })

		-- cloak re-masks on TextChanged (uncloak + cloak)
		cloak.uncloak()
		local start = hrtime()
		cloak.cloak(pattern)
		local elapsed = hrtime() - start
		total_time = total_time + elapsed
	end

	vim.api.nvim_buf_delete(bufnr, { force = true })
	return (total_time / iterations) / 1e6
end

---Benchmark camouflage.nvim re-masking after edit
---@param content string
---@param iterations number
---@return number|nil Average time in milliseconds
local function benchmark_camouflage_edit(content, iterations)
	local ok, camo_core = pcall(require, "camouflage.core")
	if not ok then
		return nil
	end

	-- Create buffer
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content, "\n"))
	vim.api.nvim_set_current_buf(bufnr)
	vim.api.nvim_buf_set_name(bufnr, "test_edit.env")
	vim.bo[bufnr].filetype = "dotenv"

	-- Initial mask
	camo_core.apply_decorations(bufnr, "test_edit.env")

	local total_time = 0
	for i = 1, iterations do
		-- Simulate edit
		vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { "MODIFIED_" .. i .. "=new_secret_value_xxxxx" })

		-- camouflage re-masks by clearing + reapplying (full buffer)
		camo_core.clear_decorations(bufnr)
		local start = hrtime()
		camo_core.apply_decorations(bufnr, "test_edit.env")
		local elapsed = hrtime() - start
		total_time = total_time + elapsed
	end

	vim.api.nvim_buf_delete(bufnr, { force = true })
	return (total_time / iterations) / 1e6
end

---Benchmark Pure Lua re-masking after edit (full buffer re-scan)
---@param content string
---@param iterations number
---@return number Average time in milliseconds
local function benchmark_pure_lua_edit(content, iterations)
	-- Create buffer
	local bufnr = vim.api.nvim_create_buf(false, true)
	local buf_lines = vim.split(content, "\n")
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, buf_lines)
	vim.api.nvim_set_current_buf(bufnr)

	local ns = vim.api.nvim_create_namespace("pure_lua_bench_edit")
	local pattern = "=()(.+)()"

	-- Initial mask
	for lnum, line in ipairs(buf_lines) do
		local from, match, to = string.find(line, pattern)
		if from then
			local mask = string.rep("*", vim.fn.strchars(match))
			vim.api.nvim_buf_set_extmark(bufnr, ns, lnum - 1, from - 1, {
				virt_text = { { mask, "Comment" } },
				virt_text_pos = "overlay",
				end_col = to - 1,
				priority = 200,
			})
		end
	end

	local total_time = 0
	for i = 1, iterations do
		-- Simulate edit
		local new_line = "MODIFIED_" .. i .. "=new_secret_value_xxxxx"
		buf_lines[1] = new_line
		vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { new_line })

		-- Pure Lua re-processes entire buffer on change (no incremental path)
		vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
		local start = hrtime()
		for lnum, line in ipairs(buf_lines) do
			local from, match, to = string.find(line, pattern)
			if from then
				local mask = string.rep("*", vim.fn.strchars(match))
				vim.api.nvim_buf_set_extmark(bufnr, ns, lnum - 1, from - 1, {
					virt_text = { { mask, "Comment" } },
					virt_text_pos = "overlay",
					end_col = to - 1,
					priority = 200,
				})
			end
		end
		local elapsed = hrtime() - start
		total_time = total_time + elapsed
	end

	vim.api.nvim_buf_delete(bufnr, { force = true })
	return (total_time / iterations) / 1e6
end

--------------------------------------------------------------------------------
-- MAIN RUNNER
--------------------------------------------------------------------------------

---Round to 3 decimal places
---@param n number
---@return number
local function round3(n)
	return math.floor(n * 1000) / 1000
end

---Main benchmark runner
local function run_benchmarks()
	local results = {
		metadata = {
			iterations = ITERATIONS,
			timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
			neovim_version = vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch,
		},
		benchmarks = {},
	}

	for _, size in ipairs(SIZES) do
		local content = generate_env_content(size)

		print(string.format("\n=== Benchmarking %d lines ===", size))

		-- Parsing benchmarks
		local shelter_parse = benchmark_shelter_parse(content, ITERATIONS)
		local cloak_parse = benchmark_cloak_parse(content, ITERATIONS)
		local camouflage_parse = benchmark_camouflage_parse(content, ITERATIONS)
		local pure_lua_parse = benchmark_pure_lua_parse(content, ITERATIONS)
		local fmt_ms = function(v) return v and string.format("%.3fms", v) or "N/A" end
		print(string.format(
			"  Parse:   shelter=%.3fms, cloak=%s, camouflage=%s, pure_lua=%s",
			shelter_parse, fmt_ms(cloak_parse), fmt_ms(camouflage_parse), fmt_ms(pure_lua_parse)
		))

		-- Preview benchmarks
		local shelter_preview = benchmark_shelter_preview(content, ITERATIONS)
		local cloak_preview = benchmark_cloak_preview(content, ITERATIONS)
		local camouflage_preview = benchmark_camouflage_preview(content, ITERATIONS)
		local pure_lua_preview = benchmark_pure_lua_preview(content, ITERATIONS)
		print(string.format(
			"  Preview: shelter=%.3fms, cloak=%s, camouflage=%s, pure_lua=%s",
			shelter_preview, fmt_ms(cloak_preview), fmt_ms(camouflage_preview), fmt_ms(pure_lua_preview)
		))

		-- Edit benchmarks
		local shelter_edit = benchmark_shelter_edit(content, ITERATIONS)
		local cloak_edit = benchmark_cloak_edit(content, ITERATIONS)
		local camouflage_edit = benchmark_camouflage_edit(content, ITERATIONS)
		local pure_lua_edit = benchmark_pure_lua_edit(content, ITERATIONS)
		print(string.format(
			"  Edit:    shelter=%.3fms, cloak=%s, camouflage=%s, pure_lua=%s",
			shelter_edit, fmt_ms(cloak_edit), fmt_ms(camouflage_edit), fmt_ms(pure_lua_edit)
		))

		results.benchmarks[tostring(size)] = {
			lines = size,
			-- Parsing (raw engine)
			shelter_parse_ms = round3(shelter_parse),
			cloak_parse_ms = cloak_parse and round3(cloak_parse) or nil,
			camouflage_parse_ms = camouflage_parse and round3(camouflage_parse) or nil,
			pure_lua_parse_ms = pure_lua_parse and round3(pure_lua_parse) or nil,
			-- Preview (Telescope/FZF)
			shelter_preview_ms = round3(shelter_preview),
			cloak_preview_ms = cloak_preview and round3(cloak_preview) or nil,
			camouflage_preview_ms = camouflage_preview and round3(camouflage_preview) or nil,
			pure_lua_preview_ms = pure_lua_preview and round3(pure_lua_preview) or nil,
			-- Edit (re-masking)
			shelter_edit_ms = round3(shelter_edit),
			cloak_edit_ms = cloak_edit and round3(cloak_edit) or nil,
			camouflage_edit_ms = camouflage_edit and round3(camouflage_edit) or nil,
			pure_lua_edit_ms = pure_lua_edit and round3(pure_lua_edit) or nil,
		}
	end

	-- Write JSON to file
	local json = vim.json.encode(results)
	local f = io.open(OUTPUT_FILE, "w")
	if f then
		f:write(json)
		f:close()
		print("\nResults written to " .. OUTPUT_FILE)
	else
		print("\nERROR: Could not write to " .. OUTPUT_FILE)
	end
end

-- Run and exit
run_benchmarks()
vim.cmd("qa!")
