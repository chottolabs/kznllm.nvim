local BaseProvider = require 'kznllm-v3.specs'


local M = {}

---@class OpenAIProvider : BaseProvider
M.OpenAIProvider = BaseProvider:new({
  api_key_name = 'OPENAI_API_KEY',
  base_url = 'https://api.openai.com',
})

---@class LambdaProvider : OpenAIProvider
M.LambdaProvider = BaseProvider:new({
  api_key_name = 'LAMBDA_API_KEY',
  base_url = 'https://api.lambdalabs.com',
})

---@class GroqProvider : OpenAIProvider
M.GroqProvider = BaseProvider:new({
  api_key_name = 'GROQ_API_KEY',
  base_url = 'https://api.groq.com/openai',
})

---@class DeepSeekProvider : OpenAIProvider
M.GroqProvider = BaseProvider:new({
  api_key_name = 'DEEPSEEK_API_KEY',
  base_url = 'https://api.deepseek.com',
})


---
--- TYPE ANNOTATIONS
---

---@class OpenAIAPIBody : OpenAIParameters
---@field messages OpenAIMessage[]
---@field stop? string[] | string
---@field stream? boolean
---@field stream_options? { include_usage: boolean }
---@field n? integer
---@field tool_choice? table
---@field tools? table[]
---@field response_format? { type: "json_object" } | { type: "json_schema", json_schema: table }

---@class OpenAIParameters
---@field max_completion_tokens? integer
---@field temperature? number
---@field top_p? number
---@field frequency_penalty? number
---@field presence_penalty? number

---@class OpenAIMessage
---@field role "system" | "user" | "assistant"
---@field content string

--- Process server-sent events based on OpenAI spec
--- [See Documentation](https://platform.openai.com/docs/api-reference/chat/create#chat-create-stream)
---
---@param line string
---@return string
function M.OpenAIProvider:handle_sse_stream(line)
  -- based on sse spec (OpenAI spec uses data-only server-sent events)
  local data = line:match '^data: (.+)$'

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

return M
