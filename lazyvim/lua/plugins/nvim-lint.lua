return {
  "mfussenegger/nvim-lint",

  opts = {
    linters_by_ft = {
      ansible = { "ansible_lint", "yamllint" },
      go = { "golangcilint" },
      python = { "pylint", "pflake8" },
      yaml = { "yamllint" },
    },
  },
}
