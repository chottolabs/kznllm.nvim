local M = {}

--- Constructs arguments for constructing an HTTP request to the OpenAI API
--- using cURL.
---
---@param opts { api_key_name: string, url: string, model: string }
---@param prompt string
---@param system_prompt string
---@return string[]
function M.make_openai_spec_curl_args(opts, prompt, system_prompt)
  local url = opts.url
  local api_key = opts.api_key_name and os.getenv(opts.api_key_name)
  local data = {
    messages = { { role = 'system', content = system_prompt }, { role = 'user', content = prompt } },
    model = opts.model,
    temperature = 0.7,
    stream = true,
  }
  local args = { '-N', '-X', 'POST', '-H', 'Content-Type: application/json', '-d', vim.json.encode(data) }
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
---@param line string
---@return string
function M.handle_openai_spec_data(line)
  -- based on sse spec (OpenAI spec uses data-only server-sent events)
  local data, data_epos
  _, data_epos = string.find(line, '^data: ')

  if data_epos then
    data = string.sub(line, data_epos + 1)
  end

  local content = ''

  if data and data:match '"delta":' then
    local json = vim.json.decode(data)
    if json.choices and json.choices[1] and json.choices[1].delta then
      content = json.choices[1].delta.content
    end
  end

  return content
end

return M
