if vim.g.loaded_heya then return end
vim.g.loaded_heya = true

vim.api.nvim_create_user_command('Heya', function()
  require('heya').open()
end, { desc = 'Open the port and process dashboard' })
