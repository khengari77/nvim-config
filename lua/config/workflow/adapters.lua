local P = require("config.workflow.projects")
local M = {}
local function exists(path)
  return vim.fn.filereadable(path) == 1
end
function M.python(root)
  if P.context(root).python then
    return P.context(root).python
  end
  if vim.g.python_api_python then
    return vim.g.python_api_python
  end
  local prefix = vim.env.VIRTUAL_ENV or vim.env.CONDA_PREFIX
  if prefix and vim.fn.executable(prefix .. "/bin/python") == 1 then
    return prefix .. "/bin/python"
  end
  for _, d in ipairs({ ".venv", "venv" }) do
    if vim.fn.executable(root .. "/" .. d .. "/bin/python") == 1 then
      return root .. "/" .. d .. "/bin/python"
    end
  end
  return "python3"
end
local function cargo_runs(dir, add)
  local text = table.concat(vim.fn.readfile(dir .. "/Cargo.toml"), "\n")
  local function binaries(manifest)
    local cwd = vim.fs.dirname(manifest)
    local section, package_name, names = "", nil, {}
    for _, line in ipairs(vim.fn.readfile(manifest)) do
      section = line:match("^%s*%[%[([^%]]+)%]%]") or line:match("^%s*%[([^%]]+)%]") or section
      local name = line:match('^%s*name%s*=%s*"([^"]+)"') or line:match("^%s*name%s*=%s*'([^']+)'")
      if name and section == "package" then
        package_name = name
      end
      if name and section == "bin" then
        names[name] = true
      end
    end
    if package_name and exists(cwd .. "/src/main.rs") then
      names[package_name] = true
    end
    for _, file in ipairs(vim.fn.glob(cwd .. "/src/bin/*.rs", false, true)) do
      names[vim.fn.fnamemodify(file, ":t:r")] = true
    end
    for _, file in ipairs(vim.fn.glob(cwd .. "/src/bin/*/main.rs", false, true)) do
      names[vim.fn.fnamemodify(file, ":h:t")] = true
    end
    for name in pairs(names) do
      add(cwd, "cargo run " .. name, "run", { "cargo", "run", "--manifest-path", manifest, "--bin", name })
    end
  end
  binaries(dir .. "/Cargo.toml")
  local members = text:match("members%s*=%s*(%b[])")
  if members then
    for member in members:gmatch([=[["']([^"']+)["']]=]) do
      for _, manifest in ipairs(vim.fn.glob(dir .. "/" .. member .. "/Cargo.toml", false, true)) do
        binaries(manifest)
      end
    end
  end
end
function M.discover(root, scope)
  local tasks = {}
  local function add(dir, name, kind, argv)
    tasks[#tasks + 1] = {
      id = dir .. ":" .. name,
      text = vim.fn.fnamemodify(dir, ":~") .. " | " .. name,
      argv = argv,
      cwd = dir,
      kind = kind,
    }
  end
  for _, dir in ipairs(P.directories(root, scope)) do
    if exists(dir .. "/package.json") then
      local ok, data = pcall(function()
        return vim.json.decode(table.concat(vim.fn.readfile(dir .. "/package.json"), "\n"))
      end)
      if ok then
        local manager = P.context(root).manager
        if not manager or manager == "auto" then
          manager = data.packageManager and data.packageManager:match("^([^@]+)")
          if not manager then
            for _, ancestor in ipairs(P.directories(root, scope)) do
              if exists(ancestor .. "/package.json") then
                local valid, manifest = pcall(function()
                  return vim.json.decode(table.concat(vim.fn.readfile(ancestor .. "/package.json"), "\n"))
                end)
                if valid and manifest.packageManager then
                  manager = manifest.packageManager:match("^([^@]+)")
                end
              end
              if manager then
                break
              end
              for _, pair in ipairs({
                { "bun.lock", "bun" },
                { "bun.lockb", "bun" },
                { "pnpm-lock.yaml", "pnpm" },
                { "yarn.lock", "yarn" },
                { "package-lock.json", "npm" },
              }) do
                if exists(ancestor .. "/" .. pair[1]) then
                  manager = pair[2]
                  break
                end
              end
              if manager then
                break
              end
            end
          end
          manager = manager or "npm"
        end
        for name in pairs(data.scripts or {}) do
          local kind = name:match("^test") and "test"
            or name == "build" and "build"
            or (name == "dev" or name == "start") and "run"
            or "task"
          add(dir, name, kind, { manager, "run", name })
        end
      end
    end
    if exists(dir .. "/Cargo.toml") then
      for _, name in ipairs({ "build", "test", "check" }) do
        add(dir, "cargo " .. name, name == "check" and "task" or name, { "cargo", name })
      end
    end
    if exists(dir .. "/Cargo.toml") then
      cargo_runs(dir, add)
    end
    if exists(dir .. "/CMakeLists.txt") then
      local build = P.context(root).build or dir .. "/build"
      if exists(build .. "/CMakeCache.txt") then
        add(dir, "CMake build", "build", { "cmake", "--build", build })
        add(dir, "CTest", "test", { "ctest", "--test-dir", build, "--output-on-failure" })
        tasks[#tasks + 1] = {
          id = dir .. ":cmake-executable",
          text = dir .. " | Run built executable…",
          kind = "run",
          cwd = dir,
          executable_dir = build,
          argv = {},
        }
      end
    end
    for _, marker in ipairs({ "gradlew", "build.gradle", "build.gradle.kts" }) do
      if exists(dir .. "/" .. marker) then
        local gradle = exists(dir .. "/gradlew") and dir .. "/gradlew" or "gradle"
        add(dir, "Gradle build", "build", { gradle, "build" })
        add(dir, "Gradle test", "test", { gradle, "test" })
        break
      end
    end
    if exists(dir .. "/platformio.ini") then
      add(dir, "PlatformIO build", "build", { "pio", "run" })
      add(dir, "PlatformIO test", "test", { "pio", "test" })
    end
    if exists(dir .. "/go.mod") then
      add(dir, "Go build", "build", { "go", "build", "./..." })
      add(dir, "Go test", "test", { "go", "test", "./..." })
      add(dir, "Go run", "run", { "go", "run", "." })
    end
    if exists(dir .. "/pyproject.toml") or exists(dir .. "/pytest.ini") then
      add(dir, "Python tests", "test", { M.python(root), "-m", "pytest" })
    end
    if exists(dir .. "/Makefile") then
      add(dir, "Make (default target)", "build", { "make" })
      -- Only parse straightforward target declarations; never evaluate Makefiles.
      for _, line in ipairs(vim.fn.readfile(dir .. "/Makefile")) do
        local name = line:match("^([%w_%-]+):[^=]") or line:match("^([%w_%-]+):$")
        if name and name:sub(1, 1) ~= "." then
          add(dir, "make " .. name, name == "test" and "test" or "task", { "make", name })
        end
      end
    end
    for _, pair in ipairs({ { "justfile", "just" }, { "Justfile", "just" } }) do
      if exists(dir .. "/" .. pair[1]) then
        for _, line in ipairs(vim.fn.readfile(dir .. "/" .. pair[1])) do
          local name = line:match("^([%w_%-]+):")
          if name then
            add(dir, "just " .. name, name == "test" and "test" or "task", { "just", name })
          end
        end
        break
      end
    end
    local markers = {}
    for name, kind in vim.fs.dir(dir) do
      if kind == "file" then
        markers[name] = true
      end
    end
    for _, pair in ipairs({ { ".nimble", "nimble" }, { ".cabal", "cabal" } }) do
      for name in pairs(markers) do
        if name:sub(-#pair[1]) == pair[1] then
          for _, action in ipairs({ "build", "test" }) do
            add(dir, pair[2] .. " " .. action, action, { pair[2], action })
          end
          break
        end
      end
    end
    if markers["stack.yaml"] then
      for _, action in ipairs({ "build", "test" }) do
        add(dir, "stack " .. action, action, { "stack", action })
      end
    end
    if markers["dune-project"] then
      add(dir, "Dune build", "build", { "dune", "build" })
      add(dir, "Dune test", "test", { "dune", "runtest" })
    end
    if markers["spago.yaml"] or markers["spago.dhall"] then
      for _, action in ipairs({ "build", "test", "run" }) do
        add(dir, "Spago " .. action, action, { "spago", action })
      end
    end
  end
  for _, task in ipairs((vim.g.project_workflow or {}).tasks or {}) do
    if not task.root or task.root == root then
      local copy = vim.deepcopy(task)
      copy.cwd = copy.cwd or root
      copy.text = copy.name or table.concat(copy.argv, " ")
      copy.id = copy.cwd .. ":" .. copy.text
      tasks[#tasks + 1] = copy
    end
  end
  local unique, seen = {}, {}
  for _, task in ipairs(tasks) do
    if not seen[task.id] then
      seen[task.id] = true
      unique[#unique + 1] = task
    end
  end
  table.sort(unique, function(a, b)
    return a.text < b.text
  end)
  return unique
end
function M.file(path, root, standalone)
  local ext = vim.fn.fnamemodify(path, ":e")
  if not standalone and vim.tbl_contains({ "c", "cc", "cpp", "rs", "go", "nim", "hs", "ml" }, ext) then
    local dir = vim.fs.dirname(path)
    while dir and (dir == root or dir:sub(1, #root + 1) == root .. "/") do
      for _, marker in ipairs({
        "Cargo.toml",
        "CMakeLists.txt",
        "Makefile",
        "go.mod",
        "stack.yaml",
        "dune-project",
        "platformio.ini",
      }) do
        if exists(dir .. "/" .. marker) then
          return nil
        end
      end
      local found = false
      for name in vim.fs.dir(dir) do
        if name:match("%.cabal$") or name:match("%.nimble$") then
          found = true
        end
      end
      if found then
        return nil
      end
      if dir == root then
        break
      end
      dir = vim.fs.dirname(dir)
    end
  end
  local runtimes = {
    py = { M.python(root) },
    js = { "node" },
    mjs = { "node" },
    cjs = { "node" },
    ts = { "bun", "run" },
    tsx = { "bun", "run" },
    lua = { "lua" },
    sh = { "bash" },
    hs = { "runghc" },
    go = { "go", "run" },
    ml = { "ocaml" },
    mojo = { "mojo" },
  }
  local argv = runtimes[ext]
  if argv then
    argv = vim.deepcopy(argv)
    argv[#argv + 1] = path
    return { argv = argv, cwd = root, kind = "run", text = "Run " .. vim.fn.fnamemodify(path, ":t"), id = path }
  end
  local compilers =
    { c = { "cc" }, cpp = { "c++" }, cc = { "c++" }, rs = { "rustc" }, nim = { "nim", "c", "--hints:off" } }
  local compile = compilers[ext]
  if compile then
    local directory = vim.fn.stdpath("cache") .. "/workflow/" .. vim.fn.sha256(path):sub(1, 16)
    vim.fn.mkdir(directory, "p")
    local binary = directory .. "/program"
    if ext == "nim" then
      vim.list_extend(compile, { "--nimcache:" .. directory .. "/nimcache", "--out:" .. binary, path })
    else
      vim.list_extend(compile, { path, "-o", binary })
    end
    return {
      argv = { binary },
      prepare = compile,
      cwd = root,
      kind = "run",
      id = path,
      text = "Compile/run " .. vim.fn.fnamemodify(path, ":t"),
    }
  end
end
return M
