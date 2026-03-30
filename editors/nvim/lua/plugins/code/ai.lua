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
  -- 5. COPILOT.LUA — ghost text suggestions, <C-j> to accept
  -- ─────────────────────────────────────────────────────────────────────────
  {
    "zbirenbaum/copilot.lua",
    cmd = "Copilot",
    event = "InsertEnter",
    enabled = function() return vim.fn.filereadable(vim.fn.expand("~/.disable_copilot")) == 0 end,
    opts = {
      suggestion = {
        enabled = true,
        auto_trigger = true,
        hide_during_completion = false,
        keymap = {
          accept = "<C-j>",
          dismiss = "<C-]>",
        },
      },
      panel = { enabled = false },
      filetypes = { markdown = true, help = false },
    },
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
      chat.setup({
        model = "claude-sonnet-4.6",
        -- Include current buffer as context in every message.
        -- Equivalent to typing #buffer at the start of each prompt.
        resources = "buffer",
      })

      vim.keymap.set({ "n", "v" }, "<leader>ce", "<cmd>CopilotChatToggle<cr>", { desc = "Toggle CopilotChat" })

      vim.keymap.set(
        "n",
        "<leader>cr",
        function() chat.ask("Review this buffer and suggest improvements.", { selection = false }) end,
        { desc = "Copilot Review Buffer" }
      )

      vim.keymap.set(
        "v",
        "<leader>cr",
        function() chat.ask("Review this code and suggest improvements.", { selection = true }) end,
        { desc = "Copilot Review Selection" }
      )
    end,
  },

  -- ─────────────────────────────────────────────────────────────────────────
  -- 8. SIDEKICK.NVIM — AI CLI terminal + Copilot Next Edit Suggestions
  --    <leader>cp  Toggle sidekick with Claude CLI (right split, inside Neovim)
  --    Also provides NES (Next Edit Suggestions) via Copilot LSP.
  -- ─────────────────────────────────────────────────────────────────────────
  {
    "folke/sidekick.nvim",
    event = "VeryLazy",
    opts = {
      -- Disable Next Edit Suggestions — causes lag by firing Copilot LSP
      -- requests on every TextChanged event. CLI terminal is all we need.
      nes = { enabled = false },
      cli = {
        watch = true,
        tools = {
          claude = { cmd = { "claude", "--model", "claude-sonnet-4-6" } },
        },
      },
    },
    keys = {
      {
        "<leader>cp",
        function() require("sidekick.cli").toggle({ name = "copilot", focus = true }) end,
        desc = "Sidekick: Copilot CLI",
        mode = "n",
      },
    },
  },
}
