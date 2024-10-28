---@class BaseProvider
---@field private api_key string
---@field base_url string
local BaseProvider = {}

---@class BaseProviderOptions
---@field api_key_name string
---@field base_url string

---@param opts BaseProviderOptions
---@return BaseProvider
function BaseProvider:new(opts)
  local api_key = os.getenv(opts.api_key_name)
  if not api_key then
    error(("ERROR: %s is missing from environment variables"):format(opts.api_key_name))
  end

  local instance = {
    api_key = api_key,
    base_url = opts.base_url,
  }

  setmetatable(instance, {__index = self})
  return instance
end


---@class BaseProviderCurlOptions: BaseProviderHeaderOptions
---@field data table

---@class BaseProviderHeaderOptions
---@field endpoint string
---@field auth_format? string
---@field extra_headers? string[]

---@param opts BaseProviderCurlOptions
---@return string[]
function BaseProvider:make_curl_args(opts)
  local url = self.base_url .. opts.endpoint

  local args = {
    '-s', '--fail-with-body', '-N', --silent, with errors, unbuffered output
    '-X', 'POST',
    '-H', 'Content-Type: application/json',
    '-H', (opts.auth_format and opts.auth_format or 'Authorization: Bearer %s'):format(self.api_key),
  }

  if opts.extra_headers ~= nil then
    for _, header in ipairs(opts.extra_headers) do
      vim.list_extend(args, { '-H', header })
    end
  end

  vim.list_extend(args, {
    '-d', vim.json.encode(opts.data),
    url,
  })
  return args
end

---@param line string
---@return string?
function BaseProvider:handle_sse_stream(line)
  error("handle_sse_stream NOT IMPLEMENTED", 1)
end

return BaseProvider
