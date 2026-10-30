local M = {}
local cache = vim.fn.stdpath("cache") .. "/python-api"
local config = vim.fn.stdpath("config")
local busy = false
local function run(argv, done)
  vim.system(
    argv,
    { text = true, cwd = require("config.workflow.projects").root() },
    vim.schedule_wrap(function(result)
      if result.code ~= 0 then
        busy = false
        vim.notify(result.stderr or result.stdout, vim.log.levels.ERROR)
      else
        done(result.stdout)
      end
    end)
  )
end
-- Resolve the environment at invocation time, so :cd and venv switches work.
local function environment()
  local projects = require("config.workflow.projects")
  local root = projects.root()
  local context_python = projects.context(root).python
  if context_python then
    return nil, context_python, vim.fn.sha256(context_python):sub(1, 16)
  end
  local prefix = vim.g.python_api_environment
  if not prefix and not vim.g.python_api_python then
    prefix = vim.env.VIRTUAL_ENV or vim.env.CONDA_PREFIX
  end
  if not prefix and not vim.g.python_api_python then
    local directory = root
    local boundary = vim.fs.root(directory, { ".git", "pyproject.toml", "setup.cfg", "requirements.txt" }) or directory
    while directory do
      for _, name in ipairs({ ".venv", "venv" }) do
        local candidate = directory .. "/" .. name
        if vim.uv.fs_stat(candidate .. "/bin/python") then
          prefix = candidate
          break
        end
      end
      if prefix or directory == boundary then
        break
      end
      local parent = vim.fs.dirname(directory)
      if parent == directory then
        break
      end
      directory = parent
    end
  end
  local python = vim.g.python_api_python or (prefix and prefix .. "/bin/python") or "python3"
  local roots = vim.g.python_api_extra_roots or {}
  -- pyenv's executable is a stable shim even when the selected version changes.
  local version_file = vim.fs.find(".python-version", { upward = true, path = root })[1]
    or ((vim.env.PYENV_ROOT or (vim.env.HOME .. "/.pyenv")) .. "/version")
  local version = vim.fn.filereadable(version_file) == 1 and table.concat(vim.fn.readfile(version_file), "\n") or ""
  local identity = vim.json.encode({
    prefix or "",
    vim.fn.exepath(python),
    roots,
    vim.env.PYENV_VERSION or version,
    vim.env.PYTHONUSERBASE or "",
    vim.env.PYTHONNOUSERSITE or "",
  })
  return prefix, python, vim.fn.sha256(identity):sub(1, 16)
end
local function package_args()
  local prefix, python, key = environment()
  local argv = { python, "-I", "-S", config .. "/scripts/python_api_index.py" }
  if prefix then
    vim.list_extend(argv, { "--environment", prefix })
  end
  for _, root in ipairs(vim.g.python_api_extra_roots or {}) do
    vim.list_extend(argv, { "--extra-root", root })
  end
  return argv, key
end
function M.package_path(name)
  local _, key = package_args()
  return cache .. "/packages/" .. key .. "/" .. name .. ".json"
end
function M.package(name, query, rebuild)
  if not name:match("^[%w_]+$") then
    return vim.notify("Invalid Python package name", vim.log.levels.ERROR)
  end
  local path = M.package_path(name)
  if not rebuild and vim.uv.fs_stat(path) then
    return M.search(query, path, name)
  end
  if busy then
    return vim.notify("Python API build already running")
  end
  busy = true
  local argv = package_args()
  vim.list_extend(argv, { "--package", name, "--package-only", "--output", path })
  vim.notify("Indexing " .. name .. " in a background process…")
  run(argv, function(output)
    busy = false
    vim.notify(output)
    if not rebuild then
      M.search(query, path, name)
    end
  end)
end
function M.packages(query)
  local argv = package_args()
  vim.list_extend(argv, { "--list-packages" })
  run(argv, function(output)
    local ok, data = pcall(vim.json.decode, output)
    if not ok then
      return vim.notify("Cannot discover Python packages: " .. output, vim.log.levels.ERROR)
    end
    local items = {}
    for _, name in ipairs(data.packages) do
      items[#items + 1] = { text = name }
    end
    Snacks.picker({
      title = "Installed Python packages",
      items = items,
      format = "text",
      preview = "none",
      confirm = function(picker, item)
        if item then
          picker:close()
          M.package(item.text, query)
        end
      end,
    })
  end)
end
function M.rebuild()
  if busy then
    return vim.notify("Python API build already running")
  end
  busy = true
  local argv = {
    vim.g.python_api_python or "python3",
    "-I",
    "-S",
    config .. "/scripts/python_api_index.py",
    "--root",
    vim.g.python_api_typeshed or cache .. "/typeshed/stdlib",
    "--output",
    cache .. "/index.json",
  }
  table.insert(argv, "--no-packages")
  run(argv, function(output)
    busy = false
    vim.notify(output)
  end)
end
function M.setup_index(update)
  if busy then
    return vim.notify("Python API build already running")
  end
  vim.fn.mkdir(cache, "p")
  if vim.uv.fs_stat(cache .. "/typeshed") then
    if not update then
      return M.rebuild()
    end
    busy = true
    run({ "git", "-C", cache .. "/typeshed", "pull", "--ff-only" }, function()
      busy = false
      run({ "git", "-C", cache .. "/typeshed", "rev-parse", "HEAD" }, function(revision)
        vim.fn.writefile({ vim.trim(revision) }, cache .. "/revision")
        M.rebuild()
      end)
    end)
  else
    busy = true
    run({ "git", "clone", "--depth=1", "https://github.com/python/typeshed.git", cache .. "/typeshed" }, function()
      busy = false
      run({ "git", "-C", cache .. "/typeshed", "rev-parse", "HEAD" }, function(revision)
        vim.fn.writefile({ vim.trim(revision) }, cache .. "/revision")
        M.rebuild()
      end)
    end)
  end
end
local function detail(e)
  return table.concat({
    "# " .. e.name,
    "",
    "```python",
    e.name .. e.signature,
    "```",
    "",
    e.doc,
    "",
    "Conditions: " .. (e.guard ~= "" and e.guard or "unconditional"),
    "",
    "Source: " .. e.source .. ":" .. e.line,
    "",
    e.origin == "package" and "Installed-package signature (parsed without execution)."
      or "Typeshed signature; full prose documentation may require a browser.",
  }, "\n")
end
function M.search(query, path, scope)
  local ok, data = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(path or cache .. "/index.json"), "\n"))
  end)
  if not ok or type(data) ~= "table" or (data.version ~= 1 and data.version ~= 2) or type(data.entries) ~= "table" then
    return vim.notify(
      scope and ("Missing or invalid package index. Run :PythonApiPackage! " .. scope)
        or "Missing or invalid Python API index. Run :PythonApiSetup or :PythonApiRebuild",
      vim.log.levels.WARN
    )
  end
  local grouped = {}
  for _, e in ipairs(data.entries) do
    local group = grouped[e.name]
    if not group then
      group = { entry = e, signatures = {}, docs = {}, variants = {} }
      grouped[e.name] = group
    end
    group.signatures[e.signature] = true
    local variant = e.signature .. "\0" .. e.guard .. "\0" .. e.source
    if not group.variants[variant] then
      group.variants[variant] = true
      group.docs[#group.docs + 1] = e
    end
  end
  local items = {}
  for name, group in pairs(grouped) do
    local signatures = vim.tbl_keys(group.signatures)
    table.sort(signatures)
    local private = false
    for part in name:gmatch("[^.]+") do
      if part:sub(1, 1) == "_" then
        private = true
      end
    end
    items[#items + 1] = {
      text = name .. " " .. table.concat(signatures, " | "),
      entry = group.entry,
      overloads = group.docs,
      private = private,
    }
  end
  local show_private = false
  local function open_picker(pattern)
    local visible = vim.tbl_filter(function(item)
      return show_private or not item.private
    end, items)
    local current_picker
    if #items == 0 then
      return vim.notify(
        "No static Python APIs found; this package may use compiled or dynamic implementations.",
        vim.log.levels.WARN
      )
    end
    current_picker = Snacks.picker({
      title = "Python API: " .. (scope or "stdlib"),
      items = visible,
      pattern = pattern or query or "",
      sort = function(a, b)
        local needle = current_picker and current_picker.input.filter.pattern or pattern or query or ""
        local function rank(item)
          if needle:match("^[%w_.]+$") then
            if item.entry.name == needle then
              return 2
            end
            if item.entry.name:match("[^.]+$") == needle then
              return 1
            end
          end
          return 0
        end
        local ar, br = rank(a), rank(b)
        if ar ~= br then
          return ar > br
        end
        if a.score ~= b.score then
          return a.score > b.score
        end
        return a.text < b.text
      end,
      format = "text",
      preview = function(ctx)
        ctx.preview:reset()
        ctx.preview:set_lines(vim.split(table.concat(vim.tbl_map(detail, ctx.item.overloads), "\n\n"), "\n"))
        ctx.preview:highlight({ ft = "markdown" })
      end,
      matcher = { filename_bonus = false, file_pos = false },
      confirm = function(picker, item)
        if not item then
          return
        end
        picker:close()
        vim.cmd("new")
        vim.bo.buftype = "nofile"
        vim.bo.bufhidden = "wipe"
        vim.bo.swapfile = false
        vim.api.nvim_buf_set_lines(
          0,
          0,
          -1,
          false,
          vim.split(table.concat(vim.tbl_map(detail, item.overloads), "\n\n"), "\n")
        )
        vim.bo.filetype = "markdown"
        vim.bo.modifiable = false
        vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = true })
      end,
      actions = {
        toggle_private = function(picker)
          local pattern = picker:filter().pattern
          picker:close()
          show_private = not show_private
          open_picker(pattern)
        end,
        source = function(picker, item)
          if item then
            picker:close()
            vim.cmd.edit(vim.fn.fnameescape(item.entry.source))
            vim.api.nvim_win_set_cursor(0, { item.entry.line, 0 })
          end
        end,
        python_docs = function(_, item)
          if item then
            vim.ui.open(
              (
                item.entry.origin == "package" and "https://www.google.com/search?q="
                or "https://docs.python.org/3/search.html?q="
              )
                .. vim.uri_encode(
                  item.entry.name:gsub("^builtins%.", "")
                    .. (item.entry.origin == "package" and " Python documentation" or "")
                )
            )
          end
        end,
      },
      win = {
        input = {
          keys = {
            ["<C-o>"] = { "python_docs", mode = { "n", "i" } },
            ["<C-s>"] = { "source", mode = { "n", "i" } },
            ["<M-p>"] = { "toggle_private", mode = { "n", "i" } },
          },
        },
      },
    })
  end
  open_picker(query)
end
return M
