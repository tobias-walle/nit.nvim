-- lua/nit/init.lua

---@class NitComment
---@field type string
---@field text string
---@field extmark_id? integer
---@field original_line? string

---@class NitState
---@field comments table<string, table<integer, NitComment>>
---@field initialized boolean

---@class NitOpts
---@field picker? 'snacks'|'telescope'|'quickfix'|'auto'
---@field confirm_clear? boolean
---@field notify_wrap? boolean

local M = {}

local ns = vim.api.nvim_create_namespace('nit')
local augroup = nil

---@type NitState
local state = {
  comments = {},
  initialized = false,
}

---@type NitOpts
local config = {
  picker = 'auto',
  confirm_clear = true,
  notify_wrap = false,
}

local TYPES = { 'NOTE', 'SUGGESTION', 'ISSUE', 'PRAISE' }
local HL = {
  NOTE = 'DiagnosticHint',
  SUGGESTION = 'DiagnosticInfo',
  ISSUE = 'DiagnosticWarn',
  PRAISE = 'DiagnosticOk',
}

-- Utilities

---@param bufnr integer
---@return boolean
local function is_valid_buf(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  local bt = vim.bo[bufnr].buftype
  return bt == '' or bt == 'acwrite'
end

---@param file string
---@return string
local function normalize_path(file)
  if file == '' then return '' end
  local absolute = vim.fn.fnamemodify(file, ':p')

  -- Try to resolve symlinks
  local realpath = vim.loop.fs_realpath(absolute)
  if realpath then
    return realpath
  end

  -- Fallback to absolute path if realpath fails (file doesn't exist yet)
  return absolute
end

---@param msg string
---@param level? integer
local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = 'nit.nvim' })
end

---@return 'snacks'|'telescope'|'quickfix'
local function detect_picker()
  if config.picker ~= 'auto' then
    return config.picker
  end

  local has_snacks, snacks = pcall(require, 'snacks')
  if has_snacks and snacks.picker then return 'snacks' end

  local has_telescope = pcall(require, 'telescope')
  if has_telescope then return 'telescope' end

  return 'quickfix'
end

---@param bufnr integer
---@param lnum integer
---@return string
local function get_line_content(bufnr, lnum)
  local lines = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)
  return lines[1] or ''
end

---@param file string
---@return boolean
local function file_exists(file)
  return vim.fn.filereadable(file) == 1
end

---@param bufnr integer
---@param extmark_id integer
---@return integer? lnum 1-indexed line number or nil if not found
local function get_extmark_lnum(bufnr, extmark_id)
  local mark = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, extmark_id, {})
  if mark and #mark >= 1 then
    return mark[1] + 1
  end
  return nil
end

---@param file string
---@return integer? bufnr
local function get_bufnr_for_file(file)
  for _, bufinfo in ipairs(vim.fn.getbufinfo({ bufloaded = 1 })) do
    if normalize_path(bufinfo.name) == file then
      return bufinfo.bufnr
    end
  end
  return nil
end

-- Core functions

---@param bufnr integer
---@param lnum integer
---@param comment NitComment
---@return integer extmark_id
local function render(bufnr, lnum, comment)
  if comment.extmark_id then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, comment.extmark_id)
  end

  local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns, lnum - 1, 0, {
    virt_lines = {
      { { string.format('  💬 [%s] %s', comment.type, comment.text), HL[comment.type] } },
    },
    virt_lines_above = true,
    sign_text = '●',
    sign_hl_group = HL[comment.type],
    invalidate = true,
    right_gravity = false,
  })

  return extmark_id
end

---@param bufnr integer
local function restore_comments(bufnr)
  if not is_valid_buf(bufnr) then return end

  local file = normalize_path(vim.api.nvim_buf_get_name(bufnr))
  local comments = state.comments[file]
  if not comments then return end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local to_remove = {}

  for lnum, comment in pairs(comments) do
    if lnum > 0 and lnum <= line_count then
      comment.extmark_id = render(bufnr, lnum, comment)
    else
      table.insert(to_remove, lnum)
    end
  end

  for _, lnum in ipairs(to_remove) do
    comments[lnum] = nil
  end
end

---@param bufnr integer
---@return string file, integer lnum
local function get_cursor_context(bufnr)
  local file = normalize_path(vim.api.nvim_buf_get_name(bufnr))
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  return file, lnum
end

---@param file string
---@param use_extmarks? boolean
---@return {lnum: integer, comment: NitComment}[]
local function get_sorted_comments(file, use_extmarks)
  local comments = state.comments[file]
  if not comments then return {} end

  local bufnr = use_extmarks and get_bufnr_for_file(file) or nil
  local result = {}

  for stored_lnum, comment in pairs(comments) do
    local lnum = stored_lnum

    if bufnr and comment.extmark_id then
      local extmark_lnum = get_extmark_lnum(bufnr, comment.extmark_id)
      if extmark_lnum then
        lnum = extmark_lnum
      end
    end

    table.insert(result, { lnum = lnum, comment = comment })
  end

  table.sort(result, function(a, b) return a.lnum < b.lnum end)
  return result
end

---@return {file: string, lnum: integer, comment: NitComment, exists: boolean}[]
local function collect_comments()
  local items = {}

  for file, comments in pairs(state.comments) do
    local exists = file_exists(file)
    local bufnr = get_bufnr_for_file(file)

    for stored_lnum, comment in pairs(comments) do
      local lnum = stored_lnum

      if bufnr and comment.extmark_id then
        local extmark_lnum = get_extmark_lnum(bufnr, comment.extmark_id)
        if extmark_lnum then
          lnum = extmark_lnum
        end
      end

      table.insert(items, {
        file = file,
        lnum = lnum,
        comment = comment,
        exists = exists,
      })
    end
  end

  table.sort(items, function(a, b)
    if a.file ~= b.file then return a.file < b.file end
    return a.lnum < b.lnum
  end)

  return items
end

---@param file string
local function sync_extmark_positions(file)
  local comments = state.comments[file]
  if not comments then return end

  local bufnr = get_bufnr_for_file(file)
  if not bufnr then return end

  local updated = {}
  local collisions = {}

  for stored_lnum, comment in pairs(comments) do
    local lnum = stored_lnum

    if comment.extmark_id then
      local extmark_lnum = get_extmark_lnum(bufnr, comment.extmark_id)
      if extmark_lnum then
        lnum = extmark_lnum
      end
    end

    if updated[lnum] then
      -- Collision detected
      collisions[lnum] = collisions[lnum] or { updated[lnum] }
      table.insert(collisions[lnum], comment)
    else
      updated[lnum] = comment
    end
  end

  -- Resolve collisions by offsetting to next available line
  for lnum, coll_comments in pairs(collisions) do
    for i, comment in ipairs(coll_comments) do
      local offset_lnum = lnum + i - 1
      while updated[offset_lnum] do
        offset_lnum = offset_lnum + 1
      end
      updated[offset_lnum] = comment
    end
  end

  state.comments[file] = updated
end

-- Picker implementations

---@param items table[]
local function list_snacks(items)
  local snacks = require('snacks')

  local picker_items = vim.tbl_map(function(item)
    local prefix = item.exists and '' or '[DELETED] '
    return {
      text = string.format('%s[%s] %s', prefix, item.comment.type, item.comment.text),
      file = item.file,
      pos = { item.lnum, 0 },
      exists = item.exists,
    }
  end, items)

  snacks.picker({
    items = picker_items,
    format = function(picker_item)
      local short = vim.fn.fnamemodify(picker_item.file, ':~:.')
      return string.format('%s:%d %s', short, picker_item.pos[1], picker_item.text)
    end,
    confirm = function(picker, picker_item)
      picker:close()
      if picker_item.exists then
        vim.cmd('edit ' .. vim.fn.fnameescape(picker_item.file))
        vim.api.nvim_win_set_cursor(0, picker_item.pos)
      else
        notify('File no longer exists: ' .. picker_item.file, vim.log.levels.WARN)
      end
    end,
  })
end

---@param items table[]
local function list_telescope(items)
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')

  pickers.new({}, {
    prompt_title = 'Nits',
    finder = finders.new_table({
      results = items,
      entry_maker = function(item)
        local short = vim.fn.fnamemodify(item.file, ':~:.')
        local prefix = item.exists and '' or '[DELETED] '
        local display = string.format('%s%s:%d [%s] %s', prefix, short, item.lnum, item.comment.type, item.comment.text)
        return {
          value = item,
          display = display,
          ordinal = display,
          filename = item.file,
          lnum = item.lnum,
          exists = item.exists,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    previewer = conf.grep_previewer({}),
    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
          if selection.exists then
            vim.cmd('edit ' .. vim.fn.fnameescape(selection.filename))
            vim.api.nvim_win_set_cursor(0, { selection.lnum, 0 })
          else
            notify('File no longer exists: ' .. selection.filename, vim.log.levels.WARN)
          end
        end
      end)
      return true
    end,
  }):find()
end

---@param items table[]
local function list_quickfix(items)
  local qf_items = vim.tbl_map(function(item)
    local prefix = item.exists and '' or '[DELETED] '
    return {
      filename = item.file,
      lnum = item.lnum,
      col = 1,
      text = string.format('%s[%s] %s', prefix, item.comment.type, item.comment.text),
      type = item.comment.type:sub(1, 1),
      valid = item.exists,
    }
  end, items)

  vim.fn.setqflist({}, ' ', {
    title = 'Nits',
    items = qf_items,
  })

  vim.cmd('copen')
end

-- Public API

---@param bufnr? integer
---@param lnum? integer
---@param type string
---@param text string
function M.add(bufnr, lnum, type, text)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not is_valid_buf(bufnr) then
    notify('Cannot add comment to this buffer type', vim.log.levels.WARN)
    return
  end

  local file = normalize_path(vim.api.nvim_buf_get_name(bufnr))
  if file == '' then
    notify('Cannot add comment to unnamed buffer', vim.log.levels.WARN)
    return
  end

  lnum = lnum or vim.api.nvim_win_get_cursor(0)[1]

  -- Validate type parameter
  local valid_type = false
  for _, t in ipairs(TYPES) do
    if t == type then
      valid_type = true
      break
    end
  end
  if not valid_type then
    notify(string.format('Invalid comment type: %s (must be one of: %s)',
      type, table.concat(TYPES, ', ')), vim.log.levels.ERROR)
    return
  end

  sync_extmark_positions(file)

  state.comments[file] = state.comments[file] or {}

  ---@type NitComment
  local comment = {
    type = type,
    text = text,
    extmark_id = nil,
    original_line = vim.trim(get_line_content(bufnr, lnum)),
  }

  local old = state.comments[file][lnum]
  if old and old.extmark_id then
    comment.extmark_id = old.extmark_id
  end

  comment.extmark_id = render(bufnr, lnum, comment)
  state.comments[file][lnum] = comment
end

function M.delete()
  local bufnr = vim.api.nvim_get_current_buf()
  local file, cursor_lnum = get_cursor_context(bufnr)

  sync_extmark_positions(file)

  local comments = state.comments[file]
  if not comments then
    notify('No comment at cursor', vim.log.levels.WARN)
    return
  end

  local found_lnum = nil
  for lnum, comment in pairs(comments) do
    local actual_lnum = lnum
    if comment.extmark_id then
      local extmark_lnum = get_extmark_lnum(bufnr, comment.extmark_id)
      if extmark_lnum then
        actual_lnum = extmark_lnum
      end
    end
    if actual_lnum == cursor_lnum then
      found_lnum = lnum
      break
    end
  end

  if not found_lnum then
    notify('No comment at cursor', vim.log.levels.WARN)
    return
  end

  local comment = comments[found_lnum]
  if comment.extmark_id then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, comment.extmark_id)
  end

  comments[found_lnum] = nil
  notify('Deleted comment')
end

function M.next()
  local bufnr = vim.api.nvim_get_current_buf()
  local file, cursor = get_cursor_context(bufnr)
  local sorted = get_sorted_comments(file, true)

  if #sorted == 0 then
    notify('No comments in buffer')
    return
  end

  for _, item in ipairs(sorted) do
    if item.lnum > cursor then
      vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
      vim.cmd('normal! zz')
      return
    end
  end

  vim.api.nvim_win_set_cursor(0, { sorted[1].lnum, 0 })
  vim.cmd('normal! zz')
  if config.notify_wrap then
    notify('Wrapped to first comment')
  end
end

function M.prev()
  local bufnr = vim.api.nvim_get_current_buf()
  local file, cursor = get_cursor_context(bufnr)
  local sorted = get_sorted_comments(file, true)

  if #sorted == 0 then
    notify('No comments in buffer')
    return
  end

  for i = #sorted, 1, -1 do
    if sorted[i].lnum < cursor then
      vim.api.nvim_win_set_cursor(0, { sorted[i].lnum, 0 })
      vim.cmd('normal! zz')
      return
    end
  end

  vim.api.nvim_win_set_cursor(0, { sorted[#sorted].lnum, 0 })
  vim.cmd('normal! zz')
  if config.notify_wrap then
    notify('Wrapped to last comment')
  end
end

function M.input()
  local target_buf = vim.api.nvim_get_current_buf()
  if not is_valid_buf(target_buf) then
    notify('Cannot add comment to this buffer type', vim.log.levels.WARN)
    return
  end

  local file, target_lnum = get_cursor_context(target_buf)
  if file == '' then
    notify('Cannot add comment to unnamed buffer', vim.log.levels.WARN)
    return
  end

  sync_extmark_positions(file)

  local existing = nil
  local existing_lnum = nil
  if state.comments[file] then
    for lnum, comment in pairs(state.comments[file]) do
      local actual_lnum = lnum
      if comment.extmark_id then
        local extmark_lnum = get_extmark_lnum(target_buf, comment.extmark_id)
        if extmark_lnum then
          actual_lnum = extmark_lnum
        end
      end
      if actual_lnum == target_lnum then
        existing = comment
        existing_lnum = lnum
        break
      end
    end
  end

  local type_idx = 1
  local prefill = ''

  if existing then
    prefill = existing.text
    for i, t in ipairs(TYPES) do
      if t == existing.type then
        type_idx = i
        break
      end
    end
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'nit_input'

  local width = math.min(70, vim.o.columns - 4)
  local height = 5

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'cursor',
    row = 1,
    col = 0,
    width = width,
    height = height,
    style = 'minimal',
    border = 'rounded',
    title = string.format(' [%s] ', TYPES[type_idx]),
    title_pos = 'center',
    footer = ' S-Enter/C-s: submit | Tab: cycle type ',
    footer_pos = 'center',
  })

  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true

  if prefill ~= '' then
    local prefill_lines = vim.split(prefill, '\n')
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, prefill_lines)
    vim.schedule(function()
      if vim.api.nvim_win_is_valid(win) then
        local last_line = #prefill_lines
        local last_col = #prefill_lines[last_line]
        vim.api.nvim_win_set_cursor(win, { last_line, last_col })
      end
    end)
  end

  local closed = false

  local function update_title()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_config(win, {
        title = string.format(' [%s] ', TYPES[type_idx]),
      })
    end
  end

  local function close()
    if closed then return end
    closed = true
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function submit()
    if closed or not vim.api.nvim_buf_is_valid(buf) then return end

    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = vim.trim(table.concat(lines, '\n'))
    close()

    if text == '' then
      if existing and existing_lnum then
        if existing.extmark_id then
          pcall(vim.api.nvim_buf_del_extmark, target_buf, ns, existing.extmark_id)
        end
        state.comments[file][existing_lnum] = nil
        notify('Deleted comment')
      end
      return
    end

    if existing and existing_lnum then
      state.comments[file][existing_lnum] = nil
    end

    M.add(target_buf, target_lnum, TYPES[type_idx], text)
    notify(existing and 'Updated comment' or 'Added comment')
  end

  local kopts = { buffer = buf, nowait = true }

  vim.keymap.set('i', '<Tab>', function()
    type_idx = (type_idx % #TYPES) + 1
    update_title()
  end, kopts)

  vim.keymap.set('i', '<S-Tab>', function()
    type_idx = ((type_idx - 2) % #TYPES) + 1
    update_title()
  end, kopts)

  -- Submit: S-Enter (modern terminals) or C-s (fallback)
  vim.keymap.set('i', '<S-CR>', submit, kopts)
  vim.keymap.set('i', '<C-s>', submit, kopts)
  vim.keymap.set('n', '<CR>', submit, kopts)

  -- Cancel
  vim.keymap.set({ 'i', 'n' }, '<Esc>', close, kopts)
  vim.keymap.set('n', 'q', close, kopts)

  vim.api.nvim_create_autocmd('WinLeave', {
    buffer = buf,
    once = true,
    callback = close,
  })

  vim.cmd('startinsert!')
end

function M.list()
  local items = collect_comments()

  if #items == 0 then
    notify('No comments')
    return
  end

  local picker = detect_picker()

  if picker == 'snacks' then
    list_snacks(items)
  elseif picker == 'telescope' then
    list_telescope(items)
  else
    list_quickfix(items)
  end
end

function M.export()
  local items = collect_comments()

  if #items == 0 then
    notify('No comments to export', vim.log.levels.WARN)
    return
  end

  local deleted_files = {}
  for _, item in ipairs(items) do
    if not item.exists and not deleted_files[item.file] then
      deleted_files[item.file] = true
    end
  end

  if next(deleted_files) then
    local count = vim.tbl_count(deleted_files)
    notify(string.format('Warning: %d file(s) no longer exist', count), vim.log.levels.WARN)
  end

  local lines = {
    'I reviewed your code and have the following comments. Please address them.',
    '',
    'Comment types: ISSUE (problems to fix), SUGGESTION (improvements), NOTE (observations), PRAISE (positive feedback)',
    '',
  }

  for i, item in ipairs(items) do
    local short = vim.fn.fnamemodify(item.file, ':~:.')
    local prefix = item.exists and '' or '[DELETED FILE] '

    local context = ''
    if item.comment.original_line and item.comment.original_line ~= '' then
      local orig = item.comment.original_line
      if #orig > 60 then
        orig = orig:sub(1, 57) .. '...'
      end
      context = string.format('\n   > `%s`', orig)
    end

    local text = item.comment.text:gsub('\n', '\n   ')

    table.insert(lines, string.format(
      '%d. %s**[%s]** `%s:%d` - %s%s',
      i, prefix, item.comment.type, short, item.lnum, text, context
    ))
  end

  local export_text = table.concat(lines, '\n')

  -- Try clipboard registers in order of preference
  local success = false
  local registers = { '+', '*', '"' }  -- system clipboard, selection, unnamed

  for _, reg in ipairs(registers) do
    local ok = pcall(vim.fn.setreg, reg, export_text)
    if ok then
      success = true
      if reg == '+' or reg == '*' then
        notify(string.format('Exported %d comments to system clipboard', #items))
      else
        notify(string.format('Exported %d comments to register "%s" (clipboard unavailable)', #items, reg))
      end
      break
    end
  end

  if not success then
    notify('Failed to export: clipboard unavailable. Install +clipboard support or xclip/xsel',
      vim.log.levels.ERROR)
  end
end

function M.clear()
  local total = M.count()

  if total == 0 then
    notify('No comments to clear')
    return
  end

  local function do_clear()
    for file in pairs(state.comments) do
      for _, bufinfo in ipairs(vim.fn.getbufinfo({ bufloaded = 1 })) do
        if normalize_path(bufinfo.name) == file then
          vim.api.nvim_buf_clear_namespace(bufinfo.bufnr, ns, 0, -1)
        end
      end
    end
    state.comments = {}
    notify(string.format('Cleared %d comments', total))
  end

  if config.confirm_clear then
    vim.ui.select({ 'Yes', 'No' }, {
      prompt = string.format('Clear all %d comments?', total),
    }, function(choice)
      if choice == 'Yes' then
        do_clear()
      end
    end)
  else
    do_clear()
  end
end

---Get all comments for a file or all files
---@param file? string Optional file path (normalized). If nil, returns all comments.
---@return table<string, table<integer, NitComment>>
function M.get_comments(file)
  if file then
    local normalized = normalize_path(file)
    return vim.deepcopy(state.comments[normalized] or {})
  else
    return vim.deepcopy(state.comments)
  end
end

---@return integer
function M.count()
  local count = 0
  for _, comments in pairs(state.comments) do
    count = count + vim.tbl_count(comments)
  end
  return count
end

---@return table<string, integer>
function M.count_by_file()
  local counts = {}
  for file, comments in pairs(state.comments) do
    local short = vim.fn.fnamemodify(file, ':~:.')
    counts[short] = vim.tbl_count(comments)
  end
  return counts
end

---@param opts? NitOpts
function M.setup(opts)
  if state.initialized then
    return
  end

  opts = opts or {}
  vim.validate({
    opts = { opts, 'table' },
    picker = { opts.picker, 'string', true },
    confirm_clear = { opts.confirm_clear, 'boolean', true },
    notify_wrap = { opts.notify_wrap, 'boolean', true },
  })

  config = vim.tbl_deep_extend('force', config, opts)

  -- Create augroup
  augroup = vim.api.nvim_create_augroup('nit', { clear = true })

  vim.api.nvim_create_autocmd('BufWinEnter', {
    group = augroup,
    callback = function(ev)
      restore_comments(ev.buf)
    end,
  })

  local commands = {
    NitAdd = { fn = M.input, desc = 'Add or edit comment' },
    NitDelete = { fn = M.delete, desc = 'Delete comment at cursor' },
    NitList = { fn = M.list, desc = 'List all comments' },
    NitExport = { fn = M.export, desc = 'Export comments to clipboard' },
    NitClear = { fn = M.clear, desc = 'Clear all comments' },
    NitNext = { fn = M.next, desc = 'Go to next comment' },
    NitPrev = { fn = M.prev, desc = 'Go to previous comment' },
  }

  for name, cmd in pairs(commands) do
    vim.api.nvim_create_user_command(name, cmd.fn, { desc = cmd.desc })
  end

  state.initialized = true
end

return M
