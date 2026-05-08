return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        mojo = {},
      },
    },
  },

  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "mojo" } },
    init = function()
      vim.api.nvim_create_autocmd("User", {
        pattern = "TSUpdate",
        callback = function()
          require("nvim-treesitter.parsers").mojo = {
            install_info = {
              url = "https://github.com/lsh/tree-sitter-mojo",
            },
          }
        end,
      })
    end,
  },
}
