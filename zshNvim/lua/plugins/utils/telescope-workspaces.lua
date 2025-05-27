return {
  "natecraddock/workspaces.nvim",
  config = function()
    require("workspaces").setup({
      hooks = {
        open = function()
          vim.cmd(":lua Snacks.picker.files({hidden = true})")
        end,
      },
    })
  end,
}
