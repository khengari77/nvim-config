return {
  id = "python",
  label = "Python",
  filetypes = { "python" },
  sources = {
    {
      id = "stdlib",
      label = "Standard library",
      open = function(query)
        require("config.python_api").search(query)
      end,
    },
    {
      id = "packages",
      label = "Installed packages",
      open = function(query)
        require("config.python_api").packages(query)
      end,
    },
  },
}
