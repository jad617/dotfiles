return {
  "mfussenegger/nvim-lint",

  opts = {
    linters_by_ft = {
      ansible = { "ansible_lint", "yamllint" },
      python = { "pylint", "pflake8" },
      yaml = { "yamllint" },
    },
  },
}
