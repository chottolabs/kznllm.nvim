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
function M.write_content_at_cursor(content, win_id)
  vim.schedule(function()
    local row, col = unpack(api.nvim_win_get_cursor(win_id))
    local win_width = vim.api.nvim_win_get_width(win_id) - 4

    local lines = {}
    local current_line = api.nvim_buf_get_lines(0, row - 1, row, true)[1]
    local remaining_width = win_width - #current_line:sub(1, col)

    for _, line in ipairs(vim.split(content, '\n')) do
      if remaining_width > 0 then
        table.insert(lines, line:sub(1, remaining_width))
        line = line:sub(remaining_width + 1)
      end

      while #line > 0 do
        if #line > win_width then
          table.insert(lines, line:sub(1, win_width))
          line = line:sub(win_width + 1)
        else
          table.insert(lines, line)
          line = ''
        end
      end

      remaining_width = win_width
    end

    vim.cmd 'undojoin'
    api.nvim_put(lines, 'c', true, true)
    api.nvim_put({}, 'c', true, true)

    local num_lines = #lines
    local last_line_length = #lines[num_lines]
    local new_row = row + num_lines - 1
    local new_col = (new_row == row) and (col + last_line_length) or last_line_length
    api.nvim_win_set_cursor(win_id, { new_row, new_col })
  end)
end

return M
