local api = vim.api
local process = require('heya.process')
local M = {}
local active

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = 'heya.nvim' })
end

local function valid(state)
  return active == state and api.nvim_buf_is_valid(state.buf) and api.nvim_win_is_valid(state.win)
end

local function close(state)
  if active ~= state then return end
  active = nil
  for _, win in ipairs({ state.search_win, state.win }) do
    if api.nvim_win_is_valid(win) then api.nvim_win_close(win, true) end
  end
  for _, buf in ipairs({ state.search_buf, state.buf }) do
    if api.nvim_buf_is_valid(buf) then api.nvim_buf_delete(buf, { force = true }) end
  end
  if api.nvim_win_is_valid(state.previous_win) then api.nvim_set_current_win(state.previous_win) end
end

local function format(row)
  return string.format('%-6d %-5s %-8d %-24s %s', row.port, row.protocol, row.pid, row.command, row.address)
end

-- Only exact original rows can be retained. Arbitrary edits must never become kills.
local function collect(state)
  local remaining = {}
  for _, line in ipairs(api.nvim_buf_get_lines(state.buf, 0, -1, false)) do
    if line ~= '' then
      if not state.rendered[line] then
        notify('Only delete rows. Undo other edits before searching, refreshing, or writing.', vim.log.levels.ERROR)
        return false
      end
      remaining[line] = true
    end
  end
  for line, row in pairs(state.rendered) do
    if not remaining[line] then state.pending[row.pid] = row.command end
  end
  return true
end

local function render(state)
  if not valid(state) then return end
  local query = api.nvim_buf_get_lines(state.search_buf, 0, 1, false)[1] or ''
  local candidates = {}
  for _, row in ipairs(state.rows) do
    if not state.pending[row.pid] then candidates[#candidates + 1] = format(row) end
  end
  local lines = query == '' and candidates or vim.fn.matchfuzzy(candidates, query)
  local by_line = {}
  for _, row in ipairs(state.rows) do by_line[format(row)] = row end
  state.rendered = {}
  for _, line in ipairs(lines) do state.rendered[line] = by_line[line] end
  api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modified = false
  local count = vim.tbl_count(state.pending)
  api.nvim_win_set_config(state.win, {
    title = string.format(' Heya · %d sockets · %d pending kills ', #lines, count),
    title_pos = 'center',
  })
end

local function refresh(state)
  if state.busy or not collect(state) then return end
  state.busy = true
  process.list(function(err, rows)
    if not valid(state) then return end
    state.busy = false
    if err then notify(err, vim.log.levels.ERROR); return end
    state.rows = rows
    render(state)
  end)
end

local function save(state)
  if state.busy then notify('Please wait for the current operation.'); return end
  if not collect(state) then return end
  if next(state.pending) == nil then
    vim.bo[state.buf].modified = false
    notify('No processes marked for termination.')
    return
  end
  state.busy = true
  process.list(function(err, rows)
    if not valid(state) then return end
    if err then state.busy = false; notify(err, vim.log.levels.ERROR); return end
    local current, targets = {}, {}
    for _, row in ipairs(rows) do current[row.pid] = row.command end
    for pid, command in pairs(state.pending) do
      if current[pid] == command then targets[#targets + 1] = pid
      else state.pending[pid] = nil end
    end
    local index, killed = 0, 0
    local function next_target()
      if not valid(state) then return end
      index = index + 1
      local pid = targets[index]
      if not pid then
        state.busy = false
        notify(string.format('Sent SIG%s to %d process(es).', state.config.signal, killed))
        render(state)
        refresh(state)
        return
      end
      process.kill(pid, state.config.signal, function(kill_err)
        if kill_err then notify(string.format('PID %d: %s', pid, kill_err), vim.log.levels.ERROR)
        else state.pending[pid] = nil; killed = killed + 1 end
        next_target()
      end)
    end
    next_target()
  end)
end

function M.open(config)
  if active and valid(active) then api.nvim_set_current_win(active.win); return end
  local width = math.max(1, math.min(vim.o.columns - 4, math.floor(vim.o.columns * config.width)))
  local height = math.max(1, math.min(vim.o.lines - 8, math.floor(vim.o.lines * config.height)))
  local top = math.max(0, math.floor((vim.o.lines - height - 5) / 2))
  local left = math.max(0, math.floor((vim.o.columns - width) / 2))
  local state = {
    config = vim.deepcopy(config), rows = {}, pending = {}, rendered = {},
    previous_win = api.nvim_get_current_win(),
    buf = api.nvim_create_buf(false, true), search_buf = api.nvim_create_buf(false, true),
  }
  vim.bo[state.buf].buftype = 'acwrite'
  vim.bo[state.buf].bufhidden = 'wipe'
  vim.bo[state.buf].swapfile = false
  vim.bo[state.buf].filetype = 'heya'
  api.nvim_buf_set_name(state.buf, 'heya://ports')
  state.search_win = api.nvim_open_win(state.search_buf, false, {
    relative = 'editor', row = top, col = left, width = width, height = 1,
    style = 'minimal', border = config.border, title = ' Search command or port ', title_pos = 'left',
  })
  state.win = api.nvim_open_win(state.buf, true, {
    relative = 'editor', row = top + 3, col = left, width = width, height = height,
    style = 'minimal', border = config.border,
    title = ' Heya ', footer = ' / search · dd delete · :w kill · R refresh · q close ',
    footer_pos = 'center',
  })
  active = state
  vim.wo[state.win].wrap = false
  vim.wo[state.win].cursorline = true
  vim.bo[state.search_buf].bufhidden = 'wipe'
  local function map(buf, mode, key, action)
    vim.keymap.set(mode, key, action, { buffer = buf, silent = true, nowait = true })
  end
  local function focus_results()
    vim.cmd('stopinsert')
    if valid(state) then api.nvim_set_current_win(state.win) end
  end
  map(state.buf, 'n', '/', function()
    if not collect(state) then return end
    api.nvim_set_current_win(state.search_win)
    vim.cmd('startinsert!')
  end)
  map(state.buf, 'n', 'q', function() close(state) end)
  map(state.buf, 'n', '<Esc>', function() close(state) end)
  map(state.buf, 'n', 'R', function() refresh(state) end)
  map(state.search_buf, { 'i', 'n' }, '<CR>', focus_results)
  map(state.search_buf, { 'i', 'n' }, '<Esc>', focus_results)
  map(state.search_buf, 'n', 'q', function() close(state) end)
  api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    buffer = state.search_buf, callback = function()
      if valid(state) and collect(state) then render(state) end
    end,
  })
  api.nvim_create_autocmd('BufWriteCmd', { buffer = state.buf, callback = function() save(state) end })
  api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(state.win), once = true,
    callback = function() vim.schedule(function() close(state) end) end,
  })
  refresh(state)
end

return M
