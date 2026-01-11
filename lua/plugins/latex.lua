return {
  {
    "lervag/vimtex",
    ft = { "tex", "bib" }, -- Requirement 1: Load only for .tex files
    config = function()
      -- Requirement 3: Use Zathura for viewing the PDF
      vim.g.vimtex_view_method = "zathura"
      vim.g.vimtex_compiler_method = "xelatex"

      -- Requirement 2: Detect changes and rerender automatically
      vim.g.vimtex_compiler_latexmk = {
        continuous = 1, -- Enable continuous compilation on save
        executable = "latexmk",
        options = {
          "-pdf",
          "-shell-escape",
          "-verbose",
          "-file-line-error",
          "-synctex=1", -- Crucial for forward/inverse search
          "-interaction=nonstopmode",
        },
      }

      -- Automatically start the compiler when a .tex file is opened
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "tex",
        callback = function()
          vim.cmd("VimtexCompile")
        end,
        desc = "Start VimTeX compilation on file open",
      })

      -- Keymaps for essential VimTeX functions
      vim.keymap.set("n", "<leader>ll", "<cmd>VimtexCompile<cr>", { desc = "VimTeX Compile" })
      vim.keymap.set("n", "<leader>lv", "<cmd>VimtexView<cr>", { desc = "VimTeX View PDF" })
      vim.keymap.set("n", "<leader>lc", "<cmd>VimtexClean<cr>", { desc = "VimTeX Clean Aux Files" })
      vim.keymap.set("n", "<leader>lt", "<cmd>VimtexTocToggle<cr>", { desc = "VimTeX Toggle TOC" })
    end,
  },

  -- Requirement 4: LSP and Snippets for an Overleaf-like experience
  {
    "neovim/nvim-lspconfig",
    dependencies = { "williamboman/mason.nvim" },
    opts = {
      servers = {
        -- This ensures the Texlab language server is set up for autocompletion etc.
        texlab = {},
      },
    },
  },
  {
    "hrsh7th/nvim-cmp",
    dependencies = { "saadparwaiz1/cmp_luasnip" },
    opts = function(_, opts)
      -- Add luasnip to the list of completion sources
      opts.sources = opts.sources or {}
      table.insert(opts.sources, { name = "luasnip" })
    end,
  },
  {
    "L3MON4D3/LuaSnip",
    dependencies = { "honza/vim-snippets" }, -- Provides a base set of snippets
    opts = {},
  },
}
