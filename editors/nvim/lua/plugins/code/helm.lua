return {
  -- Filetype detection for Helm chart templates (*.yaml / *.tpl inside templates/)
  -- helm_ls LSP is configured in vars.lua; treesitter helm parser handles highlighting
  { "towolf/vim-helm", ft = "helm" },
}
