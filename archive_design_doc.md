# Design Document: telescope-cached-headings.nvim

## 1. Overview
`telescope-cached-headings.nvim` is a Neovim plugin designed to optimize the navigation of massive files (100k+ lines, primarily LaTeX) by caching their headings. It functions as a standard Telescope picker but intercepts the heading extraction process to check for a pre-generated cache file. This significantly reduces latency where parsing headings in real-time causes noticeable UI freezing.

## 2. Core Logic & Workflow

### 2.1 The "Picker" Workflow
Command: `:Telescope cached_headings` (or mapped keybind).

1.  **Context Detection**: Identify the current buffer's full file path and file type.
2.  **Cache Key Generation**: Determine the expected location of the cache file based on the `cache_strategy` config.
3.  **Cache Resolution**:
    *   **Scenario A (Cache Exists)**: Read the cache file. Parse the lines into Telescope entry format.
    *   **Scenario B (No Cache)**: Trigger the **High-Performance Parser**, generate the cache file immediately, and then serve the results to Telescope.
4.  **Display**: Open the Telescope prompt.
5.  **Selection (Smart Jump)**:
    *   On selection, the plugin performs a **Verification Check** (see Section 2.3).

### 2.2 The "Update" Workflow
Command: `:CachedHeadingsUpdate` (or via Telescope picker action).

1.  Force the **High-Performance Parser** to scan the current buffer.
2.  Overwrite the existing cache file.
3.  Notify the user ("Cache updated").

### 2.3 Phase 2: Stale Cache Handling (Smart Jump)
To handle the "Staleness" problem without forcing constant updates:

1.  User selects a heading from the picker (Cached location: Line 500).
2.  Plugin checks Line 500 in the actual buffer.
3.  **Match**: If Line 500 matches the cached heading text -> **Jump**.
4.  **Mismatch**:
    *   If `enable_smart_jump` is `true`:
        *   Scan a localized window (e.g., +/- 200 lines) around Line 500.
        *   **Found (e.g., at 505)**: Jump to 505, **background update the cache file**, and print: *"Heading shifted. Cache auto-updated."*
        *   **Not Found**: Jump to original Line 500 and print: *"[Warning] Heading not found at cached location. Please run :CachedHeadingsUpdate."*

## 3. Architecture & Components

### 3.1 Parsing Strategy (Efficiency)
For files with ~100,000 lines, DOM-based parsers (like Treesitter) can sometimes incur startup overhead.
*   **Primary Method** (suggestion): Lua `io.lines` Stream Parsing. This is the most memory-efficient method in Neovim. We iterate over the file line-by-line using Lua's JIT compiler patterns. This avoids loading the whole file string into memory if possible.

Optionally, more than one solution can be implemented and exposed to the user and they can
pick which one they deem is fastest.

### 3.2 Configuration Options (Setup)
Users should be able to configure:

*   `cache_strategy`:
    *   `"local"`: Stores `.filename.tex.headings` in the same directory.
    *   `"global"`: Stores caches in `stdpath('data')/cached_headings/`.
*   `allowed_filetypes`: List of filetypes (e.g., `{'tex', 'markdown'}`).
*   `auto_update`: Boolean. Default `false`. If `true`, updates cache on `BufWritePost`.
*   `enable_smart_jump`: Boolean. Default `true`. Attempts to find shifted headings if cache is stale.

### 3.3 Dependencies
*   `nvim-telescope/telescope.nvim`
*   `nvim-lua/plenary.nvim` (File system/Path logic)

## 4. Implementation Details

### 4.1 Directory Structure
```text
telescope-cached-headings.nvim/
├── doc/
│   └── telescope-cached-headings.txt  # Native Vim Help
├── lua/
│   └── telescope/
│       └── _extensions/
│           ├── cached_headings.lua    # Extension registration
│           └── cached_headings/
│               ├── picker.lua         # Telescope picker definition
│               ├── cache.lua          # I/O Logic
│               ├── parser.lua         # High-perf scanning logic
│               └── utils.lua          # Smart jump verification logic
└── README.md
```

### 4.2 Key Function Signatures

**`parser.lua`**
```lua
-- Uses io.lines for maximum speed on large files
-- Returns: { { text = "\section{...}", line = 10, level = 1 }, ... }
M.scan_file = function(filepath, filetype) end
```

**`utils.lua` (Smart Jump)**
```lua
-- Verifies if the target line still holds the heading.
-- If not, searches neighborhood. Returns new_line_num or nil.
M.verify_or_find = function(bufnr, target_line, heading_text) end
```

## 5. Documentation (Help File)

A standard Vim help file will be created at `doc/telescope-cached-headings.txt`.

**Structure Draft:**

```vim
*telescope-cached-headings.txt*  Cache headings for massive files

TELESCOPE CACHED HEADINGS                    *telescope-cached-headings*

1. Intro .................... |telescope-cached-headings-intro|
2. Setup .................... |telescope-cached-headings-setup|
3. Usage .................... |telescope-cached-headings-usage|
4. Configuration ............ |telescope-cached-headings-config|

==============================================================================
1. INTRO                                   *telescope-cached-headings-intro*

This plugin creates a cache of headings for specified filetypes.
It is optimized for massive LaTeX files (100k+ lines) where standard
parsing causes input lag.

==============================================================================
4. CONFIGURATION                          *telescope-cached-headings-config*

cache_strategy ~
    Type: string
    Default: "global"

    - "local": Creates a hidden file (e.g., .main.tex.headings) in the
      same directory as your file. Useful if you want to verify the cache
      manually or share it (though remember to gitignore it).
    - "global": Stores all caches in Neovim's standard data directory.
      Keeps your project clean.

auto_update ~
    Type: boolean
    Default: false

    If true, the cache updates every time you save the file.
    WARNING: On 100k line files, this might cause a slight delay on save.

enable_smart_jump ~
    Type: boolean
    Default: true

    If the file has changed since the cache was created, the heading might
    have moved. If this is true, the plugin will try to find the heading
    near the expected location and update the cache automatically.

==============================================================================
```
