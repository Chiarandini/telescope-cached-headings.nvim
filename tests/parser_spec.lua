-- Run with:
--   nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}"

local parser = require("telescope._extensions.cached_headings.parser")

-- Resolve the fixtures directory relative to this spec file.
local this_file   = debug.getinfo(1, "S").source:sub(2)   -- strip leading '@'
local tests_dir   = vim.fn.fnamemodify(this_file, ":p:h")
local fixtures    = tests_dir .. "/fixtures"

-- ─── Helpers ──────────────────────────────────────────────────────────────────

local function scan(filename, filetype, opts)
  return parser.scan_file(fixtures .. "/" .. filename, filetype, opts)
end

local function find(results, title)
  for _, e in ipairs(results) do
    if e.title == title then return e end
  end
  return nil
end

-- ─── Markdown ─────────────────────────────────────────────────────────────────

describe("parser – markdown", function()
  local results

  before_each(function()
    results = scan("sample.md", "markdown")
  end)

  it("returns a non-empty table", function()
    assert.is_true(#results > 0)
  end)

  it("detects h1 heading", function()
    local e = find(results, "Introduction")
    assert.is_not_nil(e, "h1 'Introduction' not found")
    assert.equal(1,    e.level)
    assert.equal("h1", e.kind)
    assert.equal(false, e.starred)
  end)

  it("detects h2 heading", function()
    local e = find(results, "Background")
    assert.is_not_nil(e, "h2 'Background' not found")
    assert.equal(2,    e.level)
    assert.equal("h2", e.kind)
  end)

  it("detects h3 heading", function()
    local e = find(results, "Details")
    assert.is_not_nil(e, "h3 'Details' not found")
    assert.equal(3,    e.level)
    assert.equal("h3", e.kind)
  end)

  it("detects h4 heading", function()
    local e = find(results, "Fine Details")
    assert.is_not_nil(e, "h4 'Fine Details' not found")
    assert.equal(4,    e.level)
    assert.equal("h4", e.kind)
  end)

  it("detects second h2", function()
    local e = find(results, "Conclusion")
    assert.is_not_nil(e, "h2 'Conclusion' not found")
    assert.equal(2,    e.level)
    assert.equal("h2", e.kind)
  end)

  it("detects second h1", function()
    local e = find(results, "Part Two")
    assert.is_not_nil(e, "second h1 'Part Two' not found")
    assert.equal(1,    e.level)
    assert.equal("h1", e.kind)
  end)

  it("does NOT match #no-space (missing space after #)", function()
    assert.is_nil(find(results, "not-a-heading (missing space)"))
  end)

  it("does NOT match ##no-space", function()
    assert.is_nil(find(results, "also-not-a-heading"))
  end)

  it("records correct line numbers", function()
    local e = find(results, "Introduction")
    assert.is_not_nil(e)
    assert.equal(1, e.line)
  end)

  it("stores the full heading line in 'text'", function()
    local e = find(results, "Background")
    assert.is_not_nil(e)
    assert.equal("## Background", e.text)
  end)
end)

-- ─── LaTeX ────────────────────────────────────────────────────────────────────

describe("parser – latex (non-starred)", function()
  local results

  before_each(function()
    results = scan("sample.tex", "tex", { include_starred = false })
  end)

  it("returns a non-empty table", function()
    assert.is_true(#results > 0)
  end)

  it("detects \\part", function()
    local e = find(results, "The First Part")
    assert.is_not_nil(e, "\\part not found")
    assert.equal(1,      e.level)
    assert.equal("part", e.kind)
    assert.equal(false,  e.starred)
  end)

  it("detects \\chapter", function()
    local e = find(results, "Background")
    assert.is_not_nil(e, "\\chapter not found")
    assert.equal(2,         e.level)
    assert.equal("chapter", e.kind)
  end)

  it("detects \\section", function()
    local e = find(results, "Overview")
    assert.is_not_nil(e, "\\section not found")
    assert.equal(3,         e.level)
    assert.equal("section", e.kind)
  end)

  it("detects \\subsection", function()
    local e = find(results, "Details")
    assert.is_not_nil(e, "\\subsection not found")
    assert.equal(4,            e.level)
    assert.equal("subsection", e.kind)
  end)

  it("detects \\subsubsection", function()
    local e = find(results, "Fine Points")
    assert.is_not_nil(e, "\\subsubsection not found")
    assert.equal(5,               e.level)
    assert.equal("subsubsection", e.kind)
  end)

  it("does NOT match starred variants when include_starred = false", function()
    assert.is_nil(find(results, "An Unnumbered Section"))
    assert.is_nil(find(results, "Starred Subsection"))
  end)

  it("does not match \\notacommand", function()
    assert.is_nil(find(results, "Something"))
  end)
end)

describe("parser – latex (with starred)", function()
  local results

  before_each(function()
    results = scan("sample.tex", "tex", { include_starred = true })
  end)

  it("includes \\section*", function()
    local e = find(results, "An Unnumbered Section")
    assert.is_not_nil(e, "\\section* not found")
    assert.equal(3,         e.level)
    assert.equal("section", e.kind)
    assert.equal(true,      e.starred)
  end)

  it("includes \\subsection*", function()
    local e = find(results, "Starred Subsection")
    assert.is_not_nil(e, "\\subsection* not found")
    assert.equal(4,            e.level)
    assert.equal("subsection", e.kind)
    assert.equal(true,         e.starred)
  end)
end)

-- ─── Org ──────────────────────────────────────────────────────────────────────

describe("parser – org", function()
  local results

  before_each(function()
    results = scan("sample.org", "org")
  end)

  it("returns a non-empty table", function()
    assert.is_true(#results > 0)
  end)

  it("detects * heading (level 1)", function()
    local e = find(results, "Top Level Heading")
    assert.is_not_nil(e, "level-1 org heading not found")
    assert.equal(1,    e.level)
    assert.equal("h1", e.kind)
    assert.equal(false, e.starred)
  end)

  it("detects ** heading (level 2)", function()
    local e = find(results, "Second Level")
    assert.is_not_nil(e, "level-2 org heading not found")
    assert.equal(2,    e.level)
    assert.equal("h2", e.kind)
  end)

  it("detects *** heading (level 3)", function()
    local e = find(results, "Third Level")
    assert.is_not_nil(e, "level-3 org heading not found")
    assert.equal(3,    e.level)
    assert.equal("h3", e.kind)
  end)

  it("detects **** heading (level 4)", function()
    local e = find(results, "Fourth Level")
    assert.is_not_nil(e, "level-4 org heading not found")
    assert.equal(4,    e.level)
    assert.equal("h4", e.kind)
  end)

  it("does NOT match *no-space", function()
    assert.is_nil(find(results, "not-a-heading (missing space)"))
  end)
end)

-- ─── Edge cases ───────────────────────────────────────────────────────────────

describe("parser – edge cases", function()
  it("returns empty table for non-existent file", function()
    local r = parser.scan_file("/tmp/__nonexistent_file_xyz__.md", "markdown")
    assert.are.same({}, r)
  end)

  it("returns empty table for unsupported filetype", function()
    local r = parser.scan_file(fixtures .. "/sample.md", "python")
    assert.are.same({}, r)
  end)
end)

-- ─── Recursive include scanning (Phase 2) ────────────────────────────────────

describe("parser – latex recursive scan_includes", function()
  local results, deps

  before_each(function()
    results, deps = parser.scan_file(
      fixtures .. "/main.tex",
      "tex",
      { scan_includes = true, recursive_limit = 5 }
    )
  end)

  it("returns a non-empty table", function()
    assert.is_true(#results > 0)
  end)

  it("returns a deps table as second return value", function()
    assert.is_table(deps)
  end)

  it("finds headings from the root file", function()
    local found = false
    for _, e in ipairs(results) do
      if e.title == "The Whole Document" then found = true end
    end
    assert.is_true(found, "\\part in main.tex not found")
  end)

  it("finds headings from chapter1.tex (\\include)", function()
    local found = false
    for _, e in ipairs(results) do
      if e.title == "First Chapter" then found = true end
    end
    assert.is_true(found, "\\chapter{First Chapter} not found")
  end)

  it("finds headings from chapter2.tex (\\input)", function()
    local found = false
    for _, e in ipairs(results) do
      if e.title == "Second Chapter" then found = true end
    end
    assert.is_true(found, "\\chapter{Second Chapter} not found")
  end)

  it("root-file headings have source_file = ''", function()
    for _, e in ipairs(results) do
      if e.title == "The Whole Document" or e.title == "An Interlude in Main" then
        assert.equal("", e.source_file, "root entry should have empty source_file")
      end
    end
  end)

  it("sub-file headings have the correct relative source_file", function()
    for _, e in ipairs(results) do
      if e.title == "First Chapter" then
        assert.equal("chapters/chapter1.tex", e.source_file)
      end
      if e.title == "Second Chapter" then
        assert.equal("chapters/chapter2.tex", e.source_file)
      end
    end
  end)

  it("preserves DFS document order", function()
    -- Expected order of titles:
    --   The Whole Document (main, \part)
    --   First Chapter      (chapter1)
    --   Opening of Chapter One (chapter1)
    --   Details of First   (chapter1)
    --   An Interlude in Main (main, \section)
    --   Second Chapter     (chapter2)
    --   Another Section    (chapter2)
    local titles = {}
    for _, e in ipairs(results) do
      table.insert(titles, e.title)
    end
    assert.equal("The Whole Document",    titles[1])
    assert.equal("First Chapter",          titles[2])
    assert.equal("Opening of Chapter One", titles[3])
    assert.equal("Details of First",       titles[4])
    assert.equal("An Interlude in Main",   titles[5])
    assert.equal("Second Chapter",         titles[6])
    assert.equal("Another Section",        titles[7])
  end)

  it("deps table contains the included sub-files", function()
    assert.is_not_nil(deps["chapters/chapter1.tex"], "chapter1.tex not in deps")
    assert.is_not_nil(deps["chapters/chapter2.tex"], "chapter2.tex not in deps")
  end)

  it("deps table does NOT contain the root file", function()
    assert.is_nil(deps[""], "root file should not be in deps")
    assert.is_nil(deps["main.tex"], "root file should not be in deps")
  end)

  it("without scan_includes does NOT follow includes", function()
    local r = parser.scan_file(fixtures .. "/main.tex", "tex", { scan_includes = false })
    -- Only root-file headings (\part + \section); chapters not followed
    local titles = {}
    for _, e in ipairs(r) do table.insert(titles, e.title) end
    assert.equal(2, #titles)
    assert.equal("The Whole Document",  titles[1])
    assert.equal("An Interlude in Main", titles[2])
  end)
end)

describe("parser – recursive cycle and depth guard", function()
  it("scan_includes on a file with no includes returns only that file's headings", function()
    local r, d = parser.scan_file(
      fixtures .. "/chapters/chapter1.tex",
      "tex",
      { scan_includes = true }
    )
    assert.is_table(d)
    assert.equal(0, vim.tbl_count(d), "no deps expected when no includes found")
    assert.equal(3, #r)  -- chapter, section, subsection
  end)
end)
