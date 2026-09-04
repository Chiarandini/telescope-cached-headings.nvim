# telescope-cached-headings.nvim

A Telescope extension for fast heading navigation in large files. Uses fast parsing
strategies since ```Telescope headings``` lags on my huge files. Furthermore, instead of
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
- **Multi-file LaTeX** — follow `\input`, `\include`, and `\subfile` directives
  and show all headings from the entire document in a single unified picker
- **Subfile toggle** — when editing a LaTeX subfile (using the `subfiles` package),
  press a key to instantly switch between a local view of just your subfile's
  headings and a full document view, with the cursor pre-positioned on the first
  heading from your subfile
- **Copy with transform** — press a key inside the picker to copy the selected
  heading's title to the system clipboard; an optional `copy_transform` hook lets
  you wrap or reformat it before copying

## Requirements

- [nvim-telescope/telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [nvim-lua/plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [Chiarandini/latex-nav-core.nvim](https://github.com/Chiarandini/latex-nav-core.nvim) — shared cache utilities

## Why so fast?

 1. Streaming with io.lines(): The file is never fully loaded into memory. io.lines() is a lazy iterator that reads one line at a time from the C standard library — no Lua table holding 100k lines, no calling vim.fn.readfile()

  2. Pre-compiled patterns:
  The LaTeX patterns are built once at module load time via an IIFE and stored in LATEX_PATTERNS. Inside the loop,
  line:find(pat.plain) reuses the same compiled pattern string on every line rather than constructing a new pattern string per line.

  3. Early-exit pattern matching:
  For each line it tries line:find(pat.plain) first. ```string.find``` anchors to the start (^)
  so it bails out immediately on the vast majority of lines (anything that doesn't start
  with \section etc.) — the match fails in O(1) on non-heading lines.

  4. Caching:
  After the first scan, results are written to a flat text file. Subsequent opens read the cache instead of rescanning. The cache is only invalidated when the file's mtime changes (or manually).

  So for a 100k-line LaTeX file, most of the lines are rejected by a single anchored ```string.find``` call, the rest of the file is streamed without ever sitting in memory, and after the first open it's just a cache read.

## Installation

**lazy.nvim**

```lua
{
  "Chiarandini/telescope-cached-headings.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim",
    "Chiarandini/latex-nav-core.nvim",
  },
  config = function()
    require("telescope").load_extension("cached_headings")
  end,
}
```

**packer.nvim**

```lua
use {
  "Chiarandini/telescope-cached-headings.nvim",
  requires = {
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim",
    "Chiarandini/latex-nav-core.nvim",
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

      -- Multi-file LaTeX: follow \input / \include / \subfile directives
      scan_includes          = false,
      recursive_limit        = 5,
      ignore_include_pattern = "",

      -- Subfile toggle: manual root override and toggle key
      root_file          = "",
      subfile_toggle_key = "<C-g>",

      -- Copy heading title to clipboard
      copy_label_key = "<C-y>",
      -- copy_transform: nil (raw title), a prefix→format table, or a function.
      -- copy_transform = function(title) return "[[" .. title .. "]]" end,
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

## Multi-file LaTeX

When `scan_includes = true`, the picker follows `\input`, `\include`, and
`\subfile` directives and shows all headings from the entire document tree in
document order. Each heading from an included file is annotated with its
relative filename (shown in a dimmed colour), so you can filter by filename as
well as heading text.

```lua
cached_headings = {
  scan_includes          = true,
  recursive_limit        = 5,   -- max nesting depth
  ignore_include_pattern = "appendix",  -- skip paths matching this Lua pattern
}
```

Jumping to a heading in an included file opens that file automatically.

## Subfile Toggle

If you work with the LaTeX [`subfiles`](https://ctan.org/pkg/subfiles) package,
the plugin detects when you are editing a subfile by looking for a
`\documentclass[root.tex]{subfiles}` declaration near the top of the file.

When detected, the picker title changes to indicate the current mode and the
available toggle key:

- **Local mode** (default): shows only the current subfile's headings —
  title reads `Headings (subfile) [<C-g>: full doc]`
- **Global mode**: shows the full document TOC scanned from the root file,
  with the cursor pre-positioned on the first heading from your subfile —
  title reads `Headings (full doc) [<C-g>: subfile]`

Press the toggle key (`<C-g>` by default) inside the picker to switch between
modes. Press it again to return.

If your root file is not resolvable from `\documentclass[...]` (e.g. the
argument is a variable or an unusual path), you can set `root_file` to an
absolute path as a fallback:

```lua
cached_headings = {
  root_file          = "/home/user/thesis/main.tex",
  subfile_toggle_key = "<C-g>",
}
```

## Copy Heading

Press `copy_label_key` (default `<C-y>`) inside the picker to copy the selected
heading's title to the system clipboard (`+` register) without jumping to the
file. The copied text is the clean, extracted title — e.g. `Introduction` from
`\section{Introduction}` or `## Introduction`.

### `copy_transform`

An optional hook that transforms the title string before it is placed in the
clipboard. Accepts two forms:

**Table** — map title prefixes to Lua format strings (`%s` is replaced with the
full title):

```lua
copy_transform = {
  ["Appendix"] = "appendix~\\ref{%s}",
},
```

**Function** — for any transformation logic:

```lua
copy_transform = function(title)
  return "[[" .. title .. "]]"  -- wiki-link style
end,
```

When `copy_transform` is `nil` (the default) the raw extracted title is copied.

## Configuration Reference

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `cache_strategy` | `string` | `"global"` | `"global"` stores caches in `stdpath("data")/cached_headings/`; `"local"` places a hidden `.filename.headings` file next to your source file |
| `allowed_filetypes` | `string[]` | `{"tex","markdown","org"}` | Filetypes the plugin activates for |
| `auto_update` | `boolean` | `false` | Regenerate cache on every `BufWritePost` for supported files |
| `enable_smart_jump` | `boolean` | `true` | Search for shifted headings instead of jumping blindly |
| `smart_jump_window` | `integer` | `200` | Lines to search on each side of the cached position |
| `include_starred` | `boolean` | `false` | Include LaTeX starred variants (`\section*`, etc.) |
| `scan_includes` | `boolean` | `false` | Follow `\input`/`\include`/`\subfile` and show the whole document tree |
| `recursive_limit` | `integer` | `5` | Maximum include nesting depth (guards against circular includes) |
| `ignore_include_pattern` | `string` | `""` | Lua pattern — include paths matching it are skipped |
| `root_file` | `string` | `""` | Absolute path to the root `.tex` file; fallback when auto-detection fails |
| `subfile_toggle_key` | `string` | `"<C-g>"` | Key to toggle between local and full-document view inside the picker |
| `copy_label_key` | `string` | `"<C-y>"` | Key to copy the selected heading title to the system clipboard without opening the file |
| `copy_transform` | `table\|function\|nil` | `nil` | Transform applied to the heading title before copying; see [Copy Heading](#copy-heading) |

## Cache Format

Cache files are plain text and human-readable. Single-file caches use one line
per heading:

```
line_number|level|full_heading_text
```

Multi-file caches (produced when `scan_includes = true`) use a versioned format
with dependency metadata:

```
# v2
# dep:chapters/intro.tex=1718000000
# dep:chapters/conclusion.tex=1718000001
|12|1|\part{Foundations}
chapters/intro.tex|3|3|\section{Introduction}
chapters/intro.tex|10|4|\subsection{Motivation}
```

For the `"local"` cache strategy the file is placed next to your source file
(add `*.headings` to `.gitignore`).

## Help

Full documentation is available in Neovim after installation:

```
:help telescope-cached-headings
```
