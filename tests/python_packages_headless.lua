local api = require("config.python_api")
local function log(message)
  io.stderr:write(message .. "\n")
end
vim.notify = function(message)
  log(tostring(message))
end
local function rss()
  for _, line in ipairs(vim.fn.readfile("/proc/self/status")) do
    if line:match("^VmRSS:") then
      return line
    end
  end
end
local before = api.package_path("requests")
local original = vim.env.VIRTUAL_ENV
vim.env.VIRTUAL_ENV = "/tmp/different-python-environment"
assert(before ~= api.package_path("requests"), "environments share a package cache")
vim.env.VIRTUAL_ENV = original
local pyenv_version = vim.env.PYENV_VERSION
vim.env.PYENV_VERSION = "different-version"
assert(before ~= api.package_path("requests"), "pyenv selections share a cache")
vim.env.PYENV_VERSION = pyenv_version
assert(vim.fn.exists(":PythonApiPackages") == 2)
assert(vim.fn.exists(":PythonApiPackage") == 2)
local started = vim.uv.hrtime()
api.packages("requests.get")
assert(
  vim.wait(10000, function()
    return #Snacks.picker.get() > 0
  end, 20),
  "package picker did not open"
)
local chooser = Snacks.picker.get()[1]
assert(chooser.opts.title == "Installed Python packages")
log(string.format("Package discovery/picker: %.1f ms", (vim.uv.hrtime() - started) / 1e6))
chooser.opts.confirm(chooser, { text = "requests" })
assert(
  vim.wait(15000, function()
    local picker = Snacks.picker.get()[1]
    return picker and picker.opts.title == "Python API: requests"
  end, 20),
  "requests API picker did not open"
)
local data = vim.json.decode(table.concat(vim.fn.readfile(api.package_path("requests")), "\n"))
local found = false
for _, entry in ipairs(data.entries) do
  assert(entry.origin == "package")
  if entry.name == "requests.get" then
    found = true
  end
end
assert(found, "requests.get re-export missing")
for _, picker in ipairs(Snacks.picker.get()) do
  picker:close()
end
collectgarbage("collect")
log("Before cached requests search: " .. rss())
started = vim.uv.hrtime()
api.package("requests", "requests.get")
vim.wait(50)
log(string.format("Cached requests picker: %.1f ms; %s", (vim.uv.hrtime() - started) / 1e6, rss()))
for _, picker in ipairs(Snacks.picker.get()) do
  picker:close()
end
-- Optional timing probe for a larger independently generated catalogue.
if vim.env.PYTHON_API_NUMPY_TEST_INDEX then
  local numpy_path = api.package_path("numpy")
  vim.fn.mkdir(vim.fs.dirname(numpy_path), "p")
  vim.fn.writefile(vim.fn.readfile(vim.env.PYTHON_API_NUMPY_TEST_INDEX), numpy_path)
  collectgarbage("collect")
  started = vim.uv.hrtime()
  api.package("numpy", "numpy.array")
  vim.wait(50)
  log(string.format("Cached NumPy picker: %.1f ms; %s", (vim.uv.hrtime() - started) / 1e6, rss()))
  assert(#Snacks.picker.get() > 0)
  for _, picker in ipairs(Snacks.picker.get()) do
    picker:close()
  end
end
vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy" })
assert(vim.fn.maparg("<leader>pH", "n") ~= "")
log("Installed-package integration checks passed")
