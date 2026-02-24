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

---Read a cache file and return a list of entries.
---Each line in the file must have the format: line_num|level|text
---
---@param cache_path string
---@return table|nil  List of { line, level, text } or nil if file does not exist.
M.read_cache = function(cache_path)
  local file = io.open(cache_path, "r")
  if not file then
    return nil
  end

  local entries = {}
  for raw in file:lines() do
    -- Skip comment lines (first char '#') used for metadata
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

  file:close()
  return entries
end

---Write a list of parser entries to a cache file.
---Parser entries have { line, level, text } (title is not cached; re-derived
---from text at display time to keep the cache format minimal).
---
---@param cache_path string
---@param entries table  List of { line, level, text }
---@return boolean, string|nil  success, error_message
M.write_cache = function(cache_path, entries)
  local file = io.open(cache_path, "w")
  if not file then
    return false, "Could not open cache file for writing: " .. cache_path
  end

  for _, entry in ipairs(entries) do
    file:write(string.format("%d|%d|%s\n", entry.line, entry.level, entry.text))
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
