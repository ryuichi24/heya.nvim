# heya.nvim

A floating Neovim dashboard for busy ports and the processes using them. Fuzzy
search by command or port, navigate with Vim motions, delete rows, and write the
buffer to terminate the corresponding processes.

## Requirements

- Neovim 0.10+
- macOS or Linux with `lsof` and `kill` on your PATH

The dashboard lists TCP listeners and bound UDP sockets visible to your user.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'ryuichi24/heya.nvim',
  cmd = 'Heya',
  keys = {
    { '<leader>hp', '<cmd>Heya<cr>', desc = 'Ports and processes' },
  },
  opts = {},
}
```

For a local checkout:

```lua
{
  dir = '~/dev/personal/projects/heya.nvim',
  cmd = 'Heya',
  opts = {},
}
```

No setup call is required with the default options. You can also create your own
keymap directly:

```lua
vim.keymap.set('n', '<leader>hp', '<cmd>Heya<cr>', { desc = 'Ports and processes' })
```

## Usage

1. Run `:Heya`.
2. Press `/` to focus the search field. Results update as you type; clear the
   field to show all sockets. Press Enter or Escape to return to the results.
3. Navigate with `j`, `k`, `gg`, `G`, and other normal Vim motions.
4. Delete a row with `dd`, or select several rows and press `d`.
5. Run `:w` to send `SIGTERM` to the marked processes.

Rows show **port, protocol, PID, command, and address**. Search fuzzy-matches the
whole row, so PID and address searches work too.

| Key / command | Action |
| --- | --- |
| `/` | Edit search |
| Enter / Escape in search | Focus results |
| `dd` / visual `d` | Mark processes by deleting rows |
| `u` | Undo a deletion before changing the search or refreshing |
| `:w` | Terminate marked processes |
| `R` | Refresh sockets |
| `q` / Escape in results | Close and discard pending deletions |

Deleting any socket row marks its entire process, including its other ports.
Pending deletions persist when you change the search or refresh. Writing applies
all pending deletions, including those outside the current search. Each PID is
signaled once. Processes that no longer own a socket, or whose command has
changed, are skipped. Failed signals are reported and remain pending for retry.

The result buffer is editable, but only row deletion is supported: undo text
edits before searching, refreshing, or writing. Closing without writing discards
the pending operations. A signal terminates the process rather than just closing
one socket; services with automatic restart may reappear.

## Configuration

```lua
require('heya').setup({
  width = 0.85,       -- fraction of editor columns
  height = 0.7,       -- fraction of editor lines
  border = 'rounded',
  signal = 'TERM',    -- use 'KILL' for forced termination
})
```

Process discovery is asynchronous. The plugin runs commands as the current user
and reports permission errors when a process cannot be terminated.

## Development

Run the headless checks with:

```sh
nvim --headless -u NONE -l tests/headless.lua
```

The checks exercise filtering, pending deletions, write behavior, window cleanup,
and discovery/termination of a disposable TCP listener. The listener check also
requires Python 3.
