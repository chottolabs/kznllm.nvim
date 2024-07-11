local M = {}
local api = vim.api

-- Global variable to store the window ID
local input_win_id = nil

-- Define the function that creates the window and handles the input
local function create_input_window()
  local buf = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')

  local width = vim.api.nvim_get_option 'columns'
  local height = vim.api.nvim_get_option 'lines'

  local win_height = math.ceil(height * 0.8)
  local win_width = math.ceil(width * 0.8)

  local row = math.ceil((height - win_height) / 2)
  local col = math.ceil((width - win_width) / 2)

  local opts = {
    style = 'minimal',
    relative = 'editor',
    width = win_width,
    height = win_height,
    row = row,
    col = col,
    border = 'rounded',
    focusable = true,
  }

  local win = vim.api.nvim_open_win(buf, true, opts)
  input_win_id = win -- Store the window ID

  -- Set focus to the new window
  vim.api.nvim_set_current_win(win)

  vim.api.nvim_win_set_option(win, 'wrap', false)
  vim.api.nvim_win_set_option(win, 'cursorline', true)

  local content = ''
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { content })

  vim.api.nvim_create_autocmd('BufLeave', {
    buffer = buf,
    callback = function()
      vim.api.nvim_win_close(win, true)
      input_win_id = nil -- Reset the window ID when closed
    end,
  })

  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':close<CR>', { noremap = true, silent = true })
end

local function input_text(text)
  if input_win_id and vim.api.nvim_win_is_valid(input_win_id) then
    local buf = vim.api.nvim_win_get_buf(input_win_id)
    local lines = vim.split(text, '\n')
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, { '', '---', '' }) -- Add an extra newline
    vim.api.nvim_win_set_cursor(input_win_id, { vim.api.nvim_buf_line_count(buf), 0 })
  else
    print 'Input window is not open. Use :ShowInput to open it first.'
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
    input_win_id = 0
  else
    -- after getting lines, exit visual mode and go to end of the current line
    api.nvim_feedkeys(api.nvim_replace_termcodes('<Esc>', false, true, true), 'nx', false)
    api.nvim_feedkeys('$', 'nx', false)

    create_input_window()
  end

  local system_prompt = opts.system_prompt
  if system_prompt == nil then
    system_prompt = 'You are a tsundere uwu anime. Yell at me for not setting my configuration for my llm plugin correctly'
  end

  local user_prompt = table.concat({ visual_selection, replace_prompt }, '\n')

  if input_win_id ~= 0 then
    input_text(system_prompt)
    input_text(user_prompt)
  end
  local active_job = make_job_fn(opts, system_prompt, user_prompt, input_win_id)
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
