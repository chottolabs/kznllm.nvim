local BaseProvider = require 'kznllm.specs'
local Path = require 'plenary.path'
local utils = require 'kznllm.utils'

local M = {}

---@class OpenAIProvider : BaseProvider
M.OpenAIProvider = {}

---@param opts? BaseProviderOptions
---@return OpenAIProvider
function M.OpenAIProvider:new(opts)
  -- Call parent constructor with base options

  local instance = BaseProvider:new({
    api_key_name = (opts and opts.api_key_name) and opts.api_key_name or 'OPENAI_API_KEY',
    base_url = (opts and opts.base_url) and opts.base_url or 'https://api.openai.com',
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
function M.OpenAIProvider:handle_sse_stream(buf)
  -- based on sse spec (OpenAI spec uses data-only server-sent events)
  local content = ''

  for data in buf:gmatch('data: ({.-})\n') do
    if data and data:match '"delta":' then
      local json = vim.json.decode(data)
      -- sglang server returns the role as one of the events and it becomes `vim.NIL`, so we have to handle it here
      if json.choices and json.choices[1] and json.choices[1].delta and json.choices[1].delta.content and json.choices[1].delta.content ~= vim.NIL then
        content = content .. json.choices[1].delta.content
      else
        vim.print(data)
      end
    end
  end

  return content
end

---@class OpenAIPresetConfig
---@field id string
---@field description string
---@field curl_options OpenAICurlOptions

---@class OpenAIPresetSystemTemplate
---@field path Path

---@class OpenAIPresetMessageTemplate
---@field type OpenAIMessageContentType
---@field role OpenAIMessageRole
---@field path Path

---@class OpenAIPresetBuilder : BasePresetBuilder
---@field provider OpenAIProvider
---@field system_templates OpenAIPresetSystemTemplate[]
---@field message_templates OpenAIPresetMessageTemplate[]
---@field debug_template? Path
---@field headers OpenAIHeaders
---@field params OpenAIParameters
M.OpenAIPresetBuilder = {}

---@param opts? { provider: OpenAIProvider, headers: OpenAIHeaders, params: OpenAIParameters, debug_template_path: Path }
---@return OpenAIPresetBuilder
function M.OpenAIPresetBuilder:new(opts)
  local instance = {
    provider = (opts and opts.provider) and opts.provider or M.OpenAIProvider:new(),
    debug_template_path = (opts and opts.debug_template_path) or utils.TEMPLATE_PATH / 'openai' / 'debug.xml.jinja',
    headers = (opts and opts.headers) and opts.headers or {
      endpoint = '/v1/chat/completions',
      extra_headers = {},
    },
    params = (opts and opts.params) and opts.params or {
      ['model'] = 'o1-mini',
      ['stream'] = true,
    },
    system_templates = {},
    message_templates = {}
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
    table.insert(
      messages,
      {
        role = "system",
        content = utils.make_prompt_from_template {
          template_path = template.path,
          prompt_args = args,
        }
      })
  end

  for _, template in ipairs(self.message_templates) do
    if template.type == "text" then
      table.insert(
        messages,
        {
          role = template.role,
          content = {
            {
              type = template.type,
              text = utils.make_prompt_from_template {
                template_path = template.path,
                prompt_args = args,
              }
            },
          }
        })
    end
  end

  return vim.tbl_extend(
    'keep',
    self.headers,
    {
      data = vim.tbl_extend(
        'keep',
        self.params,
        { messages = messages }
      )
    })
end

return M
