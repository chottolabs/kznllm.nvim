local utils = require 'kznllm.utils'
local M = {}
local api = vim.api

if vim.fn.executable 'minijinja-cli' ~= 1 then
  error("Can't find minijinja-cli, download it from https://github.com/mitsuhiko/minijinja or add it to $PATH", 1)
end

-- Global variable to store the buffer number
local input_buf_nr = nil
local group = api.nvim_create_augroup('LLM_AutoGroup', { clear = true })

--- Invokes an LLM via a supported API spec in "buffer" mode
---
--- Must provide the function for constructing cURL arguments and a handler
--- function for processing server-sent events.
---
---@param opts { system_prompt_template: string, user_prompt_templates: string[] }
---@param make_job_fn function
function M.invoke_llm_buffer_mode(opts, make_job_fn)
  api.nvim_clear_autocmds { group = group }

  local visual_selection = utils.get_visual_selection()

  if opts.system_prompt_template == nil or opts.user_prompt_templates == nil or #opts.user_prompt_templates == 0 then
    error('You must set `system_prompt_template` and `user_prompt_templates`, see the project repo for more info https://github.com/chottolabs/kznllm.nvim/', 1)
  end

  local user_input = nil
  vim.ui.input({ prompt = 'prompt: ' }, function(input)
    if input ~= nil then
      user_input = input
    end
  end)

  if user_input == nil then
    return
  end

  local prompt_args = {
    system_prompt_template = opts.system_prompt_template,
    user_prompt_templates = opts.user_prompt_templates,
    user_prompt_args = {
      supporting_context = visual_selection,
      user_query = user_input,
    },
  }

  -- after getting lines, exit visual mode and go to end of the current line
  api.nvim_feedkeys(api.nvim_replace_termcodes('<Esc>', false, true, true), 'nx', false)
  api.nvim_feedkeys('$', 'nx', false)

  local rendered_messages = {
    system_message = nil,
    user_messages = {},
  }

  rendered_messages.system_message = utils.make_prompt_from_template(opts.system_prompt_template, prompt_args)

  for _, user_prompt_template in ipairs(opts.user_prompt_templates) do
    local rendered_prompt = utils.make_prompt_from_template(user_prompt_template, prompt_args)
    table.insert(rendered_messages.user_messages, rendered_prompt)
  end

  -- if buffer is already open, make job from full buffer
  if input_buf_nr and api.nvim_buf_is_valid(input_buf_nr) then
    api.nvim_set_current_buf(input_buf_nr)
    api.nvim_buf_call(input_buf_nr, function()
      vim.cmd 'bdelete!'
    end)
  end
  local cur_buf = api.nvim_get_current_buf()

  input_buf_nr = utils.create_input_buffer(cur_buf, prompt_args)
  -- Set up autocmd to clear the buffer number when it's deleted
  api.nvim_create_autocmd('BufDelete', {
    buffer = input_buf_nr,
    callback = function()
      input_buf_nr = nil
    end,
  })

  local active_job = make_job_fn(rendered_messages, utils.write_content_at_end)
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
---@param opts { system_prompt_template: string, user_prompt_templates: string[] }
---@param make_job_fn function
function M.invoke_llm_replace_mode(opts, make_job_fn)
  api.nvim_clear_autocmds { group = group }

  local visual_selection = utils.get_visual_selection()

  local prompt_args = {
    system_prompt_template = opts.system_prompt_template,
    user_prompt_templates = opts.user_prompt_templates,
    user_prompt_args = {
      code_snippet = visual_selection,
    },
  }

  if opts.system_prompt_template == nil or opts.user_prompt_templates == nil or #opts.user_prompt_templates == 0 then
    error('You must set `system_prompt_template` and `user_prompt_templates`, see the project repo for more info https://github.com/chottolabs/kznllm.nvim/', 1)
  end

  local rendered_messages = {
    system_message = nil,
    user_messages = {},
  }

  rendered_messages.system_message = utils.make_prompt_from_template(opts.system_prompt_template, prompt_args)

  for _, user_prompt_template in ipairs(opts.user_prompt_templates) do
    local rendered_prompt = utils.make_prompt_from_template(user_prompt_template, prompt_args)
    table.insert(rendered_messages.user_messages, rendered_prompt)
  end

  api.nvim_feedkeys('c', 'nx', false)

  local active_job = make_job_fn(rendered_messages, utils.write_content_at_cursor)
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
