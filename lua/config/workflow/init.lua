local P = require("config.workflow.projects")
local A = require("config.workflow.adapters")
local M = {
  jobs = {},
  logs = {},
  last = {},
  windows = {},
  diagnostics = {},
  log_context = {},
  case_runs = {},
  case_results = {},
}
local function output(root, key)
  key = key or root
  local buf = M.logs[key]
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    buf = vim.api.nvim_create_buf(false, true)
    M.logs[key] = buf
    vim.bo[buf].filetype = "log"
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].modifiable = false
    vim.b[buf].workflow_root = root
  end
  local win = M.windows[root]
  if not win or not vim.api.nvim_win_is_valid(win) then
    vim.cmd("botright 12split")
    win = vim.api.nvim_get_current_win()
    M.windows[root] = win
  end
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_set_current_win(win)
  return buf
end
local function append(buf, lines)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
    vim.bo[buf].modified = false
    vim.bo[buf].modifiable = false
  end
end
function M.parse(lines, cwd, errorformat)
  if errorformat then
    local previous = vim.fn.getcwd()
    -- getqflist resolves file names relative to cwd, without changing editor cwd.
    local items = vim.fn.getqflist({ lines = lines, efm = errorformat }).items
    for _, item in ipairs(items) do
      if item.bufnr and item.bufnr > 0 then
        local path = vim.api.nvim_buf_get_name(item.bufnr)
        if path:sub(1, #previous + 1) == previous .. "/" then
          item.bufnr = vim.fn.bufadd(cwd .. "/" .. path:sub(#previous + 2))
        end
      end
    end
    return items
  end
  local items = {}
  for _, raw in ipairs(lines) do
    local line = raw:gsub("\27%[[%d;]*m", "")
    local file, row, column, message = line:match("^%s*([^:]+):(%d+):(%d+):%s*(.*)")
    if not file then
      file, row, message = line:match("^%s*([^:]+):(%d+):%s*(.*)")
    end
    if not file then
      file, row = line:match('File "([^"]+)", line (%d+)')
    end
    if not file then
      file, row, column = line:match("%-%->%s+(.+):(%d+):(%d+)")
    end
    if file then
      if file:sub(1, 1) ~= "/" then
        file = cwd .. "/" .. file
      end
      items[#items + 1] =
        { filename = vim.fs.normalize(file), lnum = tonumber(row), col = tonumber(column) or 1, text = message or line }
    end
  end
  return items
end
function M.resolve(task, callback)
  if not task.executable_dir then
    return callback(task)
  end
  vim.ui.input(
    { prompt = "Executable to run: ", default = task.executable_dir .. "/", completion = "file" },
    function(path)
      if not path then
        return
      end
      path = vim.fn.fnamemodify(path, ":p")
      if vim.fn.executable(path) ~= 1 or vim.fn.isdirectory(path) == 1 then
        return vim.notify("Choose an existing executable file", vim.log.levels.ERROR)
      end
      local resolved = vim.deepcopy(task)
      resolved.argv = { path }
      resolved.executable_dir = nil
      resolved.id = task.id .. ":" .. path
      callback(resolved)
    end
  )
end
function M.run(task, done, root)
  if task.executable_dir then
    return M.resolve(task, function(t)
      M.run(t, done, root)
    end)
  end
  root = root or P.root()
  if M.jobs[task.id] then
    return vim.notify("This task is already running")
  end
  local command = task.prepare or task.argv
  if vim.fn.executable(command[1]) ~= 1 then
    return vim.notify("Missing executable: " .. command[1], vim.log.levels.ERROR)
  end
  local buf = output(root, task.id)
  M.log_context[task.id] = { root = root, text = task.text }
  M.latest = M.latest or {}
  M.latest[root] = task.id
  append(buf, { "", "$ " .. table.concat(command, " "), "cwd: " .. task.cwd })
  M.last[root] = vim.deepcopy(task)
  P.context(root).last = task.id
  P.context(root).last_cwd = task.cwd
  P.save()
  local lines = {}
  local function launch(argv, prepared)
    if vim.fn.executable(argv[1]) ~= 1 then
      append(buf, { "Missing executable: " .. argv[1] })
      if done then
        done(-1, lines)
      end
      return
    end
    local pending = { stdout = "", stderr = "" }
    local function receive(stream, data)
      if not data or #data == 0 then
        return
      end
      local text = pending[stream] .. table.concat(data, "\n")
      local complete = vim.split(text, "\n", { plain = true })
      pending[stream] = table.remove(complete) or ""
      vim.list_extend(lines, complete)
      append(buf, complete)
    end
    local ok, job = pcall(vim.fn.jobstart, argv, {
      cwd = task.cwd,
      env = task.env,
      on_stdout = function(_, data)
        receive("stdout", data)
      end,
      on_stderr = function(_, data)
        receive("stderr", data)
      end,
      on_exit = function(_, code)
        M.jobs[task.id] = nil
        if code == 0 and prepared then
          return launch(task.argv, false)
        end
        append(buf, { "[exit " .. code .. "]" })
        for _, text in pairs(pending) do
          if text ~= "" then
            lines[#lines + 1] = text
            append(buf, { text })
          end
        end
        local parsed = M.parse(lines, task.cwd, task.errorformat)
        M.diagnostics[task.id] = parsed
        vim.fn.setqflist({}, " ", { title = task.text, items = parsed })
        if done then
          done(code, lines)
        end
      end,
    })
    if not ok or job <= 0 then
      vim.notify("Cannot start " .. argv[1] .. ": " .. tostring(job), vim.log.levels.ERROR)
      M.jobs[task.id] = nil
      return
    end
    M.jobs[task.id] = { job = job, task = task, buf = buf }
  end
  launch(command, task.prepare ~= nil)
end
function M.tasks(kind)
  local root = P.root()
  local items = {}
  for _, task in ipairs(A.discover(root)) do
    if not kind or task.kind == kind then
      items[#items + 1] = task
    end
  end
  if #items == 0 and kind == "run" then
    items[1] = {
      id = root .. ":executable",
      text = "Choose a built executable…",
      kind = "run",
      cwd = root,
      argv = {},
      executable_dir = P.context(root).build or root,
    }
  end
  if #items == 0 then
    return vim.notify(
      "No " .. (kind or "project") .. " tasks found. Configure project_workflow.tasks for custom commands."
    )
  end
  P.pick(items, "Project " .. (kind or "tasks"), function(task)
    M.run(task, nil, root)
  end)
end
function M.file()
  local root = P.root()
  local path = vim.api.nvim_buf_get_name(0)
  if vim.bo.modified then
    vim.cmd.write()
  end
  local task = A.file(path, root)
  if task then
    M.run(task, nil, root)
  else
    M.tasks("run")
  end
end
function M.repeat_task()
  local root = P.root()
  local task = M.last[root]
  if not task then
    for _, candidate in ipairs(A.discover(root, P.context(root).last_cwd)) do
      if candidate.id == P.context(root).last then
        task = candidate
        break
      end
    end
  end
  if task then
    M.run(task, nil, root)
  else
    vim.notify("No previous task for this project")
  end
end
function M.stop()
  local items = {}
  for _, value in pairs(M.jobs) do
    items[#items + 1] = { text = value.task.text, job = value.job }
  end
  for key, value in pairs(M.case_runs) do
    items[#items + 1] = { text = "Cases: " .. key, suite = value }
  end
  P.pick(items, "Stop task", function(item)
    if item.suite then
      item.suite.cancelled = true
      if item.suite.process then
        item.suite.process:kill(15)
      end
    else
      vim.fn.jobstop(item.job)
    end
  end)
end
function M.show()
  local root = P.root()
  local items = {}
  for key, value in pairs(M.log_context) do
    if value.root == root then
      items[#items + 1] = { text = value.text, key = key }
    end
  end
  local function open(item)
    output(root, item.key)
    if M.diagnostics[item.key] then
      vim.fn.setqflist({}, " ", { title = item.text, items = M.diagnostics[item.key] })
    end
  end
  if #items == 1 then
    open(items[1])
  elseif #items > 1 then
    P.pick(items, "Task output", open)
  else
    output(root)
  end
end
function M.scratch()
  local root = P.root()
  P.pick(
    vim.tbl_map(
      function(ft)
        return { text = ft }
      end,
      { "python", "javascript", "typescript", "lua", "sh", "go", "c", "cpp", "rust", "haskell", "nim", "ocaml", "mojo" }
    ),
    "Scratch language",
    function(item)
      local extensions =
        { python = "py", javascript = "js", typescript = "ts", rust = "rs", haskell = "hs", ocaml = "ml" }
      local directory = vim.fn.stdpath("state") .. "/workflow-scratch/" .. vim.fn.sha256(root):sub(1, 16)
      vim.fn.mkdir(directory, "p")
      local win = Snacks.scratch({ file = directory .. "/scratch." .. (extensions[item.text] or item.text) })
      if not win then
        return
      end
      vim.b[win.buf].workflow_root = root
      vim.b[win.buf].workflow_file = vim.api.nvim_buf_get_name(win.buf)
      vim.keymap.set("n", "<localleader>r", function()
        vim.api.nvim_buf_call(win.buf, function()
          vim.cmd.write()
          local task = A.file(vim.api.nvim_buf_get_name(win.buf), root, true)
          if task then
            M.run(task, nil, root)
          end
        end)
      end, { buffer = win.buf, desc = "Run scratch" })
    end
  )
end
function M.case_directory(path)
  local directory = vim.fn.stdpath("state") .. "/workflow-cases/" .. vim.fn.sha256(path):sub(1, 16)
  vim.fn.mkdir(directory, "p")
  return directory
end
function M.edit_case()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    return vim.notify("Open a source file before creating cases")
  end
  local root, directory = P.root(), M.case_directory(path)
  vim.ui.input({ prompt = "Case name: ", default = "sample" }, function(name)
    if not name or not name:match("^[%w_-]+$") then
      return
    end
    for _, ext in ipairs({ "in", "out" }) do
      local file = directory .. "/" .. name .. "." .. ext
      if vim.fn.filereadable(file) == 0 then
        vim.fn.writefile({}, file)
      end
      vim.cmd("vsplit " .. vim.fn.fnameescape(file))
      vim.b.workflow_root = root
      vim.b.workflow_file = vim.api.nvim_buf_get_name(0)
      vim.b.workflow_case_source = path
    end
  end)
end
function M.run_cases(path, target, root, done)
  root = root or P.root()
  if target.executable_dir then
    return M.resolve(target, function(t)
      M.run_cases(path, t, root, done)
    end)
  end
  if M.case_runs[path] then
    return vim.notify("Cases are already running for this file")
  end
  local command = target.prepare or target.argv
  if vim.fn.executable(command[1]) ~= 1 then
    return vim.notify("Missing executable: " .. command[1], vim.log.levels.ERROR)
  end
  local inputs = vim.fn.glob(M.case_directory(path) .. "/*.in", false, true)
  if #inputs == 0 then
    return vim.notify("No cases. Use :ProjectCaseEdit first.")
  end
  local key = "cases:" .. path
  local buf = output(root, key)
  M.log_context[key] = { root = root, text = "Cases: " .. vim.fn.fnamemodify(path, ":t") }
  local suite = { cancelled = false, results = {} }
  M.case_runs[path] = suite
  local index = 0
  local function finish()
    M.case_runs[path] = nil
    M.case_results[path] = suite.results
    append(buf, { suite.cancelled and "[cases cancelled]" or "[cases complete]" })
    if done then
      done(suite.results)
    end
  end
  local function read(file)
    local f = io.open(file, "rb")
    if not f then
      return nil
    end
    local value = f:read("*a")
    f:close()
    return value
  end
  local function next_case()
    index = index + 1
    if suite.cancelled or not inputs[index] then
      return finish()
    end
    local input = inputs[index]
    local expected = read(input:gsub("%.in$", ".out"))
    if not expected then
      append(buf, { "Missing expected output for " .. input })
      return next_case()
    end
    local actual, stderr, overflow = "", "", false
    local ok, process = pcall(
      vim.system,
      target.argv,
      {
        cwd = target.cwd,
        env = target.env,
        stdin = read(input),
        timeout = (vim.g.project_workflow or {}).case_timeout_ms or 5000,
        stdout = function(_, data)
          if not data then
            return
          end
          if #actual + #data > ((vim.g.project_workflow or {}).case_output_limit_bytes or 1048576) then
            overflow = true
            if suite.process then
              suite.process:kill(9)
            end
          else
            actual = actual .. data
          end
        end,
        stderr = function(_, data)
          if data then
            stderr = stderr .. data:sub(1, math.max(0, 65536 - #stderr))
          end
        end,
      },
      vim.schedule_wrap(function(result)
        actual = actual:gsub("\r\n", "\n")
        expected = expected:gsub("\r\n", "\n")
        local pass = result.code == 0 and not overflow and actual == expected
        suite.results[#suite.results + 1] = { name = input, pass = pass, code = result.code, overflow = overflow }
        append(
          buf,
          { vim.fn.fnamemodify(input, ":t") .. ": " .. (pass and "PASS" or "FAIL") .. " (exit " .. result.code .. ")" }
        )
        if not pass then
          append(buf, { "--- expected", "+++ actual" })
          append(buf, vim.split(vim.diff(expected, actual, { result_type = "unified" }), "\n"))
          if stderr ~= "" then
            append(buf, vim.split(stderr, "\n"))
          end
          if overflow then
            append(buf, { "Output limit exceeded (1 MiB)" })
          end
        end
        next_case()
      end)
    )
    if not ok then
      append(buf, { tostring(process) })
      return finish()
    end
    suite.process = process
  end
  if target.prepare then
    suite.process = vim.system(
      target.prepare,
      { cwd = target.cwd, env = target.env, text = true },
      vim.schedule_wrap(function(result)
        if result.code == 0 and not suite.cancelled then
          next_case()
        else
          append(buf, vim.split(result.stderr or "Compilation failed", "\n"))
          finish()
        end
      end)
    )
  else
    next_case()
  end
end
function M.cases()
  local root = P.root()
  local path = vim.b.workflow_case_source or vim.api.nvim_buf_get_name(0)
  if path == "" then
    return vim.notify("Open a source file before running cases")
  end
  if vim.bo.modified then
    vim.cmd.write()
  end
  local task = A.file(path, root)
  if task then
    M.run_cases(path, task, root)
  else
    local items = vim.tbl_filter(function(t)
      return t.kind == "run"
    end, A.discover(root))
    P.pick(items, "Case executable", function(t)
      M.run_cases(path, t, root)
    end)
  end
end
function M.symbols()
  local supported = false
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
    if client:supports_method("textDocument/documentSymbol") then
      supported = true
    end
  end
  if supported then
    Snacks.picker.lsp_symbols()
  else
    local ok = pcall(vim.treesitter.get_parser)
    if ok then
      Snacks.picker.treesitter()
    else
      vim.notify("No LSP symbols or Treesitter parser for this buffer")
    end
  end
end
return M
