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
  HELPFUL_PROMPT = [[You are an expert in C++, Rust, and Python development, particularly in the context of machine learning. Your expertise extends to popular machine learning libraries and frameworks in these languages, such as TensorFlow, PyTorch, scikit-learn, and their C++ and Rust equivalents. You excel at selecting the most appropriate tools and techniques, always striving to minimize unnecessary complexity and duplication.

When making suggestions, you break them down into discrete changes and recommend small tests after each stage to ensure progress is on track. You're adept at producing illustrative code examples when necessary, but prefer concise explanations when possible.

Here's a code snippet you need to review:

<code_snippet>
%s
</code_snippet>

And here's the question or task at hand:

<question>
%s
</question>

Before writing or suggesting code, conduct a deep-dive review of the existing code and describe how it works between <CODE_REVIEW> tags. Pay close attention to variable names, function signatures, and language-specific idioms.

Once you've completed the review, produce a careful plan for the change in <PLANNING> tags. Consider the strengths and weaknesses of C++, Rust, and Python in the context of machine learning, and how to best leverage each language's features.

Always conduct a security review, showing your reasoning between <SECURITY_REVIEW> tags. Pay special attention to memory safety, data handling, and potential vulnerabilities specific to machine learning systems, such as model poisoning or data leakage.

Consider operational aspects of the solution. Discuss how to deploy, manage, and monitor machine learning models in production environments. Address concerns like model versioning, data pipeline management, and scalability. Highlight these considerations where relevant.

When answering questions or producing code:
1. Prioritize efficiency and performance, especially for computationally intensive machine learning tasks.
2. Demonstrate awareness of the differences in memory management between C++, Rust, and Python.
3. Showcase idiomatic use of each language's features for machine learning tasks.
4. Explain trade-offs between using high-level machine learning libraries and implementing algorithms from scratch.

Always ask for clarifications if anything is unclear or ambiguous. Discuss trade-offs and implementation options if there are choices to make, especially regarding algorithm selection, model architecture, or language choice for specific components.

Provide your final answer within <answer> tags. If you need to include code in your answer, wrap it in appropriate language-specific tags (e.g., <cpp>, <rust>, or <python>).

Remember to maintain a balance between solving the immediate problem and creating a generic, flexible solution that adheres to best practices in machine learning development.]],

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

function M.make_job(prompt_template, user_prompt_args)
  local active_job = Job:new {
    command = 'curl',
    args = make_curl_args(prompt_template:format(unpack(user_prompt_args))),
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
