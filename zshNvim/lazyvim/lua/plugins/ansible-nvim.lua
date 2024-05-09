return {
  "mfussenegger/nvim-ansible",
  keys = {
    {
      "<leader>tr",
      function()
        require("ansible").run()
      end,
      silent = true,
    },
  },
}
