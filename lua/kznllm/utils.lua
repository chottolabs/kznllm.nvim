local M = {}
local api = vim.api

--- Inserts content at the current cursor position in the active Neovim buffer.
---
--- This function schedules the insertion to occur on the next event loop iteration,
--- ensuring it doesn't interfere with other ongoing Neovim operations.
---
--- @param content string The text content to be inserted at the cursor position.
---
--- Behavior:
--- 1. Retrieves the current cursor position.
--- 2. Splits the input content into lines.
--- 3. Uses 'undojoin' to prevent creating an undo state for every token.
--- 4. Inserts the content at the cursor position.
--- 5. Moves the cursor to the end of the inserted content.
---
--- Note: This function modifies the current buffer and cursor position.
function M.write_content_at_cursor(content)
  vim.schedule(function()
    local row, col = unpack(api.nvim_win_get_cursor(0))

    local lines = vim.split(content, '\n')

    vim.cmd 'undojoin'
    api.nvim_put(lines, 'c', true, true)
    api.nvim_put({}, 'c', true, true)

    local num_lines = #lines
    local last_line_length = num_lines > 0 and #lines[num_lines] or 0
    local new_row = row + num_lines - 1
    local new_col = (new_row == row) and (col + last_line_length) or last_line_length
    api.nvim_win_set_cursor(0, { new_row, new_col })
  end)
end

function M.write_content_at_end(content)
  vim.schedule(function()
    local current_pos = vim.api.nvim_win_get_cursor(0)
    vim.cmd 'normal! G'

    local srow, erow, scol, ecol = -1, -1, -1, -1
    vim.cmd 'undojoin'
    local lines = vim.split(content, '\n')
    api.nvim_buf_set_text(0, srow, scol, erow, ecol, lines)

    api.nvim_win_set_cursor(0, current_pos)
  end)
end

-- Define the function that creates the buffer and handles the input
function M.create_input_buffer(input_buf_nr, filepath, initial_content)
  input_buf_nr = api.nvim_create_buf(true, false)
  api.nvim_buf_set_name(input_buf_nr, filepath)
  api.nvim_set_option_value('buflisted', true, { buf = input_buf_nr })

  api.nvim_set_current_buf(input_buf_nr)
  api.nvim_set_option_value('wrap', true, { win = 0 })
  api.nvim_set_option_value('linebreak', true, { win = 0 })
  api.nvim_set_option_value('breakindent', true, { win = 0 })

  -- Set initial content
  api.nvim_buf_set_lines(input_buf_nr, 0, -1, false, vim.split(initial_content, '\n'))

  local num_lines = api.nvim_buf_line_count(input_buf_nr)
  api.nvim_win_set_cursor(0, { num_lines, 0 })

  -- Set up autocmd to clear the buffer number when it's deleted
  api.nvim_create_autocmd('BufDelete', {
    buffer = input_buf_nr,
    callback = function()
      input_buf_nr = nil
    end,
  })

  -- Set up key mapping to close the buffer
  api.nvim_buf_set_keymap(input_buf_nr, 'n', 'w', '', {
    noremap = true,
    silent = true,
    callback = function()
      -- Trigger the LLM_Escape event
      api.nvim_exec_autocmds('User', { pattern = 'LLM_Escape' })

      api.nvim_buf_call(input_buf_nr, function()
        vim.cmd 'write'
      end)

      -- Switch to the previous buffer
      api.nvim_command 'buffer #'
    end,
  })

  -- Set up key mapping to close the buffer
  api.nvim_buf_set_keymap(input_buf_nr, 'n', 'q', '', {
    noremap = true,
    silent = true,
    callback = function()
      -- Trigger the LLM_Escape event
      api.nvim_exec_autocmds('User', { pattern = 'LLM_Escape' })

      api.nvim_buf_call(input_buf_nr, function()
        vim.cmd 'bdelete!'
      end)
    end,
  })
end

--- Handle visual selection using the start of the visual selection and current
--- cursor position in the most common modes (i.e. visual, visual lines, visual block)
---
--- Note: visual block is handled the same as visual lines
--- @return string
function M.get_visual_selection()
  -- use this instead of vim.api.nvim_buf_get_mark because it gives the "last" visual selection
  local _, srow, scol = unpack(vim.fn.getpos 'v')
  local _, erow, ecol = unpack(vim.fn.getpos '.')
  local mode = api.nvim_get_mode().mode

  -- Ensure start is before end
  if srow > erow or (srow == erow and scol > ecol) then
    srow, erow = erow, srow
    scol, ecol = ecol, scol
    -- move cursor to the other end of visual selection
    api.nvim_feedkeys('o', 'nx', false)
  end

  local lines = {}
  if mode == 'V' or mode == '\22' then
    lines = api.nvim_buf_get_lines(0, srow - 1, erow, false)
  elseif (srow == erow) and (scol == ecol) then
    lines = {}
  else
    lines = api.nvim_buf_get_text(0, srow - 1, scol - 1, erow - 1, ecol, {})
  end

  local content = table.concat(lines, '\n')

  if content == '' then
    vim.print 'no prompt selection found... use a [v]isual selection mode'
  end

  return content
end

return M
