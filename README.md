# nit.nvim

A Neovim plugin for leaving review comments in code and exporting them as structured feedback for AI agents.

- Typed comments (ISSUE, NOTE) rendered as virtual text
- Comments follow line movements automatically via extmarks
- Export all comments as LLM-optimized markdown in one shot
- Navigate between comments with `:NitNext` / `:NitPrev`
- Works with Snacks, Telescope, or quickfix pickers

## Getting Started

1. Install with your plugin manager (see Installation section for keymaps)
2. Call `require('nit').setup()` in your config
3. Review code and add comments with `:NitAdd` (or your keymap)
4. Export all comments with `:NitExport` (or your keymap)
5. Paste into your AI agent, let it fix everything at once

## Installation

```lua
-- lazy.nvim
{
  'tobias-walle/nit.nvim',
  config = function()
    require('nit').setup()
  end,
  keys = {
    { '<leader>nc', function() require('nit').input() end, desc = 'Add/edit nit' },
    { '<leader>nd', function() require('nit').delete() end, desc = 'Delete nit' },
    { '<leader>nl', function() require('nit').list() end, desc = 'List nits' },
    { '<leader>ne', function() require('nit').export() end, desc = 'Export nits' },
    { '<leader>nx', function() require('nit').clear() end, desc = 'Clear all nits' },
    { ']r', function() require('nit').next() end, desc = 'Next nit' },
    { '[r', function() require('nit').prev() end, desc = 'Prev nit' },
  },
}
```

## Comment Input

Use `:NitAdd` (or your configured keymap) to open the input window:

| Key | Action |
|-----|--------|
| `Enter` | New line |
| `S-Enter` / `C-s` | Submit comment |
| `Tab` / `S-Tab` | Cycle comment type |
| `Esc` / `q` | Cancel |

Submit empty text on an existing comment to delete it.

## Configuration

All options are optional.

```lua
require('nit').setup({
  picker = 'auto',       -- 'snacks' | 'telescope' | 'quickfix' | 'auto'
  confirm_clear = true,  -- Ask before clearing all comments
})
```

### Picker Selection

The `picker` option controls which UI is used for listing comments:

- `'auto'` (default): Tries Snacks → Telescope → Quickfix
- `'snacks'`: Requires [snacks.nvim](https://github.com/folke/snacks.nvim)
- `'telescope'`: Requires [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- `'quickfix'`: Always available, no dependencies

## Export Format

Exported markdown is optimized for LLM consumption with context included:

```markdown
I reviewed your code and have the following comments. Please address them.

Comment types: ISSUE (problems to fix), NOTE (observations)

1. **[ISSUE]** `src/auth.lua:42` - Magic number should be a constant
   > `if attempts > 5 then`
2. **[NOTE]** `src/auth.lua:87` - This pattern appears in multiple places
```

Each comment includes:
- Type (ISSUE, NOTE)
- File path and line number
- Your comment text
- Original line context (truncated to 60 chars)

## Statusline Integration

```lua
-- Example statusline component
local count = require('nit').count()
if count > 0 then
  return '💬 ' .. count
end

-- Or per-file counts
local counts = require('nit').count_by_file()
-- Returns: { ["src/foo.lua"] = 3, ["src/bar.lua"] = 1 }
```

## Implementation Notes

- Comments are stored in-memory only (no persistence across sessions)
- Rendered using extmarks with `virt_lines` and sign column indicators
- Line tracking handled automatically by extmark API
- Only works on normal file buffers (rejects special buffer types)
- Comments beyond EOF are silently skipped on buffer restore
- Deleted files are detected on export with warnings

## Development

To work on nit.nvim locally, replace the GitHub URL with a local path in your lazy.nvim config:

```lua
{
  dir = '~/Projects/nit.nvim',  -- Instead of 'tobias-walle/nit.nvim'
  -- ... rest of config stays the same
}
```

## License

MIT
