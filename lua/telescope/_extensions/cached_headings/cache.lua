local M = {}

---Return the path where the cache file for `filepath` should be stored.
---
---  "local"  -> same directory as the file, hidden: .filename.ext.headings
---  "global" -> stdpath("data")/cached_headings/<sha256>.headings
---              The sha256 of the absolute filepath is used so any path length
---              and character set is handled safely.
---
---@param filepath string  Absolute path to the source file.
---@param strategy string  "local" | "global"
---@return string
M.get_cache_path = function(filepath, strategy)
  if strategy == "local" then
    local dir      = vim.fn.fnamemodify(filepath, ":h")
    local filename = vim.fn.fnamemodify(filepath, ":t")
    return dir .. "/." .. filename .. ".headings"
  else
    local cache_dir = vim.fn.stdpath("data") .. "/cached_headings"
    vim.fn.mkdir(cache_dir, "p")
    local hash = vim.fn.sha256(filepath)
    return cache_dir .. "/" .. hash .. ".headings"
  end
end

---Read a cache file and return its entries.
---
---Supports two cache formats:
---  v1 (legacy): lines are  "line_num|level|text"
---  v2 (phase 2): first line is "# v2", then optional "# dep:path=mtime" metadata,
---                then data lines "source_file|line_num|level|text"
---
---For v2 caches, if root_dir is provided, dependency mtimes are validated.
---Returns nil if the file does not exist OR if any dependency has changed.
---
---@param cache_path string
---@param root_dir string|nil  Project root dir, used for v2 mtime validation.
---@return table|nil  List of entries, or nil if missing/stale.
---@return boolean    True when the cache was in v2 format, false otherwise.
M.read_cache = function(cache_path, root_dir)
  local file = io.open(cache_path, "r")
  if not file then
    return nil, false
  end

  local first_line = file:read("*l")
  if not first_line then
    file:close()
    return {}, false
  end

  -- ── v2 format ─────────────────────────────────────────────────────────────
  if first_line == "# v2" then
    local deps    = {}
    local entries = {}

    for raw in file:lines() do
      if raw:sub(1, 6) == "# dep:" then
        -- Parse:  # dep:relative/path.tex=1234567890
        local rel_path, mtime_str = raw:sub(7):match("^(.+)=(%d+)$")
        if rel_path then
          deps[rel_path] = tonumber(mtime_str)
        end
      elseif raw:sub(1, 1) ~= "#" then
        -- Data line:  source_file|line_num|level|text
        -- source_file may be empty (root file entries start with "|").
        local source, line_num, level, text = raw:match("^(.-)|(%d+)|(%d+)|(.+)$")
        if line_num then
          table.insert(entries, {
            source_file = source,
            line        = tonumber(line_num),
            level       = tonumber(level),
            text        = text,
          })
        end
      end
    end

    file:close()

    -- Validate dependency mtimes if a root directory was supplied
    if root_dir then
      for rel_path, stored_mtime in pairs(deps) do
        local abs_path      = root_dir .. "/" .. rel_path
        local current_mtime = vim.fn.getftime(abs_path)
        if current_mtime ~= stored_mtime then
          return nil, true  -- stale: force rescan
        end
      end
    end

    return entries, true
  end

  -- ── v1 format (legacy) ────────────────────────────────────────────────────
  local entries = {}

  local function process_v1_line(raw)
    if raw:sub(1, 1) ~= "#" then
      local line_num, level, text = raw:match("^(%d+)|(%d+)|(.+)$")
      if line_num then
        table.insert(entries, {
          line  = tonumber(line_num),
          level = tonumber(level),
          text  = text,
        })
      end
    end
  end

  process_v1_line(first_line)  -- first line already consumed above
  for raw in file:lines() do
    process_v1_line(raw)
  end

  file:close()
  return entries, false
end

---Write a list of heading entries to a cache file.
---
---When `deps` is provided (non-nil), writes v2 format with metadata.
---Otherwise writes the legacy v1 format for backward compatibility.
---
---@param cache_path string
---@param entries table  List of { line, level, text } or { source_file, line, level, text }
---@param deps table|nil  Optional dependency map { [rel_path] = mtime }
---@return boolean, string|nil  success, error_message
M.write_cache = function(cache_path, entries, deps)
  local file = io.open(cache_path, "w")
  if not file then
    return false, "Could not open cache file for writing: " .. cache_path
  end

  if deps ~= nil then
    -- v2 format
    file:write("# v2\n")
    for rel_path, mtime in pairs(deps) do
      file:write(string.format("# dep:%s=%d\n", rel_path, mtime))
    end
    for _, entry in ipairs(entries) do
      local source = entry.source_file or ""
      file:write(string.format("%s|%d|%d|%s\n", source, entry.line, entry.level, entry.text))
    end
  else
    -- v1 format (original)
    for _, entry in ipairs(entries) do
      file:write(string.format("%d|%d|%s\n", entry.line, entry.level, entry.text))
    end
  end

  file:close()
  return true, nil
end

---Delete all cache files managed by this plugin.
---
---For the "global" strategy every *.headings file inside the cache directory
---is removed.  For "local" the files are scattered next to source files, so
---enumeration is not feasible; the function returns an explanatory message.
---
---@param strategy string  "local" | "global"
---@return integer, string|nil  number of files deleted, error message or nil
M.wipe_all_caches = function(strategy)
  if strategy ~= "global" then
    return 0, "wipe_all is only supported for the 'global' cache strategy. "
      .. "Delete *.headings files manually from your project directories."
  end

  local cache_dir = vim.fn.stdpath("data") .. "/cached_headings"
  local files     = vim.fn.glob(cache_dir .. "/*.headings", false, true)
  local count     = 0
  for _, f in ipairs(files) do
    if vim.fn.delete(f) == 0 then
      count = count + 1
    end
  end
  return count, nil
end

return M
