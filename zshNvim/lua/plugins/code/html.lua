  -- html auto reload
return {
  'barrett-ruth/live-server.nvim',
  build = {
    'sudo npm install -g live-server',
    'sudo yarn global add live-server'
  },
  config = true,
}

