return {
  {
    "yuttie/comfortable-motion.vim",
    enabled = true,
    config = function()
      ------------------------------------------------------------
      -- [[ local vars ]]
      ------------------------------------------------------------
      local cmd = vim.cmd -- cmd
      local map = vim.api.nvim_set_keymap -- set keys
      local options = { noremap = true, silent = true }

      ------------------------------------------------------------
      -- [[ Config ]]
      ------------------------------------------------------------
      cmd([[let g:comfortable_motion_no_default_key_mappings = 1]])
      cmd([[let g:comfortable_motion_scroll_down_key = "j"]])
      cmd([[let g:comfortable_motion_scroll_up_key = "k"]])
      cmd([[let g:comfortable_motion_friction = 300.0]])
      cmd([[let g:comfortable_motion_air_drag = 4.0]])

      ------------------------------------------------------------
      -- [[ Key Bindings ]]
      ------------------------------------------------------------

      -- [[ Default]]
      map("n", "<C-o>", ":call comfortable_motion#flick(-75)<CR>", options)
      map("n", "<C-p>", ":call comfortable_motion#flick(75)<CR>", options)

      -- TODO: need to find a way to force this behavior
      map("i", "<C-p>", "<C-c>:call comfortable_motion#flick(100)<CR>", options)
      map("i", "<C-o>", "<C-c>:call comfortable_motion#flick(-100)<CR>", options)
    end,
  },
  {
    "karb94/neoscroll.nvim",
    enabled = false,
    event = "VeryLazy",
    config = function()
      require("neoscroll").setup({
        hide_cursor = false,
        stop_eof = true,
        respect_scrolloff = true,
        easing_function = nil,
        performance_mode = true,
      })
      local t = {}
      -- keep j/k as pure cursor moves; use Ctrl-d/u/f/b and zt/zz/zb
      t["<C-o>"] = { "scroll", { "-vim.wo.scroll", "true", "150" } }
      t["<C-p>"] = { "scroll", { "vim.wo.scroll", "true", "150" } }
      t["<C-b>"] = { "scroll", { "-vim.api.nvim_win_get_height(0)", "true", "200" } }
      t["<C-f>"] = { "scroll", { "vim.api.nvim_win_get_height(0)", "true", "200" } }
      t["zt"] = { "zt", { "150" } }
      t["zz"] = { "zz", { "150" } }
      t["zb"] = { "zb", { "150" } }
      require("neoscroll.config").set_mappings(t)
    end,
  },
}
