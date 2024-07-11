local M = {}
local api = vim.api

-- Global variable to store the buffer number
local input_buf_nr = nil

-- Define the function that creates the buffer and handles the input
local function create_input_buffer()
  -- Create a new buffer
  input_buf_nr = vim.api.nvim_create_buf(false, true)

  -- Set buffer options
  vim.api.nvim_buf_set_option(input_buf_nr, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(input_buf_nr, 'bufhidden', 'hide')
  vim.api.nvim_buf_set_option(input_buf_nr, 'swapfile', false)
  vim.api.nvim_buf_set_option(input_buf_nr, 'filetype', 'input-buffer')

  -- Set buffer name
  vim.api.nvim_buf_set_name(input_buf_nr, 'Input Buffer')

  -- Switch to the new buffer
  vim.api.nvim_set_current_buf(input_buf_nr)

  -- Enable text wrapping
  vim.api.nvim_win_set_option(0, 'wrap', true)
  vim.api.nvim_win_set_option(0, 'linebreak', true)
  vim.api.nvim_win_set_option(0, 'breakindent', true)

  -- Move cursor to the end of the buffer
  local line_count = vim.api.nvim_buf_line_count(input_buf_nr)
  vim.api.nvim_win_set_cursor(0, { line_count, 0 })

  -- Set up autocmd to clear the buffer number when it's deleted
  vim.api.nvim_create_autocmd('BufDelete', {
    buffer = input_buf_nr,
    callback = function()
      input_buf_nr = nil
    end,
  })

  -- Set up key mapping to close the buffer
  vim.api.nvim_buf_set_keymap(input_buf_nr, 'n', 'q', ':bdelete<CR>:doautocmd User LLM_Escape<CR>', { noremap = true, silent = true })
end

local function input_text(text)
  if input_buf_nr and vim.api.nvim_buf_is_valid(input_buf_nr) then
    local line_count = vim.api.nvim_buf_line_count(input_buf_nr)
    local lines_to_insert = vim.split(text, '\n')

    -- Add separator after the text if the buffer is not empty
    if line_count > 0 then
      table.insert(lines_to_insert, '')
      table.insert(lines_to_insert, '---')
      table.insert(lines_to_insert, '')
      table.insert(lines_to_insert, '')
    end

    vim.api.nvim_buf_set_lines(input_buf_nr, line_count, -1, false, lines_to_insert)

    -- Switch to the buffer if it's not currently visible
    if vim.api.nvim_get_current_buf() ~= input_buf_nr then
      vim.api.nvim_set_current_buf(input_buf_nr)
    end

    -- Move cursor to the end of the newly inserted text
    local new_line_count = vim.api.nvim_buf_line_count(input_buf_nr)

    -- Set cursor to the last line of the inserted text
    vim.api.nvim_win_set_cursor(0, { new_line_count, 0 })

    -- Move cursor to the end of the last line
    local last_line = vim.api.nvim_get_current_line()
    vim.api.nvim_win_set_cursor(0, { new_line_count, #last_line })
  end
end

--- Handle visual selection using the start of the visual selection and current
--- cursor position in the most common modes (i.e. visual, visual lines, visual block)
---
--- Note: visual block is handled the same as visual lines
--- @return string
local function get_visual_selection()
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

local group = api.nvim_create_augroup('LLM_AutoGroup', { clear = true })

--- Invokes an LLM via a supported API spec
---
--- Must provide the function for constructing cURL arguments and a handler
--- function for processing server-sent events.
---
---@param opts { api_key_name: string, url: string, model: string, system_prompt: string, replace: boolean }
---@param make_job_fn function
function M.invoke_llm_and_stream_into_editor(opts, make_job_fn)
  api.nvim_clear_autocmds { group = group }

  local visual_selection = get_visual_selection()

  local replace_prompt = nil
  if opts.replace then
    vim.ui.input({ prompt = 'prompt: ' }, function(input)
      replace_prompt = input
    end)
    if replace_prompt == nil then
      return
    end

    api.nvim_feedkeys('d', 'nx', false)
  else
    -- after getting lines, exit visual mode and go to end of the current line
    api.nvim_feedkeys(api.nvim_replace_termcodes('<Esc>', false, true, true), 'nx', false)
    api.nvim_feedkeys('$', 'nx', false)

    if input_buf_nr and vim.api.nvim_buf_is_valid(input_buf_nr) then
      vim.api.nvim_set_current_buf(input_buf_nr)
    else
      create_input_buffer()
    end
  end

  local system_prompt = opts.system_prompt
  if system_prompt == nil then
    system_prompt = 'You are a tsundere uwu anime. Yell at me for not setting my configuration for my llm plugin correctly'
  end

  local user_prompt = table.concat({ visual_selection, replace_prompt }, '\n')

  if input_buf_nr ~= 0 then
    input_text(system_prompt)
    input_text(user_prompt)
  end
  local active_job = make_job_fn(opts, system_prompt, user_prompt)
  active_job:start()
  api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'LLM_Escape',
    callback = function()
      if active_job.is_shutdown ~= true then
        active_job:shutdown()
        print 'LLM streaming cancelled'
      end
    end,
  })

  api.nvim_set_keymap('n', '<Esc>', ':doautocmd User LLM_Escape<CR>', { noremap = true, silent = true })
end

return M
