local BaseProvider = require 'kznllm-v3.specs'

local M = {}

---@class OpenAIProvider : BaseProvider
M.OpenAIProvider = BaseProvider:new {
  api_key_name = 'OPENAI_API_KEY',
  base_url = 'https://api.openai.com',
}

---@class LambdaProvider : OpenAIProvider
M.LambdaProvider = M.OpenAIProvider:new {
  api_key_name = 'LAMBDA_API_KEY',
  base_url = 'https://api.lambdalabs.com',
}

---@class GroqProvider : OpenAIProvider
M.GroqProvider = M.OpenAIProvider:new {
  api_key_name = 'GROQ_API_KEY',
  base_url = 'https://api.groq.com/openai',
}

---@class DeepSeekProvider : OpenAIProvider
M.DeepSeekProvider = M.OpenAIProvider:new {
  api_key_name = 'DEEPSEEK_API_KEY',
  base_url = 'https://api.deepseek.com',
}

---@class VLLMProvider : OpenAIProvider
M.VLLMProvider = M.OpenAIProvider:new {
  api_key_name = 'VLLM_API_KEY',
  base_url = 'http://research.local:8000',
}

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
---@param buf string
---@return string
function M.OpenAIProvider:handle_sse_stream(buf)
  -- based on sse spec (OpenAI spec uses data-only server-sent events)
  local content = {}

  for data in buf:gmatch('data: (%b{})%s+') do
    if data and data:match '"delta":' then
      local json = vim.json.decode(data)
      -- sglang server returns the role as one of the events and it becomes `vim.NIL`, so we have to handle it here
      if json.choices and json.choices[1] and json.choices[1].delta and json.choices[1].delta.content and json.choices[1].delta.content ~= vim.NIL then
        table.insert(content, json.choices[1].delta.content)
      else
        vim.print(data)
      end
    end
  end

  return table.concat(content, '')
end

return M
