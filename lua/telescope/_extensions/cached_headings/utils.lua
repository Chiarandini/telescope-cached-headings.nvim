-- Thin compatibility wrapper.
--
-- The real implementation of verify_or_find has moved to the shared module
-- `latex_nav_core.latex` (function: `verify_or_find_heading`). This file
-- re-exports it under the old name so existing require() call sites keep
-- working while downstream code migrates to latex_nav_core directly.

local M = {}

M.verify_or_find = function(bufnr, target_line, heading_text, window_size)
  return require("latex_nav_core.latex").verify_or_find_heading(
    bufnr, target_line, heading_text, window_size
  )
end

return M
