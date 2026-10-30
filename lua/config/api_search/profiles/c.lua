return {
  id = "c",
  label = "C",
  filetypes = { "c" },
  sources = {
    {
      id = "stdlib",
      label = "Standard library",
      open = function(query)
        require("config.api_search.local").standard("c", query)
      end,
    },
    {
      id = "headers",
      label = "Specific header (optional)",
      open = function(query)
        require("config.api_search.local").headers("c", query)
      end,
    },
    {
      id = "project",
      label = "Project source",
      open = function(query)
        require("config.api_search.local").project("c", query)
      end,
    },
  },
}
