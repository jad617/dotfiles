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
    ---@class snacks.indent.Config
    ---@field enabled? boolean
    indent = {
      priority = 1,
      enabled = true, -- enable indent guides
      char = "│",
      only_scope = false, -- only show indent guides of the scope
      only_current = false, -- only show indent guides in the current window
      indent = {
        hl = "SnacksIndent",
        -- hl = {
        --   "SnacksIndent1",
        --   "SnacksIndent2",
        --   "SnacksIndent3",
        --   "SnacksIndent4",
        --   "SnacksIndent5",
        --   "SnacksIndent6",
        --   "SnacksIndent7",
        --   "SnacksIndent8",
        -- },
      },
    },
    -- animate scopes. Enabled by default for Neovim >= 0.10
    -- Works on older versions but has to trigger redraws during animation.
    ---@class snacks.indent.animate: snacks.animate.Config
    ---@field enabled? boolean
    --- * out: animate outwards from the cursor
    --- * up: animate upwards from the cursor
    --- * down: animate downwards from the cursor
    --- * up_down: animate up or down based on the cursor position
    ---@field style? "out"|"up_down"|"down"|"up"
    animate = {
      enabled = vim.fn.has("nvim-0.10") == 1,
      style = "out",
      easing = "linear",
      duration = {
        step = 20, -- ms per step
        total = 500, -- maximum duration
      },
    },
    ---@class snacks.indent.Scope.Config: snacks.scope.Config
    scope = {
      enabled = true, -- enable highlighting the current scope
      priority = 200,
      char = "│",
      underline = false, -- underline the start of the scope
      only_current = false, -- only show scope in the current window
      hl = "SnacksIndentScope", ---@type string|string[] hl group for scopes
    },
    chunk = {
      -- when enabled, scopes will be rendered as chunks, except for the
      -- top-level scope which will be rendered as a scope.
      enabled = false,
      -- only show chunk scopes in the current window
      only_current = false,
      priority = 200,
      hl = "SnacksIndentChunk", ---@type string|string[] hl group for chunk scopes
      char = {
        corner_top = "┌",
        corner_bottom = "└",
        -- corner_top = "╭",
        -- corner_bottom = "╰",
        horizontal = "─",
        vertical = "│",
        arrow = ">",
      },
    },
    blank = {
      char = " ",
      -- char = "·",
      hl = "SnacksIndentBlank", ---@type string|string[] hl group for blank spaces
    },
    input = {
      enabled = true,
      icon = " ",
      icon_hl = "SnacksInputIcon",
      icon_pos = "title",
      prompt_pos = "title",
      win = { style = "input" },
      expand = true,
    },
    notifier = { enabled = true },
    -- quickfile = { enabled = true },
    -- scroll = { enabled = true },
    -- statuscolumn = { enabled = true },
    -- words = { enabled = true },
    -- styles = {
    --   input = {
    --     backdrop = false,
    --     position = "float",
    --     border = "rounded",
    --     title_pos = "center",
    --     height = 1,
    --     width = 60,
    --     relative = "editor",
    --     noautocmd = true,
    --     row = 2,
    --     -- relative = "cursor",
    --     -- row = -3,
    --     -- col = 0,
    --     wo = {
    --       winhighlight = "NormalFloat:SnacksInputNormal,FloatBorder:SnacksInputBorder,FloatTitle:SnacksInputTitle",
    --       cursorline = false,
    --     },
    --     bo = {
    --       filetype = "snacks_input",
    --       buftype = "prompt",
    --     },
    --     --- buffer local variables
    --     b = {
    --       completion = false, -- disable blink completions in input
    --     },
    --     keys = {
    --       n_esc = { "<esc>", { "cmp_close", "cancel" }, mode = "n", expr = true },
    --       i_esc = { "<esc>", { "cmp_close", "stopinsert" }, mode = "i", expr = true },
    --       i_cr = { "<cr>", { "cmp_accept", "confirm" }, mode = "i", expr = true },
    --       i_tab = { "<tab>", { "cmp_select_next", "cmp" }, mode = "i", expr = true },
    --       q = "cancel",
    --     },
    --   },
    -- },

    statuscolumn = { enabled = true },
    gitbrowse = { enabled = true },
  },
}
