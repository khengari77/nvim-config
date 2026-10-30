return {
  {
    "folke/snacks.nvim",
    init = function()
      vim.api.nvim_create_user_command("ApiIndexRebuild", function()
        require("config.api_search.local").rebuild()
      end, {})
      local function api()
        return require("config.python_api")
      end
      vim.api.nvim_create_user_command("ApiSearch", function(o)
        require("config.api_search").search(o.args)
      end, { nargs = "*" })
      vim.api.nvim_create_user_command("ApiSearchCurrent", function(o)
        require("config.api_search").current(o.args)
      end, { nargs = "*" })
      vim.api.nvim_create_user_command("PythonApiPackages", function(o)
        api().packages(o.args)
      end, { nargs = "?" })
      vim.api.nvim_create_user_command("PythonApiPackage", function(o)
        local args = vim.split(o.args, " ", { trimempty = true })
        local name = table.remove(args, 1)
        api().package(name, table.concat(args, " "), o.bang)
      end, { nargs = "+", bang = true })
      for name, fn in pairs({
        PythonApiSearch = function(o)
          api().search(o.args)
        end,
        PythonApiSetup = function()
          api().setup_index(false)
        end,
        PythonApiUpdate = function()
          api().setup_index(true)
        end,
        PythonApiRebuild = function()
          api().rebuild()
        end,
      }) do
        vim.api.nvim_create_user_command(name, fn, { nargs = name == "PythonApiSearch" and "?" or 0 })
      end
      vim.api.nvim_create_user_command("InterviewPractice", function(o)
        require("config.interview").command(o.args)
      end, {
        nargs = "?",
        complete = function()
          return { "on", "off", "toggle", "status" }
        end,
      })
      -- Load the startup flag before any AI plugin initializes.
      require("config.interview")
    end,
  },
  {
    "supermaven-inc/supermaven-nvim",
    optional = true,
    config = function(_, opts)
      require("config.interview").supermaven()
      local source = require("supermaven-nvim.cmp")
      local available = source.is_available
      source.is_available = function(...)
        return not require("config.interview").active and available(...)
      end
      require("supermaven-nvim").setup(opts)
    end,
  },
}
