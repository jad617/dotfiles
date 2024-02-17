return {
  "nvim-neo-tree/neo-tree.nvim",
  opts = {
    close_if_last_window = true,
    window = {
      mappings = {
        ["<C-v>"] = "open_vsplit",
        ["<C-x>"] = "open_split",
      },
    },
  },
}
