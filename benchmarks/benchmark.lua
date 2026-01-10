-- Performance benchmark: shelter.nvim vs cloak.nvim
-- Run with: nvim --headless -u benchmarks/minimal_init.lua -l benchmarks/benchmark.lua
--
-- Output: JSON file (benchmark_results.json) with timing results

local ITERATIONS = 10
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

---Benchmark shelter.nvim masking engine
---@param content string
---@param iterations number
---@return number Average time in milliseconds
local function benchmark_shelter(content, iterations)
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

---Benchmark cloak.nvim masking
---@param content string
---@param iterations number
---@return number|nil Average time in milliseconds, or nil if cloak not available
local function benchmark_cloak(content, iterations)
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

    local shelter_time = benchmark_shelter(content, ITERATIONS)
    local cloak_time = benchmark_cloak(content, ITERATIONS)

    results.benchmarks[tostring(size)] = {
      lines = size,
      shelter_ms = math.floor(shelter_time * 1000) / 1000, -- 3 decimal places
      cloak_ms = cloak_time and (math.floor(cloak_time * 1000) / 1000) or nil,
    }

    -- Print progress
    print(string.format("Completed %d lines: shelter=%.3fms, cloak=%s",
      size, shelter_time, cloak_time and string.format("%.3fms", cloak_time) or "N/A"))
  end

  -- Write JSON to file
  local json = vim.json.encode(results)
  local f = io.open(OUTPUT_FILE, "w")
  if f then
    f:write(json)
    f:close()
    print("Results written to " .. OUTPUT_FILE)
  else
    print("ERROR: Could not write to " .. OUTPUT_FILE)
  end
end

-- Run and exit
run_benchmarks()
vim.cmd("qa!")
