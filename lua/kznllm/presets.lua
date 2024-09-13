--
-- This module provides the basic feature set from kznllm v0.1 with the addition of exported presets.
-- Your lazy config still wants to define the keymaps to make it work (see the main project README.md for recommended setup)
--
local kznllm = require 'kznllm'
local Path = require 'plenary.path'
local api = vim.api

local M = {}

--TODO: PROMPT_ARGS_STATE is just a bad persistence layer at the moment, I don't really want to write files everywhere...

-- ORIGIN refers to the buffer where the user invoked the plugin.
-- SCRATCH is a temporary buffer for debugging/chat.
M.BUFFER_STATE = {
  SCRATCH = nil,
  ORIGIN = nil,
}

M.PROMPT_ARGS_STATE = {
  current_buffer_path = nil,
  current_buffer_context = nil,
  current_buffer_filetype = nil,
  visual_selection = nil,
  user_query = nil,
  replace = nil,
  context_files = nil,
  prefill = nil,
}

M.NS_ID = api.nvim_create_namespace 'kznllm_ns'

local plugin_dir = debug.getinfo(1, "S").source:sub(2):gsub("/lua/.*$", "")
local TEMPLATE_DIRECTORY = Path:new(plugin_dir) / 'templates'

local group = api.nvim_create_augroup('LLM_AutoGroup', { clear = true })
---Example implementation of a `make_data_fn` compatible with `kznllm.invoke_llm` for groq spec
---@param prompt_args any
---@param opts { model: string, prefill:string, data_params: table, stop_param: table, template_directory: Path, debug: boolean }
---@return table
---
local function make_data_for_openai_chat(prompt_args, opts)
  local template_directory = opts.template_directory or TEMPLATE_DIRECTORY
  local messages = {
    {
      role = 'system',
      content = kznllm.make_prompt_from_template(template_directory / 'nous_research/fill_mode_system_prompt.xml.jinja', prompt_args),
    },
    {
      role = 'user',
      content = kznllm.make_prompt_from_template(template_directory / 'nous_research/fill_mode_user_prompt.xml.jinja', prompt_args),
    },
  }

  local data = {
    messages = messages,
    model = opts.model,
    stream = true,
  }

  if M.PROMPT_ARGS_STATE.replace and opts.prefill and opts.stop_param then
    table.insert(messages, {
      role = 'assistant',
      content = opts.prefill .. prompt_args.current_buffer_filetype .. '\n',
    })
    data = vim.tbl_extend('keep', data, opts.stop_param)
  end

  data = vim.tbl_extend('keep', data, opts.data_params)

  return data
end

local function make_data_for_deepseek_chat(prompt_args, opts)
  local template_directory = opts.template_directory or TEMPLATE_DIRECTORY
  local messages = {
    {
      role = 'system',
      content = kznllm.make_prompt_from_template(template_directory / 'nous_research/fill_mode_system_prompt.xml.jinja', prompt_args),
    },
    {
      role = 'user',
      content = kznllm.make_prompt_from_template(template_directory / 'nous_research/fill_mode_user_prompt.xml.jinja', prompt_args),
    },
  }

  local data = {
    messages = messages,
    model = opts.model,
    stream = true,
  }

  if M.PROMPT_ARGS_STATE.replace and opts.prefill and opts.stop_param then
    table.insert(messages, {
      role = 'assistant',
      content = opts.prefill .. prompt_args.current_buffer_filetype .. '\n',
      prefix = true,
    })
    data = vim.tbl_extend('keep', data, opts.stop_param)
  end

  data = vim.tbl_extend('keep', data, opts.data_params)

  return data
end

---Example implementation of a `make_data_fn` compatible with `kznllm.invoke_llm` for anthropic spec
---@param prompt_args any
---@param opts any
---@return table
local function make_data_for_anthropic_chat(prompt_args, opts)
  local template_directory = opts.template_directory or TEMPLATE_DIRECTORY
  local data = {
    system = kznllm.make_prompt_from_template(template_directory / 'anthropic/fill_mode_system_prompt.xml.jinja', prompt_args),
    messages = {
      {
        role = 'user',
        content = kznllm.make_prompt_from_template(template_directory / 'anthropic/fill_mode_user_prompt.xml.jinja', prompt_args),
      },
    },
    model = opts.model,
    stream = true,
  }
  data = vim.tbl_extend('keep', data, opts.data_params)

  return data
end

---Example implementation of a `make_data_fn` compatible with `kznllm.invoke_llm` for vllm completions spec
---@param prompt_args any
---@param opts any
---@return table
local function make_data_for_openai_completions(prompt_args, opts)
  local template_directory = opts.template_directory or TEMPLATE_DIRECTORY
  local data = {
    prompt = kznllm.make_prompt_from_template(template_directory / 'vllm/fill_mode_instruct_completion_prompt.xml.jinja', prompt_args),
    model = opts.model,
    temperature = 1.5,
    min_p = 1.0,
    stream = true,
  }

  return data
end

local function openai_debug_fn(data, ns_id, extmark_id, opts)
  kznllm.write_content_at_extmark('model: ' .. opts.model, ns_id, extmark_id)
  for _, message in ipairs(data.messages) do
    kznllm.write_content_at_extmark('\n\n---\n\n', ns_id, extmark_id)
    kznllm.write_content_at_extmark(message.role .. ':\n\n', ns_id, extmark_id)
    kznllm.write_content_at_extmark(message.content, ns_id, extmark_id)
  end
  if not (M.PROMPT_ARGS_STATE.replace and opts.prefill) then
    kznllm.write_content_at_extmark('\n\n---\n\n', ns_id, extmark_id)
  end
  vim.cmd 'normal! G'
end

local function vllm_completions_debug_fn(data, ns_id, extmark_id, opts)
  kznllm.write_content_at_extmark('model: ' .. opts.model, ns_id, extmark_id)
  kznllm.write_content_at_extmark('\n\n---\n\n', ns_id, extmark_id)
  kznllm.write_content_at_extmark(data.prompt, ns_id, extmark_id)
  kznllm.write_content_at_extmark('\n\n---\n\n', ns_id, extmark_id)
  vim.cmd 'normal! G'
end

local function anthropic_debug_fn(data, ns_id, extmark_id, opts)
  kznllm.write_content_at_extmark('model: ' .. opts.model, ns_id, extmark_id)
  kznllm.write_content_at_extmark('\n\n---\n\n', ns_id, extmark_id)

  kznllm.write_content_at_extmark('system' .. ':\n\n', ns_id, extmark_id)
  kznllm.write_content_at_extmark(data.system, ns_id, extmark_id)
  kznllm.write_content_at_extmark('\n\n---\n\n', ns_id, extmark_id)
  for _, message in ipairs(data.messages) do
    kznllm.write_content_at_extmark(message.role .. ':\n\n', ns_id, extmark_id)
    kznllm.write_content_at_extmark(message.content, ns_id, extmark_id)
    kznllm.write_content_at_extmark('\n\n---\n\n', ns_id, extmark_id)
    vim.cmd 'normal! G'
  end
end

--- Working implementation of "inline" fill mode
--- Invokes an LLM via a supported API spec defined by
---
--- Must provide the function for constructing cURL arguments and a handler
--- function for processing server-sent events.
---
---@param make_data_fn fun(prompt_args: table, opts: table)
---@param make_curl_args_fn fun(data: table, opts: table)
---@param make_job_fn fun(data: table, writer_fn: fun(content: string), on_exit_fn: fun())
---@param opts { debug: string?, debug_fn: fun(data: table, ns_id: integer, extmark_id: integer, opts: table)?, stop_dir: Path?, context_dir_id: string?, data_params: table, prefill: boolean }
function M.invoke_llm(make_data_fn, make_curl_args_fn, make_job_fn, opts)
  api.nvim_clear_autocmds { group = group }

  local active_job

  M.BUFFER_STATE.ORIGIN = api.nvim_win_get_buf(0)

  kznllm.get_user_input(function(input)
    M.PROMPT_ARGS_STATE.user_query = input
    M.PROMPT_ARGS_STATE.replace = not (api.nvim_get_mode().mode == 'n')

    local visual_selection = kznllm.get_visual_selection(opts)
    M.PROMPT_ARGS_STATE.visual_selection = visual_selection

    local context_dir = kznllm.find_context_directory(opts)
    if context_dir then
      M.PROMPT_ARGS_STATE.context_files = kznllm.get_project_files(context_dir, opts)
    end

    -- don't update current context if scratch buffer is open
    if not M.BUFFER_STATE.SCRATCH then
      -- similar to rendering a template, but we want to get the context of the file without relying on the changes being saved
      local buf_filetype, buf_path, buf_context = kznllm.get_buffer_context(M.BUFFER_STATE.ORIGIN, opts)
      M.PROMPT_ARGS_STATE.current_buffer_filetype = buf_filetype
      M.PROMPT_ARGS_STATE.current_buffer_path = buf_path
      M.PROMPT_ARGS_STATE.current_buffer_context = buf_context
    end
    M.PROMPT_ARGS_STATE.prefill = opts.prefill

    local data = make_data_fn(M.PROMPT_ARGS_STATE, opts)

    local stream_end_extmark_id

    -- open up scratch buffer before setting extmark
    if opts and opts.debug and opts.debug_fn then
      if M.BUFFER_STATE.SCRATCH then
        api.nvim_buf_delete(M.BUFFER_STATE.SCRATCH, { force = true })
        M.BUFFER_STATE.SCRATCH = nil
      end
      M.BUFFER_STATE.SCRATCH = kznllm.make_scratch_buffer()

      -- Set up key mapping to close the buffer
      api.nvim_buf_set_keymap(M.BUFFER_STATE.SCRATCH, 'n', '<leader>q', '', {
        noremap = true,
        silent = true,
        callback = function()
          api.nvim_exec_autocmds('User', { pattern = 'LLM_Escape' })
          api.nvim_buf_delete(M.BUFFER_STATE.SCRATCH, { force = true })
          M.BUFFER_STATE.SCRATCH = nil
        end,
      })

      stream_end_extmark_id = api.nvim_buf_set_extmark(M.BUFFER_STATE.SCRATCH, M.NS_ID, 0, 0, {})
      opts.debug_fn(data, M.NS_ID, stream_end_extmark_id, opts)
    else
      local _, crow, ccol = unpack(vim.fn.getpos '.')
      stream_end_extmark_id = api.nvim_buf_set_extmark(M.BUFFER_STATE.ORIGIN, M.NS_ID, crow - 1, ccol - 1, { strict = false })
    end

    local args = make_curl_args_fn(data, opts)

    -- Make a no-op change to the buffer at the specified extmark to avoid calling undojoin after undo
    kznllm.noop(M.NS_ID, stream_end_extmark_id)

    active_job = make_job_fn(args, function(content)
      kznllm.write_content_at_extmark(content, M.NS_ID, stream_end_extmark_id)
    end, function()
      api.nvim_buf_del_extmark(0, M.NS_ID, stream_end_extmark_id)
    end)

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
  end)
end

-- for vllm, add openai w/ kwargs (i.e. url + api_key)
-- { id = 'openai', opts = { api_key_name = 'VLLM_API_KEY', url = 'http://research.local:8000/v1/chat/completions' } }
local presets = {
  {
    id = 'chat-model',
    provider = 'groq',
    make_data_fn = make_data_for_openai_chat,
    opts = {
      model = 'llama-3.1-70b-versatile',
      data_params = {
        -- max_tokens = 8192,
        temperature = 0.7,
      },
      -- doesn't support prefill
      -- stop_param = { stop = { '```' } },
      -- prefill = '```',
      debug_fn = openai_debug_fn,
      base_url = 'https://api.groq.com',
      endpoint = '/openai/v1/chat/completions',
    },
  },
  {
    id = 'chat-model',
    provider = 'lambda',
    make_data_fn = make_data_for_openai_chat,
    opts = {
      model = 'hermes-3-llama-3.1-405b-fp8',
      data_params = {
        -- max_tokens = 8192,
        -- temperature = 2.1,
        temperature = 1.5,
        min_p = 0.05,
        logprobs = 1,
      },
      -- stop_param = { stop_token_ids = { 74694 } },
      -- prefill = '```',
      debug_fn = openai_debug_fn,
      base_url = 'https://api.lambdalabs.com',
      endpoint = '/v1/chat/completions',
    },
  },
  {
    id = 'chat-model',
    provider = 'anthropic',
    make_data_fn = make_data_for_anthropic_chat,
    opts = {
      model = 'claude-3-5-sonnet-20240620',
      data_params = {
        max_tokens = 8192,
        temperature = 0.7,
      },
      debug_fn = anthropic_debug_fn,
      base_url = 'https://api.anthropic.com',
      endpoint = '/v1/messages',
    },
  },
  {
    id = 'chat-model',
    provider = 'openai',
    make_data_fn = make_data_for_openai_chat,
    opts = {
      model = 'gpt-4o-mini',
      data_params = {
        max_tokens = 16384,
        temperature = 0.7,
      },
      debug_fn = openai_debug_fn,
      base_url = 'https://api.openai.com',
      endpoint = '/v1/chat/completions',
    },
  },
  {
    id = 'chat-model',
    provider = 'deepseek',
    make_data_fn = make_data_for_deepseek_chat,
    opts = {
      model = 'deepseek-chat',
      data_params = {
        max_tokens = 8192,
        temperature = 0,
      },
      stop_param = { stop = { '```' } },
      prefill = '```',
      debug_fn = openai_debug_fn,
      base_url = 'https://api.deepseek.com',
      endpoint = '/beta/v1/chat/completions',
    },
  },
  {
    id = 'completion-model',
    provider = 'vllm',
    make_data_fn = make_data_for_openai_chat,
    opts = {
      model = 'meta-llama/Meta-Llama-3.1-8B-Instruct',
      data_params = {
        max_tokens = 8192,
        min_p = 0.9,
        temperature = 2.1,
      },
      debug_fn = openai_debug_fn,
      endpoint = '/v1/chat/completions',
    },
  },
}

return vim.tbl_extend('keep', M, presets)
