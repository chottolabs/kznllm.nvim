local M = {}
-- can overwrite in lazy config so that it uses different setting at runtime
M.API_KEY_NAME = 'GROQ_API_KEY'
M.URL = 'https://api.groq.com/openai/v1/chat/completions'

M.MODELS = {
  LLAMA_3_1_405B = { name = 'llama-3.1-405b-reasoning', max_tokens = 131072 },
  LLAMA_3_1_70B = { name = 'llama-3.1-70b-versatile', max_tokens = 131072 },
  LLAMA_3_70B = { name = 'llama3-70b-8192', max_tokens = 8192 },
}
M.SELECTED_MODEL = M.MODELS.LLAMA_3_1_70B

M.PROMPT_TEMPLATES = {

  NOUS_RESEARCH = {
    FILL_MODE_SYSTEM_PROMPT = 'nous_research/fill_mode_system_prompt.xml.jinja',
    FILL_MODE_USER_PROMPT = 'nous_research/fill_mode_user_prompt.xml.jinja',
  },

  GROQ = {
    --- this prompt has to be written to output valid code
    FILL_MODE_SYSTEM_PROMPT = 'groq/fill_mode_system_prompt.xml.jinja',
    FILL_MODE_USER_PROMPT = 'groq/fill_mode_user_prompt.xml.jinja',
  },
}

local API_ERROR_MESSAGE = [[
ERROR: api key is set to %s and is missing from your environment variables.

Load somewhere safely from config `export %s=<api_key>`]]

local Job = require 'plenary.job'

--- Constructs arguments for constructing an HTTP request to the OpenAI API
--- using cURL.
---
---@param rendered_messages { role: string, content: string }[]
---@return string[]
local function make_curl_args(rendered_messages)
  local url = M.URL
  local api_key = os.getenv(M.API_KEY_NAME)

  local data = {
    messages = rendered_messages,
    model = M.SELECTED_MODEL.name,
    temperature = 0.7,
    stream = true,
  }

  local args = { '-s', '-N', '-X', 'POST', '-H', 'Content-Type: application/json', '-d', vim.json.encode(data) }
  if api_key then
    table.insert(args, '-H')
    table.insert(args, 'Authorization: Bearer ' .. api_key)
  else
    error(string.format(API_ERROR_MESSAGE, M.API_KEY_NAME, M.API_KEY_NAME), 1)
  end
  table.insert(args, url)
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

---@param rendered_messages { role: string, content: string }[]
---@param writer_fn fun(content: string)
function M.make_job(rendered_messages, writer_fn, on_exit_fn)
  local active_job = Job:new {
    command = 'curl',
    args = make_curl_args(rendered_messages),
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

return M
