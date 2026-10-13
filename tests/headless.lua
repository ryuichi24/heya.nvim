-- Run: nvim --headless -u NONE -l tests/headless.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.cmd('runtime plugin/heya.lua')

local process = require('heya.process')
local parsed = process.parse('p123\ncnode\nn127.0.0.1:3000\nn[::1]:3000\n', 'TCP')
assert(#parsed == 2 and parsed[1].port == 3000 and parsed[2].pid == 123)
assert(#process.parse('p123\ncnode\nn*:service\n', 'TCP') == 0)

local original_list, original_kill = process.list, process.kill
local rows = {
  { pid = 123, command = 'node', port = 3000, protocol = 'TCP', address = '*:3000' },
  { pid = 123, command = 'node', port = 3001, protocol = 'TCP', address = '*:3001' },
  { pid = 456, command = 'python', port = 8000, protocol = 'TCP', address = '*:8000' },
}
local killed = {}
process.list = function(callback) callback(nil, rows) end
process.kill = function(pid, signal, callback)
  assert(signal == 'TERM')
  killed[#killed + 1] = pid
  local remaining = {}
  for _, row in ipairs(rows) do
    if row.pid ~= pid then remaining[#remaining + 1] = row end
  end
  rows = remaining
  callback(nil)
end

vim.cmd('Heya')
local results = vim.api.nvim_get_current_buf()
assert(#vim.api.nvim_buf_get_lines(results, 0, -1, false) == 3)
vim.api.nvim_buf_set_lines(results, 0, 1, false, {})
local search
for _, win in ipairs(vim.api.nvim_list_wins()) do
  local buf = vim.api.nvim_win_get_buf(win)
  if win ~= vim.api.nvim_get_current_win() and vim.api.nvim_win_get_config(win).relative ~= '' then
    search = buf
  end
end
assert(search)
vim.api.nvim_buf_set_lines(search, 0, -1, false, { 'python' })
vim.api.nvim_exec_autocmds('TextChanged', { buffer = search })
local filtered = vim.api.nvim_buf_get_lines(results, 0, -1, false)
assert(#filtered == 1 and filtered[1]:match('python'))
vim.cmd('write')
assert(#killed == 1 and killed[1] == 123, 'hidden deletions must be saved once per PID')
vim.cmd('write')
assert(#killed == 1, 'refresh must not requeue terminated processes')
vim.api.nvim_buf_set_lines(results, 0, -1, false, { 'edited text' })
pcall(vim.cmd, 'write')
assert(#killed == 1, 'text edits must not terminate processes')
vim.cmd('close!')
vim.wait(100, function() return not vim.api.nvim_buf_is_valid(search) end)
assert(not vim.api.nvim_buf_is_valid(search), 'closing dashboard must clean up search')
process.list, process.kill = original_list, original_kill

-- Verify discovery and termination against a real disposable TCP listener.
local output = ''
local child = vim.system({ 'python3', '-u', '-c',
  'import socket,time; s=socket.socket(); s.bind(("127.0.0.1",0)); s.listen(); print(s.getsockname()[1],flush=True); time.sleep(30)',
}, { stdout = function(_, data) if data then output = output .. data end end })
local ok, err = pcall(function()
  assert(vim.wait(5000, function() return output:match('%d+\n') ~= nil end), 'listener did not start')
  local port = tonumber(output:match('%d+'))
  local finished, list_error, discovered
  process.list(function(error, items) list_error, discovered, finished = error, items, true end)
  assert(vim.wait(10000, function() return finished end), 'discovery timed out')
  assert(not list_error, list_error)
  local found = false
  for _, row in ipairs(discovered) do
    if row.pid == child.pid and row.port == port then found = true end
  end
  assert(found, 'listener missing from lsof discovery')
  local terminated, kill_error
  process.kill(child.pid, 'TERM', function(error) kill_error, terminated = error, true end)
  assert(vim.wait(5000, function() return terminated end), 'termination timed out')
  assert(not kill_error, kill_error)
end)
child:kill(15)
child:wait(5000)
assert(ok, err)
print('heya: all checks passed')
