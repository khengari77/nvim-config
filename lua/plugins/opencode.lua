return {
  {
    "NickvanDyke/opencode.nvim",
    dependencies = {
      -- Required for `snacks` provider (UI elements).
      { "folke/snacks.nvim", opts = { input = {}, picker = {}, terminal = {} } },
      -- Required to register the keymap title
      "folke/which-key.nvim",
    },
    config = function()
      ----------------------------------------------------------------
      -- 1. Register the Group Name for Which-Key
      ----------------------------------------------------------------
      local wk = require("which-key")
      wk.add({
        { "<leader>o", group = "opencode" },
      })

      ----------------------------------------------------------------
      -- 2. Opencode Setup
      ----------------------------------------------------------------
      ---@type opencode.Opts
      vim.g.opencode_opts = {
        -- Configuration options go here
      }

      -- Required so Neovim detects file changes if the AI modifies them
      vim.o.autoread = true

      ----------------------------------------------------------------
      -- 3. Keymaps
      ----------------------------------------------------------------

      -- Ask the AI (Mapped to <leader>oa)
      vim.keymap.set({ "n", "x" }, "<leader>oa", function()
        require("opencode").ask("@this: ", { submit = true })
      end, { desc = "Ask Opencode" })

      -- Select an action (Mapped to <leader>os)
      vim.keymap.set({ "n", "x" }, "<leader>os", function()
        require("opencode").select()
      end, { desc = "Select Opencode Action" })

      -- Toggle the chat window (Mapped to Ctrl + .)
      vim.keymap.set({ "n", "t" }, "<C-.>", function()
        require("opencode").toggle()
      end, { desc = "Toggle Opencode Window" })

      -- Operators: Add context to the AI without opening the window immediately
      -- "go" + motion (e.g., goip = add inner paragraph)
      vim.keymap.set({ "n", "x" }, "go", function()
        return require("opencode").operator("@this ")
      end, { expr = true, desc = "Add range to Opencode" })

      -- "goo" (Add current line)
      vim.keymap.set("n", "goo", function()
        return require("opencode").operator("@this ") .. "_"
      end, { expr = true, desc = "Add line to Opencode" })

      -- Scrolling inside the AI window
      vim.keymap.set("n", "<S-C-u>", function()
        require("opencode").command("session.half.page.up")
      end, { desc = "Opencode half page up" })
      vim.keymap.set("n", "<S-C-d>", function()
        require("opencode").command("session.half.page.down")
      end, { desc = "Opencode half page down" })
    end,
  },
}
