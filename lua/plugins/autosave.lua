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

    -- Conditions for saving
    conditions = {
      exists = true, -- File must exist on disk
      modifiable = true, -- Buffer must be modifiable
    },
  },
}
