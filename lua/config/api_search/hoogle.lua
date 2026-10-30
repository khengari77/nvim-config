local M = {}
local function plain(value)
  return (value or "")
    :gsub("</?[%a][%w]*[^>]*>", "")
    :gsub("&gt;", ">")
    :gsub("&lt;", "<")
    :gsub("&amp;", "&")
    :gsub("&quot;", '"')
    :gsub("&#39;", "'")
end
function M.entries(data)
  local entries = {}
  for _, row in ipairs(data) do
    local signature = plain(row.item or row.self)
    local name = signature:match("^(.-)%s+::") or signature
    local module = type(row.module) == "table" and row.module.name or ""
    entries[#entries + 1] = {
      name = (module ~= "" and module .. "." or "") .. name,
      signature = signature,
      doc = plain(row.docs),
      source = "",
      line = 1,
      url = row.url or "",
    }
  end
  return entries
end
function M.search(mode, query, force)
  if not query or vim.trim(query) == "" then
    return vim.ui.input({ prompt = "Hoogle name or type signature: " }, function(value)
      if value and vim.trim(value) ~= "" then
        M.search(mode, value, force)
      end
    end)
  end
  local cfg = (vim.g.api_search_config or {}).haskell or {}
  local executable = cfg.executable or "hoogle"
  local path = vim.fn.stdpath("cache")
    .. "/api-search/hoogle-"
    .. vim.fn.sha256(mode .. query .. executable .. (cfg.database or ""))
    .. ".json"
  local function show(data)
    require("config.api_search.local").show(M.entries(data), "Hoogle (" .. mode .. "): " .. query, "", function()
      M.search(mode, query, true)
    end)
  end
  if not force and vim.fn.filereadable(path) == 1 then
    local ok, data = pcall(function()
      return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
    end)
    if ok and type(data) == "table" then
      return show(data)
    end
  end
  local argv
  if mode == "local" then
    if vim.fn.executable(executable) == 0 then
      return vim.notify(
        "Local Hoogle is not installed. Configure api_search_config.haskell.executable and a generated database, or choose the online source.",
        vim.log.levels.WARN
      )
    end
    argv = { executable, "--json", "--count=100", query }
    if cfg.database then
      vim.list_extend(argv, { "--database", cfg.database })
    end
  else
    argv = {
      "curl",
      "--fail",
      "--silent",
      "--show-error",
      "--max-time",
      "15",
      "--get",
      "https://hoogle.haskell.org/",
      "--data-urlencode",
      "mode=json",
      "--data-urlencode",
      "format=text",
      "--data-urlencode",
      "count=100",
      "--data-urlencode",
      "hoogle=" .. query,
    }
  end
  if vim.fn.executable(argv[1]) == 0 then
    return vim.notify("Missing executable: " .. argv[1], vim.log.levels.ERROR)
  end
  vim.system(
    argv,
    { text = true, timeout = 20000 },
    vim.schedule_wrap(function(result)
      if result.code ~= 0 then
        return vim.notify("Hoogle: " .. (result.stderr or result.stdout), vim.log.levels.ERROR)
      end
      local ok, data = pcall(vim.json.decode, result.stdout)
      if not ok or type(data) ~= "table" or not vim.islist(data) then
        return vim.notify("Hoogle returned an invalid response", vim.log.levels.ERROR)
      end
      vim.fn.mkdir(vim.fs.dirname(path), "p")
      vim.fn.writefile(vim.split(result.stdout, "\n", { plain = true }), path .. ".tmp")
      vim.uv.fs_rename(path .. ".tmp", path)
      show(data)
    end)
  )
end
return M
