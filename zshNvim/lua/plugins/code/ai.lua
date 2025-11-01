return {
  -- official copilot plugin
  {
    "github/copilot.vim",
    enabled = function()
      return vim.fn.filereadable(vim.fn.expand("~/.disable_copilot")) == 0
    end,
    config = function()
      -- 🌟 Keymaps for inline suggestions
      vim.g.copilot_no_tab_map = true
      vim.api.nvim_set_keymap("i", "<C-J>", 'copilot#Accept("<CR>")', { silent = true, expr = true })
    end,
  },

  -- copilot chat plugin
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    dependencies = {
      { "github/copilot.vim" }, -- official Copilot plugin (auth + inline suggestions)
      { "nvim-lua/plenary.nvim" },
    },
    enabled = function()
      return vim.fn.filereadable(vim.fn.expand("~/.disable_copilot")) == 0
    end,
    config = function()
      local chat = require("CopilotChat")

      chat.setup({
        -- optional UI configs here (float, split, etc.)
      })

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
