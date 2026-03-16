return {
  -- ~/.config/nvim/lua/plugins/ai.lua
  -- AI tooling for JS frontend + Go backend + Terraform project
  -- Prerequisites:
  --   export ANTHROPIC_API_KEY="sk-ant-..."
  --   npm install -g @anthropic-ai/claude-code   (for claudecode.nvim)

  -- ─────────────────────────────────────────────────────────────────────────
  -- 1. RENDER-MARKDOWN  — pretty markdown in chat buffers
  -- ─────────────────────────────────────────────────────────────────────────
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown", "codecompanion" },
    keys = {
      { "<leader>m", "<cmd>RenderMarkdown toggle<cr>", desc = "Toggle Render Markdown" },
    },
    opts = {
      enabled = true,
      heading = { enabled = true },
      code = { enabled = true },
      anti_conceal = {
        disabled_modes = { "n" },
      },
      win_options = {
        concealcursor = {
          rendered = "n",
        },
      },
    },
  },

  -- ─────────────────────────────────────────────────────────────────────────
  -- 2. FIDGET — spinner/progress toasts while Claude thinks
  -- ─────────────────────────────────────────────────────────────────────────
  {
    "j-hui/fidget.nvim",
    event = "VeryLazy",
    opts = {},
  },

  -- ─────────────────────────────────────────────────────────────────────────
  -- 3. CODECOMPANION — primary AI chat + inline assistant
  --    <leader>cc  Toggle chat sidebar (full buffer context auto-included)
  -- ─────────────────────────────────────────────────────────────────────────
  {
    "olimorris/codecompanion.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
      "MeanderingProgrammer/render-markdown.nvim",
      "j-hui/fidget.nvim",
    },
    event = "VeryLazy",
    keys = {
      { "<leader>cc", "<cmd>CodeCompanionChat Toggle<cr>", desc = "Toggle AI chat (CodeCompanion)" },
      { "<leader>ci", "<cmd>CodeCompanion<cr>", desc = "Inline AI", mode = { "n", "v" } },
      -- Renamed from <leader>ca to avoid conflict with Claude CLI
      { "<leader>cA", "<cmd>CodeCompanionActions<cr>", desc = "AI actions", mode = { "n", "v" } },
      { "<leader>cx", "<cmd>CodeCompanionChat Add<cr>", desc = "Add to chat", mode = "v" },
      { "<leader>cf", "<cmd>CodeCompanion /fix<cr>", desc = "Fix code", mode = { "n", "v" } },
      { "<leader>ct", "<cmd>CodeCompanion /tests<cr>", desc = "Write tests", mode = { "n", "v" } },
      { "<leader>cd", "<cmd>CodeCompanion /doc<cr>", desc = "Write docs", mode = { "n", "v" } },
    },
    opts = {
      strategies = {
        chat = { adapter = "anthropic" },
        inline = { adapter = "anthropic" },
        cmd = { adapter = "anthropic" },
      },
      adapters = {
        anthropic = function()
          return require("codecompanion.adapters").extend("anthropic", {
            schema = {
              model = { default = "claude-sonnet-4-6" },
              max_tokens = { default = 8192 },
            },
          })
        end,
      },
      display = {
        chat = {
          show_token_count = true,
          show_settings = false,
          render_markdown = true,
          window = {
            layout = "vertical",
            width = 0.35,
          },
        },
        action_palette = { provider = "default" },
        diff = { provider = "mini_diff" },
      },
    },
  },

  -- ─────────────────────────────────────────────────────────────────────────
  -- 4. CLAUDECODE.NVIM — Claude Code CLI via WebSocket MCP (full buffer access)
  --    <leader>ca  Toggle Claude CLI terminal (right split, inside Neovim)
  -- ─────────────────────────────────────────────────────────────────────────
  {
    "coder/claudecode.nvim",
    event = "VeryLazy",
    config = true,
    keys = {
      { "<leader>ca", "<cmd>ClaudeCode<cr>", desc = "Toggle Claude CLI" },
      { "<leader>as", "<cmd>ClaudeCodeSend<cr>", desc = "Send selection to Claude", mode = "v" },
      { "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Accept Claude diff" },
      { "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Deny Claude diff" },
    },
    opts = {
      terminal = {
        provider = "native",
        split_side = "right",
        split_width_percentage = 0.40,
      },
      auto_insert = true,
      auto_close_on_exit = false,
    },
  },

  -- ─────────────────────────────────────────────────────────────────────────
  -- 5. COPILOT.LUA — inline suggestions via cmp
  -- ─────────────────────────────────────────────────────────────────────────
  {
    "zbirenbaum/copilot.lua",
    cmd = "Copilot",
    event = "InsertEnter",
    enabled = function() return vim.fn.filereadable(vim.fn.expand("~/.disable_copilot")) == 0 end,
    opts = {
      suggestion = { enabled = false },
      panel = { enabled = false },
      filetypes = { markdown = true, help = false },
    },
  },

  -- ─────────────────────────────────────────────────────────────────────────
  -- 6. COPILOT-CMP — routes Copilot suggestions into nvim-cmp menu
  -- ─────────────────────────────────────────────────────────────────────────
  {
    "zbirenbaum/copilot-cmp",
    enabled = function() return vim.fn.filereadable(vim.fn.expand("~/.disable_copilot")) == 0 end,
    dependencies = { "zbirenbaum/copilot.lua" },
    config = true,
  },

  -- ─────────────────────────────────────────────────────────────────────────
  -- 7. COPILOTCHAT — Copilot AI chat with full buffer awareness
  --    <leader>ce  Toggle CopilotChat sidebar
  -- ─────────────────────────────────────────────────────────────────────────
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    dependencies = {
      { "zbirenbaum/copilot.lua" },
      { "nvim-lua/plenary.nvim" },
    },
    enabled = function() return vim.fn.filereadable(vim.fn.expand("~/.disable_copilot")) == 0 end,
    cmd = { "CopilotChat", "CopilotChatToggle", "CopilotChatReset" },
    keys = {
      { "<leader>ce", "<cmd>CopilotChatToggle<cr>", mode = { "n", "v" }, desc = "Toggle CopilotChat" },
    },
    config = function()
      local chat = require("CopilotChat")
      -- No model override — CopilotChat uses GitHub Copilot's API, not Anthropic's.
      -- Model names differ (e.g. "gpt-4o", "claude-3.5-sonnet") and are managed
      -- by Copilot. Let it use its default.
      chat.setup({ model = "claude-sonnet-4.6" })

      vim.keymap.set({ "n", "v" }, "<leader>ce", "<cmd>CopilotChatToggle<cr>", { desc = "Toggle CopilotChat" })

      vim.keymap.set("n", "<leader>cr", function()
        chat.ask("Review this buffer and suggest improvements.", { selection = false })
      end, { desc = "Copilot Review Buffer" })

      vim.keymap.set("v", "<leader>cr", function()
        chat.ask("Review this code and suggest improvements.", { selection = true })
      end, { desc = "Copilot Review Selection" })
    end,
  },

  -- ─────────────────────────────────────────────────────────────────────────
  -- 8. COPILOT CLI — persistent terminal split for `gh copilot` commands
  --    <leader>cp  Toggle Copilot CLI terminal (right split, inside Neovim)
  --    Usage inside the split: gh copilot suggest "..."
  --                             gh copilot explain "..."
  -- ─────────────────────────────────────────────────────────────────────────
  {
    -- No new plugin needed — Snacks.terminal handles this.
    -- This empty spec is a placeholder to document the keymap below.
    -- The actual keymap is registered via snacks.nvim keys.
    "folke/snacks.nvim",
    keys = {
      {
        "<leader>cp",
        function()
          Snacks.terminal(nil, {
            id = "copilot-cli",
            win = {
              position = "right",
              width = 0.40,
              border = "rounded",
              title = " Copilot CLI ",
              title_pos = "center",
            },
            start_insert = true,
            auto_close = false,
          })
        end,
        desc = "Toggle Copilot CLI terminal",
      },
    },
  },
}
