return {
  "ahmedkhalf/project.nvim",
  config = function()
    require("project_nvim").setup({
      detection_methods = { "pattern" },
      patterns = {
        "mvnw.cmd",
        "VERSION",
        "providers.tf",
        "provider.tf",
        "Makefile",
        "lazy-lock.json",
        "package.json",
        "ansible.cfg",
      },
    })
  end,
}
