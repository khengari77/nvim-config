return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      -- The postsolar tree-sitter-purescript grammar, plus the svelte grammar
      -- that hosts <script lang="purescript"> blocks. Highlights for the
      -- injected PureScript come from after/queries/svelte/injections.scm.
      vim.list_extend(opts.ensure_installed or {}, { "purescript", "svelte" })
    end,
  },
}
