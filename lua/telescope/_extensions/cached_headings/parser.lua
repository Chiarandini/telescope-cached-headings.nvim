-- Thin compatibility wrapper.
--
-- The real implementation now lives in `latex_nav_core.cached_headings.parser`.
-- Re-exported so existing
-- `require("telescope._extensions.cached_headings.parser")` call sites keep
-- working.

return require("latex_nav_core.cached_headings.parser")
