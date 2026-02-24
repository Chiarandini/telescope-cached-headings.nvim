local M = {}

---Verify whether `heading_text` is still at `target_line` in the buffer.
---If not, search a window of +/- `window_size` lines around that position.
---
---Returns:
---  - The verified/found line number on success.
---  - nil if the heading could not be located within the search window.
---
---@param bufnr integer   Buffer number to search in.
---@param target_line integer  1-based line number from the cache.
---@param heading_text string  Exact text stored in the cache for this heading.
---@param window_size integer  Number of lines to search on each side when the
---                            exact line does not match.
---@return integer|nil
M.verify_or_find = function(bufnr, target_line, heading_text, window_size)
  local total_lines = vim.api.nvim_buf_line_count(bufnr)

  -- Clamp target_line to valid range
  target_line = math.max(1, math.min(target_line, total_lines))

  -- Fast path: check exact cached position first (0-based index for nvim API)
  local exact = vim.api.nvim_buf_get_lines(bufnr, target_line - 1, target_line, false)[1]
  if exact and vim.trim(exact) == heading_text then
    return target_line
  end

  -- Slow path: search the neighborhood
  local search_start = math.max(1, target_line - window_size)
  local search_end   = math.min(total_lines, target_line + window_size)

  local lines = vim.api.nvim_buf_get_lines(bufnr, search_start - 1, search_end, false)

  for i, line in ipairs(lines) do
    if vim.trim(line) == heading_text then
      return search_start + i - 1
    end
  end

  return nil
end

return M
