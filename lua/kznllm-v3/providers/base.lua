local Job = require('plenary.job')

---@class BaseProvider
---@field api_key string
---@field base_url string
---@field handle_data_fn fun(string)
---@field template_directory Path
local BaseProvider = {}

---@class BaseProviderOptions
---@field api_key_name string
---@field base_url string
---@field handle_data_fn fun(string)
---@field template_directory Path

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
    handle_data_fn = opts.handle_data_fn,
    template_directory = opts.template_directory,
  }

  setmetatable(instance, {__index = self})
  return instance
end

---@class BaseProviderCurlOptions
---@field endpoint string
---@field auth_format? string
---@field extra_headers? string[]
---@field data table

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

---@param args table
---@param writer_fn fun(content: string)
---@param on_exit_fn function
function BaseProvider:make_job(args, writer_fn, on_exit_fn)

  return Job:new({
    command = 'curl',
    args = args,
    enable_recording = true,
    on_stdout = function(_, line)
      local content = self.handle_data_fn(line)
      if content then
        vim.schedule(function() writer_fn(content) end)
      end
    end,
    on_stderr = function(err) error(err, 1) end,
    on_exit = function(job, code)
      vim.schedule(function()
        if code ~= 0 then
          vim.notify(('[curl] (exit code: %d)\n%s'):format(code, table.concat(job:result(), '\n')), vim.log.levels.ERROR)
        else
          on_exit_fn()
        end
      end)
    end
  })
end

return BaseProvider
