local BaseProvider = require('kznllm.specs')
local utils = require('kznllm.utils')

local M = {}

---@class DeepSeekProvider : BaseProvider
---@field make_curl_args fun(self, opts: DeepSeekCurlOptions)
M.DeepSeekProvider = {}

---@param opts? BaseProviderOptions
---@return DeepSeekProvider
function M.DeepSeekProvider:new(opts)
  -- Call parent constructor with base options

  local o = opts or {}
  local instance = BaseProvider:new({
    api_key_name = o.api_key_name or 'DeepSeek_API_KEY',
    base_url = o.base_url or 'https://api.deepseek.com',
  })

  -- Set proper metatable for inheritance
  setmetatable(instance, { __index = self })
  setmetatable(self, { __index = BaseProvider })

  ---silence lsp warning
  ---@type DeepSeekProvider
  return instance
end

---
--- TYPE ANNOTATIONS
---

---@class DeepSeekCurlOptions : DeepSeekHeaders
---@field data DeepSeekBody

---@class DeepSeekHeaders
---@field endpoint string
---@field auth_format? string
---@field extra_headers? string[]

---@class DeepSeekBody : DeepSeekParameters, DeepSeekPromptContext

---@class DeepSeekPromptContext
---@field messages DeepSeekMessage[]

---@class DeepSeekParameters
---@field model string
---@field max_tokens? integer
---@field max_completion_tokens? integer
---@field temperature? number
---@field top_p? number
---@field frequency_penalty? number
---@field presence_penalty? number

---@alias DeepSeekMessageRole "system" | "user" | "assistant"
---@class DeepSeekMessage
---@field role DeepSeekMessageRole
---@field content string | DeepSeekMessageContent[]

---@alias DeepSeekMessageContentType "text" | "image"
---@class DeepSeekMessageContent
---@field type DeepSeekMessageContentType
---@field text string

--- Process server-sent events based on DeepSeek spec
--- [See Documentation](https://platform.openai.com/docs/api-reference/chat/create#chat-create-stream)
---
---@param buf string
---@return string
function M.DeepSeekProvider.handle_sse_stream(buf)
  -- based on sse spec (DeepSeek spec uses data-only server-sent events)
  local content = ''

  vim.print(buf)
  for data in buf:gmatch('data: ({.-})\n') do
    -- if data and data:match '"delta":' then
    local json = vim.json.decode(data)
    -- reasoning returns null for content which turns into `vim.NIL`, so we have to handle it here
    if json.choices[1].delta.content and json.choices[1].delta.content ~= vim.NIL then
      content = content .. json.choices[1].delta.content
    elseif json.choices[1].delta.reasoning_content and json.choices[1].delta.reasoning_content ~= vim.NIL then
      content = content .. json.choices[1].delta.reasoning_content
    else
      vim.print(data)
    end
    -- end
  end

  return content
end

---@class DeepSeekPresetConfig
---@field id string
---@field description string
---@field curl_options DeepSeekCurlOptions

---@class DeepSeekPresetSystemTemplate
---@field path string

---@class DeepSeekPresetMessageTemplate
---@field type DeepSeekMessageContentType
---@field role DeepSeekMessageRole
---@field path string

---@class DeepSeekPresetBuilder : BasePresetBuilder
---@field provider DeepSeekProvider
---@field system_templates DeepSeekPresetSystemTemplate[]
---@field message_templates DeepSeekPresetMessageTemplate[]
---@field debug_template? string
---@field headers DeepSeekHeaders
---@field params DeepSeekParameters
M.DeepSeekPresetBuilder = {}

local openai_template_path = utils.join_path({ utils.TEMPLATE_PATH, 'openai' })

---@param opts? { provider: DeepSeekProvider, headers: DeepSeekHeaders, params: DeepSeekParameters, debug_template_path: string }
---@return DeepSeekPresetBuilder
function M.DeepSeekPresetBuilder:new(opts)
  local o = opts or {}
  local instance = {
    provider = o.provider or M.DeepSeekProvider:new(),
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

---@param opts { params: DeepSeekParameters, headers: DeepSeekHeaders, provider: DeepSeekProvider }
function M.DeepSeekPresetBuilder:with_opts(opts)
  local cpy = vim.deepcopy(self)
  for k, v in pairs(opts) do
    cpy[k] = v
  end
  return cpy
end

---@param system_templates DeepSeekPresetSystemTemplate[]
function M.DeepSeekPresetBuilder:add_system_prompts(system_templates)
  for _, template in ipairs(system_templates) do
    table.insert(self.system_templates, 1, template)
  end
  return self
end

---@param message_templates DeepSeekPresetMessageTemplate[]
function M.DeepSeekPresetBuilder:add_message_prompts(message_templates)
  for _, template in ipairs(message_templates) do
    table.insert(self.message_templates, template)
  end
  return self
end

---@return DeepSeekCurlOptions
function M.DeepSeekPresetBuilder:build(args)
  ---@type DeepSeekMessage[]
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
