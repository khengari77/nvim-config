return {
  {
    "nvim-lualine/lualine.nvim",
    optional = true,
    opts = function(_, opts)
      table.insert(opts.sections.lualine_x, 1, {
        function()
          return require("config.interview").statusline()
        end,
        color = function()
          return { fg = Snacks.util.color(require("config.interview").active and "DiagnosticWarn" or "Comment") }
        end,
      })
    end,
  },
}
