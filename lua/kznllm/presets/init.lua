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
---@field debug_template_path? string
---@field provider BaseProvider
---@field config BasePresetConfig
---@field system_templates table[]
---@field message_templates table[]
---@field headers BaseHeaders
---@field params BaseParameters
---@field add_system_templates fun(self: BasePresetBuilder, templates: table)
---@field add_message_templates fun(self: BasePresetBuilder, templates: table)
---@field with_opts fun(self: BasePresetBuilder, params: table)
---@field build fun(self: BasePresetBuilder, args: table)
