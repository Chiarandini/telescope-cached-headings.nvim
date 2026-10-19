local telescope = require("telescope")

local DEFAULT_CONFIG = {
  -- "local"  -> hidden file next to your source file
  -- "global" -> stdpath("data")/cached_headings/
  cache_strategy    = "global",

  -- Filetypes the picker will activate for
  allowed_filetypes = { "tex", "markdown", "org" },

  -- Automatically regenerate the cache whenever you save a supported file
  auto_update       = false,

  -- Show a vim.notify message after a successful cache update
  notify_on_update  = true,

  -- Search ±N lines around the cached position when a heading seems to have moved
  enable_smart_jump = true,
  smart_jump_window = 200,

  -- Include LaTeX starred variants: \section*, \subsection*, etc.
  include_starred   = false,

  -- Extra LaTeX sectioning commands and their depth, merged over the
  -- built-ins (part 1 .. subsubsection 5); false removes a built-in.
  --   latex_headings = { bonussection = 3, paragraph = 6, part = false }
  latex_headings    = {},

  -- Phase 2: multi-file LaTeX support
  -- When true, \input / \include / \subfile directives are followed and
  -- headings from all included files are shown in a single unified picker.
  -- Only applies to "tex" filetypes. Default false to keep it opt-in.
  scan_includes          = false,
  recursive_limit        = 5,    -- max include nesting depth (guards circular deps)
  ignore_include_pattern = "",   -- Lua pattern; matching include paths are skipped

  -- Phase 3: subfile toggle
  root_file          = "",        -- manual override: absolute path to the root .tex file
  subfile_toggle_key = "<C-g>",   -- key to toggle local↔global mode inside the picker

  -- Copy heading title to system clipboard without opening the file
  copy_label_key = "<C-y>",       -- key to yank the heading title into the + register

  -- Optional transformation applied to the heading title before it is copied.
  -- Accepts either:
  --   • a table  { ["prefix"] = "format string with %s" }
  --   • a function(title: string) -> string
  -- When nil (default) the raw heading title is copied unchanged.
  copy_transform = nil,
}

-- Module-level config table populated during setup()
local config = {}

-- ─── Helpers ─────────────────────────────────────────────────────────────────

---Run a full cache regeneration for the given buffer.
---Called by :CachedHeadingsUpdate and the auto_update autocmd.
---@param bufnr integer
local function update_cache_for_buf(bufnr)
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local filetype = vim.bo[bufnr].filetype

  if filepath == "" then
    vim.notify("[cached_headings] No file associated with current buffer.", vim.log.levels.WARN)
    return
  end

  local allowed = false
  for _, ft in ipairs(config.allowed_filetypes) do
    if ft == filetype then
      allowed = true
      break
    end
  end

  if not allowed then
    vim.notify(
      string.format("[cached_headings] Filetype '%s' is not supported.", filetype),
      vim.log.levels.WARN
    )
    return
  end

  local scan_opts = require("telescope._extensions.cached_headings.picker").scan_opts(config, "local")
  local entries, _, _, err = require("latex_nav_core.cached_headings").refresh(
    filepath, filetype, scan_opts, config.cache_strategy)

  if not err then
    if config.notify_on_update then
      vim.notify(
        string.format("[cached_headings] Cache updated (%d headings).", #entries),
        vim.log.levels.INFO
      )
    end
  else
    vim.notify("[cached_headings] Failed to write cache: " .. err, vim.log.levels.ERROR)
  end
end

-- ─── Extension registration ───────────────────────────────────────────────────

return telescope.register_extension({

  setup = function(ext_config, _telescope_config)
    if not pcall(require, "latex_nav_core.cached_headings") then
      vim.notify(
        "[cached_headings] latex-nav-core.nvim is missing or too old.\n"
          .. "  Install or update 'Chiarandini/latex-nav-core.nvim'.",
        vim.log.levels.ERROR
      )
      return
    end

    config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, ext_config or {})
    local ok, err = require("latex_nav_core.cached_headings.parser").validate_latex_headings(config.latex_headings)
    if not ok then error("telescope-cached-headings: " .. err, 0) end

    -- :CachedHeadingsUpdate — force-regenerate cache for the current buffer
    vim.api.nvim_create_user_command("CachedHeadingsUpdate", function()
      update_cache_for_buf(vim.api.nvim_get_current_buf())
    end, { desc = "Regenerate telescope-cached-headings cache for current file" })

    -- :CachedHeadingsWipeAll — delete every cache file written by this plugin
    vim.api.nvim_create_user_command("CachedHeadingsWipeAll", function()
      local cache = require("latex_nav_core.cached_headings.cache")
      local count, err = cache.wipe_all_caches(config.cache_strategy)
      if err then
        vim.notify("[cached_headings] " .. err, vim.log.levels.WARN)
      else
        vim.notify(
          string.format("[cached_headings] Wiped %d cache file(s).", count),
          vim.log.levels.INFO
        )
      end
    end, { desc = "Delete all telescope-cached-headings cache files" })

    -- Auto-update on save when opt-in
    if config.auto_update then
      vim.api.nvim_create_autocmd("BufWritePost", {
        group = vim.api.nvim_create_augroup("CachedHeadingsAutoUpdate", { clear = true }),
        pattern = "*",
        desc = "telescope-cached-headings: auto-regenerate cache on save",
        callback = function(ev)
          local filetype = vim.bo[ev.buf].filetype
          for _, ft in ipairs(config.allowed_filetypes) do
            if ft == filetype then
              update_cache_for_buf(ev.buf)
              break
            end
          end
        end,
      })
    end
  end,

  exports = {
    cached_headings = function(opts)
      require("telescope._extensions.cached_headings.picker").open(opts or {}, config)
    end,
  },
})
