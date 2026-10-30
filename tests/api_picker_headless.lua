local path = vim.fn.tempname() .. ".json"
local function entry(name, signature)
  return { name = name, signature = signature, source = "/tmp/api-fixture.pyi", line = 1, guard = "", doc = "fixture" }
end
vim.fn.writefile(
  {
    vim.json.encode({
      version = 2,
      entries = {
        entry("builtins.sorted", "(iterable: Iterable[T], key: Callable) -> list[T]"),
        entry("builtins.sorted", "(iterable: Iterable[T], reverse: bool) -> list[T]"),
        entry("unittest.sorted_list_difference", "(expected, actual)"),
        entry("_internal.sorted", "(private: bool)"),
      },
    }),
  },
  path
)
local api = require("config.python_api")
api.search("sorted", path, "fixture")
local function picker()
  assert(vim.wait(3000, function()
    local p = Snacks.picker.get()[1]
    return p and p:count() > 0
  end))
  vim.wait(100)
  return Snacks.picker.get()[1]
end
local p = picker()
assert(p:items()[1].entry.name == "builtins.sorted", "exact simple name not prioritized")
local sorted
for _, item in ipairs(p:items()) do
  assert(not item.private, "private symbol shown by default")
  if item.entry.name == "builtins.sorted" then
    sorted = item
  end
end
assert(sorted and #sorted.overloads == 2, "overloads not grouped")
assert(
  sorted.text:find("reverse", 1, true) and sorted.text:find("Callable", 1, true),
  "overload signatures not searchable"
)
p.opts.actions.toggle_private(p)
p = picker()
local private = false
for _, item in ipairs(p:items()) do
  if item.private then
    private = true
  end
end
assert(private, "private toggle failed")
p:close()
api.search("builtins.sorted", path, "fixture")
p = picker()
assert(p:items()[1].entry.name == "builtins.sorted")
p:close()
vim.fn.delete(path)
print("API picker grouping, exact matching and private-toggle checks passed")
