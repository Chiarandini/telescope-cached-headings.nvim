local M = {}

local actions      = require("telescope.actions")
local action_state = require("telescope.actions.state")
local finders      = require("telescope.finders")
local pickers      = require("telescope.pickers")
local conf         = require("telescope.config").values

local cache  = require("telescope._extensions.cached_headings.cache")
local parser = require("telescope._extensions.cached_headings.parser")
local utils  = require("telescope._extensions.cached_headings.utils")

-- Indentation prefix per heading level (up to 6 levels)
local INDENT = { "", "  ", "    ", "      ", "        ", "          " }

---Extract a clean, human-readable title from a cached heading line.
---For display in the picker only — smart jump always uses the raw text.
---@param text string  Raw heading line as stored in cache.
---@param filetype string
---@return string
local function extract_title(text, filetype)
  if filetype == "tex" then
    -- Grab the first brace group: \section{Title} or \section*{Title}
    return text:match("{(.-)}") or text
  elseif filetype == "markdown" then
    return text:match("^#+%s+(.+)$") or text
  elseif filetype == "org" then
    return text:match("^%*+%s+(.+)$") or text
  end
  return text
end

---Build the display string shown in the Telescope prompt.
---Format: "<indent><title>"  (starred entries get a trailing " *")
---@param entry table  { text, level, starred, ... }
---@param filetype string
---@return string
local function make_display(entry, filetype)
  local indent = INDENT[math.min(entry.level, #INDENT)] or ""
  local title  = extract_title(entry.text, filetype)
  if entry.starred then
    return indent .. title .. " *"
  end
  return indent .. title
end

---Open the cached-headings Telescope picker for the current buffer.
---@param opts table   Passed through to pickers.new().
---@param config table Plugin configuration (merged defaults + user overrides).
M.open = function(opts, config)
  local bufnr    = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local filetype = vim.bo[bufnr].filetype

  if filepath == "" then
    vim.notify("[cached_headings] No file associated with current buffer.", vim.log.levels.WARN)
    return
  end

  -- Normalise the filetype: Neovim reports "tex" for LaTeX files
  local ft_allowed = false
  for _, ft in ipairs(config.allowed_filetypes) do
    if ft == filetype then
      ft_allowed = true
      break
    end
  end

  if not ft_allowed then
    vim.notify(
      string.format("[cached_headings] Filetype '%s' is not in allowed_filetypes.", filetype),
      vim.log.levels.WARN
    )
    return
  end

  local cache_path = cache.get_cache_path(filepath, config.cache_strategy)
  local entries    = cache.read_cache(cache_path)

  if not entries then
    -- No cache yet — generate it now
    local raw = parser.scan_file(filepath, filetype, { include_starred = config.include_starred })
    cache.write_cache(cache_path, raw)
    entries = raw
  end

  if #entries == 0 then
    vim.notify("[cached_headings] No headings found in this file.", vim.log.levels.INFO)
    return
  end

  pickers.new(opts, {
    prompt_title = "Headings",

    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        -- parser entries already have { text, level, starred }
        -- cache entries are { text, level } — starred defaults to false
        local starred = entry.starred or false
        local display = make_display(
          { text = entry.text, level = entry.level, starred = starred },
          filetype
        )
        return {
          value    = entry,
          display  = display,
          ordinal  = extract_title(entry.text, filetype),
          filename = filepath,
          lnum     = entry.line,
        }
      end,
    }),

    sorter   = conf.generic_sorter(opts),
    previewer = conf.grep_previewer(opts),

    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)

        if not selection then
          return
        end

        local entry = selection.value

        if config.enable_smart_jump then
          local found = utils.verify_or_find(
            bufnr,
            entry.line,
            entry.text,
            config.smart_jump_window
          )

          if found == entry.line then
            -- Exact match — silent jump
            vim.api.nvim_win_set_cursor(0, { found, 0 })
          elseif found then
            -- Heading shifted — jump and update cache entry
            vim.api.nvim_win_set_cursor(0, { found, 0 })
            vim.notify("[cached_headings] Heading shifted. Cache auto-updated.", vim.log.levels.INFO)

            -- Re-read, patch the one entry, write back
            local all = cache.read_cache(cache_path)
            if all then
              for _, e in ipairs(all) do
                if e.line == entry.line and e.text == entry.text then
                  e.line = found
                  break
                end
              end
              cache.write_cache(cache_path, all)
            end
          else
            -- Not found anywhere in window — jump to original and warn
            vim.api.nvim_win_set_cursor(0, { entry.line, 0 })
            vim.notify(
              "[cached_headings] [Warning] Heading not found at cached location. "
                .. "Please run :CachedHeadingsUpdate.",
              vim.log.levels.WARN
            )
          end
        else
          vim.api.nvim_win_set_cursor(0, { entry.line, 0 })
        end

        -- Centre the view on the jumped-to line
        vim.cmd("normal! zz")
      end)

      return true
    end,
  }):find()
end

return M
