local BaseProvider = require('kznllm.specs')
local utils = require('kznllm.utils')

local M = {}

---@class AnthropicProvider : BaseProvider
M.AnthropicProvider = {}

---@param opts? BaseProviderOptions
---@return AnthropicProvider
function M.AnthropicProvider:new(opts)
  -- Call parent constructor with base options
  local o = opts or {}
  local instance = BaseProvider:new({
    api_key_name = o.api_key_name or 'ANTHROPIC_API_KEY',
    base_url = o.base_url or 'https://api.anthropic.com',
  })

  -- Set proper metatable for inheritance
  setmetatable(instance, { __index = self })
  setmetatable(self, { __index = BaseProvider })

  ---silence lsp warning
  ---@type AnthropicProvider
  return instance
end

---
--- TYPE ANNOTATIONS
---

---@class AnthropicCurlOptions : AnthropicAPIHeaders
---@field data AnthropicAPIBody

---@class AnthropicAPIHeaders
---@field endpoint string
---@field auth_format? string
---@field extra_headers? string[]

---@class AnthropicAPIBody : AnthropicParameters, AnthropicPromptContext

---@class AnthropicPromptContext
---@field system AnthropicSystemContext[]
---@field messages AnthropicMessage[]

---@class AnthropicParameters
---@field model string | 'claude-3-5-sonnet-latest' | 'claude-3-5-haiku-latest'
---@field stop_sequences? string[]
---@field max_tokens? integer
---@field temperature? number
---@field top_k? integer
---@field top_p? number
---@field stream? boolean
---@field tool_choice? table
---@field tools? table[]

---@class AnthropicSystemContext
---@field type AnthropicSystemContentType
---@field text string
---@field cache_control? AnthropicCacheControl

---@alias AnthropicSystemContentType "text"
---@alias AnthropicMessageContentType "text" | "image" | "tool_use" | "tool_result" | "document"

---@class AnthropicCacheControl
---@field type "ephemeral"

---@alias AnthropicMessageRole "user" | "assistant"

---@class AnthropicMessageTextContent
---@field type "text"
---@field text string

---@class AnthropicMessage
---@field role AnthropicMessageRole
---@field content string | AnthropicMessageTextContent[]

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
function M.AnthropicProvider.handle_sse_stream(line)
  local content = ''
  for event, data in line:gmatch('event: ([%w_]+)\ndata: ({.-})\n') do
    if event == 'content_block_delta' then
      local json = vim.json.decode(data)
      if json.delta and json.delta.text then
        content = content .. json.delta.text
      end
    elseif event == 'content_block_start' then
    elseif event == 'content_block_stop' then
    elseif event == 'message_start' then
      vim.print(data)
    elseif event == 'message_stop' then
    elseif event == 'message_delta' then
    elseif event == 'ping' then
    elseif event == 'error' then
      vim.print(data)
    else
      vim.print(data)
    end
  end

  return content
end

---@class AnthropicPresetSystemTemplate
---@field type AnthropicSystemContentType
---@field path string
---@field cache_control? AnthropicCacheControl

---@class AnthropicPresetMessageTemplate
---@field role AnthropicMessageRole
---@field type AnthropicMessageContentType
---@field path string
---@field cache_control? AnthropicCacheControl

---@class AnthropicPresetBuilder : BasePresetBuilder
---@field provider AnthropicProvider
---@field debug_template? string
---@field system_templates AnthropicPresetSystemTemplate[]
---@field message_templates AnthropicPresetMessageTemplate[]
---@field headers AnthropicAPIHeaders
---@field params AnthropicParameters
M.AnthropicPresetBuilder = {}

local anthropic_template_path = utils.join_path({ utils.TEMPLATE_PATH, 'anthropic' })

---@param opts? { provider?: AnthropicProvider, debug_template_path?: string, headers?: AnthropicAPIHeaders, params?: AnthropicParameters }
---@return AnthropicPresetBuilder
function M.AnthropicPresetBuilder:new(opts)
  local o = opts or {}
  local instance = {
    debug_template_path = o.debug_template_path or utils.join_path({ anthropic_template_path, 'debug.xml.jinja' }),
    provider = o.provider or M.AnthropicProvider:new(),
    headers = o.headers or {
      endpoint = '/v1/messages',
      auth_format = 'x-api-key: %s',
      extra_headers = {
        'anthropic-version: 2023-06-01',
        'anthropic-beta: prompt-caching-2024-07-31',
      },
    },
    params = o.params or {
      ['model'] = 'claude-3-5-sonnet-20241022',
      ['stream'] = true,
      ['max_tokens'] = 8192,
      ['temperature'] = 0.7,
    },
    system_templates = {},
    message_templates = {},
  }
  setmetatable(instance, { __index = self })
  return instance
end

---@param opts { params: AnthropicParameters, headers: AnthropicAPIHeaders, provider: AnthropicProvider }
function M.AnthropicPresetBuilder:with_opts(opts)
  local cpy = vim.deepcopy(self)
  for k, v in pairs(opts) do
    cpy[k] = v
  end
  return cpy
end

--- Mutates the builder's system templates
---@param system_templates AnthropicPresetSystemTemplate[]
function M.AnthropicPresetBuilder:add_system_prompts(system_templates)
  for _, template in ipairs(system_templates) do
    table.insert(self.system_templates, template)
  end
  return self
end

--- Mutates the builder's message templates
---@param message_templates AnthropicPresetMessageTemplate[]
function M.AnthropicPresetBuilder:add_message_prompts(message_templates)
  for _, template in ipairs(message_templates) do
    table.insert(self.message_templates, template)
  end
  return self
end

---Renders all templates and builds curl args in the correct format according to Anthropic API spec
---@return AnthropicCurlOptions
function M.AnthropicPresetBuilder:build(args)
  ---@type AnthropicSystemContext[]
  local system = {}

  for _, template in ipairs(self.system_templates) do
    if template.type == 'text' then
      table.insert(system, {
        type = template.type,
        text = utils.make_prompt_from_template({ template_path = template.path, prompt_args = args }),
        cache_control = template.cache_control,
      })
    end
  end

  ---@type AnthropicMessage[]
  local messages = {}

  for _, template in ipairs(self.message_templates) do
    if template.type == 'text' then
      local message_content = {
        type = 'text',
        text = utils.make_prompt_from_template({ template_path = template.path, prompt_args = args }),
        cache_control = template.cache_control,
      }
      table.insert(messages, {
        role = template.role,
        content = { message_content },
      })
    end
  end

  return vim.tbl_extend('keep', self.headers, {
    data = vim.tbl_extend('keep', self.params, { system = system, messages = messages }),
  })
end

return M
