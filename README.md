# shelter.nvim

<div align="center">

![Neovim](https://img.shields.io/badge/NeoVim-%2357A143.svg?&style=for-the-badge&logo=neovim&logoColor=white)
![Lua](https://img.shields.io/badge/lua-%232C2D72.svg?style=for-the-badge&logo=lua&logoColor=white)
![Rust](https://img.shields.io/badge/rust-%23000000.svg?style=for-the-badge&logo=rust&logoColor=white)

**Protect sensitive values in your environment files with intelligent, blazingly fast masking.**

</div>

---

## Why shelter.nvim?

- **Blazingly Fast**: 1.1x-5x faster than alternatives with Rust-native parsing and line-specific re-masking
- **Instant Feedback**: No debounce delay - masks update immediately as you type
- **Smart Re-masking**: Only re-processes changed lines, not the entire buffer
- **EDF Compliant**: Full support for quotes, escapes, and multi-line values
- **Extensible**: Factory pattern mode system with unlimited custom modes

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Commands](#commands)
- [Mode System](#mode-system)
- [Pattern Matching](#pattern-matching)
- [Performance](#performance)
- [Comparison with cloak.nvim](#comparison-with-cloaknvim)
- [API Reference](#api-reference)
- [Architecture](#architecture)
- [License](#license)

---

## Features

### Core

- **Buffer Masking**: Auto-mask values in `.env` files on open
- **Line Peek**: Reveal values temporarily with `:Shelter peek` (3-second auto-hide)
- **Quote Preservation**: Masks preserve surrounding quotes visually

### Integrations

- **Telescope**: Mask values in file previews
- **FZF-lua**: Mask values in file previews
- **Snacks.nvim**: Mask values in file previews
- **Completion**: Auto-disable nvim-cmp/blink-cmp in env buffers

### Mode System

- **Built-in Modes**: `full`, `partial`, `none`
- **Custom Modes**: Define unlimited custom masking behaviors
- **Pattern Matching**: Map glob patterns to modes per-key or per-file

---

## Requirements

- Neovim 0.9+
- LuaJIT (included with Neovim)
- Rust toolchain (for building)

---

## Installation

### lazy.nvim

```lua
{
  "philosofonusus/shelter.nvim",
  build = "build.lua",
  config = function()
    require("shelter").setup({})
  end,
}
```

### packer.nvim

```lua
use {
  "philosofonusus/shelter.nvim",
  run = "build.lua",
  config = function()
    require("shelter").setup({})
  end,
}
```

---

## Quick Start

```lua
-- Minimal: just buffer masking
require("shelter").setup({})

-- With Telescope previewer
require("shelter").setup({
  modules = {
    files = true,
    telescope_previewer = true,
  },
})

-- Partial masking by default
require("shelter").setup({
  default_mode = "partial",
})
```

---

## Configuration

```lua
require("shelter").setup({
  -- Masking character
  mask_char = "*",

  -- Highlight group for masked text
  highlight_group = "Comment",

  -- Skip masking in comment lines
  skip_comments = true,

  -- Default mode: "full" | "partial" | "none" | custom
  default_mode = "full",

  -- Filetypes to mask
  env_filetypes = { "dotenv", "sh", "conf" },

  -- Mode configurations
  modes = {
    full = {
      mask_char = "*",
      preserve_length = true,
      -- fixed_length = 8,  -- Override with fixed length
    },
    partial = {
      show_start = 3,
      show_end = 3,
      min_mask = 3,
      fallback_mode = "full",  -- For short values
    },
  },

  -- Key patterns -> mode mapping (glob syntax)
  patterns = {
    ["*_PUBLIC"] = "none",
    ["*_SECRET"] = "full",
    ["DB_*"] = "partial",
  },

  -- Source file patterns -> mode mapping
  sources = {
    [".env.local"] = "none",
    [".env.production"] = "full",
  },

  -- Module toggles
  modules = {
    files = {
      shelter_on_leave = true,
      disable_cmp = true,
    },
    telescope_previewer = false,
    fzf_previewer = false,
    snacks_previewer = false,
  },
})
```

---

## Commands

| Command                     | Description                     |
| --------------------------- | ------------------------------- |
| `:Shelter toggle [module]`  | Toggle masking on/off           |
| `:Shelter enable [module]`  | Enable masking                  |
| `:Shelter disable [module]` | Disable masking                 |
| `:Shelter peek`             | Reveal current line (3 seconds) |
| `:Shelter info`             | Show status and modes           |
| `:Shelter build`            | Rebuild native library          |

**Modules**: `files`, `telescope_previewer`, `fzf_previewer`, `snacks_previewer`

---

## Mode System

### Built-in Modes

| Mode      | Example                    | Description                 |
| --------- | -------------------------- | --------------------------- |
| `full`    | `secret123` → `*********`  | Mask all characters         |
| `partial` | `secret123` → `sec****123` | Show start/end, mask middle |
| `none`    | `secret123` → `secret123`  | No masking                  |

### Custom Modes

```lua
require("shelter").setup({
  modes = {
    -- Simple custom mode
    redact = {
      description = "Replace with [REDACTED]",
      apply = function(self, ctx)
        return "[REDACTED]"
      end,
    },

    -- With options
    truncate = {
      description = "Truncate with suffix",
      schema = {
        max_length = { type = "number", default = 5 },
        suffix = { type = "string", default = "..." },
      },
      apply = function(self, ctx)
        local max = self.options.max_length
        if #ctx.value <= max then
          return ctx.value
        end
        return ctx.value:sub(1, max) .. self.options.suffix
      end,
    },
  },

  patterns = {
    ["*_TOKEN"] = "truncate",
  },
})
```

### Mode Context

```lua
---@class ShelterModeContext
---@field key string           -- Variable name (e.g., "API_KEY")
---@field value string         -- Original value
---@field source string|nil    -- File path
---@field line_number number   -- Line in file
---@field quote_type number    -- 0=none, 1=single, 2=double
---@field is_comment boolean   -- In a comment?
---@field config table         -- Plugin config
```

---

## Pattern Matching

### Key Patterns (Glob Syntax)

```lua
patterns = {
  ["*_KEY"] = "full",       -- API_KEY, SECRET_KEY
  ["*_PUBLIC*"] = "none",   -- PUBLIC_KEY, MY_PUBLIC_VAR
  ["DB_*"] = "partial",     -- DB_HOST, DB_PASSWORD
  ["DEBUG"] = "none",       -- Exact match
}
```

### Source File Patterns

```lua
sources = {
  [".env.local"] = "none",
  [".env.production"] = "full",
  [".env.*.local"] = "none",
}
```

### Priority

1. Specific key pattern match
2. Specific source pattern match
3. Default mode

---

## Performance

<!-- BENCHMARK_START -->
### Performance Benchmarks

Measured on GitHub Actions (Ubuntu, averaged over 100 iterations):

#### Parsing Performance

| Lines | shelter.nvim | cloak.nvim | Difference |
|-------|--------------|------------|------------|
| 10    | 0.02 ms      | 0.07 ms      | 3.2x faster |
| 50    | 0.05 ms      | 0.18 ms      | 3.6x faster |
| 100    | 0.08 ms      | 0.36 ms      | 4.4x faster |
| 500    | 0.42 ms      | 1.85 ms      | 4.4x faster |

#### Preview Performance (Telescope)

| Lines | shelter.nvim | cloak.nvim | Difference |
|-------|--------------|------------|------------|
| 10    | 0.02 ms      | 0.05 ms      | 2.7x faster |
| 50    | 0.04 ms      | 0.18 ms      | 4.1x faster |
| 100    | 0.07 ms      | 0.38 ms      | 5.7x faster |
| 500    | 0.45 ms      | 2.01 ms      | 4.5x faster |

#### Edit Re-masking Performance

| Lines | shelter.nvim | cloak.nvim | Difference |
|-------|--------------|------------|------------|
| 10    | 0.05 ms      | 0.05 ms      | ~same |
| 50    | 0.16 ms      | 0.19 ms      | 1.2x faster |
| 100    | 0.33 ms      | 0.41 ms      | 1.2x faster |
| 500    | 1.76 ms      | 1.71 ms      | ~same |

*Last updated: 2026-01-11*
<!-- BENCHMARK_END -->

### Why So Fast?

1. **Rust-Native Parsing**: EDF parsing via LuaJIT FFI - no Lua pattern matching overhead
2. **Line-Specific Re-masking**: On edit, only affected lines are re-processed
3. **Zero Debounce**: Instant mask updates with `nvim_buf_attach` on_lines callback
4. **Pre-computed Offsets**: O(1) byte-to-line conversion from Rust

---

## Comparison with cloak.nvim

| Feature                | shelter.nvim               | cloak.nvim            |
| ---------------------- | -------------------------- | --------------------- |
| **Performance**        | ✅ **1.1x-5x faster**      | 🟡 Pure Lua           |
| **Re-masking**         | ✅ Line-specific (instant) | 🟡 Full buffer        |
| **Partial Masking**    | ✅ Built-in mode           | 🟡 Pattern workaround |
| **Multi-line Values**  | ✅ Full support            | ❌ None               |
| **Quote Handling**     | ✅ EDF compliant           | 🟡 Pattern-dependent  |
| **Preview Support**    | ✅ Telescope, FZF, Snacks  | 🟡 Telescope only     |
| **Completion Disable** | ✅ nvim-cmp + blink-cmp    | 🟡 nvim-cmp only      |
| **Custom Modes**       | ✅ Factory pattern         | 🟡 Lua patterns       |
| **Runtime Info**       | ✅ `:Shelter info`         | ❌ None               |
| **Build Step**         | 🟡 Requires Rust           | ✅ None               |
| **Any Filetype**       | 🟡 Env files only          | ✅ Any filetype       |
| **Lines of Code**      | 🟡 ~2500 LOC               | ✅ ~300 LOC           |

**Choose shelter.nvim** for dotenv files with maximum performance and features.

**Choose cloak.nvim** for any filetype with minimal setup.

---

## API Reference

```lua
local shelter = require("shelter")

-- Setup
shelter.setup(opts)

-- State
shelter.is_enabled("files")      -- Check module status
shelter.toggle("files")          -- Toggle module
shelter.get_config()             -- Get configuration

-- Actions
shelter.peek()                   -- Reveal current line
shelter.info()                   -- Show plugin info
shelter.build()                  -- Build native library

-- Modes
shelter.register_mode(name, def) -- Register custom mode
shelter.mask_value(value, opts)  -- Mask a value directly
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    shelter.nvim (Lua)                   │
├─────────────────────────────────────────────────────────┤
│  Config │ State │ Mode Factory │ Engine │ Integrations │
└─────────────────────────────────────────────────────────┘
                          │ LuaJIT FFI
                          ▼
┌─────────────────────────────────────────────────────────┐
│               shelter-core (Rust cdylib)                │
├─────────────────────────────────────────────────────────┤
│         EDF Parsing (korni) + Line Offsets              │
└─────────────────────────────────────────────────────────┘
```

### Key Components

- **Engine**: Coordinates parsing, mode selection, and mask generation
- **Mode Factory**: Creates and manages masking mode instances
- **Extmarks**: Applies masks via Neovim's extmark API with virtual text
- **nvim_buf_attach**: Tracks line changes for instant re-masking

---

## License

MIT
