-- stylua: ignore
return
{
  "neovim/nvim-lspconfig",
  enabled = true,
  opts = {
    -- autoformat = false,
    -- format = {
    --   formatting_options = nil,
    --   timeout_ms = nil,
    -- },
    servers = {
      -- bashls = {},
      ansiblels = {},
      cssls = {},
      dockerls = {}, -- docker
      helm_ls = {
        settings = {
          ['helm-ls'] = {
            yamlls = {
              path = "yaml-language-server",
            }
          }
        }
      },
      yamlls = {},
      html = {},
      golangci_lint_ls = {}, -- golangci
      pyright = {},
      tflint = {
          filetypes = {"terraform"},
          pattern = {"*.tf"},
        }, -- terraform docs
      terraformls = {
          filetypes = {"terraform"},
          pattern = {"*.tf"},
      }, -- terraform
      lua_ls = { -- lua
        settings = {
          Lua = {
            diagnostics = {
              globals = { "vim" }, -- removes warning: 'Global vim is undefined'
            },
          },
        },
      },
      gopls = {
        settings = {
          gopls = {
            -- gofumpt = true,
            codelenses = {
              gc_details = false,
              generate = true,
              regenerate_cgo = true,
              run_govulncheck = true,
              test = true,
              tidy = true,
              upgrade_dependency = true,
              vendor = true,
            },
            hints = {
              assignVariableTypes = true,
              compositeLiteralFields = true,
              compositeLiteralTypes = true,
              constantValues = true,
              functionTypeParameters = true,
              parameterNames = true,
              rangeVariableTypes = true,
            },
            analyses = {
              fieldalignment = true,
              nilness = true,
              unusedparams = true,
              unusedwrite = true,
              useany = true,
            },
            usePlaceholders = true,
            completeUnimported = true,
            staticcheck = true,
            directoryFilters = { "-.git", "-.vscode", "-.idea", "-.vscode-test", "-node_modules" },
            -- semanticTokens = true,
          },
        },
      },
    },
  },
}
