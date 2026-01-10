-- Minimal init for benchmark tests
-- Run with: nvim --headless -u benchmarks/minimal_init.lua -l benchmarks/benchmark.lua

-- Set up runtimepath to include shelter.nvim
local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.runtimepath:prepend(plugin_root)

-- Add cloak.nvim to runtimepath (cloned by CI to /tmp/cloak.nvim)
local cloak_paths = {
  "/tmp/cloak.nvim",
  vim.fn.expand("~/.local/share/nvim/lazy/cloak.nvim"),
  vim.fn.expand("~/.local/share/nvim/site/pack/vendor/start/cloak.nvim"),
}

for _, cloak_path in ipairs(cloak_paths) do
  if vim.fn.isdirectory(cloak_path) == 1 then
    vim.opt.runtimepath:prepend(cloak_path)
    break
  end
end

-- Initialize shelter.nvim with default config
require("shelter").setup({
  skip_comments = true,
  mask_char = "*",
  default_mode = "full",
})

-- Initialize cloak.nvim with matching config
local cloak_ok, cloak = pcall(require, "cloak")
if cloak_ok then
  cloak.setup({
    enabled = true,
    cloak_character = "*",
    highlight_group = "Comment",
    patterns = {
      {
        file_pattern = ".env*",
        cloak_pattern = "=.+",
      },
    },
  })
end
