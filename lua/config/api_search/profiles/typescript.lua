return {
  id = "typescript",
  label = "TypeScript",
  filetypes = { "typescript", "typescriptreact" },
  sources = {
    {
      id = "stdlib",
      label = "Standard declaration libraries",
      open = function(query)
        require("config.api_search.local").typescript(query)
      end,
    },
    {
      id = "packages",
      label = "Installed packages",
      open = function(query)
        require("config.api_search.local").packages("typescript", query)
      end,
    },
    {
      id = "project",
      label = "Project source",
      open = function(query)
        require("config.api_search.local").project("typescript", query)
      end,
    },
  },
}
