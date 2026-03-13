return {
  {
    "mrjones2014/smart-splits.nvim",
    enabled = true,
    version = "*",
    keys = {
      { "<S-Left>",  function() require("smart-splits").move_cursor_left()  end, silent = true },
      { "<S-Down>",  function() require("smart-splits").move_cursor_down()  end, silent = true },
      { "<S-Up>",    function() require("smart-splits").move_cursor_up()    end, silent = true },
      { "<S-Right>", function() require("smart-splits").move_cursor_right() end, silent = true },
    },
    config = function()
      vim.g.smart_splits_multiplexer_integration = "wezterm"
      require("smart-splits").setup({ at_edge = "stop" })
    end,
  },
}
