local M = {}

local Job = require 'plenary.job'
local utils = require 'kznllm.utils'
local current_event_state = nil

--- Constructs arguments for constructing an HTTP request to the Anthropic API
--- using cURL.
---
---@param opts { api_key_name: string, url: string, model: string }
---@param system_prompt string
---@param user_prompt string
---@return string[]
local function make_curl_args(opts, system_prompt, user_prompt)
  local url = opts.url
  local api_key = opts.api_key_name and os.getenv(opts.api_key_name)
  local data = {
    system = system_prompt,
    messages = { { role = 'user', content = user_prompt } },
    model = opts.model,
    stream = true,
    max_tokens = 4096,
  }
  local args = { '-s', '-N', '-X', 'POST', '-H', 'Content-Type: application/json', '-d', vim.json.encode(data) }
  if api_key then
    table.insert(args, '-H')
    table.insert(args, 'x-api-key: ' .. api_key)
    table.insert(args, '-H')
    table.insert(args, 'anthropic-version: 2023-06-01')
  end
  table.insert(args, url)
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

function M.make_job(opts, system_prompt, user_prompt, win_id)
  local active_job = Job:new {
    command = 'curl',
    args = make_curl_args(opts, system_prompt, user_prompt),
    on_stdout = function(_, out)
      -- based on sse spec (Anthropic spec has several distinct events)
      -- Anthropic's sse spec requires you to manage the current event state
      local _, event_epos = string.find(out, '^event: ')

      if event_epos then
        current_event_state = string.sub(out, event_epos + 1)
        return
      end

      if current_event_state == 'content_block_delta' then
        local data, data_epos
        _, data_epos = string.find(out, '^data: ')

        if data_epos then
          data = string.sub(out, data_epos + 1)
        end

        local content = handle_data(data)
        if content and content ~= nil then
          utils.write_content_at_cursor(content, win_id)
        end
      end
    end,
    on_stderr = function(_, _) end,
    on_exit = function() end,
  }
  return active_job
end

return M
