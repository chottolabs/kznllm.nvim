local M = {}

local API_KEY_NAME = 'ANTHROPIC_API_KEY'
local BASE_URL = 'https://api.anthropic.com'

local API_ERROR_MESSAGE = [[
ERROR: anthropic api key is set to %s and is missing from your environment variables.

Load somewhere safely from config `export %s=<api_key>`]]

local Job = require 'plenary.job'
local current_event_state = nil

--- Constructs arguments for constructing an HTTP request to the OpenAI API
--- using cURL.
---
---@param data table
---@return string[]
function M.make_curl_args(data, opts)
  local url = (opts and opts.base_url or BASE_URL) .. (opts and opts.endpoint)
  local api_key = os.getenv(opts and opts.api_key_name or API_KEY_NAME)

  if not api_key then
    error(API_ERROR_MESSAGE:format(API_KEY_NAME, API_KEY_NAME), 1)
  end

  local args = {
    '-s', --silent
    '--fail-with-body',
    '-N', --no buffer
    '-X',
    'POST',
    '-H',
    'Content-Type: application/json',
    '-d',
    vim.json.encode(data),
    '-H',
    'x-api-key: ' .. api_key,
    '-H',
    'anthropic-version: 2023-06-01',
    '-H',
    'anthropic-beta: max-tokens-3-5-sonnet-2024-07-15',
    url,
  }

  return args
end

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
---@param data string
---@return string
local function handle_data(data)
  local content = ''
  if data then
    local json = vim.json.decode(data)

    if json.delta and json.delta.text then
      content = json.delta.text
    end
  end

  return content
end

function M.make_job(args, writer_fn, on_exit_fn)
  local active_job = Job:new {
    command = 'curl',
    args = args,
    enable_recording = true,
    on_stdout = function(_, line)
      if line == '' then
        return
      end

      -- based on sse spec (Anthropic spec has several distinct events)
      -- Anthropic's sse spec requires you to manage the current event state
      local event = line:match '^event: (.+)$'

      if event then
        current_event_state = event
        return
      end

      if current_event_state == 'content_block_delta' then
        local data = line:match '^data: (.+)$'

        local content = handle_data(data)
        if content and content ~= nil then
          vim.schedule(function()
            writer_fn(content)
          end)
        end
      elseif current_event_state == 'message_start' then
        local data = line:match '^data: (.+)$'
        vim.print(data)
      elseif current_event_state == 'message_delta' then
        local data = line:match '^data: (.+)$'
        vim.print(data)
      end
    end,
    on_stderr = function(message, _)
      error(message, 1)
    end,
    on_exit = function(job, exit_code)
      local stdout_result = job:result()
      local stdout_message = table.concat(stdout_result, '\n')

      vim.schedule(function()
        if exit_code ~= 0 then
          vim.notify('[Curl] (exit code: ' .. exit_code .. ')\n' .. stdout_message, vim.log.levels.ERROR)
        else
          on_exit_fn()
        end
      end)
    end,
  }
  return active_job
end

return M
