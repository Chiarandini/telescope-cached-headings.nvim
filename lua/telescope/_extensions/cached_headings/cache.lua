-- Thin compatibility wrapper.
--
-- The real implementations now live in `latex_nav_core.cached_headings.cache`.
-- This file re-exports them so existing
-- `require("telescope._extensions.cached_headings.cache")` call sites (the
-- picker in this plugin, plus anyone depending on the old path) keep
-- working while downstream code migrates to latex_nav_core directly.

return require("latex_nav_core.cached_headings.cache")
