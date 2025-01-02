return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  ---@type snacks.Config
  opts = {
    bigfile = { enabled = true },
    dashboard = {
      enabled = true,
      sections = {
        { section = "header" },
        { title = "Keymaps", section = "keys", icon = " ", pane = 1, padding = 1, indent = 2 },
        {
          title = "Workspaces",
          icon = " ",
          action = function()
            vim.cmd("Telescope workspaces")
          end,
          key = "w",
          padding = 1,
        },
        {
          title = "Projects",
          section = "projects",
          -- dirs = { "~/intelcom/" },
          icon = " ",
          pane = 1,
          indent = 2,
          padding = 1,
          limit = 20,
          cwd = true,
        },
        {
          title = "Recent Files",
          section = "recent_files",
          icon = " ",
          pane = 1,
          indent = 2,
          padding = 1,
        },
        {
          section = "terminal",
          cmd = "colorscript -e square",
          pane = 1,
          height = 5,
          padding = 1,
        },
        { section = "startup", pane = 1 },
      },
    },
    -- indent = {
    --   enabled = true,
    -- },
    -- indent = {
    --   priority = 1,
    --   enabled = true, -- enable indent guides
    --   char = "│",
    --   only_scope = false, -- only show indent guides of the scope
    --   only_current = false, -- only show indent guides in the current window
    --   -- hl = "SnacksIndent", ---@type string|string[] hl groups for indent guides
    --   -- can be a list of hl groups to cycle through
    --   hl = {
    --     "SnacksIndent1",
    --     "SnacksIndent2",
    --     "SnacksIndent3",
    --     "SnacksIndent4",
    --     "SnacksIndent5",
    --     "SnacksIndent6",
    --     "SnacksIndent7",
    --     "SnacksIndent8",
    --   },
    -- },
    -- animate = {
    --   enabled = vim.fn.has("nvim-0.10") == 1,
    --   style = "out",
    --   easing = "linear",
    --   duration = 20,
    -- },
    -- input = { enabled = true },
    -- notifier = { enabled = true },
    -- quickfile = { enabled = true },
    -- scroll = { enabled = true },
    -- statuscolumn = { enabled = true },
    -- words = { enabled = true },
  },
}
