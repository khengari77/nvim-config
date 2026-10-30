-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

vim.keymap.set("n", vim.g.api_search_key or vim.g.python_api_key or "<leader>ph", function()
  require("config.api_search").search()
end, { desc = "API search: choose language" })
vim.keymap.set("n", "<leader>uI", function()
  require("config.interview").command("toggle")
end, { desc = "Toggle AI-free interview practice" })

vim.keymap.set("n", vim.g.api_search_current_key or vim.g.python_api_packages_key or "<leader>pH", function()
  require("config.api_search").current()
end, { desc = "API search: current language" })
