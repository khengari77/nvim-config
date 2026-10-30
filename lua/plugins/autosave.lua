return {
  "pocco81/auto-save.nvim",
  -- Don't lazy-load so it's always active
  lazy = false,
  opts = {
    -- Set to true to enable autosave
    enabled = true,

    -- A list of events that trigger saving
    trigger_events = { "InsertLeave", "TextChanged" },

    -- A debounce delay in milliseconds. This is very important for the 'TextChanged'
    -- event, as it prevents saving on every single keystroke. A 1-2 second delay
    -- is usually a good balance.
    debounce_delay = 1500,

    -- Save only existing, writable files. Debounced callbacks can outlive buffers.
    condition = function(buf)
      if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
        return false
      end
      local opts = vim.bo[buf]
      if opts.buftype ~= "" or not opts.modifiable or opts.readonly then
        return false
      end
      local name = vim.api.nvim_buf_get_name(buf)
      local stat = name ~= "" and vim.uv.fs_stat(name)
      return stat and stat.type == "file" and vim.fn.filewritable(name) == 1 or false
    end,
  },
}
