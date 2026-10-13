local M = {}

M.config = {
  width = 0.85,
  height = 0.7,
  border = 'rounded',
  signal = 'TERM',
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
end

function M.open()
  if not vim.system then
    vim.notify('heya.nvim requires Neovim 0.10 or newer', vim.log.levels.ERROR)
    return
  end
  require('heya.dashboard').open(M.config)
end

return M
