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
-- Each entry: { pattern_nonstarred, pattern_starred, level }
local LATEX_PATTERNS = (function()
  local t = {}
  for _, def in ipairs(LATEX_COMMANDS) do
    table.insert(t, {
      plain   = "^%s*\\" .. def.cmd .. "%s*{",
      starred = "^%s*\\" .. def.cmd .. "%*%s*{",
      level   = def.level,
    })
  end
  return t
end)()

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
        return { text = vim.trim(line), title = title, line = line_num, level = pat.level, starred = false }
      end
    elseif include_starred and line:find(pat.starred) then
      local title = latex_title(line)
      if title then
        return { text = vim.trim(line), title = title, line = line_num, level = pat.level, starred = true }
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
  local hashes, title = line:match("^(#{1,6})%s+(.+)$")
  if hashes then
    return {
      text  = vim.trim(line),
      title = vim.trim(title),
      line  = line_num,
      level = #hashes,
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
      text  = vim.trim(line),
      title = vim.trim(title),
      line  = line_num,
      level = #stars,
      starred = false,
    }
  end
  return nil
end

---Scan a file and return all heading entries.
---Uses io.lines for memory-efficient streaming on large files.
---
---@param filepath string  Absolute path to the file on disk.
---@param filetype string  Neovim filetype string ("tex", "markdown", "org").
---@param opts table|nil  Optional: { include_starred = bool }
---@return table  List of { text, title, line, level, starred }
M.scan_file = function(filepath, filetype, opts)
  opts = opts or {}
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

return M
