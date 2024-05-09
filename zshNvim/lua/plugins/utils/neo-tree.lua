return {
  "nvim-neo-tree/neo-tree.nvim",
   branch = "v3.x",
   dependencies = {
     "nvim-lua/plenary.nvim",
     "nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
     "MunifTanjim/nui.nvim",
     -- "3rd/image.nvim", -- Optional image support in preview window: See `# Preview Mode` for more information
   },
  opts = {
    enable_diagnostics = false,
    close_if_last_window = true,
    window = {
      mappings = {
        ["<C-v>"] = "open_vsplit",
        ["<C-x>"] = "open_split",
        ["<C-t>"] = "open_tabnew",
        ["u"] = "navigate_up",
      },
    },
    buffers = {
      follow_current_file = {
        enabled = false, -- This will find and focus the file in the active buffer every time
      },
    },
    filesystem = {
      filtered_items = {
        visible = false,
        show_hidden_count = true,
        hide_dotfiles = true,
        hide_gitignored = true,
        hide_by_name = {
          ".git",
          ".gitignore",
          ".DS_Store",
          "bootstrap",
          "bootstrap.zip",
          "main.zip",
        },
        always_show = { -- remains visible even if other settings would normally hide it
          ".env",
          ".github",
          ".gitlab-ci.yml",
          ".gitlab-ci.yaml",
          ".helmignore",
          ".terraform-docs.yml",
          ".terraform-docs.yaml",
        },
      },
      follow_current_file = {
        enabled = false,
      },
    },
    default_component_configs = {
      indent = {
        indent_size = 2,
        padding = 1, -- extra padding on left hand side
        -- indent guides
        with_markers = true,
        indent_marker = "│",
        last_indent_marker = "└",
        highlight = "NeoTreeIndentMarker",
        -- expander config, needed for nesting files
        with_expanders = nil, -- if nil and file nesting is enabled, will enable expanders
        expander_collapsed = "",
        expander_expanded = "",
        expander_highlight = "NeoTreeExpander",
      },
      git_status = {
        symbols = {
          -- Change type
          added = "+", -- or "✚", but this is redundant info if you use git_status_colors on the name
          modified = "{}", -- or "", but this is redundant info if you use git_status_colors on the name
          deleted = "✖", -- this can only be used in the git_status source
          renamed = "󰁕", -- this can only be used in the git_status source
          -- Status type
          untracked = "^",
          ignored = "",
          unstaged = "*",
          staged = "",
          conflict = "",
        },
      },
      -- If you don't want to use these columns, you can set `enabled = false` for each of them individually
      file_size = {
        enabled = false,
        -- required_width = 64, -- min width of window required to show this column
      },
      type = {
        enabled = false,
        -- required_width = 122, -- min width of window required to show this column
      },
      last_modified = {
        enabled = false,
        -- required_width = 88, -- min width of window required to show this column
      },
      created = {
        enabled = false,
        -- required_width = 110, -- min width of window required to show this column
      },
      symlink_target = {
        enabled = false,
      },
    },
  },
}
