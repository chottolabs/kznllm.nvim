local M = {}
M.API_KEY_NAME = 'GROQ_API_KEY'
M.URL = 'https://api.groq.com/openai/v1/chat/completions'

M.MODELS = {
  LLAMA_3_70B = 'llama3-70b-8192',
}
M.SELECTED_MODEL = M.MODELS.LLAMA_3_70B

M.PROMPT_TEMPLATES = {
  --- this prompt should let the model yap into a separate buffer
  HELPFUL_PROMPT = [[You are an AI programming assistant integrated into a code editor. Your purpose is to help the user with programming tasks as they write code.
Key capabilities:
- Thoroughly analyze the user's code and provide insightful suggestions for improvements related to best practices, performance, readability, and maintainability. Explain your reasoning.
- Answer coding questions in detail, using examples from the user's own code when relevant. Break down complex topics step- Spot potential bugs and logical errors. Alert the user and suggest fixes.
- Upon request, add helpful comments explaining complex or unclear code.
- Suggest relevant documentation, StackOverflow answers, and other resources related to the user's code and questions.
- Engage in back-and-forth conversations to understand the user's intent and provide the most helpful information.
- Keep concise and use markdown.
- When asked to create code, only generate the code. No bugs.
- Think step by step]],

  --- this prompt has to be written to output valid code
  REPLACE_PROMPT = [[You should replace the code that you are sent, only following the comments. Do not talk at all. Only output valid code. Do not provide any backticks that surround the code. Never ever output backticks like this ```. Any comment that is asking you for something should be removed after you satisfy them. Other comments should left alone. Do not output backticks]],
}

local API_ERROR_MESSAGE = [[
ERROR: groq api key is set to %s and is missing from your environment variables.

Load somewhere safely from config `export %s=<api_key>`]]

local Job = require 'plenary.job'
local utils = require 'kznllm.utils'

--- Constructs arguments for constructing an HTTP request to the OpenAI API
--- using cURL.
---
---@param user_prompt string
---@param system_prompt string
---@return string[]
local function make_curl_args(system_prompt, user_prompt)
  local url = M.URL
  local api_key = os.getenv(M.API_KEY_NAME)
  local data = {
    messages = { { role = 'system', content = system_prompt }, { role = 'user', content = user_prompt } },
    model = M.SELECTED_MODEL,
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
---@param data string
---@return string
local function handle_data(data)
  local content = ''

  if data and data:match '"delta":' then
    local json = vim.json.decode(data)
    if json.choices and json.choices[1] and json.choices[1].delta and json.choices[1].delta.content then
      content = json.choices[1].delta.content
    end
  end

  return content
end

function M.make_job(system_prompt, user_prompt)
  local active_job = Job:new {
    command = 'curl',
    args = make_curl_args(system_prompt, user_prompt),
    on_stdout = function(_, out)
      -- based on sse spec (OpenAI spec uses data-only server-sent events)
      local data, data_epos
      _, data_epos = string.find(out, '^data: ')

      if data_epos then
        data = string.sub(out, data_epos + 1)
      end

      local content = handle_data(data)
      if content and content ~= nil then
        utils.write_content_at_cursor(content)
      end
    end,
    on_stderr = function(_, _) end,
    on_exit = function() end,
  }
  return active_job
end

return M
