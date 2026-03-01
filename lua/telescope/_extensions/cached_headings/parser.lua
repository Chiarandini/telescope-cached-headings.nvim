local M = {}

-- LaTeX sectioning commands in order of hierarchy (level = index)
local LATEX_COMMANDS = {
  { cmd = "part",          level = 1 },
  { cmd = "chapter",       level = 2 },
  { cmd = "section",       level = 3 },
  { cmd = "subsection",    level = 4 },
  { cmd = "subsubsection", level = 5 },
}

-- Pre-build LaTeX patterns once so they are not re-created per line
-- Each entry: { pattern_nonstarred, pattern_starred, level, cmd }
local LATEX_PATTERNS = (function()
  local t = {}
  for _, def in ipairs(LATEX_COMMANDS) do
    table.insert(t, {
      plain   = "^%s*\\" .. def.cmd .. "%s*{",
      starred = "^%s*\\" .. def.cmd .. "%*%s*{",
      level   = def.level,
      cmd     = def.cmd,
    })
  end
  return t
end)()

-- Pre-compiled patterns for detecting LaTeX include directives.
-- Lua patterns have no alternation, so we keep three separate patterns.
local INCLUDE_PATTERNS = {
  "^%s*\\input%s*{(.-)}",
  "^%s*\\include%s*{(.-)}",
  "^%s*\\subfile%s*{(.-)}",
}

---Extract the title text from a LaTeX heading line.
---Handles the first brace group (non-nested). Returns nil on failure.
---@param line string
---@return string|nil
local function latex_title(line)
  return line:match("{(.-)}")
end

---Parse a single LaTeX line. Returns an entry or nil.
---@param line string
---@param line_num integer
---@param include_starred boolean
---@return table|nil
local function parse_latex(line, line_num, include_starred)
  for _, pat in ipairs(LATEX_PATTERNS) do
    if line:find(pat.plain) then
      local title = latex_title(line)
      if title then
        return { text = vim.trim(line), title = title, line = line_num, level = pat.level, kind = pat.cmd, starred = false }
      end
    elseif include_starred and line:find(pat.starred) then
      local title = latex_title(line)
      if title then
        return { text = vim.trim(line), title = title, line = line_num, level = pat.level, kind = pat.cmd, starred = true }
      end
    end
  end
  return nil
end

---Parse a single Markdown line. Returns an entry or nil.
---@param line string
---@param line_num integer
---@return table|nil
local function parse_markdown(line, line_num)
  -- NOTE: Lua patterns do not support {n,m} quantifiers; use + and check length.
  local hashes, title = line:match("^(#+)%s+(.+)$")
  if hashes and #hashes <= 6 then
    return {
      text    = vim.trim(line),
      title   = vim.trim(title),
      line    = line_num,
      level   = #hashes,
      kind    = "h" .. #hashes,
      starred = false,
    }
  end
  return nil
end

---Parse a single org-mode line. Returns an entry or nil.
---@param line string
---@param line_num integer
---@return table|nil
local function parse_org(line, line_num)
  local stars, title = line:match("^(%*+)%s+(.+)$")
  if stars then
    return {
      text    = vim.trim(line),
      title   = vim.trim(title),
      line    = line_num,
      level   = #stars,
      kind    = "h" .. #stars,
      starred = false,
    }
  end
  return nil
end

---Resolve a LaTeX include argument to an absolute path.
---Appends ".tex" if the bare path is not readable. Returns nil if not found.
---@param raw_path string  The argument from \input{...}, e.g. "chapters/intro"
---@param root_dir string  Absolute path of the project root directory.
---@return string|nil
local function resolve_include(raw_path, root_dir)
  raw_path = vim.trim(raw_path)
  if raw_path == "" then return nil end
  local abs = root_dir .. "/" .. raw_path
  if vim.fn.filereadable(abs) == 1 then return abs end
  local abs_tex = abs .. ".tex"
  if vim.fn.filereadable(abs_tex) == 1 then return abs_tex end
  return nil
end

---Internal DFS scanner. Accumulates heading entries and dependency mtimes.
---
---@param filepath   string   Absolute path of the file to scan now.
---@param source_rel string   Path relative to root_dir ("" for the root file).
---@param root_dir   string   Absolute path of the project root (no trailing slash).
---@param filetype   string
---@param opts       table    { include_starred, scan_includes, recursive_limit, ignore_include_pattern }
---@param visited    table    Map of absolute paths already visited (cycle guard).
---@param depth      integer  Current recursion depth (starts at 0 for root file).
---@param results    table    Accumulator: list of heading entries.
---@param deps       table    Accumulator: { [rel_path] = mtime } for sub-files.
local function scan_recursive(filepath, source_rel, root_dir, filetype, opts, visited, depth, results, deps)
  if depth > (opts.recursive_limit or 5) then return end
  if visited[filepath] then return end
  visited[filepath] = true

  -- Record mtime for sub-files (not root — root staleness is user-managed)
  if source_rel ~= "" then
    deps[source_rel] = vim.fn.getftime(filepath)
  end

  local file = io.open(filepath, "r")
  if not file then
    local level = source_rel == "" and vim.log.levels.ERROR or vim.log.levels.WARN
    vim.notify("[cached_headings] Could not open file: " .. filepath, level)
    return
  end

  -- Read all lines so we can recurse mid-sequence (DFS order).
  -- This loads one file at a time into a Lua table; avoids Neovim buffers.
  local lines = {}
  for line in file:lines() do
    table.insert(lines, line)
  end
  file:close()

  local include_starred   = opts.include_starred or false
  local scan_includes     = opts.scan_includes or false
  local ignore_pat        = opts.ignore_include_pattern

  for line_num, line in ipairs(lines) do
    local entry

    if filetype == "tex" then
      entry = parse_latex(line, line_num, include_starred)

      -- Detect include directives and recurse (DFS, preserving document order)
      if not entry and scan_includes then
        for _, inc_pat in ipairs(INCLUDE_PATTERNS) do
          local raw_path = line:match(inc_pat)
          if raw_path then
            local skip = ignore_pat and ignore_pat ~= "" and raw_path:find(ignore_pat)
            if not skip then
              local abs_included = resolve_include(raw_path, root_dir)
              if abs_included then
                -- Compute path relative to root_dir
                local rel
                if abs_included:sub(1, #root_dir + 1) == root_dir .. "/" then
                  rel = abs_included:sub(#root_dir + 2)
                else
                  rel = abs_included  -- outside root_dir; store absolute
                end
                scan_recursive(abs_included, rel, root_dir, filetype, opts, visited, depth + 1, results, deps)
              end
            end
            break  -- at most one include directive per line
          end
        end
      end

    elseif filetype == "markdown" then
      entry = parse_markdown(line, line_num)
    elseif filetype == "org" then
      entry = parse_org(line, line_num)
    end

    if entry then
      entry.source_file = source_rel
      table.insert(results, entry)
    end
  end
end

---Scan a file and return all heading entries.
---
---When opts.scan_includes is true (LaTeX only), also recursively scans
---files referenced by \input, \include, and \subfile directives. In that
---case a second return value (deps table) is provided for cache metadata.
---
---@param filepath string  Absolute path to the file on disk.
---@param filetype string  Neovim filetype string ("tex", "markdown", "org").
---@param opts table|nil  Optional: { include_starred, scan_includes, recursive_limit, ignore_include_pattern }
---@return table          List of heading entries { text, title, line, level, kind, starred, source_file? }
---@return table|nil      Dependency mtime map { [rel_path] = mtime } or nil when not applicable.
M.scan_file = function(filepath, filetype, opts)
  opts = opts or {}

  if opts.scan_includes and filetype == "tex" then
    -- Normalise root_dir (remove trailing slash)
    local root_dir = vim.fn.fnamemodify(filepath, ":h")
    if root_dir:sub(-1) == "/" then
      root_dir = root_dir:sub(1, -2)
    end

    local results = {}
    local deps    = {}
    local visited = {}
    scan_recursive(filepath, "", root_dir, filetype, opts, visited, 0, results, deps)
    return results, deps
  end

  -- ── Original single-file streaming path (no source_file needed) ──────────
  local include_starred = opts.include_starred or false

  local file = io.open(filepath, "r")
  if not file then
    vim.notify("[cached_headings] Could not open file: " .. filepath, vim.log.levels.ERROR)
    return {}
  end

  local results = {}
  local line_num = 0

  for line in file:lines() do
    line_num = line_num + 1
    local entry

    if filetype == "tex" then
      entry = parse_latex(line, line_num, include_starred)
    elseif filetype == "markdown" then
      entry = parse_markdown(line, line_num)
    elseif filetype == "org" then
      entry = parse_org(line, line_num)
    end

    if entry then
      table.insert(results, entry)
    end
  end

  file:close()
  return results
end

--- Detect the root file of a LaTeX subfile by parsing
--- \documentclass[root.tex]{subfiles} from the first 20 lines.
--- Returns the absolute, normalised path to the root file, or nil.
---@param filepath string  Absolute path of the subfile.
---@return string|nil
M.find_root_via_subfiles = function(filepath)
  local f = io.open(filepath, "r")
  if not f then return nil end
  local count = 0
  for line in f:lines() do
    count = count + 1
    if count > 20 then break end
    local rel = line:match("\\documentclass%[(.-)%]{subfiles}")
    if rel then
      f:close()
      local dir = vim.fn.fnamemodify(filepath, ":h")
      local abs = vim.fn.fnamemodify(dir .. "/" .. rel, ":p")
      -- :p may add a trailing slash for bare directory names; strip it
      if abs:sub(-1) == "/" then abs = abs:sub(1, -2) end
      if vim.fn.filereadable(abs) == 1 then return abs end
      return nil
    end
  end
  f:close()
  return nil
end

return M
