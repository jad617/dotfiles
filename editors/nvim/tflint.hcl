# tflint config used by Neovim's tflint language server (see lua/config/vars.lua).
# Silences the version-constraint nags; every other recommended rule stays on.

rule "terraform_required_providers" {
  enabled = false
}

rule "terraform_required_version" {
  enabled = false
}
