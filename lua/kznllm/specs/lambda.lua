local kznllm = require 'kznllm'
local Path = require 'plenary.path'

local M = {}

local API_KEY_NAME = 'LAMBDA_API_KEY'
local URL = 'https://api.lambdalabs.com/v1/chat/completions'

local TEMPLATE_PATH = vim.fn.expand(vim.fn.stdpath 'data') .. '/lazy/kznllm.nvim'

M.MODELS = {
  { name = 'hermes-3-llama-3.1-405b-fp8' },
}

M.SELECTED_MODEL_IDX = 1

-- for chat completion models using `messages`
M.MESSAGE_TEMPLATES = {
  NOUS_RESEARCH = {
    FILL_MODE_SYSTEM_PROMPT = 'nous_research/fill_mode_system_prompt.xml.jinja',
    FILL_MODE_USER_PROMPT = 'nous_research/fill_mode_user_prompt.xml.jinja',
  },

  -- defaults
  FILL_MODE_SYSTEM_PROMPT = 'nous_research/fill_mode_system_prompt.xml.jinja',
  FILL_MODE_USER_PROMPT = 'nous_research/fill_mode_user_prompt.xml.jinja',
}

local API_ERROR_MESSAGE = [[
ERROR: api key is set to %s and is missing from your environment variables.

Load somewhere safely from config `export %s=<api_key>`]]

local Job = require 'plenary.job'

--- Constructs arguments for constructing an HTTP request to the OpenAI API
--- using cURL.
---
---@param data table
---@return string[]
function M.make_curl_args(data, opts)
  local url = opts and opts.url or URL
  local api_key = os.getenv(opts and opts.api_key_name or API_KEY_NAME)

  if not api_key then
    error(API_ERROR_MESSAGE:format(API_KEY_NAME, API_KEY_NAME), 1)
  end

  local args = {
    '-s', --silent
    '-N', --no buffer
    '-X',
    'POST',
    '-H',
    'Content-Type: application/json',
    '-d',
    vim.json.encode(data),
    '-H',
    'Authorization: Bearer ' .. api_key,
    url,
  }

  return args
end

--- Process server-sent events based on OpenAI spec
--- [See Documentation](https://platform.openai.com/docs/api-reference/chat/create#chat-create-stream)
---
---@param out string
---@return string
local function handle_data(out)
  -- based on sse spec (OpenAI spec uses data-only server-sent events)
  local data, data_epos
  _, data_epos = string.find(out, '^data: ')

  if data_epos then
    data = string.sub(out, data_epos + 1)
  end

  local content = ''

  if data and data:match '"delta":' then
    local json = vim.json.decode(data)
    if json.choices and json.choices[1] and json.choices[1].delta and json.choices[1].delta.content then
      content = json.choices[1].delta.content
    else
      vim.print(data)
    end
  end

  return content
end

---@param args table
---@param writer_fn fun(content: string)
function M.make_job(args, writer_fn, on_exit_fn)
  local active_job = Job:new {
    command = 'curl',
    args = args,
    on_stdout = function(_, out)
      local content = handle_data(out)
      if content and content ~= nil then
        vim.schedule(function()
          writer_fn(content)
        end)
      end
    end,
    on_stderr = function(message, _)
      error(message, 1)
    end,
    on_exit = function()
      vim.schedule(function()
        on_exit_fn()
      end)
    end,
  }
  return active_job
end

---Example implementation of a `make_data_fn` compatible with `kznllm.invoke_llm` for groq spec
---@param prompt_args any
---@param opts any
---@return table
function M.make_data_for_chat(prompt_args, opts)
  local template_path = Path:new(opts and opts.template_path or TEMPLATE_PATH)
  local messages = {
    {
      role = 'system',
      content = kznllm.make_prompt_from_template(template_path / M.MESSAGE_TEMPLATES.FILL_MODE_SYSTEM_PROMPT, prompt_args),
    },
    {
      role = 'user',
      content = kznllm.make_prompt_from_template(template_path / M.MESSAGE_TEMPLATES.FILL_MODE_USER_PROMPT, prompt_args),
    },
  }

  local data = {
    messages = messages,
    model = M.MODELS[M.SELECTED_MODEL_IDX].name,
    temperature = 0.7,
    stream = true,
  }

  if opts and opts.debug then
    local extmark_id = vim.api.nvim_buf_set_extmark(kznllm.BUFFER_STATE.SCRATCH, kznllm.NS_ID, 0, 0, {})
    kznllm.write_content_at_extmark('model: ' .. M.MODELS[M.SELECTED_MODEL_IDX].name, extmark_id)
    kznllm.write_content_at_extmark('\n\n---\n\n', extmark_id)
    for _, message in ipairs(data.messages) do
      kznllm.write_content_at_extmark(message.role .. ':\n\n', extmark_id)
      kznllm.write_content_at_extmark(message.content, extmark_id)
      kznllm.write_content_at_extmark('\n\n---\n\n', extmark_id)
      vim.cmd 'normal! G'
    end
  end

  return data
end

return M
