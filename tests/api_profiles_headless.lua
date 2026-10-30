assert(vim.fn.exists(":ApiSearch") == 2)
assert(vim.fn.exists(":ApiSearchCurrent") == 2)
assert(vim.fn.exists(":PythonApiSearch") == 2)
assert(vim.fn.exists(":ProjectTasks") == 2)
assert(not package.loaded["config.api_search"])
assert(not package.loaded["config.python_api"], "backend loaded at startup")
local original_picker = Snacks.picker
local dialogs, calls = {}, {}
Snacks.picker = function(opts)
  dialogs[#dialogs + 1] = opts
end
local api = require("config.api_search")
assert(#api.profiles() == 6, "default languages missing")
assert(not package.loaded["config.api_search.local"] and not package.loaded["config.api_search.hoogle"])
vim.g.api_search_profiles = { "config.api_search.profiles.python" }
api.search("iterable key")
assert(dialogs[1].title == "API search language")
assert(#dialogs[1].items == 1 and dialogs[1].items[1].text == "Python")
assert(not package.loaded["config.python_api"], "language chooser loaded backend")
local closed = false
local window = {
  close = function()
    closed = true
  end,
}
local function select(label)
  local dialog = dialogs[#dialogs]
  for _, item in ipairs(dialog.items) do
    if item.text == label then
      dialog.confirm(window, item)
      return
    end
  end
  error("Missing picker item " .. label)
end
select("Python")
assert(closed and dialogs[#dialogs].title == "Python API sources")
assert(not package.loaded["config.python_api"], "source chooser loaded backend")
package.loaded["config.python_api"] = {
  search = function(query)
    calls[#calls + 1] = { "stdlib", query }
  end,
  packages = function(query)
    calls[#calls + 1] = { "packages", query }
  end,
}
select("Standard library")
assert(calls[1][1] == "stdlib" and calls[1][2] == "iterable key")
api.search("asyncio gather")
select("Python")
select("Installed packages")
assert(calls[2][1] == "packages" and calls[2][2] == "asyncio gather")
-- Dismissal at either stage must have no backend side effects.
local count = #calls
api.search()
dialogs[#dialogs].confirm(window, nil)
assert(#calls == count)
api.search()
select("Python")
dialogs[#dialogs].confirm(window, nil)
assert(#calls == count)
vim.bo.filetype = "python"
vim.cmd("ApiSearchCurrent Callable Iterable")
assert(dialogs[#dialogs].title == "Python API sources")
select("Standard library")
assert(calls[#calls][2] == "Callable Iterable")
local notify = vim.notify
local notices = {}
vim.notify = function(msg)
  notices[#notices + 1] = msg
end
vim.bo.filetype = "rust"
api.current("foo")
assert(dialogs[#dialogs].title == "API search language" and #notices == 1)
assert(#calls == count + 1, "unsupported filetype silently invoked a backend")
vim.bo.filetype = ""
api.current()
assert(#notices == 2)
-- A new profile needs no dispatcher changes. A single source opens directly.
package.preload["fixture.api_profile"] = function()
  return {
    id = "fixture",
    label = "Fixture",
    filetypes = { "fixture" },
    sources = {
      {
        id = "local",
        label = "Local",
        open = function(query)
          calls[#calls + 1] = { "fixture", query }
        end,
      },
    },
  }
end
vim.g.api_search_profiles = { "config.api_search.profiles.python", "fixture.api_profile" }
vim.bo.filetype = "fixture"
api.current("lookup")
assert(calls[#calls][1] == "fixture" and calls[#calls][2] == "lookup")
vim.cmd("ApiSearch partial signature")
select("Fixture")
assert(calls[#calls][2] == "partial signature")
-- Conflicting filetypes offer the matching profiles, not an arbitrary backend.
package.preload["fixture.api_other"] = function()
  return {
    id = "other",
    label = "Other",
    filetypes = { "fixture" },
    sources = { { id = "local", label = "Local", open = function() end } },
  }
end
vim.g.api_search_profiles = { "fixture.api_profile", "fixture.api_other" }
api.current()
assert(dialogs[#dialogs].title == "API search language" and #dialogs[#dialogs].items == 2)
vim.g.api_search_profiles = { "fixture.api_profile", "fixture.api_profile" }
assert(#api.profiles() == 1 and #notices == 3)
vim.g.api_search_profiles = {}
api.search()
assert(notices[#notices] == "No API search profiles are configured")
-- Existing commands remain direct Python entrypoints.
vim.cmd("PythonApiSearch sorted")
assert(calls[#calls][1] == "stdlib" and calls[#calls][2] == "sorted")
vim.cmd("PythonApiPackages Callable")
assert(calls[#calls][1] == "packages" and calls[#calls][2] == "Callable")
-- Old key names remain fallbacks; new names take precedence.
local keymaps = vim.fn.stdpath("config") .. "/lua/config/keymaps.lua"
vim.g.python_api_key = "<F6>"
vim.g.python_api_packages_key = "<F7>"
dofile(keymaps)
assert(vim.fn.maparg("<F6>", "n", false, true).desc == "API search: choose language")
assert(vim.fn.maparg("<F7>", "n", false, true).desc == "API search: current language")
vim.g.api_search_key = "<F8>"
vim.g.api_search_current_key = "<F9>"
dofile(keymaps)
assert(vim.fn.maparg("<F8>", "n", false, true).desc == "API search: choose language")
assert(vim.fn.maparg("<F9>", "n", false, true).desc == "API search: current language")
vim.notify = notify
Snacks.picker = original_picker
package.loaded["config.python_api"] = nil
-- Exercise actual Snacks menus and the existing result renderer together.
vim.g.api_search_profiles = { "config.api_search.profiles.python" }
local file = vim.fn.tempname() .. ".json"
vim.fn.writefile({
  vim.json.encode({
    version = 2,
    entries = {
      {
        name = "builtins.sorted",
        signature = "(iterable) -> list",
        guard = "",
        doc = "",
        source = "/tmp/fixture.pyi",
        line = 1,
      },
    },
  }),
}, file)
api.search("sorted")
local function active(title)
  assert(vim.wait(3000, function()
    local p = Snacks.picker.get()[1]
    return p and p.opts.title == title and p:count() > 0
  end))
  return Snacks.picker.get()[1]
end
local language = active("API search language")
language.opts.confirm(language, language:items()[1])
local source = active("Python API sources")
local backend = require("config.python_api")
local search = backend.search
backend.search = function(query)
  return search(query, file, "fixture")
end
for _, item in ipairs(source:items()) do
  if item.text == "Standard library" then
    source.opts.confirm(source, item)
    break
  end
end
local results = active("Python API: fixture")
assert(results:items()[1].entry.name == "builtins.sorted")
results:close()
backend.search = search
vim.fn.delete(file)
print("Profile dispatch, cancellation, compatibility, configuration and lazy-loading checks passed")
