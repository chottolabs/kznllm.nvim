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

---@class BaseProvider
---@field api_key_name string
---@field base_url string
local BaseProvider = {}

---@class BaseProviderOptions
---@field api_key_name string
---@field base_url string

---@param opts BaseProviderOptions
---@return BaseProvider
function BaseProvider:new(opts)
  local instance = {
    api_key_name = opts.api_key_name,
    base_url = opts.base_url,
  }

  setmetatable(instance, { __index = self })
  return instance
end

---@param opts BaseProviderCurlOptions
---@return string[]
function BaseProvider:make_curl_args(opts)
  local url = self.base_url .. opts.endpoint

  local api_key = os.getenv(self.api_key_name)
  if not api_key then
    error(('ERROR: %s is missing from environment variables'):format(self.api_key_name))
  end

  -- stylua: ignore
  local args = {
    '-s', '--fail-with-body', '-N', --silent, with errors, unbuffered output
    '-X', 'POST',
    '-H', 'Content-Type: application/json',
    '-H', (opts.auth_format and opts.auth_format or 'Authorization: Bearer %s'):format(api_key),
  }

  if opts.extra_headers ~= nil then
    for _, header in ipairs(opts.extra_headers) do
      vim.list_extend(args, { '-H', header })
    end
  end

  vim.list_extend(args, { '-d', vim.json.encode(opts.data), url })
  return args
end

---@param line string
---@return string?
function BaseProvider.handle_sse_stream(line)
  error('handle_sse_stream NOT IMPLEMENTED', 1)
end

return BaseProvider
