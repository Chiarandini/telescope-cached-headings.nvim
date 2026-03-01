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

-- LaTeX level → command name (mirrors parser.lua's LATEX_COMMANDS)
local LATEX_LEVEL_KINDS = { "part", "chapter", "section", "subsection", "subsubsection" }

---Return the heading kind string for an entry, falling back to derivation
---when the `kind` field is absent (entries read from an old-format cache).
---@param entry table  { kind?, level, ... }
---@param filetype string
---@return string
local function get_kind(entry, filetype)
  if entry.kind then return entry.kind end
  if filetype == "tex" then
    return LATEX_LEVEL_KINDS[entry.level] or ("level" .. entry.level)
  end
  return "h" .. entry.level
end

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

---Build the heading portion of the display string (without filename).
---Format: "<indent>[kind] <title>"  (starred entries get a trailing " *")
---@param entry table  { text, level, kind?, starred, ... }
---@param filetype string
---@return string
local function make_display(entry, filetype)
  local indent = INDENT[math.min(entry.level, #INDENT)] or ""
  local title  = extract_title(entry.text, filetype)
  local kind   = get_kind(entry, filetype)
  local suffix = entry.starred and " *" or ""
  return indent .. "[" .. kind .. "] " .. title .. suffix
end

---Open the cached-headings Telescope picker for the current buffer.
---@param opts table   Passed through to pickers.new().
---@param config table Plugin configuration (merged defaults + user overrides).
M.open = function(opts, config)
  local bufnr    = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local filetype = vim.bo[bufnr].filetype
  local root_dir = vim.fn.fnamemodify(filepath, ":h")

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
  local entries, is_v2 = cache.read_cache(cache_path, root_dir)

  if not entries then
    -- No cache yet, or dependencies changed — generate it now
    local raw, deps = parser.scan_file(filepath, filetype, {
      include_starred        = config.include_starred,
      scan_includes          = config.scan_includes,
      recursive_limit        = config.recursive_limit,
      ignore_include_pattern = config.ignore_include_pattern,
    })
    cache.write_cache(cache_path, raw, deps)
    entries = raw
    is_v2 = deps ~= nil
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
        local source_file = entry.source_file or ""
        local abs_file    = source_file ~= ""
          and (root_dir .. "/" .. source_file)
          or filepath

        local starred = entry.starred or false
        local e       = { text = entry.text, level = entry.level, kind = entry.kind, starred = starred }

        -- Pre-compute the heading portion (indent + [kind] + title) once.
        -- The display function captures it in a closure — no re-computation per render.
        local heading_str = make_display(e, filetype)
        local kind        = get_kind(e, filetype)
        local title       = extract_title(entry.text, filetype)

        return {
          value    = entry,

          -- When source_file is set, append it in a dimmed Comment highlight.
          -- Telescope calls display(entry_table) → (string, highlight_specs).
          display  = function(_)
            if source_file ~= "" then
              local sep  = "  "
              local full = heading_str .. sep .. source_file
              -- Highlight spec: { {start_col, end_col}, hl_group } (0-indexed bytes)
              return full, { { { #heading_str + #sep, #full }, "Comment" } }
            end
            return heading_str, {}
          end,

          -- Include source_file in ordinal so users can filter by filename
          ordinal  = source_file ~= ""
            and (kind .. " " .. title .. " " .. source_file)
            or  (kind .. " " .. title),

          filename = abs_file,
          lnum     = entry.line,
        }
      end,
    }),

    sorter    = conf.generic_sorter(opts),
    previewer = conf.grep_previewer(opts),

    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)

        if not selection then
          return
        end

        local entry       = selection.value
        local source_file = entry.source_file or ""

        -- ── Local jump (heading in the root file) ─────────────────────────
        if source_file == "" then
          if config.enable_smart_jump then
            local found = utils.verify_or_find(
              bufnr,
              entry.line,
              entry.text,
              config.smart_jump_window
            )

            if found == entry.line then
              vim.api.nvim_win_set_cursor(0, { found, 0 })
            elseif found then
              vim.api.nvim_win_set_cursor(0, { found, 0 })
              vim.notify("[cached_headings] Heading shifted. Cache auto-updated.", vim.log.levels.INFO)

              -- Patch the one entry in cache, but only for v1 caches.
              -- v2 caches have multi-file deps; user should run :CachedHeadingsUpdate.
              if not is_v2 then
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
              end
            else
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

        -- ── Remote jump (heading lives in an included sub-file) ───────────
        else
          local abs_path = root_dir .. "/" .. source_file
          vim.cmd("edit " .. vim.fn.fnameescape(abs_path))
          local new_bufnr = vim.api.nvim_get_current_buf()

          if config.enable_smart_jump then
            local found = utils.verify_or_find(
              new_bufnr,
              entry.line,
              entry.text,
              config.smart_jump_window
            )
            if found then
              vim.api.nvim_win_set_cursor(0, { found, 0 })
              if found ~= entry.line then
                vim.notify(
                  "[cached_headings] Heading shifted. Run :CachedHeadingsUpdate to refresh.",
                  vim.log.levels.INFO
                )
              end
            else
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
        end

        -- Centre the view on the jumped-to line
        vim.cmd("normal! zz")
      end)

      return true
    end,
  }):find()
end

return M
