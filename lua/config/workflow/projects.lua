local M = {}
local function cfg()
  return vim.g.project_workflow or {}
end
local state
function M.state()
  if not state then
    local ok, value = pcall(function()
      return vim.json.decode(table.concat(vim.fn.readfile(vim.fn.stdpath("state") .. "/workflow.json"), "\n"))
    end)
    state = ok and type(value) == "table" and value or {}
  end
  return state
end
function M.save()
  local path = vim.fn.stdpath("state")
  vim.fn.mkdir(path, "p")
  vim.fn.writefile({ vim.json.encode(M.state()) }, path .. "/workflow.json.tmp")
  assert(vim.uv.fs_rename(path .. "/workflow.json.tmp", path .. "/workflow.json"))
end
local function detect_root()
  local file = vim.api.nvim_buf_get_name(0)
  local start = vim.bo.buftype == "" and file ~= "" and vim.fs.dirname(file) or vim.fn.getcwd()
  for _, base in ipairs(cfg().roots or { vim.env.HOME .. "/Programming" }) do
    base = vim.fn.fnamemodify(base, ":p"):gsub("/$", "")
    if start:sub(1, #base + 1) == base .. "/" then
      local child = start:sub(#base + 2):match("^[^/]+")
      local boundary = base .. "/" .. child
      local git = vim.fs.root(start, ".git")
      return git and git:sub(1, #boundary) == boundary and git or boundary
    end
  end
  return vim.fs.root(start, { ".git", "package.json", "Cargo.toml", "pyproject.toml", "CMakeLists.txt", "go.mod" })
    or vim.fn.getcwd()
end
local last_key, last_root
function M.root()
  local name = vim.api.nvim_buf_get_name(0)
  if vim.b.workflow_root and (vim.bo.buftype == "nofile" or (name ~= "" and vim.b.workflow_file == name)) then
    return vim.b.workflow_root
  end
  local key = vim.api.nvim_buf_get_name(0) .. "\0" .. vim.fn.getcwd() .. "\0" .. table.concat(cfg().roots or {}, "|")
  if key ~= last_key then
    last_key, last_root = key, detect_root()
  end
  return last_root
end
function M.context(root)
  root = root or M.root()
  local s = M.state()
  s[root] = s[root] or {}
  return s[root]
end
function M.scope(root)
  local file = vim.api.nvim_buf_get_name(0)
  local dir = vim.bo.buftype == "" and file ~= "" and vim.fs.dirname(file) or root
  return dir:sub(1, #root) == root and dir or root
end
function M.directories(root, start)
  local out, dir = {}, start or M.scope(root)
  if dir ~= root and dir:sub(1, #root + 1) ~= root .. "/" then
    dir = root
  end
  while dir do
    out[#out + 1] = dir
    if dir == root then
      break
    end
    local parent = vim.fs.dirname(dir)
    if not parent or parent == dir then
      break
    end
    dir = parent
  end
  return out
end
function M.pick(items, title, callback, extra)
  Snacks.picker(vim.tbl_extend("force", {
    title = title,
    items = items,
    format = "text",
    preview = "none",
    confirm = function(picker, item)
      if item then
        picker:close()
        callback(item)
      end
    end,
  }, extra or {}))
end
function M.open(path, restore)
  local persistence = require("persistence")
  if restore then
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[b].modified and vim.bo[b].buftype == "" then
        return vim.notify("Save modified buffers before restoring a session", vim.log.levels.WARN)
      end
    end
    persistence.save()
  end
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_config(win).relative ~= "" then
    vim.api.nvim_win_close(win, false)
  end
  vim.api.nvim_set_current_dir(path)
  -- Keep existing buffers, but open files relative to the newly selected project.
  if restore then
    persistence.load()
  else
    vim.cmd("keepalt enew")
    Snacks.picker.files({ cwd = path })
  end
end
function M.projects()
  local items, seen = {}, {}
  for _, base in ipairs(cfg().roots or { vim.env.HOME .. "/Programming" }) do
    if vim.fn.isdirectory(base) == 1 then
      for name, kind in vim.fs.dir(base) do
        local path = vim.fs.normalize(base .. "/" .. name)
        if
          kind == "directory"
          and name:sub(1, 1) ~= "."
          and not vim.tbl_contains({ "third_party", "node_modules", "vendor", "target" }, name)
          and not seen[path]
        then
          seen[path] = true
          items[#items + 1] = { text = name, path = path }
        end
      end
    end
  end
  M.pick(items, "Projects (Ctrl-s restores session)", function(item)
    M.open(item.path)
  end, {
    actions = {
      restore_session = function(picker, item)
        if item then
          picker:close()
          M.open(item.path, true)
        end
      end,
    },
    win = { input = { keys = { ["<C-s>"] = { "restore_session", mode = { "i", "n" } } } } },
  })
end
function M.worktrees()
  if not vim.uv.fs_stat(M.root() .. "/.git") then
    return vim.notify("This project has no Git repository at its root", vim.log.levels.WARN)
  end
  vim.system(
    { "git", "-C", M.root(), "worktree", "list", "--porcelain", "-z" },
    { text = true },
    vim.schedule_wrap(function(result)
      if result.code ~= 0 then
        return vim.notify(result.stderr, vim.log.levels.ERROR)
      end
      local items = {}
      for field in result.stdout:gmatch("[^%z]+") do
        local path = field:match("^worktree (.*)")
        if path then
          items[#items + 1] = { text = path, path = path }
        end
      end
      M.pick(items, "Worktrees", function(item)
        M.open(item.path)
      end)
    end)
  )
end
function M.select_context()
  local root = M.root()
  M.pick(
    { { text = "Python interpreter" }, { text = "JavaScript package manager" }, { text = "CMake build directory" } },
    "Project context",
    function(item)
      if item.text == "JavaScript package manager" then
        local items = { { text = "auto" } }
        for _, name in ipairs({ "bun", "npm", "pnpm", "yarn" }) do
          if vim.fn.executable(name) == 1 then
            items[#items + 1] = { text = name }
          end
        end
        M.pick(items, "Package manager", function(choice)
          M.context(root).manager = choice.text
          M.save()
        end)
      else
        local python = item.text == "Python interpreter"
        local default = python and (M.context(root).python or vim.fn.exepath("python3"))
          or (M.context(root).build or root .. "/build")
        vim.ui.input({
          prompt = python and "Python executable (auto resets): " or "Existing build directory (auto resets): ",
          default = default,
          completion = python and "file" or "dir",
        }, function(value)
          if not value or value == "" then
            return
          end
          if value == "auto" then
            M.context(root)[python and "python" or "build"] = nil
            M.save()
            return
          end
          value = vim.fn.expand(value)
          if value:find("/", 1, true) and value:sub(1, 1) ~= "/" then
            value = root .. "/" .. value
          end
          if not python then
            value = vim.fn.fnamemodify(value:sub(1, 1) == "/" and value or root .. "/" .. value, ":p")
          end
          if python and vim.fn.executable(value) ~= 1 or not python and vim.fn.isdirectory(value) ~= 1 then
            return vim.notify("Selection is not available", vim.log.levels.ERROR)
          end
          M.context(root)[python and "python" or "build"] = value
          M.save()
        end)
      end
    end
  )
end
return M
