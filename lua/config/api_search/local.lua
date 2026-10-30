local M = { pending = {}, last = {} }
local function config(language)
  return (vim.g.api_search_config or {})[language] or {}
end
local function root()
  return require("config.workflow.projects").root()
end
local function picker(items, title, callback)
  if #items == 0 then
    return vim.notify("No available sources found: " .. title, vim.log.levels.WARN)
  end
  Snacks.picker({
    title = title,
    items = items,
    format = "text",
    preview = "none",
    confirm = function(p, item)
      if item then
        p:close()
        callback(item)
      end
    end,
  })
end
function M.show(entries, title, query, rebuild, project)
  project = project or root()
  local groups, items = {}, {}
  for _, entry in ipairs(entries) do
    local group = groups[entry.name]
    if not group then
      group = { entry = entry, entries = {}, text = entry.name }
      groups[entry.name] = group
      group.idx = #items + 1
      items[#items + 1] = group
    end
    group.entries[#group.entries + 1] = entry
    group.text = group.text .. " " .. entry.signature
  end
  if #items == 0 then
    return vim.notify("No API declarations found for " .. title, vim.log.levels.WARN)
  end
  local function preview(item)
    local lines = { "# " .. item.entry.name, "" }
    local files = {}
    for _, e in ipairs(item.entries) do
      local doc = e.doc or ""
      if doc == "" and e.source and e.source ~= "" then
        if files[e.source] == nil then
          local ok, lines = pcall(vim.fn.readfile, e.source)
          files[e.source] = ok and lines or false
        end
        if files[e.source] then
          doc = table.concat(
            vim.list_slice(files[e.source], math.max(1, e.line - 7), math.min(#files[e.source], e.line + 12)),
            "\n"
          )
        end
      end
      vim.list_extend(lines, {
        "```",
        e.signature,
        "```",
        doc,
        e.source ~= "" and ("Source: " .. e.source .. ":" .. e.line) or "",
        e.url or "",
        "",
      })
    end
    return table.concat(lines, "\n")
  end
  local current
  current = Snacks.picker({
    title = title,
    items = items,
    sort = function(a, b)
      local needle = current and current.input.filter.pattern or query or ""
      local function rank(item)
        if needle ~= "" and item.entry.name == needle then
          return 2
        end
        if needle ~= "" and item.entry.name:match("[^:.]+$") == needle then
          return 1
        end
        return 0
      end
      if rank(a) ~= rank(b) then
        return rank(a) > rank(b)
      end
      if (a.score or 0) ~= (b.score or 0) then
        return (a.score or 0) > (b.score or 0)
      end
      return a.idx < b.idx
    end,
    matcher = { filename_bonus = false, file_pos = false },
    filter = {
      transform = function(_, filter)
        -- Snacks treats "std:..." as a field selector. Keep namespace syntax
        -- literal internally without changing the text the user is editing.
        filter.pattern = filter.pattern:gsub("%S+", function(word)
          return word:match("^[%w_]+::") and ("text:'" .. word) or word
        end)
      end,
    },
    pattern = query or "",
    format = "text",
    preview = function(ctx)
      ctx.preview:reset()
      ctx.preview:set_lines(vim.split(preview(ctx.item), "\n"))
      ctx.preview:highlight({ ft = "markdown" })
    end,
    confirm = function(p, item)
      if not item then
        return
      end
      p:close()
      vim.cmd.new()
      vim.bo.buftype = "nofile"
      vim.b.workflow_root = project
      vim.bo.bufhidden = "wipe"
      vim.bo.swapfile = false
      vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(preview(item), "\n"))
      vim.bo.filetype = "markdown"
      vim.bo.modifiable = false
      vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = true })
    end,
    actions = {
      source = function(p, item)
        if item and item.entry.source ~= "" then
          p:close()
          vim.cmd.edit(vim.fn.fnameescape(item.entry.source))
          vim.api.nvim_win_set_cursor(0, { item.entry.line, 0 })
        end
      end,
      docs = function(_, item)
        if item then
          local url = item.entry.url
          if not url or url == "" then
            url = "https://www.google.com/search?q="
              .. vim.uri_encode(item.entry.name .. " " .. title .. " documentation")
          end
          vim.ui.open(url)
        end
      end,
      rebuild = function(p)
        if rebuild then
          local pattern = p:filter().pattern
          p:close()
          rebuild(pattern)
        end
      end,
    },
    win = {
      input = {
        keys = {
          ["<C-s>"] = { "source", mode = { "i", "n" } },
          ["<C-o>"] = { "docs", mode = { "i", "n" } },
          ["<C-r>"] = { "rebuild", mode = { "i", "n" } },
        },
      },
    },
  })
end
function M.index(descriptor, query, force)
  local project = root()
  M.last[project] = descriptor
  local key = vim.fn.sha256(vim.json.encode(descriptor)):sub(1, 24)
  local path = vim.fn.stdpath("cache") .. "/api-search/" .. key .. ".json"
  local function display()
    local ok, data = pcall(function()
      return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
    end)
    if not ok or type(data) ~= "table" or data.version ~= 1 or type(data.entries) ~= "table" then
      return false
    end
    M.show(data.entries, descriptor.title, query, function(pattern)
      M.index(descriptor, pattern, true)
    end, project)
    return true
  end
  if not force and vim.fn.filereadable(path) == 1 and display() then
    return
  end
  if M.pending[key] then
    return vim.notify("This API index is already building")
  end
  local argv = {
    vim.g.api_index_python or "python3",
    "-I",
    "-S",
    vim.fn.stdpath("config") .. "/scripts/api_index.py",
    "--language",
    descriptor.language,
    "--root",
    descriptor.root,
    "--output",
    path,
  }
  for _, name in ipairs({ "file", "module" }) do
    if descriptor[name] then
      vim.list_extend(argv, { "--" .. name, descriptor[name] })
    end
  end
  for _, include in ipairs(descriptor.includes or {}) do
    vim.list_extend(argv, { "--include-root", include })
  end
  vim.list_extend(argv, { "--ctags", vim.g.api_index_ctags or "ctags" })
  if descriptor.stdlib then
    argv[#argv + 1] = "--stdlib"
  end
  if descriptor.installed then
    argv[#argv + 1] = "--installed"
  end
  if vim.fn.executable(argv[1]) == 0 then
    return vim.notify("Missing Python indexer executable: " .. argv[1], vim.log.levels.ERROR)
  end
  if descriptor.language ~= "rustdoc" and vim.fn.executable(vim.g.api_index_ctags or "ctags") == 0 then
    return vim.notify("Universal Ctags with JSON support is required for this source", vim.log.levels.ERROR)
  end
  M.pending[key] = true
  vim.notify("Indexing " .. descriptor.title .. " in the background…")
  local launched, problem = pcall(
    vim.system,
    argv,
    { text = true, cwd = project, timeout = vim.g.api_index_timeout_ms or 120000 },
    vim.schedule_wrap(function(result)
      M.pending[key] = nil
      if result.code ~= 0 then
        return vim.notify(result.stderr or result.stdout, vim.log.levels.ERROR)
      end
      vim.notify(result.stdout)
      display()
    end)
  )
  if not launched then
    M.pending[key] = nil
    vim.notify(tostring(problem), vim.log.levels.ERROR)
  end
end
function M.rebuild()
  local descriptor = M.last[root()]
  if descriptor then
    M.index(descriptor, "", true)
  else
    vim.notify("Choose a local API collection first")
  end
end
function M.project(language, query)
  M.index({ language = language, root = root(), title = language .. " project APIs" }, query)
end
local function header_root(language)
  local base = config(language).headers
  if not base then
    if language == "c" then
      base = "/usr/include"
    else
      local candidates = vim.fn.glob("/usr/include/c++/*", false, true)
      table.sort(candidates, function(a, b)
        return (tonumber(vim.fn.fnamemodify(a, ":t")) or 0) < (tonumber(vim.fn.fnamemodify(b, ":t")) or 0)
      end)
      base = candidates[#candidates]
    end
  end
  if not base or vim.fn.isdirectory(base) == 0 then
    vim.notify("Configure api_search_config." .. language .. ".headers with your SDK include directory")
    return nil
  end
  return base
end
function M.standard(language, query)
  if language == "rust" then
    return M.rustdoc(query, true)
  end
  local base = header_root(language)
  if not base then
    return
  end
  local include_roots = config(language).include_roots or { base, "/usr/include" }
  local function build(extra)
    local paths = vim.deepcopy(include_roots)
    if extra and vim.fn.isdirectory(extra) == 1 then
      paths[#paths + 1] = extra
    end
    M.index({
      language = language,
      root = base,
      stdlib = true,
      includes = paths,
      title = (language == "c" and "C" or "C++") .. " standard library",
    }, query)
  end
  local cc = language == "c" and "cc" or "c++"
  if vim.fn.executable(cc) == 0 then
    return build()
  end
  vim.system(
    { cc, "-print-file-name=include" },
    { text = true },
    vim.schedule_wrap(function(result)
      build(result.code == 0 and vim.trim(result.stdout) or nil)
    end)
  )
end
function M.headers(language, query)
  local base = header_root(language)
  if not base then
    return
  end
  local items = {}
  for name, kind in vim.fs.dir(base) do
    if
      kind == "file"
      and (
        language == "cpp"
          and (not name:find("%.") or name:match("%.h$") or name:match("%.hpp$") or name:match("%.hh$"))
        or language == "c" and name:match("%.h$")
      )
    then
      items[#items + 1] = { text = name, file = base .. "/" .. name }
    end
  end
  picker(items, language .. " headers", function(item)
    M.index({
      language = language,
      root = base,
      file = item.file,
      includes = config(language).include_roots or { base, "/usr/include" },
      title = language .. " <" .. item.text .. ">",
    }, query)
  end)
end
local function ancestors()
  return require("config.workflow.projects").directories(root())
end
function M.typescript(query)
  local sdk = config("typescript").stdlib
  if not sdk then
    for _, dir in ipairs(ancestors()) do
      if vim.fn.isdirectory(dir .. "/node_modules/typescript/lib") == 1 then
        sdk = dir .. "/node_modules/typescript/lib"
        break
      end
    end
    local executable = vim.fn.exepath("tsc")
    if not sdk and executable ~= "" then
      sdk = vim.fs.dirname(vim.fs.dirname(vim.fn.resolve(executable))) .. "/lib"
    end
  end
  local function select(directory)
    local items = {}
    for _, file in ipairs(vim.fn.glob(directory .. "/lib.*.d.ts", false, true)) do
      items[#items + 1] = { text = vim.fn.fnamemodify(file, ":t"), file = file }
    end
    picker(items, "TypeScript standard declaration libraries", function(item)
      -- TypeScript declarations contain no C includes; index the selected file only.
      M.index({
        language = "typescript",
        root = directory,
        file = item.file,
        includes = { directory },
        title = "TypeScript " .. item.text,
      }, query)
    end)
  end
  if sdk then
    select(sdk)
  else
    vim.ui.input(
      { prompt = "TypeScript lib directory: ", default = root() .. "/node_modules/typescript/lib", completion = "dir" },
      function(value)
        if value and vim.fn.isdirectory(value) == 1 then
          select(value)
        end
      end
    )
  end
end
function M.packages(language, query)
  local directories = {}
  if language == "typescript" then
    for _, dir in ipairs(ancestors()) do
      directories[#directories + 1] = dir .. "/node_modules"
    end
  else
    directories = vim.fn.glob((vim.env.CARGO_HOME or vim.env.HOME .. "/.cargo") .. "/registry/src/*", false, true)
  end
  local items, seen = {}, {}
  local function add(name, path)
    if not seen[name] then
      seen[name] = true
      items[#items + 1] = { text = name, path = path }
    end
  end
  for _, dir in ipairs(directories) do
    if vim.fn.isdirectory(dir) == 1 then
      for name in vim.fs.dir(dir) do
        local path = dir .. "/" .. name
        if name:sub(1, 1) ~= "." and vim.fn.isdirectory(path) == 1 then
          if language == "typescript" and name:sub(1, 1) == "@" then
            for child in vim.fs.dir(path) do
              if vim.fn.isdirectory(path .. "/" .. child) == 1 then
                add(name .. "/" .. child, path .. "/" .. child)
              end
            end
          else
            add(name, path)
          end
        end
      end
    end
  end
  picker(
    items,
    language == "typescript" and "Installed TypeScript packages" or "Downloaded Cargo crate sources",
    function(item)
      M.index({ language = language, root = item.path, installed = true, title = language .. " " .. item.text }, query)
    end
  )
end
function M.rustdoc(query, whole)
  local docs = config("rust").docs
  local function select(base)
    local items = { { text = "std root declarations", module = "" } }
    if vim.fn.isdirectory(base) == 0 then
      return vim.notify("Rust documentation unavailable. Install rust-docs or set api_search_config.rust.docs")
    end
    if whole then
      return M.index({ language = "rustdoc", root = base, stdlib = true, title = "Rust standard library" }, query)
    end
    for name, kind in vim.fs.dir(base) do
      if kind == "directory" then
        items[#items + 1] = { text = "std::" .. name, module = name }
      end
    end
    picker(items, "Rust standard-library modules", function(item)
      M.index({ language = "rustdoc", root = base, module = item.module, title = "Rust " .. item.text }, query)
    end)
  end
  if docs then
    return select(docs)
  end
  vim.system(
    { "rustc", "--print", "sysroot" },
    { text = true, cwd = root(), env = { RUSTUP_AUTO_INSTALL = "0" } },
    vim.schedule_wrap(function(result)
      if result.code ~= 0 then
        return vim.notify(result.stderr, vim.log.levels.ERROR)
      end
      select(vim.trim(result.stdout) .. "/share/doc/rust/html/std")
    end)
  )
end
return M
