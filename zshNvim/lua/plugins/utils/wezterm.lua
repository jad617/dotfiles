return {
  {
    "mrjones2014/smart-splits.nvim",
    version = "*",
    config = function()
      -- Tell the plugin to integrate with WezTerm
      vim.g.smart_splits_multiplexer_integration = "wezterm"

      require("smart-splits").setup({
        -- you can tweak options here if you want
        at_edge = "stop",
      })

      -- Move between splits with Shift+Arrows (NVim ⇄ WezTerm)
      vim.keymap.set("n", "<S-Left>", require("smart-splits").move_cursor_left, { silent = true })
      vim.keymap.set("n", "<S-Down>", require("smart-splits").move_cursor_down, { silent = true })
      vim.keymap.set("n", "<S-Up>", require("smart-splits").move_cursor_up, { silent = true })
      vim.keymap.set("n", "<S-Right>", require("smart-splits").move_cursor_right, { silent = true })

      -- (Optional) resizing from NVim via Alt+Arrows
      -- vim.keymap.set("n", "<M-Left>",  require("smart-splits").resize_left)
      -- vim.keymap.set("n", "<M-Down>",  require("smart-splits").resize_down)
      -- vim.keymap.set("n", "<M-Up>",    require("smart-splits").resize_up)
      -- vim.keymap.set("n", "<M-Right>", require("smart-splits").resize_right)
    end,
  },
}
