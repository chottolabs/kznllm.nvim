local M = {}

local Job = require 'plenary.job'
local utils = require 'kznllm.utils'

--- Constructs arguments for constructing an HTTP request to the OpenAI API
--- using cURL.
---
---@param opts { api_key_name: string, url: string, model: string }
---@param user_prompt string
---@param system_prompt string
---@return string[]
local function make_curl_args(opts, system_prompt, user_prompt)
  local url = opts.url
  local api_key = opts.api_key_name and os.getenv(opts.api_key_name)
  local data = {
    messages = { { role = 'system', content = system_prompt }, { role = 'user', content = user_prompt } },
    model = opts.model,
    temperature = 0.7,
    stream = true,
  }
  local args = { '-s', '-N', '-X', 'POST', '-H', 'Content-Type: application/json', '-d', vim.json.encode(data) }
  if api_key then
    table.insert(args, '-H')
    table.insert(args, 'Authorization: Bearer ' .. api_key)
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

function M.make_job(opts, system_prompt, user_prompt)
  local active_job = Job:new {
    command = 'curl',
    args = make_curl_args(opts, system_prompt, user_prompt),
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
