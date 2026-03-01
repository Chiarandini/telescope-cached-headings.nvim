# Design Doc: Phase 2 - Project-Wide Hierarchy (Recursive Scanning)

## 1. Context & Motivation
The current implementation of `telescope-cached-headings` is strictly file-local. It excels at speed (O(1) access after cache) but fails for modular LaTeX projects (e.g., Thesis, Books) where the document is split across multiple files using `\include`, `\input`, or `subfiles`.

## 2. Goals & Constraints
*   **Goal:** Provide a unified Table of Contents for a root LaTeX document that aggregates headings from all included sub-files.
*   **Constraint 1 (Speed):** The solution must maintain the "instant open" philosophy. We cannot spawn background `latex` processes or use heavy parsers.
*   **Constraint 2 (Memory):** We must not load all included files into Neovim buffers. We must stream-read them using Lua's `io` library, just like the current implementation.
*   **Toggle-able:** This feature must be opt-in (e.g., `scan_includes = true`).

## 3. Technical Strategy

### 3.1. The "Flattened" Cache Architecture
Currently, the cache is a list of headings for one file.
To support projects, we will not change the "one cache file per entry" rule. Instead, we will change **what goes into the cache**.

When `scan_includes = true`, the cache generation process becomes **recursive**.

**Current Cache Line Format:**
`line_num | level | text`

**New Cache Line Format (Phase 2):**
`relative_filepath | line_num | level | text`

*   If `relative_filepath` is empty or `.`, it refers to the current root file.
*   If it contains a path, Telescope knows to open that specific file when Enter is pressed.

### 3.2. Recursive Parsing Logic (The Algorithm)
We introduce a Depth-First Search (DFS) scanner.

1.  **Start:** User opens `main.tex` and invokes Telescope.
2.  **Check Cache:**
    *   We check the cache for `main.tex`.
    *   **Crucial Change:** The cache header must now store a "dependency hash" or a list of included files and their `mtime`s. If *any* of the included files have been modified since the cache was written, the **entire** cache for `main.tex` is invalidated and rebuilt.
3.  **If Cache Invalid (Rebuild):**
    *   Stream `main.tex`.
    *   Match `\section`, `\chapter` -> Add to list.
    *   **New Matcher:** Match `^%s*\\(?:input|include|subfile){(.-)}`.
    *   If Match Found (e.g., `chapters/intro`):
        *   Pause scanning `main.tex`.
        *   Resolve path (append `.tex` if missing).
        *   Stream `chapters/intro.tex`.
        *   Add headings from this sub-file to the master list, recording the filename.
        *   Resume scanning `main.tex`.
4.  **Write Cache:** Save the flattened list (containing headings from all files) to the cache for `main.tex`.

### 3.3. Path Resolution Strategy
This is the trickiest part of LaTeX.
*   **Root Directory:** We assume the directory of the file that started the scan is the "Root".
*   **Relative Paths:** LaTeX `\include` is usually relative to the root.
*   **Extension Handling:** We must check for the file existence with AND without `.tex` appended (users write `\include{chap1}`, not `\include{chap1.tex}`).

### 3.4. Handling "Smart Jump" in Phase 2
The current "Smart Jump" (verifying line numbers) works because the buffer is already loaded.
For Phase 2:
*   **Local Jumps:** If the selected heading is in the current buffer, perform standard Smart Jump logic.
*   **Remote Jumps:** If the selected heading is in `chapter1.tex`:
    *   Telescope's default behavior is to open the file.
    *   We can hook into the `action` to perform a "lazy smart jump": Open file -> Wait for load -> Scan near line number for the heading text -> Jump.

## 4. Performance Optimizations (Maintaining Speed)

1.  **Depth Limit:** To prevent infinite loops (Circular dependencies: A includes B, B includes A), we implement a hard recursion depth limit (e.g., `max_depth = 5`).
2.  **Cycle Detection:** Keep a table `visited_files = {}`. If we encounter a file path we have already scanned in this session, skip it.
3.  **Pattern Compilation:** The regex for finding includes must be pre-compiled in the `init` block, alongside the existing section patterns, to avoid overhead.

## 5. Configuration Interface

```lua
require("telescope").setup({
  extensions = {
    cached_headings = {
      -- Phase 2 new options
      scan_includes = true,        -- Default false (keep it simple for now)
      recursive_limit = 5,         -- Stop parsing too deep
      ignore_include_pattern = "", -- Regex to ignore specific includes (e.g. huge glossaries)
    },
  },
})
```

## 6. Risk Assessment

| Risk | Impact | Mitigation |
| :--- | :--- | :--- |
| **Circular Includes** | Infinite Loop / Crash | Implement `visited_files` check and `max_depth`. |
| **Huge Projects** | UI Lag during scan | The `io.lines` approach is still fast. A 50-file project is still less text than one massive log file. Lag is acceptable on *first* run only. |
| **Missing Files** | Scanner errors | If an included file is not found (404), silently ignore it and continue scanning `main.tex`. Do not crash. |
| **Cache Staleness** | User edits subfile, `main.tex` cache doesn't know | We must store the `mtime` of *every* included file in the `main.tex` cache metadata. Verification checks all mtimes. |

## 7. Implementation Plan

1.  **Step 1:** Refactor the internal `parser` function to accept a `filename` argument (currently it assumes current buffer).
2.  **Step 2:** Add regex support for `\input`, `\include`, `\subfile`.
3.  **Step 3:** Implement the recursive loop (DFS) and the "Flattened" list structure.
4.  **Step 4:** Update the Cache Writer/Reader to handle the new `filename|...` column.
5.  **Step 5:** Update the Telescope "Entry Maker" to display the filename (perhaps in grey text to the right) and handle opening the correct file.

This is a great direction for a "Phase 2". Dealing with multi-file projects while maintaining the "instant" feel is a classic engineering trade-off challenge.

First, here is the clarification you asked for regarding the LaTeX commands:

### Quick Primer: The 3 Ways to Split LaTeX
The plugin will need to detect these three distinct patterns.

1.  **`\input{filename}`**: The "dumbest" method. It literally copies and pastes the text from `filename.tex` into the main file at compile time. It handles nested files (A inputs B, B inputs C).
2.  **`\include{filename}`**: Smarter. It forces a page break before and after. It is **not** allowed to be nested. It is usually used in `main.tex` to pull in chapters. *Note: Users often omit the `.tex` extension here.*
3.  **`subfiles` package**: This allows you to compile `chapter1.tex` by itself, OR compile `main.tex`. It uses the syntax `\subfile{path/to/file}`.

***

Here is the Design Document for Phase 2.

# Design Doc: Phase 2 - Project-Wide Hierarchy (Recursive Scanning)

## 1. Context & Motivation
The current implementation of `telescope-cached-headings` is strictly file-local. It excels at speed (O(1) access after cache) but fails for modular LaTeX projects (e.g., Thesis, Books) where the document is split across multiple files using `\include`, `\input`, or `subfiles`.

## 2. Goals & Constraints
*   **Goal:** Provide a unified Table of Contents for a root LaTeX document that aggregates headings from all included sub-files.
*   **Constraint 1 (Speed):** The solution must maintain the "instant open" philosophy. We cannot spawn background `latex` processes or use heavy parsers.
*   **Constraint 2 (Memory):** We must not load all included files into Neovim buffers. We must stream-read them using Lua's `io` library, just like the current implementation.
*   **Toggle-able:** This feature must be opt-in (e.g., `scan_includes = true`).

## 3. Technical Strategy

### 3.1. The "Flattened" Cache Architecture
Currently, the cache is a list of headings for one file.
To support projects, we will not change the "one cache file per entry" rule. Instead, we will change **what goes into the cache**.

When `scan_includes = true`, the cache generation process becomes **recursive**.

**Current Cache Line Format:**
`line_num | level | text`

**New Cache Line Format (Phase 2):**
`relative_filepath | line_num | level | text`

*   If `relative_filepath` is empty or `.`, it refers to the current root file.
*   If it contains a path, Telescope knows to open that specific file when Enter is pressed.

### 3.2. Recursive Parsing Logic (The Algorithm)
We introduce a Depth-First Search (DFS) scanner.

1.  **Start:** User opens `main.tex` and invokes Telescope.
2.  **Check Cache:**
    *   We check the cache for `main.tex`.
    *   **Crucial Change:** The cache header must now store a "dependency hash" or a list of included files and their `mtime`s. If *any* of the included files have been modified since the cache was written, the **entire** cache for `main.tex` is invalidated and rebuilt.
3.  **If Cache Invalid (Rebuild):**
    *   Stream `main.tex`.
    *   Match `\section`, `\chapter` -> Add to list.
    *   **New Matcher:** Match `^%s*\\(?:input|include|subfile){(.-)}`.
    *   If Match Found (e.g., `chapters/intro`):
        *   Pause scanning `main.tex`.
        *   Resolve path (append `.tex` if missing).
        *   Stream `chapters/intro.tex`.
        *   Add headings from this sub-file to the master list, recording the filename.
        *   Resume scanning `main.tex`.
4.  **Write Cache:** Save the flattened list (containing headings from all files) to the cache for `main.tex`.

### 3.3. Path Resolution Strategy
This is the trickiest part of LaTeX.
*   **Root Directory:** We assume the directory of the file that started the scan is the "Root".
*   **Relative Paths:** LaTeX `\include` is usually relative to the root.
*   **Extension Handling:** We must check for the file existence with AND without `.tex` appended (users write `\include{chap1}`, not `\include{chap1.tex}`).

### 3.4. Handling "Smart Jump" in Phase 2
The current "Smart Jump" (verifying line numbers) works because the buffer is already loaded.
For Phase 2:
*   **Local Jumps:** If the selected heading is in the current buffer, perform standard Smart Jump logic.
*   **Remote Jumps:** If the selected heading is in `chapter1.tex`:
    *   Telescope's default behavior is to open the file.
    *   We can hook into the `action` to perform a "lazy smart jump": Open file -> Wait for load -> Scan near line number for the heading text -> Jump.

## 4. Performance Optimizations (Maintaining Speed)

1.  **Depth Limit:** To prevent infinite loops (Circular dependencies: A includes B, B includes A), we implement a hard recursion depth limit (e.g., `max_depth = 5`).
2.  **Cycle Detection:** Keep a table `visited_files = {}`. If we encounter a file path we have already scanned in this session, skip it.
3.  **Pattern Compilation:** The regex for finding includes must be pre-compiled in the `init` block, alongside the existing section patterns, to avoid overhead.

## 5. Configuration Interface

```lua
require("telescope").setup({
  extensions = {
    cached_headings = {
      -- Phase 2 new options
      scan_includes = true,        -- Default false (keep it simple for now)
      recursive_limit = 5,         -- Stop parsing too deep
      ignore_include_pattern = "", -- Regex to ignore specific includes (e.g. huge glossaries)
    },
  },
})
```

## 6. Risk Assessment

| Risk | Impact | Mitigation |
| :--- | :--- | :--- |
| **Circular Includes** | Infinite Loop / Crash | Implement `visited_files` check and `max_depth`. |
| **Huge Projects** | UI Lag during scan | The `io.lines` approach is still fast. A 50-file project is still less text than one massive log file. Lag is acceptable on *first* run only. |
| **Missing Files** | Scanner errors | If an included file is not found (404), silently ignore it and continue scanning `main.tex`. Do not crash. |
| **Cache Staleness** | User edits subfile, `main.tex` cache doesn't know | We must store the `mtime` of *every* included file in the `main.tex` cache metadata. Verification checks all mtimes. |

## 7. Implementation Plan

1.  **Step 1:** Refactor the internal `parser` function to accept a `filename` argument (currently it assumes current buffer).
2.  **Step 2:** Add regex support for `\input`, `\include`, `\subfile`.
3.  **Step 3:** Implement the recursive loop (DFS) and the "Flattened" list structure.
4.  **Step 4:** Update the Cache Writer/Reader to handle the new `filename|...` column.
5.  **Step 5:** Update the Telescope "Entry Maker" to display the filename (perhaps in grey text to the right) and handle opening the correct file.
