return {
  id = "cpp",
  label = "C++",
  filetypes = { "cpp" },
  sources = {
    {
      id = "stdlib",
      label = "Standard library",
      open = function(query)
        require("config.api_search.local").standard("cpp", query)
      end,
    },
    {
      id = "headers",
      label = "Specific header (optional)",
      open = function(query)
        require("config.api_search.local").headers("cpp", query)
      end,
    },
    {
      id = "project",
      label = "Project source",
      open = function(query)
        require("config.api_search.local").project("cpp", query)
      end,
    },
  },
}
