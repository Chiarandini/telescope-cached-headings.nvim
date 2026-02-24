# telescope-cached-headings.nvim

A Telescope extension for fast heading navigation in large files. Instead of
parsing headings on every invocation, the plugin writes a small cache file on
first use — making the picker essentially instant on 100k+ line LaTeX documents
where live parsing causes noticeable UI lag.

## Features

- **Instant opening** after the first use — cache is read, not regenerated
- **Smart Jump** — automatically finds a heading if it has shifted since the
  cache was written, and silently updates the cache entry
- **LaTeX, Markdown, and Org-mode** support out of the box
- **Starred LaTeX variants** (`\section*`, etc.) via opt-in config flag
- **Two cache strategies**: global (tidy) or local (inspectable)
- **Auto-update** on save via `BufWritePost` (opt-in)
- **Wipe all caches** in one command when you need a clean slate

## Requirements

- [nvim-telescope/telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [nvim-lua/plenary.nvim](https://github.com/nvim-lua/plenary.nvim)

## Installation

**lazy.nvim**

```lua
{
  "your-username/telescope-cached-headings.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim",
  },
  config = function()
    require("telescope").load_extension("cached_headings")
  end,
}
```

**packer.nvim**

```lua
use {
  "your-username/telescope-cached-headings.nvim",
  requires = {
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim",
  },
  config = function()
    require("telescope").load_extension("cached_headings")
  end,
}
```

## Setup

Pass options inside `telescope.setup()`:

```lua
require("telescope").setup({
  extensions = {
    cached_headings = {
      -- all keys are optional; defaults shown below
      cache_strategy    = "global",
      allowed_filetypes = { "tex", "markdown", "org" },
      auto_update       = false,
      enable_smart_jump = true,
      smart_jump_window = 200,
      include_starred   = false,
    },
  },
})

require("telescope").load_extension("cached_headings")
```

Suggested keybindings:

```lua
vim.keymap.set("n", "<leader>fh",
  "<cmd>Telescope cached_headings<cr>",
  { desc = "Find headings (cached)" })

vim.keymap.set("n", "<leader>fH",
  "<cmd>CachedHeadingsWipeAll<cr>",
  { desc = "Wipe all heading caches" })
```

## Usage

```
:Telescope cached_headings
```

- The first time you open the picker for a file, the cache is generated
  automatically. All subsequent opens read the cache directly.
- Headings are displayed with level-based indentation to visualise the
  document hierarchy.
- Selecting a heading triggers the **Smart Jump** (see below).

To force-rebuild the cache after making structural changes:

```
:CachedHeadingsUpdate
```

To delete every cache file and start fresh:

```
:CachedHeadingsWipeAll
```

## Smart Jump

When you select a heading the plugin verifies whether the cached line number
still holds the expected heading text in the live buffer:

| Situation | Behaviour |
|-----------|-----------|
| Exact match | Silent jump |
| Heading shifted | Jump to new position, auto-update cache entry, print info message |
| Heading missing | Jump to cached line, print warning asking you to run `:CachedHeadingsUpdate` |

Set `enable_smart_jump = false` to skip verification and always jump directly
to the cached line number.

## Configuration Reference

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `cache_strategy` | `string` | `"global"` | `"global"` stores caches in `stdpath("data")/cached_headings/`; `"local"` places a hidden `.filename.headings` file next to your source file |
| `allowed_filetypes` | `string[]` | `{"tex","markdown","org"}` | Filetypes the plugin activates for |
| `auto_update` | `boolean` | `false` | Regenerate cache on every `BufWritePost` for supported files |
| `enable_smart_jump` | `boolean` | `true` | Search for shifted headings instead of jumping blindly |
| `smart_jump_window` | `integer` | `200` | Lines to search on each side of the cached position |
| `include_starred` | `boolean` | `false` | Include LaTeX starred variants (`\section*`, etc.) |

## Cache Format

Cache files are plain text — one heading per line:

```
line_number|level|full_heading_text
```

Example:

```
12|1|\part{Foundations}
45|3|\section{Introduction}
78|4|\subsection{Motivation}
```

This format is human-readable and trivial to parse. For `"local"` strategy the
file is placed next to your source file (add `*.headings` to `.gitignore`).

## Help

Full documentation is available in Neovim after installation:

```
:help telescope-cached-headings
```
