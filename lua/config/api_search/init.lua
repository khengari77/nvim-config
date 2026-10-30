-- Profiles contain metadata and lazy source callbacks, not loaded API indexes.
local M = {}
local function valid(profile)
  if
    type(profile) ~= "table"
    or type(profile.id) ~= "string"
    or profile.id == ""
    or type(profile.label) ~= "string"
    or type(profile.filetypes) ~= "table"
    or type(profile.sources) ~= "table"
    or #profile.sources == 0
  then
    return false
  end
  for _, ft in ipairs(profile.filetypes) do
    if type(ft) ~= "string" then
      return false
    end
  end
  local seen = {}
  for _, source in ipairs(profile.sources) do
    if
      type(source) ~= "table"
      or type(source.id) ~= "string"
      or source.id == ""
      or type(source.label) ~= "string"
      or type(source.open) ~= "function"
      or seen[source.id]
    then
      return false
    end
    seen[source.id] = true
  end
  return true
end
function M.profiles()
  local profiles, seen = {}, {}
  for _, name in
    ipairs(vim.g.api_search_profiles or {
      "config.api_search.profiles.python",
      "config.api_search.profiles.typescript",
      "config.api_search.profiles.c",
      "config.api_search.profiles.cpp",
      "config.api_search.profiles.rust",
      "config.api_search.profiles.haskell",
    })
  do
    local ok, profile = pcall(require, name)
    if not ok or not valid(profile) or seen[profile.id] then
      vim.notify(
        "Cannot register API search profile "
          .. tostring(name)
          .. ": "
          .. (not ok and tostring(profile) or "invalid metadata or duplicate ID"),
        vim.log.levels.WARN
      )
    else
      seen[profile.id] = true
      profiles[#profiles + 1] = profile
    end
  end
  table.sort(profiles, function(a, b)
    return a.label < b.label
  end)
  return profiles
end
local function choose(items, title, callback)
  if #items == 0 then
    return vim.notify("No API search profiles are configured", vim.log.levels.WARN)
  end
  Snacks.picker({
    title = title,
    items = items,
    format = "text",
    preview = "none",
    confirm = function(picker, item)
      if not item then
        return
      end
      picker:close()
      callback(item.value)
    end,
  })
end
local function invoke(source, query)
  local ok, err = pcall(source.open, query or "")
  if not ok then
    vim.notify("API search failed: " .. tostring(err), vim.log.levels.ERROR)
  end
end
local function sources(profile, query)
  if #profile.sources == 1 then
    return invoke(profile.sources[1], query)
  end
  local items = {}
  for _, source in ipairs(profile.sources) do
    items[#items + 1] = { text = source.label, value = source }
  end
  choose(items, profile.label .. " API sources", function(source)
    invoke(source, query)
  end)
end
local function languages(profiles, query)
  local items = {}
  for _, profile in ipairs(profiles) do
    items[#items + 1] = { text = profile.label, value = profile }
  end
  -- Always choose a language, including when just one profile exists.
  choose(items, "API search language", function(profile)
    sources(profile, query)
  end)
end
function M.search(query)
  languages(M.profiles(), query)
end
function M.current(query)
  local filetype = vim.bo.filetype
  local profiles = M.profiles()
  local matches = {}
  for _, profile in ipairs(profiles) do
    if vim.tbl_contains(profile.filetypes, filetype) then
      matches[#matches + 1] = profile
    end
  end
  if #matches == 1 then
    return sources(matches[1], query)
  end
  if #matches > 1 then
    return languages(matches, query)
  end
  vim.notify(
    filetype == "" and "No API profile for this buffer; choose a language"
      or ("No API profile for " .. filetype .. " yet; choose a language"),
    vim.log.levels.INFO
  )
  languages(profiles, query)
end
return M
