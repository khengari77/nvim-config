return {
  id = "rust",
  label = "Rust",
  filetypes = { "rust" },
  sources = {
    {
      id = "stdlib",
      label = "Standard library (local rustdoc)",
      open = function(query)
        require("config.api_search.local").standard("rust", query)
      end,
    },
    {
      id = "module",
      label = "Specific standard-library module (optional)",
      open = function(query)
        require("config.api_search.local").rustdoc(query)
      end,
    },
    {
      id = "packages",
      label = "Downloaded Cargo crates",
      open = function(query)
        require("config.api_search.local").packages("rust", query)
      end,
    },
    {
      id = "project",
      label = "Project source",
      open = function(query)
        require("config.api_search.local").project("rust", query)
      end,
    },
  },
}
