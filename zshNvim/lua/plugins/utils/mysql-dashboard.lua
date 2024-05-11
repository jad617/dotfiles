return {
  "kristijanhusak/vim-dadbod-ui",
  dependencies = {
    { "tpope/vim-dadbod", lazy = true },
    { "kristijanhusak/vim-dadbod-completion", ft = { "sql", "mysql", "plsql" }, lazy = true },
  },
  cmd = {
    "DBUI",
    "DBUIToggle",
    "DBUIAddConnection",
    "DBUIFindBuffer",
  },
  init = function()
    -- Your DBUI configuration
    vim.g.db_ui_use_nerd_fonts = 1
  end,

  config = function()
    vim.api.nvim_create_autocmd({ "FileType" }, {
      pattern = {
        "sql",
        "mysql",
        "plsql",
      },
      callback = function()
        require("cmp").setup.buffer({ sources = { { name = "vim-dadbod-completion" } } })
      end,
    })
  end,
}

------------------------------------------------------------
-- [[ Usage ]]
------------------------------------------------------------

-- in sourced_scrip.sh:

-- nvim_db_INT() {
-- 	ssh -fN -L 3308:DB_HOSTNAME:3306 USER@SSH_JUMPBOX -i /home/USER/.ssh/SSH_KEY
--
-- 	export DB_UI_INTELCOM_INT="mysql://user:password@127.0.0.1:3308/DB_NAME"
--
-- 	nvim -c "DBUI"
--
-- 	trap "terminate_ssh_mysql 3308" EXIT
-- }
--
-- terminate_ssh_mysql() {
-- 	sleep 1
-- 	PID=$(lsof -Pni :$1 | grep '127.0.0.1' | awk '{print $2}')
--
-- 	kill $PID 2>/dev/null
-- }

-- In the terminal:
-- ❯ nvim_db_INT
