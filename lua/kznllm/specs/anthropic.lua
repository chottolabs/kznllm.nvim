local M = {}
M.API_KEY_NAME = 'ANTHROPIC_API_KEY'
M.URL = 'https://api.anthropic.com/v1/messages'

M.MODELS = {
  SONNET_3_5 = { name = 'claude-3-5-sonnet-20240620', max_tokens = 8192 },
  OPUS_3 = { name = 'claude-3-opus-20240229', max_tokens = 4096 },
  HAIKU_3 = { name = 'claude-3-haiku-20240307', max_tokens = 4096 },
}

M.SELECTED_MODEL = M.MODELS.SONNET_3_5

M.PROMPT_TEMPLATES = {
  --- this prompt should let the model yap into a separate buffer
  BUFFER_MODE_SYSTEM_PROMPT = 'anthropic/buffer_mode_system_prompt.xml.jinja',
  BUFFER_MODE_USER_PROMPT = 'anthropic/buffer_mode_user_prompt.xml.jinja',

  --- this prompt should format a bunch of files into long context multi-document format
  PROJECT_MODE_SYSTEM_PROMPT = 'anthropic/buffer_mode_system_prompt.xml.jinja',
  PROJECT_MODE_USER_PROMPT = 'anthropic/project_mode_user_prompt.xml.jinja',

  --- this prompt has to be written to output valid code
  REPLACE_MODE_SYSTEM_PROMPT = 'anthropic/replace_mode_system_prompt.xml.jinja',
  REPLACE_MODE_USER_PROMPT = 'anthropic/replace_mode_user_prompt.xml.jinja',
}

local API_ERROR_MESSAGE = [[
ERROR: anthropic api key is set to %s and is missing from your environment variables.

Load somewhere safely from config `export %s=<api_key>`]]

local Job = require 'plenary.job'
local current_event_state = nil

--- Constructs arguments for constructing an HTTP request to the Anthropic API
--- using cURL.
---
---@param rendered_messages { system_prompt: string, messages: { role: string, content: string }[] }
---@return string[]
local function make_curl_args(rendered_messages)
  local api_key = os.getenv(M.API_KEY_NAME)
  local data = {
    system = rendered_messages.system_prompt,
    messages = rendered_messages.messages,
    model = M.SELECTED_MODEL.name,
    stream = true,
    max_tokens = M.SELECTED_MODEL.max_tokens,
  }

  local args = { '-s', '-N', '-X', 'POST', '-H', 'Content-Type: application/json', '-d', vim.json.encode(data) }
  if api_key then
    args = vim.list_extend(args, {
      '-H',
      'x-api-key: ' .. api_key,
      '-H',
      'anthropic-version: 2023-06-01',
      '-H',
      'anthropic-beta: max-tokens-3-5-sonnet-2024-07-15',
    })
  else
    error(string.format(API_ERROR_MESSAGE, M.API_KEY_NAME, M.API_KEY_NAME), 1)
  end

  table.insert(args, M.URL)
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

---@param rendered_messages { system_prompt: string, messages: { role: string, content: string }[] }
function M.make_job(rendered_messages, writer_fn, completed_callback_fn)
  local active_job = Job:new {
    command = 'curl',
    args = make_curl_args(rendered_messages),
    on_stdout = function(_, out)
      if out == '' then
        return
      end

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
          writer_fn(content)
        end
      elseif current_event_state == 'message_start' then
        local data, data_epos
        _, data_epos = string.find(out, '^data: ')

        if data_epos then
          data = string.sub(out, data_epos + 1)
        end

        vim.print(data)
      elseif current_event_state == 'message_delta' then
        local data, data_epos
        _, data_epos = string.find(out, '^data: ')

        if data_epos then
          data = string.sub(out, data_epos + 1)
        end

        vim.print(data)
      end
    end,
    on_stderr = function(message, _)
      error(message, 1)
    end,
    on_exit = function()
      completed_callback_fn()
    end,
  }
  return active_job
end

return M
