local M = {}

-- lsof's field output avoids depending on column widths or command-name truncation.
function M.parse(output, protocol)
  local rows, pid, command = {}, nil, nil
  for line in output:gmatch('[^\r\n]+') do
    local field, value = line:sub(1, 1), line:sub(2)
    if field == 'p' then
      pid, command = tonumber(value), nil
    elseif field == 'c' then
      command = value
    elseif field == 'n' and pid and command then
      local port = value:match(':(%d+)$')
      if port then
        rows[#rows + 1] = {
          pid = pid,
          command = command,
          port = tonumber(port),
          protocol = protocol,
          address = value,
          id = table.concat({ pid, protocol, value }, ':'),
        }
      end
    end
  end
  return rows
end

function M.list(callback)
  if vim.fn.executable('lsof') ~= 1 then
    callback('lsof is required. Install it and make sure it is on your PATH.')
    return
  end
  local rows, errors, remaining = {}, {}, 2
  local queries = {
    { protocol = 'TCP', args = { 'lsof', '-nP', '-iTCP', '-sTCP:LISTEN', '-Fpcn' } },
    { protocol = 'UDP', args = { 'lsof', '-nP', '-iUDP', '-Fpcn' } },
  }
  for _, query in ipairs(queries) do
    vim.system(query.args, { text = true }, function(result)
      vim.schedule(function()
        -- lsof exits with 1 when there are no matching sockets.
        if result.code ~= 0 and not (result.code == 1 and (result.stderr or '') == '') then
          errors[#errors + 1] = vim.trim(result.stderr or 'lsof failed')
        end
        vim.list_extend(rows, M.parse(result.stdout or '', query.protocol))
        remaining = remaining - 1
        if remaining == 0 then
          local unique, seen = {}, {}
          for _, row in ipairs(rows) do
            if not seen[row.id] then
              seen[row.id] = true
              unique[#unique + 1] = row
            end
          end
          table.sort(unique, function(a, b)
            if a.port ~= b.port then return a.port < b.port end
            return a.id < b.id
          end)
          callback(#errors > 0 and table.concat(errors, '\n') or nil, unique)
        end
      end)
    end)
  end
end

function M.kill(pid, signal, callback)
  vim.system({ 'kill', '-' .. signal, tostring(pid) }, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        callback(nil)
      else
        callback(vim.trim(result.stderr or 'kill failed'))
      end
    end)
  end)
end

return M
