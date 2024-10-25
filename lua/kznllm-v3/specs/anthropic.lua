local BaseProvider = require 'kznllm-v3.specs'

local M = {}

---
--- TYPE ANNOTATIONS
---

---@class AnthropicCurlOptions
---@field endpoint string
---@field auth_format? string
---@field extra_headers? string[]
---@field data AnthropicAPIBody
---
---@class AnthropicAPIBody : AnthropicParameters
---@field system AnthropicSystemContext[]
---@field messages AnthropicMessage[]

---@class AnthropicParameters
---@field model string
---@field stop_sequences? string[]
---@field max_tokens? integer
---@field temperature? number
---@field top_k? integer
---@field top_p? number
---@field stream? boolean
---@field tool_choice? table
---@field tools? table[]

---@class AnthropicSystemContext
---@field type "text"
---@field text string
---@field cache_control? { type: "ephemeral" }
---
---@class AnthropicMessage
---@field role "user" | "assistant"
---@field content string

---@class AnthropicProvider : BaseProvider
M.AnthropicProvider = BaseProvider:new({
  api_key_name = 'ANTHROPIC_API_KEY',
  base_url = 'https://api.anthropic.com',
})

---
--- DATA HANDLERS
---

local current_event_state

--- Anthropic SSE Specification
--- [See Documentation](https://docs.anthropic.com/en/api/messages-streaming#event-types)
---
--- Each server-sent event includes a named event type and associated JSON
--- data. Each event will use an SSE event name (e.g. event: message_stop),
--- and include the matching event type in its data.
---
--- Each stream uses the following event flow:
---
--- 1. `message_start`: contains a Message object with empty content.
---
--- 2. A series of content blocks, each of which have a `content_block_start`,
---    one or more `content_block_delta` events, and a `content_block_stop`
---    event. Each content block will have an index that corresponds to its
---    index in the final Message content array.
---
--- 3. One or more `message_delta` events, indicating top-level changes to the
---    final Message object.
--- 4. `message_stop` event
---
--- event types: `[message_start, content_block_start, content_block_delta, content_block_stop, message_delta, message_stop, error]`
---@param line string
---@return string?
function M.AnthropicProvider:handle_sse_stream(line)
  local event = line:match('^event: (.+)$')
  if event then
    current_event_state = event
    return nil
  end

  local data
  if current_event_state == 'content_block_delta' then
    data = line:match('^data: (.+)$')
    if data then
      local json = vim.json.decode(data)
      if json.delta and json.delta.text then
        return json.delta.text
      end
    end
  elseif current_event_state == 'message_start' then
    data = line:match '^data: (.+)$'
  elseif current_event_state == 'message_delta' then
    data = line:match '^data: (.+)$'
  end

  if data then
    vim.print(data)
  end
end

return M
