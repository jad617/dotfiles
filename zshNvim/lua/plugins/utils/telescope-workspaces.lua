return {
  "natecraddock/workspaces.nvim",
  config = function()
    require("workspaces").setup({
      hooks = {
        open = function()
          -- vim.cmd(":Telescope file_browser")
          vim.cmd(":lua Snacks.picker.files({hidden = true})")
        end,
      },
    })
  end,
}

-- return {
--   "ahmedkhalf/project.nvim",
--   config = function()
--     require("project_nvim").setup({
--       detection_methods = { "pattern" },
--       patterns = {
--         "mvnw.cmd",
--         "VERSION",
--         -- "providers.tf",
--         -- "provider.tf",
--         "Makefile",
--         "lazy-lock.json",
--         "package.json",
--         "ansible.cfg",
--         "Chart.yaml",
--         "README.md",
--         ".git",
--       },
--     })
--   end,
-- }
