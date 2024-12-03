local BaseProvider = require('kznllm.specs')
local utils = require('kznllm.utils')

local M = {}

---@class OpenAIProvider : BaseProvider
---@field make_curl_args fun(self, opts: OpenAICurlOptions)
M.OpenAIProvider = {}

---@param opts? BaseProviderOptions
---@return OpenAIProvider
function M.OpenAIProvider:new(opts)
  -- Call parent constructor with base options

  local o = opts or {}
  local instance = BaseProvider:new({
    api_key_name = o.api_key_name or 'OPENAI_API_KEY',
    base_url = o.base_url or 'https://api.openai.com',
  })

  -- Set proper metatable for inheritance
  setmetatable(instance, { __index = self })
  setmetatable(self, { __index = BaseProvider })

  ---silence lsp warning
  ---@type OpenAIProvider
  return instance
end

---
--- TYPE ANNOTATIONS
---

---@class OpenAICurlOptions : OpenAIHeaders
---@field data OpenAIBody

---@class OpenAIHeaders
---@field endpoint string
---@field auth_format? string
---@field extra_headers? string[]

---@class OpenAIBody : OpenAIParameters, OpenAIPromptContext

---@class OpenAIPromptContext
---@field messages OpenAIMessage[]

---@class OpenAIParameters
---@field model string
---@field max_tokens? integer
---@field max_completion_tokens? integer
---@field temperature? number
---@field top_p? number
---@field frequency_penalty? number
---@field presence_penalty? number

---@alias OpenAIMessageRole "system" | "user" | "assistant"
---@class OpenAIMessage
---@field role OpenAIMessageRole
---@field content string | OpenAIMessageContent[]

---@alias OpenAIMessageContentType "text" | "image"
---@class OpenAIMessageContent
---@field type OpenAIMessageContentType
---@field text string

--- Process server-sent events based on OpenAI spec
--- [See Documentation](https://platform.openai.com/docs/api-reference/chat/create#chat-create-stream)
---
---@param buf string
---@return string
function M.OpenAIProvider.handle_sse_stream(buf)
  -- based on sse spec (OpenAI spec uses data-only server-sent events)
  local content = ''

  for data in buf:gmatch('data: ({.-})\n') do
    -- if data and data:match '"delta":' then
    local json = vim.json.decode(data)
    -- sglang server returns the role as one of the events and it becomes `vim.NIL`, so we have to handle it here
    if json.choices and json.choices[1] and json.choices[1].delta and json.choices[1].delta.content then
      content = content .. json.choices[1].delta.content
    else
      vim.print(data)
    end
    -- end
  end

  return content
end

---@class OpenAIPresetConfig
---@field id string
---@field description string
---@field curl_options OpenAICurlOptions

---@class OpenAIPresetSystemTemplate
---@field path string

---@class OpenAIPresetMessageTemplate
---@field type OpenAIMessageContentType
---@field role OpenAIMessageRole
---@field path string

---@class OpenAIPresetBuilder : BasePresetBuilder
---@field provider OpenAIProvider
---@field system_templates OpenAIPresetSystemTemplate[]
---@field message_templates OpenAIPresetMessageTemplate[]
---@field debug_template? string
---@field headers OpenAIHeaders
---@field params OpenAIParameters
M.OpenAIPresetBuilder = {}

local openai_template_path = utils.join_path({ utils.TEMPLATE_PATH, 'openai' })

---@param opts? { provider: OpenAIProvider, headers: OpenAIHeaders, params: OpenAIParameters, debug_template_path: string }
---@return OpenAIPresetBuilder
function M.OpenAIPresetBuilder:new(opts)
  local o = opts or {}
  local instance = {
    provider = o.provider or M.OpenAIProvider:new(),
    debug_template_path = o.debug_template_path or utils.join_path({ openai_template_path, 'debug.xml.jinja' }),
    headers = o.headers or { endpoint = '/v1/chat/completions' },
    params = (opts and opts.params) and opts.params or {
      ['model'] = 'o1-mini',
      ['stream'] = true,
    },
    system_templates = {},
    message_templates = {},
  }
  setmetatable(instance, { __index = self })
  return instance
end

---@param opts { params: OpenAIParameters, headers: OpenAIHeaders, provider: OpenAIProvider }
function M.OpenAIPresetBuilder:with_opts(opts)
  local cpy = vim.deepcopy(self)
  for k, v in pairs(opts) do
    cpy[k] = v
  end
  return cpy
end

---@param system_templates OpenAIPresetSystemTemplate[]
function M.OpenAIPresetBuilder:add_system_prompts(system_templates)
  for _, template in ipairs(system_templates) do
    table.insert(self.system_templates, 1, template)
  end
  return self
end

---@param message_templates OpenAIPresetMessageTemplate[]
function M.OpenAIPresetBuilder:add_message_prompts(message_templates)
  for _, template in ipairs(message_templates) do
    table.insert(self.message_templates, template)
  end
  return self
end

---@return OpenAICurlOptions
function M.OpenAIPresetBuilder:build(args)
  ---@type OpenAIMessage[]
  local messages = {}

  for _, template in ipairs(self.system_templates) do
    table.insert(messages, {
      role = 'system',
      content = utils.make_prompt_from_template({ template_path = template.path, prompt_args = args }),
    })
  end

  for _, template in ipairs(self.message_templates) do
    if template.type == 'text' then
      local message_content = {
        type = template.type,
        text = utils.make_prompt_from_template({ template_path = template.path, prompt_args = args }),
      }

      table.insert(messages, {
        role = template.role,
        content = { message_content },
      })
    end
  end

  return vim.tbl_extend('keep', self.headers, {
    data = vim.tbl_extend('keep', self.params, { messages = messages }),
  })
end

return M
