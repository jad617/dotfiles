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
          title = "Update Todo",
          icon = " ",
          action = function()
            vim.cmd(":e ~/todo")
          end,
          key = "t",
          padding = 1,
        },
        {
          title = "Todo List",
          icon = "󰒲 ",
          section = "terminal",
          cmd = "cat ~/todo",
          padding = 1,
          height = 10,
          ttl = 5,
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
    terminal = { win = { style = "float", relative = "editor", border = "double", height = 0.99 } },
    styles = {
      zen = {
        width = 200,
        relative = "editor",
      },
    },

    statuscolumn = { enabled = true },
    gitbrowse = { enabled = true },
    explorer = {
      enabled = true,
      replace_netrw = true, -- Replace netrw with the snacks explorer
    },
    picker = {
      sources = {
        explorer = {
          finder = "explorer",
          sort = { fields = { "sort" } },
          tree = true,
          git_status = true,
          git_status_open = false,
          supports_live = true,
          follow_file = true,
          -- focus = "input",
          auto_close = false,
          jump = { close = false },
          layout = { preset = "sidebar", preview = false },
          -- to show the explorer to the right, add the below to
          -- your config under `opts.picker.sources.explorer`
          -- layout = { layout = { position = "right" } },
          formatters = { file = { filename_only = true } },
          matcher = { sort_empty = true },
          config = function(opts)
            return require("snacks.picker.source.explorer").setup(opts)
          end,
          win = {
            list = {
              keys = {
                ["C-d"] = "close",
                ["C-n"] = "close",
                ["<BS>"] = "explorer_up",
                ["l"] = "confirm",
                ["h"] = "explorer_close", -- close directory
                ["a"] = "explorer_add",
                ["d"] = "explorer_del",
                ["r"] = "explorer_rename",
                ["c"] = "explorer_copy",
                ["m"] = "explorer_move",
                ["o"] = "explorer_open", -- open with system application
                ["P"] = "toggle_preview",
                ["y"] = "explorer_yank",
                ["u"] = "explorer_update",
                ["<c-c>"] = "explorer_cd",
                ["."] = "explorer_focus",
                ["I"] = "toggle_ignored",
                ["H"] = "toggle_hidden",
                ["Z"] = "explorer_close_all",
                ["]g"] = "explorer_git_next",
                ["[g"] = "explorer_git_prev",
              },
            },
          },
        },
      },
    },
  },
  keys = {
    {
      "<leader>z",
      function()
        Snacks.zen()
      end,
      desc = "Toggle Zoom",
    },
    {
      "<leader>Z",
      function()
        Snacks.zen.zoom()
      end,
      desc = "Toggle Zoom",
    },
    {
      "<leader>.",
      function()
        Snacks.scratch()
      end,
      desc = "Toggle Scratch Buffer",
    },
    {
      "<leader>n",
      function()
        Snacks.notifier.show_history()
      end,
      desc = "Notification History",
    },
    {
      "<leader>git",
      function()
        Snacks.gitbrowse()
      end,
      desc = "Git Browse",
      mode = { "n", "v" },
    },
    {
      "<leader>gb",
      function()
        Snacks.git.blame_line()
      end,
      desc = "Git Blame Line",
    },
    -- {
    --   "<leader>gf",
    --   function()
    --     Snacks.lazygit.log_file()
    --   end,
    --   desc = "Lazygit Current File History",
    -- },
    {
      "<leader>gg",
      function()
        Snacks.lazygit()
      end,
      desc = "Lazygit",
    },
    {
      "<leader>gl",
      function()
        Snacks.lazygit.log()
      end,
      desc = "Lazygit Log (cwd)",
    },
    {
      "<leader>un",
      function()
        Snacks.notifier.hide()
      end,
      desc = "Dismiss All Notifications",
    },
    {
      "<A-i>",
      function()
        Snacks.terminal()
      end,
      desc = "Toggle Terminal",
      mode = { "n", "t" },
    },
    {
      "ff",
      function()
        Snacks.picker.files()
      end,
      desc = "Find files",
      mode = { "n" },
    },
    {
      "fg",
      function()
        Snacks.picker.grep()
      end,
      desc = "Grep",
      mode = { "n" },
    },
    {
      "fb",
      function()
        Snacks.picker.buffers()
      end,
      desc = "Find buffers",
      mode = { "n" },
    },
    {
      "fh",
      function()
        Snacks.picker.help()
      end,
      desc = "Find help",
      mode = { "n" },
    },
    {
      "fd",
      function()
        Snacks.picker.diagnostics()
      end,
      desc = "Find diagnostics",
      mode = { "n" },
    },
    {
      "<C-n>",
      function()
        Snacks.picker.explorer()
      end,
      desc = "Open explorer",
      mode = { "n" },
    },
    -- {
    --   "<leader>g",
    --   function()
    --     local word = vim.fn.expand("<cword>") -- Get the word under the cursor
    --     Snacks.picker.grep({ glob = { "leader" } })
    --   end,
    --   desc = "Find diagnostics",
    --   mode = { "n" },
    -- },
  },
}
