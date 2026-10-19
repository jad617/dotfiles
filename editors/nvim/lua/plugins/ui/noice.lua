return {
  "folke/noice.nvim",
  enabled = true,
  event = "VeryLazy",
  dependencies = {
    "MunifTanjim/nui.nvim",
    "rcarriga/nvim-notify",
  },
  config = function()
    require("noice").setup({
      cmdline = {
        format = {
          -- lang="" is truthy in Lua and still invokes Syntax.highlight() via nvim_buf_call,
          -- which interferes with ext_cmdline in Neovim 0.12 and drops the % range specifier.
          -- lang=false is falsy: it skips the highlight branch entirely and keeps % working.
          cmdline    = { pattern = "^:", icon = "", lang = false },
          search_down = { kind = "search", pattern = "^/",  icon = " ", lang = false },
          search_up   = { kind = "search", pattern = "^%?", icon = " ", lang = false },
        },
      },
      -- nvim-cmp's docs popup still calls vim.lsp.util.stylize_markdown (deprecated
      -- in Neovim 0.12+). Let noice render that markdown instead, so the deprecated
      -- core function is never reached.
      lsp = {
        override = {
          ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
          ["vim.lsp.util.stylize_markdown"] = true,
          ["cmp.entry.get_documentation"] = true,
        },
      },
      messages = {
        enabled = true,
      },
      notify = {
        enabled = true,
      },
      routes = {
        -- Suppress benign ClaudeCode WebSocket disconnect on terminal close
        {
          filter = {
            event = "notify",
            find = "ECONNRESET",
          },
          opts = { skip = true },
        },
      },
    })

    -- Patch noice's UI event handler to gracefully skip single-word events
    -- like "restart" (Neovim 0.13-dev) that lack the expected "group_type"
    -- underscore format. Safe to remove once fixed upstream.
    local ui = require("noice.ui")
    local orig_get_handler = ui.get_handler
    ui.get_handler = function(event, ...)
      if not event:find("_") then
        return
      end
      return orig_get_handler(event, ...)
    end
  end,
}
