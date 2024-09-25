--
-- This module provides the basic feature set from kznllm v0.1 with the addition of exported presets.
-- Your lazy config still wants to define the keymaps to make it work (see the main project README.md for recommended setup)
--
local kznllm = require 'kznllm'
local Path = require 'plenary.path'
local api = vim.api

local M = {}
local PRESETS = {}

--TODO: PROMPT_ARGS_STATE is just a bad persistence layer at the moment, I don't really want to write files everywhere...

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

local plugin_dir = Path:new(debug.getinfo(1, 'S').source:sub(2)):parents()[3]
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
      content = kznllm.make_prompt_from_template(template_directory / 'deepseek/fill_mode_system_prompt.xml.jinja', prompt_args),
    },
    {
      role = 'user',
      content = kznllm.make_prompt_from_template(template_directory / 'deepseek/fill_mode_user_prompt.xml.jinja', prompt_args),
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
  vim.cmd 'normal! zz'
end

local function vllm_completions_debug_fn(data, ns_id, extmark_id, opts)
  kznllm.write_content_at_extmark('model: ' .. opts.model, ns_id, extmark_id)
  kznllm.write_content_at_extmark('\n\n---\n\n', ns_id, extmark_id)
  kznllm.write_content_at_extmark(data.prompt, ns_id, extmark_id)
  kznllm.write_content_at_extmark('\n\n---\n\n', ns_id, extmark_id)
  vim.cmd 'normal! G'
  vim.cmd 'normal! zz'
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
  end
  vim.cmd 'normal! G'
  vim.cmd 'normal! zz'
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
  local origin_buf_id = api.nvim_win_get_buf(0)

  local active_job

  kznllm.get_user_input(function(input)
    M.PROMPT_ARGS_STATE.user_query = input
    M.PROMPT_ARGS_STATE.replace = not (api.nvim_get_mode().mode == 'n')

    local visual_selection, crow, ccol = kznllm.get_visual_selection(opts)
    M.PROMPT_ARGS_STATE.visual_selection = visual_selection

    local context_dir = kznllm.find_context_directory(opts)
    if context_dir then
      M.PROMPT_ARGS_STATE.context_files = kznllm.get_project_files(context_dir, opts)
    end

    -- don't update current context if scratch buffer is open

    if not vim.b.debug then
      -- similar to rendering a template, but we want to get the context of the file without relying on the changes being saved
      local buf_filetype, buf_path, buf_context = kznllm.get_buffer_context(origin_buf_id, opts)
      M.PROMPT_ARGS_STATE.current_buffer_filetype = buf_filetype
      M.PROMPT_ARGS_STATE.current_buffer_path = buf_path
      M.PROMPT_ARGS_STATE.current_buffer_context = buf_context
    end
    M.PROMPT_ARGS_STATE.prefill = opts.prefill

    local data = make_data_fn(M.PROMPT_ARGS_STATE, opts)

    local stream_end_extmark_id
    local stream_buf_id = origin_buf_id

    -- open up scratch buffer before setting extmark
    if opts and opts.debug and opts.debug_fn then
      local scratch_buf_id = kznllm.make_scratch_buffer()
      api.nvim_buf_set_var(scratch_buf_id, 'debug', true)
      stream_buf_id = scratch_buf_id

      stream_end_extmark_id = api.nvim_buf_set_extmark(stream_buf_id, M.NS_ID, 0, 0, {})
      opts.debug_fn(data, M.NS_ID, stream_end_extmark_id, opts)
    else
      stream_end_extmark_id = api.nvim_buf_set_extmark(stream_buf_id, M.NS_ID, crow, ccol, { strict = false })
    end

    local args = make_curl_args_fn(data, opts)

    -- Make a no-op change to the buffer at the specified extmark to avoid calling undojoin after undo
    kznllm.noop(M.NS_ID, stream_end_extmark_id)

    active_job = make_job_fn(args, function(content)
      kznllm.write_content_at_extmark(content, M.NS_ID, stream_end_extmark_id)
    end, function()
      api.nvim_buf_del_extmark(stream_buf_id, M.NS_ID, stream_end_extmark_id)
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

function M.switch_presets()
  vim.ui.select(PRESETS, {
    format_item = function(item)
      local options = {}
      for k, v in pairs(item.opts.data_params or {}) do
        if type(v) == 'number' then
          local k_parts = {}
          local k_split = vim.split(k, '_')
          for i, term in ipairs(k_split) do
            if i > 1 then
              table.insert(k_parts, term:sub(0, 3))
            else
              table.insert(k_parts, term:sub(0, 4))
            end
          end
          table.insert(options, ('%-5s %-5s'):format(table.concat(k_parts, '_'), v))
        end
      end
      table.sort(options)
      return ('%-20s %10s | %s'):format(item.id, item.provider, table.concat(options, ' '))
    end,
  }, function(choice, idx)
    if not choice then
      return
    end
    vim.g.PRESET_IDX = idx
    print(('%-15s provider: %-10s'):format(choice.id, choice.provider))
  end)
end

function M.load()
  local idx = vim.g.PRESET_IDX or 1
  local preset = PRESETS[idx]
  local spec = require(('kznllm.specs.%s'):format(preset.provider))

  return spec, preset
end

-- for vllm, add openai w/ kwargs (i.e. url + api_key)
PRESETS = {
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
    id = 'chat-model',
    provider = 'vllm',
    make_data_fn = make_data_for_openai_chat,
    opts = {
      model = 'meta-llama/Llama-3.2-3B-Instruct',
      data_params = {
        max_tokens = 8192,
        min_p = 0.9,
        temperature = 2.1,
      },
      debug_fn = openai_debug_fn,
      base_url = 'http://worker.local:8000',
      endpoint = '/v1/chat/completions',
    },
  },
}

return M
