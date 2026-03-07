local M = {}

---Apply an optional copy transformation to a heading title string.
---`transform` may be:
---  • nil        – return the title unchanged
---  • table      – map of prefix strings to format strings (with %s)
---  • function   – called with the title, must return the transformed string
---@param title     string
---@param transform table|function|nil
---@return string
local function apply_transform(title, transform)
  if not transform then return title end
  if type(transform) == "function" then
    return transform(title) or title
  elseif type(transform) == "table" then
    for prefix, fmt in pairs(transform) do
      if vim.startswith(title, prefix) then
        return string.format(fmt, title)
      end
    end
  end
  return title
end

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

--- Return the 1-based index of the first entry in `entries` whose resolved
--- absolute path matches `subfile_abs`. Falls back to 1 if none found.
---@param entries   table   List of heading entries.
---@param subfile_abs string  Normalised absolute path of the current subfile.
---@param root_dir  string
---@return integer
local function find_default_selection(entries, subfile_abs, root_dir)
  for i, e in ipairs(entries) do
    local sf = e.source_file or ""
    if sf ~= "" then
      local abs = vim.fn.fnamemodify(root_dir .. "/" .. sf, ":p")
      if abs == subfile_abs then return i end
    end
  end
  return 1
end

---Open the cached-headings Telescope picker for the current buffer.
---@param opts table   Passed through to pickers.new().
---@param config table Plugin configuration (merged defaults + user overrides).
---@param overrides table|nil  Internal overrides for toggle: { mode, origin_filepath, root_filepath }
M.open = function(opts, config, overrides)
  local actions      = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local finders      = require("telescope.finders")
  local pickers      = require("telescope.pickers")
  local conf         = require("telescope.config").values
  local cache  = require("telescope._extensions.cached_headings.cache")
  local parser = require("telescope._extensions.cached_headings.parser")
  local utils  = require("telescope._extensions.cached_headings.utils")

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

  -- ── Phase 3: subfile / global-mode setup ───────────────────────────────────
  overrides = overrides or {}
  local mode            = overrides.mode or "local"
  local origin_filepath = overrides.origin_filepath or filepath
  local root_filepath   = overrides.root_filepath      -- nil in first "local" call

  -- Detect root only on the initial "local" call for .tex files
  if mode == "local" and filetype == "tex" and root_filepath == nil then
    root_filepath = parser.find_root_via_subfiles(filepath)
    if not root_filepath and config.root_file and config.root_file ~= "" then
      local abs = vim.fn.fnamemodify(config.root_file, ":p")
      if vim.fn.filereadable(abs) == 1 then
        root_filepath = abs
      end
    end
  end

  local is_subfile = root_filepath ~= nil

  -- In global mode, reload everything from the root file
  if mode == "global" then
    root_dir  = vim.fn.fnamemodify(root_filepath, ":h")
    filepath  = root_filepath
  end

  local cache_path = cache.get_cache_path(filepath, config.cache_strategy)
  local entries, is_v2 = cache.read_cache(cache_path, root_dir)

  if not entries then
    -- No cache yet, or dependencies changed — generate it now
    local scan_opts = {
      include_starred        = config.include_starred,
      scan_includes          = (mode == "global") or config.scan_includes,
      recursive_limit        = config.recursive_limit,
      ignore_include_pattern = config.ignore_include_pattern,
    }
    local raw, deps = parser.scan_file(filepath, filetype, scan_opts)
    cache.write_cache(cache_path, raw, deps)
    entries = raw
    is_v2 = deps ~= nil
  end

  if #entries == 0 then
    vim.notify("[cached_headings] No headings found in this file.", vim.log.levels.INFO)
    return
  end

  -- Smart scroll: pre-position on first heading from current subfile
  local default_idx = 1
  if mode == "global" then
    local subfile_abs = vim.fn.fnamemodify(origin_filepath, ":p")
    default_idx = find_default_selection(entries, subfile_abs, root_dir)
  end

  -- Prompt title shows current mode and toggle hint
  local toggle_key = config.subfile_toggle_key or "<C-g>"
  local prompt_title
  if is_subfile or mode == "global" then
    if mode == "local" then
      prompt_title = "Headings (subfile) [" .. toggle_key .. ": full doc]"
    else
      prompt_title = "Headings (full doc) [" .. toggle_key .. ": subfile]"
    end
  else
    prompt_title = "Headings"
  end

  pickers.new(opts, {
    prompt_title            = prompt_title,
    default_selection_index = default_idx,

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

    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if not selection then return end

        local entry = selection.value
        local sf    = entry.source_file or ""

        -- Determine the heading's absolute file path
        local heading_abs
        if sf == "" then
          heading_abs = filepath   -- root file in global mode; current file in local mode
        else
          heading_abs = vim.fn.fnamemodify(root_dir .. "/" .. sf, ":p")
        end

        -- Switch to the target file if needed
        local current_abs = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":p")
        if heading_abs ~= current_abs then
          vim.cmd("edit " .. vim.fn.fnameescape(heading_abs))
          bufnr = vim.api.nvim_get_current_buf()
        end

        -- Smart jump / plain jump
        if config.enable_smart_jump then
          local found = utils.verify_or_find(bufnr, entry.line, entry.text, config.smart_jump_window)
          if found then
            vim.api.nvim_win_set_cursor(0, { found, 0 })
            if found ~= entry.line then
              vim.notify("[cached_headings] Heading shifted. Run :CachedHeadingsUpdate.", vim.log.levels.INFO)
              if not is_v2 then
                -- patch v1 cache
                local all = cache.read_cache(cache_path)
                if all then
                  for _, e in ipairs(all) do
                    if e.line == entry.line and e.text == entry.text then e.line = found; break end
                  end
                  cache.write_cache(cache_path, all)
                end
              end
            end
          else
            vim.api.nvim_win_set_cursor(0, { entry.line, 0 })
            vim.notify("[cached_headings] Heading not found. Run :CachedHeadingsUpdate.", vim.log.levels.WARN)
          end
        else
          vim.api.nvim_win_set_cursor(0, { entry.line, 0 })
        end
        vim.cmd("normal! zz")
      end)

      -- Toggle key: only when we know there is a root file to toggle to/from
      if is_subfile or mode == "global" then
        local opposite = mode == "local" and "global" or "local"
        local toggle_fn = function()
          actions.close(prompt_bufnr)
          vim.schedule(function()
            M.open(opts, config, {
              mode            = opposite,
              origin_filepath = origin_filepath,
              root_filepath   = root_filepath,
            })
          end)
        end
        map("i", toggle_key, toggle_fn)
        map("n", toggle_key, toggle_fn)
      end

      -- Copy heading title to system clipboard
      local copy_key = config.copy_label_key or "<C-y>"
      local copy_fn = function()
        local selection = action_state.get_selected_entry()
        if not selection then return end
        local title = extract_title(selection.value.text, filetype)
        local text  = apply_transform(title, config.copy_transform)
        vim.fn.setreg("+", text)
        vim.fn.setreg('"', text)
        actions.close(prompt_bufnr)
        vim.notify('[cached_headings] Copied "' .. text .. '" to clipboard.', vim.log.levels.INFO)
      end
      map("i", copy_key, copy_fn)
      map("n", copy_key, copy_fn)

      return true
    end,
  }):find()
end

return M
