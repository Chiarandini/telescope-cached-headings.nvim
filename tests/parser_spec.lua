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
