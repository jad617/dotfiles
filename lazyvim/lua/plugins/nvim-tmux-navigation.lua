return {
  "alexghergh/nvim-tmux-navigation",
  config = function()
    require("nvim-tmux-navigation").setup({
      disable_when_zoomed = false, -- defaults to false
      keybindings = {
        left = "<S-Left>",
        down = "<S-Down>",
        up = "<S-Up>",
        right = "<S-Right>",
        -- last_active = "<C-\\>",
        -- next = "<C-Space>",
      },
    })
  end,
}
