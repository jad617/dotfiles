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
    opts = {
      heading = { enabled = true },
      code = { enabled = true },
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
      -- Open / toggle chat sidebar
      { "<leader>cc", "<cmd>CodeCompanionChat Toggle<cr>", desc = "Toggle AI chat" },
      -- Inline assistant (works in visual too)
      { "<leader>ci", "<cmd>CodeCompanion<cr>", desc = "Inline AI", mode = { "n", "v" } },
      -- Action palette (explain, fix, tests, docs …)
      { "<leader>ca", "<cmd>CodeCompanionActions<cr>", desc = "AI actions", mode = { "n", "v" } },
      -- Add selected code as context in existing chat
      { "<leader>cx", "<cmd>CodeCompanionChat Add<cr>", desc = "Add to chat", mode = "v" },
      -- Quick inline shortcuts
      { "<leader>cf", "<cmd>CodeCompanion /fix<cr>", desc = "Fix code", mode = { "n", "v" } },
      { "<leader>ct", "<cmd>CodeCompanion /tests<cr>", desc = "Write tests", mode = { "n", "v" } },
      { "<leader>cd", "<cmd>CodeCompanion /doc<cr>", desc = "Write docs", mode = { "n", "v" } },
    },
    opts = {
      -- ── Adapters ────────────────────────────────────────────────────────
      -- API key is read from $ANTHROPIC_API_KEY automatically.
      -- Use a cheaper model for background/cmd tasks to save cost.
      strategies = {
        chat = { adapter = "anthropic" }, -- Sonnet for conversation
        inline = { adapter = "anthropic" }, -- Sonnet for inline edits
        cmd = { adapter = "anthropic" }, -- for :CodeCompanionCmd
      },
      adapters = {
        anthropic = function()
          return require("codecompanion.adapters").extend("anthropic", {
            schema = {
              model = {
                -- Claude Sonnet 4.6 — best balance of speed and quality
                default = "claude-sonnet-4-6",
              },
              max_tokens = { default = 8192 },
            },
          })
        end,
      },

      -- ── Display ─────────────────────────────────────────────────────────
      display = {
        chat = {
          show_token_count = true, -- keep an eye on context usage
          show_settings = false,
          render_markdown = true,
          window = {
            layout = "vertical", -- sidebar feel
            width = 0.35, -- 35 % of screen
          },
        },
        action_palette = {
          provider = "default",
        },
        diff = {
          provider = "mini_diff", -- requires mini.diff; swap to "default" if not installed
        },
      },

      -- ── CLAUDE.md / rules ─────────────────────────────────────────────────
      -- CodeCompanion will automatically pick up CLAUDE.md at your repo root.
      -- Create one with stack-specific context (see tip below).
    },
  },

  -- ─────────────────────────────────────────────────────────────────────────
  -- 4. CLAUDECODE.NVIM — full Claude Code CLI integration via WebSocket MCP
  --    Gives Claude direct read/write access to every open buffer,
  --    LSP diagnostics, and your file explorer (@-mention files).
  -- ─────────────────────────────────────────────────────────────────────────
  {
    "coder/claudecode.nvim",
    event = "VeryLazy",
    config = true,
    keys = {
      { "<leader>ac", "<cmd>ClaudeCode<cr>", desc = "Toggle Claude Code" },
      { "<leader>af", "<cmd>ClaudeCodeFocus<cr>", desc = "Focus Claude Code" },
      { "<leader>as", "<cmd>ClaudeCodeSend<cr>", desc = "Send selection", mode = "v" },
      { "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Accept diff" },
      { "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Deny diff" },
    },
    opts = {
      terminal = {
        provider = "native", -- use Neovim's built-in terminal
        split_side = "right", -- open on the right side
        split_width_percentage = 0.40,
      },
      auto_insert = true,
      auto_close_on_exit = false, -- keep window open after Claude finishes
    },
  },

  -- ─────────────────────────────────────────────────────────────────────────
  -- 5. COPILOT.LUA — pure Lua inline suggestions (replaces copilot.vim)
  --    Suggestions routed through cmp via copilot-cmp (no ghost text)
  -- ─────────────────────────────────────────────────────────────────────────
  {
    "zbirenbaum/copilot.lua",
    cmd   = "Copilot",
    event = "InsertEnter",
    enabled = function()
      return vim.fn.filereadable(vim.fn.expand("~/.disable_copilot")) == 0
    end,
    opts = {
      suggestion = { enabled = false }, -- handled by copilot-cmp
      panel      = { enabled = false }, -- handled by copilot-cmp
      filetypes  = { markdown = true, help = false },
    },
  },

  -- ─────────────────────────────────────────────────────────────────────────
  -- 6. COPILOT-CMP — routes Copilot suggestions into nvim-cmp menu
  -- ─────────────────────────────────────────────────────────────────────────
  {
    "zbirenbaum/copilot-cmp",
    enabled = function()
      return vim.fn.filereadable(vim.fn.expand("~/.disable_copilot")) == 0
    end,
    dependencies = { "zbirenbaum/copilot.lua" },
    config = true,
  },

  -- ─────────────────────────────────────────────────────────────────────────
  -- 7. COPILOT-LSP — enables Next Edit Suggestions (NES)
  --    Predicts where you'll edit next based on recent changes
  -- ─────────────────────────────────────────────────────────────────────────
  {
    "copilotlsp-nvim/copilot-lsp",
    enabled = function()
      return vim.fn.filereadable(vim.fn.expand("~/.disable_copilot")) == 0
    end,
    event = "InsertEnter",
    opts  = {},
  },

  -- ─────────────────────────────────────────────────────────────────────────
  -- 8. SIDEKICK.NVIM — NES inline diffs + hunk navigation (by folke)
  -- ─────────────────────────────────────────────────────────────────────────
  {
    "folke/sidekick.nvim",
    enabled = function()
      return vim.fn.filereadable(vim.fn.expand("~/.disable_copilot")) == 0
    end,
    build = "npm install -g @githubnext/github-copilot-cli",
    event = "VeryLazy",
    keys  = {
      {
        "<leader>sk",
        function() require("sidekick.cli").toggle({ name = "copilot" }) end,
        desc = "Sidekick (Copilot)",
      },
    },
    opts  = {
      cli = {
        tools = {
          copilot = { cmd = { "github-copilot-cli", "--banner" } },
        },
      },
    },
  },

  -- ─────────────────────────────────────────────────────────────────────────
  -- 9. COPILOT CHAT
  -- ─────────────────────────────────────────────────────────────────────────
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    dependencies = {
      { "zbirenbaum/copilot.lua" },
      { "nvim-lua/plenary.nvim" },
    },
    enabled = function()
      return vim.fn.filereadable(vim.fn.expand("~/.disable_copilot")) == 0
    end,
    config = function()
      local chat = require("CopilotChat")

      chat.setup({
        model = "claude-sonnet-4-6",
      })

      vim.keymap.set({ "n", "v" }, "<leader>cp", "<cmd>CopilotChatToggle<cr>", { desc = "Toggle CopilotChat" })

      -- 🌟 Keymaps for buffer-level commands
      -- Review buffer
      vim.keymap.set("n", "<leader>cr", function()
        chat.ask("Review this buffer and suggest improvements.", { selection = false })
      end, { desc = "Copilot Review Buffer" })

      -- Explain buffer
      vim.keymap.set("n", "<leader>ce", function()
        chat.ask("Explain this buffer in detail.", { selection = false })
      end, { desc = "Copilot Explain Buffer" })

      -- Fix issues in buffer
      vim.keymap.set("n", "<leader>cf", function()
        chat.ask("Find bugs or errors in this buffer and suggest fixes.", { selection = false })
      end, { desc = "Copilot Fix Buffer" })

      -- 🌟 Visual mode: run on selection only
      vim.keymap.set("v", "<leader>cr", function()
        chat.ask("Review this code and suggest improvements.", { selection = true })
      end, { desc = "Copilot Review Selection" })

      vim.keymap.set("v", "<leader>ce", function()
        chat.ask("Explain this code.", { selection = true })
      end, { desc = "Copilot Explain Selection" })

      vim.keymap.set("v", "<leader>cf", function()
        chat.ask("Find bugs in this code and suggest fixes.", { selection = true })
      end, { desc = "Copilot Fix Selection" })
    end,
  },
}
