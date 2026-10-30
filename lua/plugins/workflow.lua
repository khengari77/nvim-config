return {
  {
    "folke/snacks.nvim",
    opts = function()
      local actions = {
        Pick = { "pp", "projects", "projects" },
        Worktrees = { "pw", "projects", "worktrees" },
        Context = { "pe", "projects", "select_context" },
        Tasks = { "pt", "init", "tasks" },
        Run = { "pr", "init", "file" },
        Build = {
          "pb",
          "init",
          function(m)
            m.tasks("build")
          end,
        },
        Test = {
          "pT",
          "init",
          function(m)
            m.tasks("test")
          end,
        },
        Repeat = { "pl", "init", "repeat_task" },
        Output = { "po", "init", "show" },
        Stop = { "px", "init", "stop" },
        Cases = { "pc", "init", "cases" },
        CaseEdit = { "pC", "init", "edit_case" },
        Scratch = { "ps", "init", "scratch" },
        Symbols = { "pS", "init", "symbols" },
      }
      for name, action in pairs(actions) do
        local callback = function()
          local module = require(action[2] == "init" and "config.workflow" or "config.workflow." .. action[2])
          if type(action[3]) == "function" then
            action[3](module)
          else
            module[action[3]]()
          end
        end
        vim.api.nvim_create_user_command("Project" .. name, callback, {})
        vim.keymap.set(
          "n",
          ((vim.g.project_workflow or {}).keys or {})[name] or "<leader>" .. action[1],
          callback,
          { desc = "Project " .. name }
        )
      end
    end,
  },
  {
    "nvim-lualine/lualine.nvim",
    optional = true,
    opts = function(_, opts)
      table.insert(opts.sections.lualine_x, 1, {
        function()
          if not package.loaded["config.workflow.projects"] then
            return ""
          end
          local workflow = package.loaded["config.workflow"]
          local jobs = workflow and workflow.jobs or {}
          local count = vim.tbl_count(jobs) + (workflow and vim.tbl_count(workflow.case_runs) or 0)
          local P = require("config.workflow.projects")
          local context = P.context()
          local runtime = vim.bo.filetype == "python"
              and context.python
              and ("py:" .. vim.fn.fnamemodify(context.python, ":h:h:t"))
            or context.manager
          return (runtime or "") .. (count > 0 and " tasks:" .. count or "")
        end,
      })
    end,
  },
}
