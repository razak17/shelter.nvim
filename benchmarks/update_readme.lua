-- Update README.md with benchmark results
-- Run with: nvim --headless -u benchmarks/minimal_init.lua -l benchmarks/update_readme.lua
--
-- Reads benchmark_results.json and updates the Performance Benchmarks section in README.md

local RESULTS_FILE = "benchmark_results.json"
local README_FILE = "README.md"
local BENCHMARK_START_MARKER = "<!-- BENCHMARK_START -->"
local BENCHMARK_END_MARKER = "<!-- BENCHMARK_END -->"

---Read file contents
---@param path string
---@return string|nil
local function read_file(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  return content
end

---Write file contents
---@param path string
---@param content string
---@return boolean
local function write_file(path, content)
  local f = io.open(path, "w")
  if not f then
    return false
  end
  f:write(content)
  f:close()
  return true
end

---Format a benchmark row
---@param data table
---@return string
local function format_row(data)
  local lines = data.lines
  local shelter = string.format("%.2f ms", data.shelter_ms)
  local cloak = data.cloak_ms and string.format("%.2f ms", data.cloak_ms) or "N/A"

  local diff = ""
  if data.cloak_ms and data.shelter_ms > 0 then
    local ratio = data.cloak_ms / data.shelter_ms
    if ratio > 1 then
      diff = string.format("%.1fx faster", ratio)
    elseif ratio < 1 then
      diff = string.format("%.1fx slower", 1 / ratio)
    else
      diff = "same"
    end
  end

  return string.format("| %d    | %s      | %s      | %s |", lines, shelter, cloak, diff)
end

---Generate the benchmark table markdown
---@param results table
---@return string
local function generate_benchmark_section(results)
  local lines = {
    BENCHMARK_START_MARKER,
    "### Performance Benchmarks",
    "",
    string.format("Measured on GitHub Actions (Ubuntu, averaged over %d iterations):", results.metadata.iterations),
    "",
    "| Lines | shelter.nvim | cloak.nvim | Difference |",
    "|-------|--------------|------------|------------|",
  }

  -- Sort by line count
  local sizes = {}
  for size in pairs(results.benchmarks) do
    table.insert(sizes, tonumber(size))
  end
  table.sort(sizes)

  for _, size in ipairs(sizes) do
    local data = results.benchmarks[tostring(size)]
    table.insert(lines, format_row(data))
  end

  table.insert(lines, "")
  table.insert(lines, string.format("*Last updated: %s*", results.metadata.timestamp:sub(1, 10)))
  table.insert(lines, BENCHMARK_END_MARKER)

  return table.concat(lines, "\n")
end

---Main function
local function main()
  -- Read benchmark results
  local results_json = read_file(RESULTS_FILE)
  if not results_json then
    io.stderr:write("Error: Could not read " .. RESULTS_FILE .. "\n")
    vim.cmd("cq 1")
    return
  end

  local ok, results = pcall(vim.json.decode, results_json)
  if not ok then
    io.stderr:write("Error: Invalid JSON in " .. RESULTS_FILE .. "\n")
    vim.cmd("cq 1")
    return
  end

  -- Read README
  local readme = read_file(README_FILE)
  if not readme then
    io.stderr:write("Error: Could not read " .. README_FILE .. "\n")
    vim.cmd("cq 1")
    return
  end

  -- Generate new benchmark section
  local new_section = generate_benchmark_section(results)

  -- Replace or append benchmark section
  local start_pos = readme:find(BENCHMARK_START_MARKER, 1, true)
  local end_pos = readme:find(BENCHMARK_END_MARKER, 1, true)

  local new_readme
  if start_pos and end_pos then
    -- Replace existing section
    new_readme = readme:sub(1, start_pos - 1) .. new_section .. readme:sub(end_pos + #BENCHMARK_END_MARKER)
  else
    -- Find the end of the comparison table section and insert after it
    -- Look for "### When to Choose cloak.nvim" or similar marker
    local insert_after = readme:find("### When to Choose cloak.nvim", 1, true)
    if insert_after then
      -- Find the end of that section (next ## heading or end of file)
      local section_end = readme:find("\n## ", insert_after)
      if section_end then
        new_readme = readme:sub(1, section_end - 1) .. "\n\n" .. new_section .. "\n" .. readme:sub(section_end)
      else
        new_readme = readme .. "\n\n" .. new_section
      end
    else
      -- Fallback: append to end
      new_readme = readme .. "\n\n" .. new_section
    end
  end

  -- Write updated README
  if not write_file(README_FILE, new_readme) then
    io.stderr:write("Error: Could not write " .. README_FILE .. "\n")
    vim.cmd("cq 1")
    return
  end

  io.stderr:write("Successfully updated " .. README_FILE .. " with benchmark results\n")
  vim.cmd("qa!")
end

main()
