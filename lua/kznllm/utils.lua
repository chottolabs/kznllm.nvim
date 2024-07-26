local Job = require 'plenary.job'
local M = {}
local api = vim.api

-- Specify the path where you want to save the file
M.CACHE_DIRECTORY = vim.fn.stdpath 'cache' .. '/kznllm/history/'

-- Default lazy plugin location... not sure how to get the plugin dir neatly, will likely need to be overwritten by user in init.lua
M.TEMPLATE_DIRECTORY = vim.fn.stdpath 'data' .. '/lazy/kznllm/templates/'

local success, error_message

success, error_message = os.execute('mkdir -p "' .. M.CACHE_DIRECTORY .. '"')
if not success then
  print('Error creating directory: ' .. error_message)
  return
end

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

    local num_lines = #lines
    local last_line_length = num_lines > 0 and #lines[num_lines] or 0
    local new_row = row + num_lines - 1
    local new_col = (new_row == row) and (col + last_line_length) or last_line_length
    api.nvim_win_set_cursor(0, { new_row, new_col })
  end)
end

---@param content string
function M.write_content_at_end(content)
  vim.schedule(function()
    local current_pos = vim.api.nvim_win_get_cursor(0)

    local srow, erow, scol, ecol = -1, -1, -1, -1
    vim.cmd 'undojoin'
    local lines = vim.split(content, '\n')
    api.nvim_buf_set_text(0, srow, scol, erow, ecol, lines)

    vim.cmd 'normal! G'
    api.nvim_win_set_cursor(0, current_pos)
  end)
end

---Renders a prompt template using minijinja-cli and returns the rendered lines
---
---@param prompt_template_filename string
---@param prompt_args { user_prompt_args: { code_snippet?: string, supporting_context?: string, user_query?:string } }
---@return string[]
function M.make_prompt_from_template(prompt_template_filename, prompt_args)
  local json_data = vim.json.encode(prompt_args)
  local active_job = Job:new {
    command = 'minijinja-cli',
    args = { '-f', 'json', vim.fn.expand(M.TEMPLATE_DIRECTORY) .. prompt_template_filename, '-' },
    writer = json_data,
    on_stderr = function(message, _)
      error(message, 1)
    end,
  }

  active_job:sync()
  return active_job:result()
end

local function make_scratch_buffer(prompt_args)
  local scratch_buf_nr = api.nvim_create_buf(false, true)

  -- Set buffer options
  api.nvim_set_option_value('buftype', 'nofile', { buf = scratch_buf_nr })
  api.nvim_set_option_value('bufhidden', 'hide', { buf = scratch_buf_nr })
  api.nvim_set_option_value('swapfile', false, { buf = scratch_buf_nr })
  api.nvim_set_option_value('filetype', 'xml', { buf = scratch_buf_nr })

  -- Switch to the new buffer
  api.nvim_set_current_buf(scratch_buf_nr)

  -- Enable text wrapping
  api.nvim_set_option_value('wrap', true, { win = 0 })
  api.nvim_set_option_value('linebreak', true, { win = 0 })
  api.nvim_set_option_value('breakindent', true, { win = 0 })

  local rendered_debug_content = M.make_prompt_from_template('debug_template.xml.jinja', prompt_args)
  api.nvim_buf_set_lines(scratch_buf_nr, -2, -2, false, rendered_debug_content)
  vim.cmd 'normal! gg'

  -- Set up key mapping to close the buffer
  api.nvim_buf_set_keymap(scratch_buf_nr, 'n', 'q', '', {
    noremap = true,
    silent = true,
    callback = function()
      -- Trigger the LLM_Escape event
      api.nvim_exec_autocmds('User', { pattern = 'LLM_Escape' })

      api.nvim_buf_call(scratch_buf_nr, function()
        vim.cmd 'bdelete!'
      end)
    end,
  })
end

--- Define the function that creates the buffer and handles the input
---
---@param return_buf integer
---@param prompt_args { system_prompt_template: string, user_prompt_templates: string[], user_prompt_args: { code_snippet?: string, supporting_context?: string, user_query?:string } }
---@return integer
function M.create_input_buffer(return_buf, prompt_args)
  local prompt_save_dir = M.CACHE_DIRECTORY .. tostring(os.time()) .. '/'
  local filepath = prompt_save_dir .. 'output.xml'

  local input_buf_nr = api.nvim_create_buf(true, false)
  api.nvim_buf_set_name(input_buf_nr, filepath)
  api.nvim_set_option_value('buflisted', true, { buf = input_buf_nr })
  api.nvim_set_option_value('filetype', 'xml', { buf = input_buf_nr })

  api.nvim_set_current_buf(input_buf_nr)
  api.nvim_set_option_value('wrap', true, { win = 0 })
  api.nvim_set_option_value('linebreak', true, { win = 0 })
  api.nvim_set_option_value('breakindent', true, { win = 0 })

  local num_lines = api.nvim_buf_line_count(input_buf_nr)
  api.nvim_win_set_cursor(0, { num_lines, 0 })

  -- Set up key mapping to close the buffer
  api.nvim_buf_set_keymap(input_buf_nr, 'n', 'w', '', {
    noremap = true,
    silent = true,
    callback = function()
      -- Trigger the LLM_Escape event
      api.nvim_exec_autocmds('User', { pattern = 'LLM_Escape' })

      success, error_message = os.execute('mkdir -p "' .. prompt_save_dir .. '"')
      if not success then
        error('Error creating directory: ' .. error_message)
      end

      api.nvim_buf_call(input_buf_nr, function()
        vim.cmd 'write'
      end)

      local args_file = prompt_save_dir .. 'args.json'
      local file = io.open(args_file, 'w')
      if file then
        file:write(vim.json.encode(prompt_args))
        file:close()
        print('Data written to ' .. args_file)
      else
        print('Unable to open file ' .. args_file)
      end

      -- Switch to the return buffer provided
      api.nvim_set_current_buf(return_buf)
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

  -- render input prompt for debugging
  api.nvim_buf_set_keymap(input_buf_nr, 'n', 'd', '', {
    noremap = true,
    silent = true,
    callback = function()
      -- Trigger the LLM_Escape event
      api.nvim_exec_autocmds('User', { pattern = 'LLM_Escape' })
      -- Create a new buffer
      make_scratch_buffer(prompt_args)
    end,
  })
  return input_buf_nr
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
