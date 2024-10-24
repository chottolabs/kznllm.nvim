local Job = require('plenary.job')

---@class BaseProvider
---@field private api_key string
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
---@field data? table

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

---Renders a prompt template using minijinja-cli and returns the rendered lines
---
---@param opts { filename: string, prompt_args:table } absolute path to a jinja file, typically PROMPT_ARGS_STATE which needs to be json encoded
---@return string rendered_prompt
function BaseProvider:make_prompt_from_template(opts)
  if vim.fn.executable 'minijinja-cli' ~= 1 then
    error("Can't find minijinja-cli, download it from https://github.com/mitsuhiko/minijinja or add it to $PATH", 1)
  end

  local prompt_template_path = self.template_directory / opts.filename

  if not prompt_template_path:exists() then
    error(string.format('could not find template at %s', prompt_template_path), 1)
  end

  local json_data = vim.json.encode(opts.prompt_args)
  local active_job = Job:new {
    command = 'minijinja-cli',
    args = { '-f', 'json', '--lstrip-blocks', '--trim-blocks', prompt_template_path:absolute(), '-' },
    writer = json_data,
  }

  active_job:sync()
  if active_job.code ~= 0 then
    local error_msg = table.concat(active_job:stderr_result(), '\n')
    error('[minijinja-cli] (exit code: ' .. active_job.code .. ')\n' .. error_msg, vim.log.levels.ERROR)
  end

  return table.concat(active_job:result(), '\n')
end


return BaseProvider
