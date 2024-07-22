local utils = require 'kznllm.utils'
local M = {}
local api = vim.api

-- Global variable to store the buffer number
local input_buf_nr = nil
local group = api.nvim_create_augroup('LLM_AutoGroup', { clear = true })

-- Specify the path where you want to save the file
M.CACHE_DIRECTORY = (os.getenv 'HOME' or os.getenv 'USERPROFILE') .. '/.cache/kznllm/history/'

local success, error_message = os.execute('mkdir -p "' .. M.CACHE_DIRECTORY .. '"')

if not success then
  print('Error creating directory: ' .. error_message)
  return
end

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

--- Invokes an LLM via a supported API spec in "buffer" mode
---
--- Must provide the function for constructing cURL arguments and a handler
--- function for processing server-sent events.
---
---@param opts { prompt_template: string }
---@param make_job_fn function
function M.invoke_llm_buffer_mode(opts, make_job_fn)
  api.nvim_clear_autocmds { group = group }

  local visual_selection = utils.get_visual_selection()

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
    local filepath = M.CACHE_DIRECTORY .. tostring(os.time()) .. '.txt'
    utils.create_input_buffer(
      input_buf_nr,
      filepath,
      table.concat {
        opts.prompt_template,
        context_template:format(unpack(user_prompt_args)),
      }
    )
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
end

--- Invokes an LLM via a supported API spec in "replace" mode
---
--- Must provide the function for constructing cURL arguments and a handler
--- function for processing server-sent events.
---
---@param opts { prompt_template: string }
---@param make_job_fn function
function M.invoke_llm_replace_mode(opts, make_job_fn)
  api.nvim_clear_autocmds { group = group }

  local visual_selection = utils.get_visual_selection()

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
end

api.nvim_set_keymap('n', '<Esc>', '', {
  noremap = true,
  silent = true,
  callback = function()
    api.nvim_exec_autocmds('User', { pattern = 'LLM_Escape' })
  end,
})

return M
