local P = require("config.workflow.projects")
local A = require("config.workflow.adapters")
local W = require("config.workflow")
vim.notify = function(msg)
  io.stderr:write(tostring(msg) .. "\n")
end
-- Fixture execution must not install language servers or format source files.
vim.g.autoformat = false
local lsp = require("lazy.core.config").plugins["nvim-lspconfig"]
local opts = require("lazy.core.plugin").values(lsp, "opts", false)
for _, server in pairs(opts.servers or {}) do
  if type(server) == "table" then
    server.mason = false
  end
end
local root = vim.fn.tempname() .. " project with spaces"
vim.fn.mkdir(root .. "/workspace/app", "p")
vim.fn.mkdir(root .. "/.git", "p")
vim.g.project_workflow = { roots = { root } }
vim.fn.writefile({ '{"scripts":{"test":"echo root"},"packageManager":"bun@1"}' }, root .. "/workspace/package.json")
vim.fn.writefile({ '{"scripts":{"dev":"echo dev","test":"echo app"}}' }, root .. "/workspace/app/package.json")
local file = root .. "/workspace/app/example.py"
vim.fn.writefile({ 'print("hello")' }, file)
vim.cmd("noautocmd edit " .. vim.fn.fnameescape(file))
assert(P.root() == root .. "/workspace", "inherited parent .git")
local tasks = A.discover(P.root())
assert(#tasks == 3)
for _, task in ipairs(tasks) do
  assert(task.argv[1] == "bun")
end
local project = P.root()
local finished
W.run({ id = "fixture", text = "fixture", argv = { "sh", "-c", 'printf "hello\\n"' }, cwd = project }, function(code)
  finished = code
end, project)
assert(vim.wait(5000, function()
  return finished ~= nil
end))
assert(finished == 0)
local failed
W.run({ id = "failure", text = "failure", argv = { "sh", "-c", "exit 3" }, cwd = project }, function(code)
  failed = code
end, project)
assert(vim.wait(5000, function()
  return failed ~= nil
end))
assert(failed == 3)
assert(W.logs.fixture ~= W.logs.failure, "logs shared by concurrent tasks")
W.run({ id = "stop", text = "stop", argv = { "sleep", "30" }, cwd = project }, nil, project)
local job = W.jobs.stop.job
vim.fn.jobstop(job)
assert(vim.wait(5000, function()
  return W.jobs.stop == nil
end))
-- Sample cases exercise real subprocess stdin, exact comparisons and timeouts.
local target = { argv = { "cat" }, cwd = project, kind = "run", id = "cases", text = "cases" }
local cases = W.case_directory(file)
vim.fn.writefile({ "hello" }, cases .. "/sample.in")
vim.fn.writefile({ "hello" }, cases .. "/sample.out")
local results
W.run_cases(file, target, project, function(value)
  results = value
end)
assert(vim.wait(5000, function()
  return results ~= nil
end))
assert(results[1].pass)
vim.fn.writefile({ "different" }, cases .. "/sample.out")
results = nil
W.run_cases(file, target, project, function(value)
  results = value
end)
assert(vim.wait(5000, function()
  return results ~= nil
end))
assert(not results[1].pass)
local settings = vim.g.project_workflow
settings.case_timeout_ms = 50
settings.case_output_limit_bytes = 64
vim.g.project_workflow = settings
results = nil
W.run_cases(file, { argv = { "sleep", "2" }, cwd = project }, project, function(value)
  results = value
end)
assert(vim.wait(5000, function()
  return results ~= nil
end))
assert(not results[1].pass and results[1].code ~= 0)
results = nil
W.run_cases(file, { argv = { "sh", "-c", 'printf "%0100d" 0' }, cwd = project }, project, function(value)
  results = value
end)
assert(vim.wait(5000, function()
  return results ~= nil
end))
assert(results[1].overflow)
settings.case_timeout_ms = 5000
settings.case_output_limit_bytes = 1048576
vim.g.project_workflow = settings
-- Compile a standalone fixture into Neovim's cache and run it.
if vim.fn.executable("cc") == 1 then
  local source = project .. "/compiled.c"
  vim.fn.writefile({ "#include <stdio.h>", 'int main(void) { puts("compiled"); return 0; }' }, source)
  local compiled = A.file(source, project, true)
  local compiled_exit
  W.run(compiled, function(code)
    compiled_exit = code
  end, project)
  assert(vim.wait(5000, function()
    return compiled_exit ~= nil
  end))
  assert(compiled_exit == 0)
  local dir = W.case_directory(source)
  vim.fn.writefile({}, dir .. "/one.in")
  vim.fn.writefile({ "compiled" }, dir .. "/one.out")
  vim.fn.writefile({}, dir .. "/two.in")
  vim.fn.writefile({ "compiled" }, dir .. "/two.out")
  local marker = project .. "/compile-count"
  compiled.prepare =
    { "sh", "-c", 'printf x >> "$1"; exec cc "$2" -o "$3"', "compile", marker, source, compiled.argv[1] }
  results = nil
  W.run_cases(source, compiled, project, function(value)
    results = value
  end)
  assert(vim.wait(5000, function()
    return results ~= nil
  end))
  assert(#results == 2 and results[1].pass and results[2].pass)
  assert(vim.fn.readfile(marker)[1] == "x", "compiled more than once per suite")
end
-- Diagnostic locations stay relative to the task, not the editor's directory.
local diagnostics =
  W.parse({ "src/a.cpp:3:4: error: example", '  File "script.py", line 7, in main', " --> src/lib.rs:9:2" }, project)
assert(#diagnostics == 3)
assert(diagnostics[1].filename == project .. "/src/a.cpp" and diagnostics[1].col == 4)
assert(diagnostics[2].lnum == 7 and diagnostics[3].lnum == 9)
-- Buffer preservation on project selection; stub only the file picker UI.
local original_picker = Snacks.picker.files
Snacks.picker.files = function(opts)
  assert(opts.cwd == project)
end
local buffer_count = #vim.api.nvim_list_bufs()
P.open(project)
assert(#vim.api.nvim_list_bufs() >= buffer_count)
Snacks.picker.files = original_picker
-- Scratch files are executable without changing files in the project.
local pick = P.pick
P.pick = function(_, _, callback)
  callback({ text = "python" })
end
W.scratch()
local scratch = vim.api.nvim_get_current_buf()
assert(vim.api.nvim_buf_get_name(scratch):match("scratch%.py$"))
assert(P.root() == project)
vim.api.nvim_buf_set_lines(scratch, 0, -1, false, { 'print("scratch")' })
local mapping = vim.fn.maparg("<localleader>r", "n", false, true)
assert(type(mapping.callback) == "function")
mapping.callback()
assert(vim.wait(5000, function()
  return next(W.jobs) == nil
end))
P.pick = pick
local files = Snacks.picker.files
Snacks.picker.files = function() end
P.open(project)
Snacks.picker.files = files
assert(vim.api.nvim_buf_is_valid(scratch), "project switch discarded scratch buffer")
-- Discovery against real projects is strictly read-only.
for _, name in ipairs({ "qafiyah", "Watad", "sarj-drill", "svelte-purs", "RoverSim", "AnkiDroid-Companion" }) do
  local directory = vim.env.HOME .. "/Programming/" .. name
  vim.api.nvim_set_current_dir(directory)
  vim.cmd.enew()
  local found = A.discover(directory)
  assert(#found > 0, "no tasks for " .. name)
  print(name .. ": " .. #found .. " tasks discovered")
end
vim.api.nvim_set_current_dir(vim.env.HOME .. "/Programming/Watad")
vim.cmd.enew()
local original_pick = P.pick
local listed
P.pick = function(items, title)
  assert(title == "Worktrees")
  listed = items
end
P.worktrees()
assert(vim.wait(5000, function()
  return listed ~= nil
end))
assert(#listed > 0)
P.pick = original_pick
assert(vim.fn.exists(":ProjectCases") == 2)
assert(vim.fn.exists(":ProjectPick") == 2)
print("Workflow checks passed")
