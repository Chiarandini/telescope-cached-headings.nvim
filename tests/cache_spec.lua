-- Run with:
--   nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}"

local cache = require("telescope._extensions.cached_headings.cache")

-- ─── Helpers ──────────────────────────────────────────────────────────────────

local function tmp_path()
  return vim.fn.tempname() .. ".headings"
end

-- ─── get_cache_path ───────────────────────────────────────────────────────────

describe("cache.get_cache_path", function()
  it("local strategy: hidden file next to source", function()
    local p = cache.get_cache_path("/home/user/docs/thesis.tex", "local")
    assert.equal("/home/user/docs/.thesis.tex.headings", p)
  end)

  it("global strategy: path inside stdpath(data)", function()
    local p = cache.get_cache_path("/home/user/docs/thesis.tex", "global")
    -- Should live under the data dir and end with .headings
    assert.is_true(p:find(vim.fn.stdpath("data"), 1, true) == 1)
    assert.is_true(p:sub(-9) == ".headings")
  end)

  it("global strategy: two different files produce different paths", function()
    local p1 = cache.get_cache_path("/a/foo.tex", "global")
    local p2 = cache.get_cache_path("/b/foo.tex", "global")
    assert.are_not.equal(p1, p2)
  end)
end)

-- ─── read_cache ───────────────────────────────────────────────────────────────

describe("cache.read_cache", function()
  it("returns nil for a non-existent file", function()
    assert.is_nil(cache.read_cache("/tmp/__no_such_cache_file__.headings"))
  end)
end)

-- ─── write_cache / read_cache round-trip ─────────────────────────────────────

describe("cache round-trip", function()
  local path

  before_each(function()
    path = tmp_path()
  end)

  after_each(function()
    -- clean up temp file
    os.remove(path)
  end)

  it("preserves line, level, and text for a single entry", function()
    local entries = { { line = 42, level = 3, text = "\\section{Overview}" } }
    local ok, err = cache.write_cache(path, entries)
    assert.is_true(ok, "write_cache failed: " .. tostring(err))

    local read = cache.read_cache(path)
    assert.is_not_nil(read)
    assert.equal(1, #read)
    assert.equal(42,                   read[1].line)
    assert.equal(3,                    read[1].level)
    assert.equal("\\section{Overview}", read[1].text)
  end)

  it("preserves multiple entries in order", function()
    local entries = {
      { line = 1,  level = 1, text = "# Introduction" },
      { line = 10, level = 2, text = "## Background" },
      { line = 20, level = 3, text = "### Details" },
    }
    cache.write_cache(path, entries)
    local read = cache.read_cache(path)
    assert.is_not_nil(read)
    assert.equal(3, #read)

    assert.equal(1,               read[1].line)
    assert.equal("# Introduction", read[1].text)

    assert.equal(10,             read[2].line)
    assert.equal("## Background", read[2].text)

    assert.equal(20,           read[3].line)
    assert.equal("### Details", read[3].text)
  end)

  it("handles markdown headings (text starts with #) correctly", function()
    -- This verifies that the '#' comment-skipping logic in read_cache
    -- does NOT accidentally filter out heading lines (which start with digits,
    -- not '#', since the format is "line|level|text").
    local entries = {
      { line = 1, level = 1, text = "# Top Level" },
      { line = 5, level = 2, text = "## Sub Level" },
    }
    cache.write_cache(path, entries)
    local read = cache.read_cache(path)
    assert.is_not_nil(read)
    assert.equal(2, #read)
    assert.equal("# Top Level",  read[1].text)
    assert.equal("## Sub Level", read[2].text)
  end)

  it("handles text containing pipe characters", function()
    local entries = { { line = 7, level = 2, text = "## Foo | Bar | Baz" } }
    cache.write_cache(path, entries)
    local read = cache.read_cache(path)
    assert.is_not_nil(read)
    assert.equal("## Foo | Bar | Baz", read[1].text)
  end)

  it("returns empty table for an empty cache file", function()
    cache.write_cache(path, {})
    local read = cache.read_cache(path)
    assert.is_not_nil(read)
    assert.equal(0, #read)
  end)

  it("write_cache returns false when path is unwritable", function()
    local ok, err = cache.write_cache("/no_permission_dir/__test__.headings", {})
    assert.is_false(ok)
    assert.is_string(err)
  end)
end)
