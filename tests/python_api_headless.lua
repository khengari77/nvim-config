assert(vim.fn.exists(":PythonApiSearch") == 2)
local practice = require("config.interview")
assert(practice.active, "start tests with NVIM_INTERVIEW=1")
require("lazy").load({ plugins = { "supermaven-nvim" } })
local sm = require("supermaven-nvim.api")
assert(not sm.is_running(), "AI backend started during practice")
sm.start()
assert(not sm.is_running(), "guard allowed AI startup")
assert(not require("supermaven-nvim.cmp").is_available())
assert(require("opencode").ask("must be blocked") == "")
practice.command("off")
assert(not practice.active)
assert(require("supermaven-nvim.cmp").is_available())
practice.command("on")
assert(practice.active)
local path = vim.fn.stdpath("cache") .. "/python-api/index.json"
local data = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
assert(#data.entries > 1000)
local names = {}
for _, entry in ipairs(data.entries) do
  names[entry.name] = true
end
for _, name in ipairs({ "builtins.sorted", "itertools.groupby", "asyncio.gather", "collections" }) do
  assert(names[name], "missing public API: " .. name)
end
local Matcher = require("snacks.picker.core.matcher")
for _, query in ipairs({
  "sorted",
  "itertools.groupby",
  "collections",
  "iterable key",
  "list[str]",
  "Callable",
  "Callable Iterable",
  "Iterator[T]",
  "asyncio gather",
}) do
  local matcher = Matcher.new({ filename_bonus = false, file_pos = false })
  matcher:init(query)
  local matches = {}
  for _, e in ipairs(data.entries) do
    local text = e.name .. " " .. e.signature
    local score = matcher:match({ text = text, idx = 1 })
    if score > 0 then
      matches[#matches + 1] = { score = score, text = text }
    end
  end
  table.sort(matches, function(a, b)
    return a.score > b.score
  end)
  assert(#matches > 0, "no matches for " .. query)
  print(query .. ": " .. #matches .. " matches; " .. matches[1].text)
end
require("config.python_api").search("itertools.groupby")
vim.wait(200)
local pickers = Snacks.picker.get()
assert(#pickers > 0, "picker did not open")
for _, picker in ipairs(pickers) do
  picker:close()
end
-- Simulate a running backend: practice must stop and restore it without AI calls.
local running = true
local original = { sm.is_running, sm.stop, sm.start }
sm.is_running = function()
  return running
end
sm.stop = function()
  running = false
end
sm.start = function()
  running = true
end
practice.set(false)
practice.set(true)
assert(not running)
practice.set(false)
assert(running)
sm.is_running, sm.stop, sm.start = unpack(original)
practice.set(true)
vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy" })
assert(vim.fn.maparg("<leader>ph", "n") ~= "")
local readfile = vim.fn.readfile
local notify = vim.notify
local notified = false
vim.notify = function()
  notified = true
end
vim.fn.readfile = function()
  error("missing cache")
end
require("config.python_api").search()
assert(notified)
notified = false
vim.fn.readfile = function()
  return { "invalid json" }
end
require("config.python_api").search()
assert(notified)
vim.fn.readfile = readfile
vim.notify = notify
print("Headless integration checks passed")
