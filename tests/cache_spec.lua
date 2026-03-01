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

-- ─── v2 format round-trip ─────────────────────────────────────────────────────

describe("cache v2 round-trip", function()
  local path

  before_each(function()
    path = tmp_path()
  end)

  after_each(function()
    os.remove(path)
  end)

  it("write_cache with deps writes v2 format (# v2 header)", function()
    cache.write_cache(path, {}, {})
    local f = io.open(path, "r")
    local first = f:read("*l")
    f:close()
    assert.equal("# v2", first)
  end)

  it("preserves source_file, line, level, text for sub-file entry", function()
    local entries = {
      { source_file = "chapters/intro.tex", line = 10, level = 2, text = "\\chapter{Intro}" },
    }
    local deps = { ["chapters/intro.tex"] = 9999 }
    cache.write_cache(path, entries, deps)

    local read, is_v2 = cache.read_cache(path)  -- no root_dir → skip mtime check
    assert.is_true(is_v2)
    assert.is_not_nil(read)
    assert.equal(1, #read)
    assert.equal("chapters/intro.tex", read[1].source_file)
    assert.equal(10,                   read[1].line)
    assert.equal(2,                    read[1].level)
    assert.equal("\\chapter{Intro}",   read[1].text)
  end)

  it("preserves empty source_file for root-file entries", function()
    local entries = {
      { source_file = "", line = 5, level = 1, text = "\\part{Foundations}" },
    }
    cache.write_cache(path, entries, {})

    local read = cache.read_cache(path)
    assert.is_not_nil(read)
    assert.equal("", read[1].source_file)
    assert.equal(5,  read[1].line)
  end)

  it("preserves mixed root and sub-file entries in order", function()
    local entries = {
      { source_file = "",                    line = 1,  level = 1, text = "\\part{P}" },
      { source_file = "chapters/ch1.tex",   line = 3,  level = 2, text = "\\chapter{C1}" },
      { source_file = "",                    line = 10, level = 3, text = "\\section{S}" },
      { source_file = "chapters/ch2.tex",   line = 2,  level = 2, text = "\\chapter{C2}" },
    }
    cache.write_cache(path, entries, {})

    local read = cache.read_cache(path)
    assert.is_not_nil(read)
    assert.equal(4, #read)
    assert.equal("",                   read[1].source_file)
    assert.equal("chapters/ch1.tex",  read[2].source_file)
    assert.equal("",                   read[3].source_file)
    assert.equal("chapters/ch2.tex",  read[4].source_file)
  end)

  it("write_cache without deps writes v1 format (no # v2 header)", function()
    cache.write_cache(path, { { line = 1, level = 1, text = "# H" } })
    local f = io.open(path, "r")
    local first = f:read("*l")
    f:close()
    assert.are_not.equal("# v2", first)
    -- v1 format: first line is a data line
    assert.is_truthy(first:match("^%d+|"))
  end)

  it("v2 read returns is_v2 = true", function()
    cache.write_cache(path, {}, {})
    local _, is_v2 = cache.read_cache(path)
    assert.is_true(is_v2)
  end)

  it("v1 read returns is_v2 = false", function()
    cache.write_cache(path, { { line = 1, level = 1, text = "# H" } })
    local _, is_v2 = cache.read_cache(path)
    assert.is_false(is_v2)
  end)
end)

-- ─── v2 mtime staleness ───────────────────────────────────────────────────────

describe("cache v2 mtime staleness", function()
  local root_dir, cache_path, dep_rel, dep_abs

  before_each(function()
    root_dir  = vim.fn.tempname()
    vim.fn.mkdir(root_dir .. "/chapters", "p")
    dep_rel   = "chapters/dep.tex"
    dep_abs   = root_dir .. "/" .. dep_rel
    cache_path = tmp_path()
    -- Create an actual file so getftime returns a real mtime
    local f = io.open(dep_abs, "w"); f:write("\\section{test}"); f:close()
  end)

  after_each(function()
    os.remove(dep_abs)
    vim.fn.delete(root_dir, "rf")
    os.remove(cache_path)
  end)

  it("returns nil when stored dep mtime is stale", function()
    local actual_mtime = vim.fn.getftime(dep_abs)
    local entries = { { source_file = dep_rel, line = 1, level = 3, text = "\\section{T}" } }
    -- Store a deliberately wrong mtime
    cache.write_cache(cache_path, entries, { [dep_rel] = actual_mtime - 1 })

    local result = cache.read_cache(cache_path, root_dir)
    assert.is_nil(result, "stale cache should return nil")
  end)

  it("returns entries when stored dep mtime is current", function()
    local actual_mtime = vim.fn.getftime(dep_abs)
    local entries = { { source_file = dep_rel, line = 1, level = 3, text = "\\section{T}" } }
    cache.write_cache(cache_path, entries, { [dep_rel] = actual_mtime })

    local result = cache.read_cache(cache_path, root_dir)
    assert.is_not_nil(result, "fresh cache should return entries")
    assert.equal(1, #result)
  end)

  it("skips mtime check when root_dir is not provided", function()
    -- Even with a wrong mtime, read_cache without root_dir should return entries
    local entries = { { source_file = dep_rel, line = 1, level = 3, text = "\\section{T}" } }
    cache.write_cache(cache_path, entries, { [dep_rel] = 0 })  -- obviously wrong mtime

    local result = cache.read_cache(cache_path)  -- no root_dir
    assert.is_not_nil(result, "without root_dir, mtime check is skipped")
  end)
end)
