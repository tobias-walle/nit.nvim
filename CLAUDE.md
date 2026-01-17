# CLAUDE.md

## Project: nit.nvim

A minimal Neovim plugin for annotating code with review comments. Designed for AI-assisted development workflows where you review AI-generated changes, leave comments, and export structured feedback for the AI to process in one pass.

## Core Concept

- Add typed comments (NOTE, SUGGESTION, ISSUE, PRAISE) to any line in any buffer
- Comments render as virtual text via extmarks (non-destructive)
- Export all comments as structured markdown optimized for LLM consumption
- Navigate between comments with ]r / [r

## Workflow

1. AI makes changes → open in diffview or similar
2. Navigate code, press `<leader>nc` to add comments
3. `<leader>ne` exports to clipboard
4. Paste into Claude/Cursor/etc → AI addresses all feedback in one pass
5. `:NitClear` and repeat

## Technical Decisions

- **In-memory only**: No persistence across sessions. Review sessions are ephemeral.
- **Extmarks for rendering**: Comments follow line movements automatically
- **Extmark position syncing**: Before operations, sync extmark positions back to state to handle line insertions/deletions
- **Picker fallback**: Snacks → Telescope → Quickfix
- **Buffer validation**: Only works on normal file buffers, not special buffers

## File Structure

```
nit.nvim/
├── lua/nit/
│   ├── init.lua    # Main implementation, ~850 lines
│   └── health.lua  # Healthcheck implementation
├── doc/
│   └── nit.txt     # Vim help documentation
├── README.md
└── CLAUDE.md       # This file
```

## Key APIs Used

- `vim.api.nvim_buf_set_extmark()` with `virt_lines`, `sign_text`, `invalidate`
- `vim.api.nvim_buf_get_extmark_by_id()` to read current position
- `vim.api.nvim_create_autocmd()` with augroup for BufWinEnter
- `vim.ui.select()` for confirmation dialogs
- `vim.fn.setreg('+', ...)` for clipboard

## Commands

- `:NitAdd` - Add/edit comment at cursor
- `:NitDelete` - Delete comment at cursor
- `:NitList` - List all comments (picker)
- `:NitExport` - Copy to clipboard
- `:NitClear` - Clear all (with confirmation)
- `:NitNext` / `:NitPrev` - Navigate

Note: Keymaps are user-configured. See README.md for recommended setup.

## Best Practices

### Code Organization

- Keep everything in a single file (`lua/nit/init.lua`) for simplicity
- Use clear function names and LSP annotations (`---@class`, `---@param`, `---@return`)
- Group related functions together (utilities, core functions, pickers, public API)

### State Management

- State is module-local, not global
- Always sync extmark positions before operations that depend on line numbers
- Use `pcall()` when deleting extmarks (they might already be gone)

### Error Handling

- Validate buffer types before operations (`is_valid_buf()`)
- Show user-friendly notifications via `notify()` function
- Gracefully handle missing files, deleted buffers, etc.

### Testing Changes

- Test with all three pickers (Snacks, Telescope, quickfix)
- Verify extmark tracking with line insertions/deletions
- Test edge cases: deleted files, comments beyond EOF, special buffers

## Commit Messages

Use short, single-line conventional commits:

```
feat: add multi-line comment support
fix: extmark not updating after undo
docs: update installation instructions
refactor: simplify picker detection
chore: update dependencies
```

Format: `type: short description` (no period, lowercase)

Common types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`

## Edge Cases Handled

- Line numbers shift after edits → extmark tracking
- File deleted/renamed → detected on export, shown in picker
- Accidental clear → confirmation prompt
- Empty submit while editing → deletes the comment
- Comments beyond EOF → skipped on restore
- Special buffer types → rejected

## Testing Suggestions

- Add comment, insert lines above, verify comment moves
- Add comment, delete the line, verify comment removed
- Export with deleted file, verify warning
- Test with snacks, telescope, and quickfix fallback
