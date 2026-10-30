return {
  id = "haskell",
  label = "Haskell",
  filetypes = { "haskell", "lhaskell" },
  sources = {
    {
      id = "online",
      label = "Hoogle (online, cached queries)",
      open = function(query)
        require("config.api_search.hoogle").search("online", query)
      end,
    },
    {
      id = "local",
      label = "Hoogle (local executable/database)",
      open = function(query)
        require("config.api_search.hoogle").search("local", query)
      end,
    },
  },
}
