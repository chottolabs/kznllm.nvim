local M = {}
local api = vim.api
local utils = require 'kznllm.utils'

-- Global variable to store the buffer number
local input_buf_nr = nil

local context_template = [[

---

Arguments:

<supporting_context>
%s
</supporting_context>

<user_query>
%s
</user_query>

---

]]
-- Define the function that creates the buffer and handles the input
local function create_input_buffer(initial_content)
  -- Convert timestamp to string and append .txt extension
  local filename = tostring(os.time()) .. '.txt'

  -- Create a new buffer
  input_buf_nr = api.nvim_create_buf(false, true)

  -- Set buffer options
  api.nvim_buf_set_option(input_buf_nr, 'buftype', 'nofile')
  api.nvim_buf_set_option(input_buf_nr, 'bufhidden', 'hide')
  api.nvim_buf_set_option(input_buf_nr, 'swapfile', false)
  api.nvim_buf_set_option(input_buf_nr, 'filetype', 'input-buffer')

  -- Set buffer name
  api.nvim_buf_set_name(input_buf_nr, filename)

  -- Switch to the new buffer
  api.nvim_set_current_buf(input_buf_nr)

  -- Enable text wrapping
  api.nvim_win_set_option(0, 'wrap', true)
  api.nvim_win_set_option(0, 'linebreak', true)
  api.nvim_win_set_option(0, 'breakindent', true)

  -- Set initial content
  api.nvim_buf_set_lines(input_buf_nr, 0, -1, false, vim.split(initial_content, '\n'))

  -- Add separator and move cursor after it
  local new_line_count = api.nvim_buf_line_count(input_buf_nr)
  api.nvim_win_set_cursor(0, { new_line_count, 0 })

  -- Set up autocmd to clear the buffer number when it's deleted
  api.nvim_create_autocmd('BufDelete', {
    buffer = input_buf_nr,
    callback = function()
      input_buf_nr = nil
    end,
  })

  -- Set up key mapping to close the buffer
  api.nvim_buf_set_keymap(input_buf_nr, 'n', 'q', '', {
    noremap = true,
    silent = true,
    callback = function()
      -- Trigger the LLM_Escape event
      api.nvim_exec_autocmds('User', { pattern = 'LLM_Escape' })

      utils.save_buffer(input_buf_nr, filename)
      -- Close the buffer
      api.nvim_buf_delete(input_buf_nr, { force = true })
    end,
  })
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

--- Invokes an LLM via a supported API spec in "buffer" mode
---
--- Must provide the function for constructing cURL arguments and a handler
--- function for processing server-sent events.
---
---@param opts { prompt_template: string, replace: boolean}
---@param make_job_fn function
function M.invoke_llm_buffer_mode(opts, make_job_fn)
  api.nvim_clear_autocmds { group = group }

  local visual_selection = get_visual_selection()

  if opts.prompt_template == nil then
    opts.prompt_template = 'You are a tsundere uwu anime. Yell at me for not setting my configuration for my llm plugin correctly'
  end

  local user_prompt_args = { visual_selection }
  local user_input = nil
  vim.ui.input({ prompt = 'prompt: ' }, function(input)
    if input ~= nil then
      user_input = input
    end
  end)

  if user_input == nil then
    return
  end

  vim.list_extend(user_prompt_args, { user_input })

  -- after getting lines, exit visual mode and go to end of the current line
  api.nvim_feedkeys(api.nvim_replace_termcodes('<Esc>', false, true, true), 'nx', false)
  api.nvim_feedkeys('$', 'nx', false)

  -- if buffer is already open, make job from full buffer
  if input_buf_nr and api.nvim_buf_is_valid(input_buf_nr) then
    api.nvim_set_current_buf(input_buf_nr)
    local new_line_count = api.nvim_buf_line_count(input_buf_nr)

    local context_lines = vim.split(context_template:format(unpack(user_prompt_args)), '\n')

    api.nvim_buf_set_lines(input_buf_nr, new_line_count, new_line_count, false, context_lines)
    api.nvim_win_set_cursor(0, { new_line_count + #context_lines, 0 })
  else
    create_input_buffer(table.concat { opts.prompt_template, context_template:format(unpack(user_prompt_args)) })
  end

  local active_job = make_job_fn(opts.prompt_template, user_prompt_args)
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

--- Invokes an LLM via a supported API spec in "replace" mode
---
--- Must provide the function for constructing cURL arguments and a handler
--- function for processing server-sent events.
---
---@param opts { prompt_template: string, replace: boolean}
---@param make_job_fn function
function M.invoke_llm_replace_mode(opts, make_job_fn)
  api.nvim_clear_autocmds { group = group }

  local visual_selection = get_visual_selection()

  if opts.prompt_template == nil then
    opts.prompt_template = 'You are a tsundere uwu anime. Yell at me for not setting my configuration for my llm plugin correctly'
  end

  local user_prompt_args = { visual_selection }
  api.nvim_feedkeys('c', 'nx', false)

  local active_job = make_job_fn(opts.prompt_template, user_prompt_args)
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
