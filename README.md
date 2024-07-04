Based on [dingllm.nvim](https://github.com/yacineMTB/dingllm.nvim) - but it'll probably diverge quite a bit from the original state.

- adds some docstring annotations
- refactored to better express some of the inherent coupling in the interaction
between neovim <> some LLM streaming spec.
- prompt user for additional context
- clean up and handle job state


https://github.com/chottolabs/kznllm.nvim/assets/171991982/39da67df-1ebc-4866-b563-f6b30d393162


## Usage

Make your API keys available via environment variables
```
export ANTHROPIC_API_KEY=sk-...
export GROQ_API_KEY=gsk_...
```

```lua
{
  'chottolabs/kznllm.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  config = function()
    local kznllm = require 'kznllm'
    local spec = require 'kznllm.specs.anthropic'

    local helpful_prompt = [[
You are an AI programming assistant integrated into a code editor. Your purpose is to help the user with programming tasks as they write code.
Key capabilities:
- Thoroughly analyze the user's code and provide insightful suggestions for improvements related to best practices, performance, readability, and maintainability. Explain your reasoning.
- Answer coding questions in detail, using examples from the user's own code when relevant. Break down complex topics step- Spot potential bugs and logical errors. Alert the user and suggest fixes.
- Upon request, add helpful comments explaining complex or unclear code.
- Suggest relevant documentation, StackOverflow answers, and other resources related to the user's code and questions.
- Engage in back-and-forth conversations to understand the user's intent and provide the most helpful information.
- Keep concise and use markdown.
- When asked to create code, only generate the code. No bugs.
- Think step by step]]

    local function llm_help()
      kznllm.invoke_llm_and_stream_into_editor({
        url = 'https://api.anthropic.com/v1/messages',
        model = 'claude-3-5-sonnet-20240620',
        api_key_name = 'ANTHROPIC_API_KEY',
        system_prompt = helpful_prompt,
      }, spec.make_job)
    end

    local replace_prompt =
      [[You should replace the code that you are sent, only following the comments. Do not talk at all. Only output valid code. Do not provide any backticks that surround the code. Never ever output backticks like this ```. Any comment that is asking you for something should be removed after you satisfy them. Other comments should left alone. Do not output backticks]]
    local function llm_replace()
      kznllm.invoke_llm_and_stream_into_editor({
        url = 'https://api.anthropic.com/v1/messages',
        model = 'claude-3-5-sonnet-20240620',
        api_key_name = 'ANTHROPIC_API_KEY',
        system_prompt = replace_prompt,
        replace = true,
      }, spec.make_job)
    end

    vim.keymap.set({ 'n', 'v' }, '<leader>k', llm_replace, { desc = 'Send current selection to LLM llm_replace' })
    vim.keymap.set({ 'n', 'v' }, '<leader>K', llm_help, { desc = 'Send current selection to LLM llm_help' })
  end,
}
```

or for groq
```lua
{
  'chottolabs/kznllm.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  config = function()
    local kznllm = require 'kznllm'
    local spec = require 'kznllm.specs.openai'
    ...
    local function llm_help()
      kznllm.invoke_llm_and_stream_into_editor({
        url = 'https://api.groq.com/openai/v1/chat/completions',
        model = 'llama3-70b-8192',
        api_key_name = 'GROQ_API_KEY',
        system_prompt = helpful_prompt,
      }, spec.make_job)
    end
    ...
  end,
}
```
