local telescope = require("telescope")
local picker    = require("telescope._extensions.cached_headings.picker")
local cache     = require("telescope._extensions.cached_headings.cache")
local parser    = require("telescope._extensions.cached_headings.parser")

local DEFAULT_CONFIG = {
  -- "local"  -> hidden file next to your source file
  -- "global" -> stdpath("data")/cached_headings/
  cache_strategy    = "global",

  -- Filetypes the picker will activate for
  allowed_filetypes = { "tex", "markdown", "org" },

  -- Automatically regenerate the cache whenever you save a supported file
  auto_update       = false,

  -- Search ±N lines around the cached position when a heading seems to have moved
  enable_smart_jump = true,
  smart_jump_window = 200,

  -- Include LaTeX starred variants: \section*, \subsection*, etc.
  include_starred   = false,
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

  local entries    = parser.scan_file(filepath, filetype, { include_starred = config.include_starred })
  local cache_path = cache.get_cache_path(filepath, config.cache_strategy)
  local ok, err    = cache.write_cache(cache_path, entries)

  if ok then
    vim.notify(
      string.format("[cached_headings] Cache updated (%d headings).", #entries),
      vim.log.levels.INFO
    )
  else
    vim.notify("[cached_headings] Failed to write cache: " .. (err or "unknown error"), vim.log.levels.ERROR)
  end
end

-- ─── Extension registration ───────────────────────────────────────────────────

return telescope.register_extension({

  setup = function(ext_config, _telescope_config)
    config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, ext_config or {})

    -- :CachedHeadingsUpdate — force-regenerate cache for the current buffer
    vim.api.nvim_create_user_command("CachedHeadingsUpdate", function()
      update_cache_for_buf(vim.api.nvim_get_current_buf())
    end, { desc = "Regenerate telescope-cached-headings cache for current file" })

    -- :CachedHeadingsWipeAll — delete every cache file written by this plugin
    vim.api.nvim_create_user_command("CachedHeadingsWipeAll", function()
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
      picker.open(opts or {}, config)
    end,
  },
})
