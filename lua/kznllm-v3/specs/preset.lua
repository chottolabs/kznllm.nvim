-- Preset configuration builder
---@class BasePresetConfig
---@field id string
---@field description string
---@field curl_options BaseProviderCurlOptions

---@class BaseProviderHeaderOptions
---@field endpoint string
---@field auth_format? string
---@field extra_headers? string[]

---@class BaseProviderCurlOptions: BaseProviderHeaderOptions
---@field data table

---@class BaseParameters
---@field model string

---@class BaseHeaders
---@field endpoint string
---@field auth_format? string
---@field extra_headers? string[]

---@class BasePresetBuilder
---@field debug_template_path? Path
---@field provider BaseProvider
---@field config BasePresetConfig
---@field system_templates table[]
---@field message_templates table[]
---@field headers BaseHeaders
---@field params BaseParameters
local BasePresetBuilder = {}

---@param opts { provider: BaseProvider, config: BasePresetConfig }
---@return BasePresetBuilder
function BasePresetBuilder:new(opts)
  local instance = { provider = opts.provider, config = opts.config }
  setmetatable(instance, { __index = self })
  return instance
end

---@param templates table[]
function BasePresetBuilder:add_system_templates(templates)
  error('add_system_templates NOT IMPLEMENTED', 1)
end

---@param templates table[]
function BasePresetBuilder:add_message_templates(templates)
  error('add_message_templates NOT IMPLEMENTED', 1)
end

---@param params table
function BasePresetBuilder:with_params(params)
  error('with_params NOT IMPLEMENTED', 1)
end

---@param prompt_args table
---@return BaseProviderCurlOptions
function BasePresetBuilder:build(prompt_args)
  error('build NOT IMPLEMENTED', 1)
end

return BasePresetBuilder
