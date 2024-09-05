local kznllm = require 'kznllm'
local TEMPLATE_DIRECTORY = vim.fn.stdpath 'data' .. '/lazy/kznllm/templates'

---Example implementation of a `make_data_fn` compatible with `kznllm.invoke_llm` for groq spec
---@param prompt_args any
---@param opts { model: string, temperature: number, template_directory: Path, debug: boolean }
---@return table
---
local function make_data_for_openai_chat(prompt_args, opts)
  local messages = {
    {
      role = 'system',
      content = kznllm.make_prompt_from_template(opts.template_directory / 'nous_research/fill_mode_system_prompt.xml.jinja', prompt_args),
    },
    {
      role = 'user',
      content = kznllm.make_prompt_from_template(opts.template_directory / 'nous_research/fill_mode_user_prompt.xml.jinja', prompt_args),
    },
  }

  local data = {
    messages = messages,
    model = opts.model,
    temperature = opts.temperature,
    stream = true,
  }

  return data
end

---Example implementation of a `make_data_fn` compatible with `kznllm.invoke_llm` for anthropic spec
---@param prompt_args any
---@param opts any
---@return table
local function make_data_for_anthropic_chat(prompt_args, opts)
  local data = {
    system = kznllm.make_prompt_from_template(opts.template_directory / 'anthropic/fill_mode_system_prompt.xml.jinja', {}),
    messages = {
      {
        role = 'user',
        content = kznllm.make_prompt_from_template(opts.template_directory / 'anthropic/fill_mode_user_prompt.xml.jinja', prompt_args),
      },
    },
    model = opts.model,
    temperature = opts.temperature,
    stream = true,
    max_tokens = opts.max_tokens,
  }

  return data
end

---Example implementation of a `make_data_fn` compatible with `kznllm.invoke_llm` for vllm completions spec
---@param prompt_args any
---@param opts any
---@return table
local function make_data_for_openai_completions(prompt_args, opts)
  local data = {
    prompt = kznllm.make_prompt_from_template(opts.template_directory / 'vllm/fill_mode_instruct_completion_prompt.xml.jinja', prompt_args),
    model = opts.model,
    temperature = 1.5,
    min_p = 1.0,
    stream = true,
  }

  return data
end

local function openai_debug_fn(data, extmark_id, opts)
  kznllm.write_content_at_extmark('model: ' .. opts.model, extmark_id)
  kznllm.write_content_at_extmark('\n\n---\n\n', extmark_id)
  for _, message in ipairs(data.messages) do
    kznllm.write_content_at_extmark(message.role .. ':\n\n', extmark_id)
    kznllm.write_content_at_extmark(message.content, extmark_id)
    kznllm.write_content_at_extmark('\n\n---\n\n', extmark_id)
    vim.cmd 'normal! G'
  end
end

local function vllm_completions_debug_fn(data, extmark_id, opts)
  kznllm.write_content_at_extmark('model: ' .. opts.model, extmark_id)
  kznllm.write_content_at_extmark('\n\n---\n\n', extmark_id)
  kznllm.write_content_at_extmark(data.prompt, extmark_id)
  kznllm.write_content_at_extmark('\n\n---\n\n', extmark_id)
  vim.cmd 'normal! G'
end

local function anthropic_debug_fn(data, extmark_id, opts)
  kznllm.write_content_at_extmark('model: ' .. opts.model, extmark_id)
  kznllm.write_content_at_extmark('\n\n---\n\n', extmark_id)

  kznllm.write_content_at_extmark('system' .. ':\n\n', extmark_id)
  kznllm.write_content_at_extmark(data.system, extmark_id)
  kznllm.write_content_at_extmark('\n\n---\n\n', extmark_id)
  for _, message in ipairs(data.messages) do
    kznllm.write_content_at_extmark(message.role .. ':\n\n', extmark_id)
    kznllm.write_content_at_extmark(message.content, extmark_id)
    kznllm.write_content_at_extmark('\n\n---\n\n', extmark_id)
    vim.cmd 'normal! G'
  end
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
      max_tokens = 8192,
      temperature = 0.7,
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
      max_tokens = 8192,
      temperature = 0.7,
      debug_fn = openai_debug_fn,
      base_url = 'https://api.lambdalabs.com',
      endpoint = '/v1/chat/completions',
    },
  },
  {
    id = 'chat-model',
    provider = 'anthropic',
    make_data_fn = make_data_for_anthropic_chat,
    debug_fn = anthropic_debug_fn,
    opts = {
      model = 'claude-3-5-sonnet-20240620',
      max_tokens = 8192,
      temperature = 0.7,
      debug_fn = openai_debug_fn,
      base_url = 'https://api.anthropic.com',
      endpoint = '/v1/messages',
    },
  },
  {
    id = 'chat-model',
    provider = 'openai',
    make_data_fn = make_data_for_openai_chat,
    debug_fn = openai_debug_fn,
    opts = {
      model = 'gpt-4o-mini',
      max_tokens = 16384,
      temperature = 0.7,
      debug_fn = openai_debug_fn,
      base_url = 'https://api.openai.com',
      endpoint = '/v1/chat/completions',
    },
  },
  {
    id = 'completion-model',
    provider = 'vllm',
    make_data_fn = make_data_for_openai_completions,
    debug_fn = openai_debug_fn,
    opts = {
      model = 'meta-llama/Meta-Llama-3.1-8B',
      max_tokens = 8192,
      min_p = 0.9,
      temperature = 2.1,
      debug_fn = vllm_completions_debug_fn,
      endpoint = '/v1/completions',
    },
  },
}

return presets
