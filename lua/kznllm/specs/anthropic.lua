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
  HELPFUL_PROMPT = [[You are an AI programming assistant integrated into a code editor. Your purpose is to help the user with programming tasks as they write code.
Key capabilities:
- Thoroughly analyze the user's code and provide insightful suggestions for improvements related to best practices, performance, readability, and maintainability. Explain your reasoning.
- Answer coding questions in detail, using examples from the user's own code when relevant. Break down complex topics step- Spot potential bugs and logical errors. Alert the user and suggest fixes.
- Upon request, add helpful comments explaining complex or unclear code.
- Suggest relevant documentation, StackOverflow answers, and other resources related to the user's code and questions.
- Engage in back-and-forth conversations to understand the user's intent and provide the most helpful information.
- Keep concise and use markdown.
- When asked to create code, only generate the code. No bugs.
- Think step by step]],

  --- this prompt has to be written to output valid code
  REPLACE_PROMPT = [[You will be given a code snippet with comments. Your task is to fix any errors in the code and implement any unfinished functionality indicated in the comments. Only output valid code in the provided language.

Here is the code snippet:

<code_snippet>
%s
</code_snippet>

Follow these steps to complete the task:

1. Carefully read through the entire code snippet, including all comments.

2. Identify any syntax errors, logical errors, or unimplemented functionality mentioned in the comments.

3. Fix all errors you've identified. This may include:
   - Correcting syntax mistakes
   - Addressing logical errors
   - Implementing missing functionality as described in the comments

4. Ensure that your changes maintain the original intent of the code while improving its functionality and correctness.

5. If there are multiple ways to implement a feature or fix an error, choose the most efficient and clear approach.

6. Do not add any new features or functionality beyond what is explicitly mentioned in the code or comments.

7. Maintain the original code style and formatting as much as possible, unless it directly contributes to the errors.

8. Remove any comments that are no longer relevant after your changes.

9. If you make any significant changes or implementations, add brief comments explaining your modifications.

Output your corrected and implemented code. Ensure that the code you output is complete, valid, and ready to run in the language of the original snippet.

Remember, only output valid code. Do not include any explanations, notes, or anything other than the corrected code itself.]],
}

local API_ERROR_MESSAGE = [[
ERROR: anthropic api key is set to %s and is missing from your environment variables.

Load somewhere safely from config `export %s=<api_key>`]]

local Job = require 'plenary.job'
local utils = require 'kznllm.utils'
local current_event_state = nil

--- Constructs arguments for constructing an HTTP request to the Anthropic API
--- using cURL.
---
---@param user_prompt string
---@return string[]
local function make_curl_args(user_prompt)
  local api_key = os.getenv(M.API_KEY_NAME)
  local data = {
    messages = { { role = 'user', content = user_prompt } },
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

function M.make_job(prompt_template, user_prompt)
  local active_job = Job:new {
    command = 'curl',
    args = make_curl_args(prompt_template:format(user_prompt)),
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
          utils.write_content_at_cursor(content)
        end
      end
    end,
    on_stderr = function(message, _)
      error(message, 1)
    end,
    on_exit = function() end,
  }
  return active_job
end

return M
