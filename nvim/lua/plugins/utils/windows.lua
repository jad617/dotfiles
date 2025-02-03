-- Window resizer
-- Window picker works with neo-tree
return {
  enabled = false,
  "anuvyklack/windows.nvim",
  dependencies = {
    "anuvyklack/middleclass",
    "anuvyklack/animation.nvim",
  },
  config = function()
    vim.o.winwidth = 10
    vim.o.winminwidth = 10
    vim.o.equalalways = false

    require("windows").setup({
      autowidth = {
        enable = true,
        winwidth = 4,
      },
      ignore = {
        filetype = { "NvimTree", "neo-tree", "undotree", "gundo" },
      },
      animation = {
        enable = true,
        duration = 300,
        fps = 30,
        easing = "in_out_sine",
      },
    })

    ------------------------------------------------------------
    -- [[ local vars ]]
    ------------------------------------------------------------
    local function cmd(command)
      return table.concat({ "<Cmd>", command, "<CR>" })
    end

    ------------------------------------------------------------
    -- [[ Key Bindings ]]
    ------------------------------------------------------------
    vim.keymap.set("n", "<C-w>z", cmd("WindowsMaximize"))
    vim.keymap.set("n", "<C-w>_", cmd("WindowsMaximizeVertically"))
    vim.keymap.set("n", "<C-w>|", cmd("WindowsMaximizeHorizontally"))
    vim.keymap.set("n", "<C-w>=", cmd("WindowsEqualize"))
  end,
}
