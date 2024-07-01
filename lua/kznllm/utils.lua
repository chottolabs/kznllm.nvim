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

    -- avoid flooding undo history
    vim.cmd 'undojoin'
    api.nvim_put(lines, 'c', true, true)

    local num_lines = #lines
    local last_line_length = #lines[num_lines]
    api.nvim_win_set_cursor(0, { row + num_lines - 1, col + last_line_length })
  end)
end

return M
