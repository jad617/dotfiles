return {
  -- enabled = false,
  "aserowy/tmux.nvim",
  config = function()
    require("tmux").setup({
      navigation = {
        cycle_navigation = false,
        enable_default_keybindings = false,
      },
    })

    -- [[ Keymaps ]]
    local keymap = vim.keymap -- for conciseness

    keymap.set("n", "<S-Right>", function()
      require("tmux").move_right()
    end)

    keymap.set("n", "<S-Left>", function()
      require("tmux").move_left()
    end)

    keymap.set("n", "<S-Up>", function()
      require("tmux").move_top()
    end)

    keymap.set("n", "<S-Down>", function()
      require("tmux").move_bottom()
    end)
  end,
}
