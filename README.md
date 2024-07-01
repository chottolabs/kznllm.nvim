Based on [dingllm.nvim](https://github.com/yacineMTB/dingllm.nvim) - not a fork
because it'll diverge quite a bit from the original state... I was just too
lazy to get deep into Neovim Lua documentation.

This adds some docstring annotations and refactors it to better express some of
the inherent coupling in the interaction between Neovim <> some LLM streaming
spec.

## Usage
```
{
  'chottolabs/kznllm',
  dependencies = { 'nvim-lua/plenary.nvim' },
  config = function()
    local kznllm = require 'kznllm'
    local spec = require 'kznllm.specs.openai'

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
        url = 'https://api.groq.com/openai/v1/chat/completions',
        model = 'llama3-70b-8192',
        api_key_name = 'GROQ_API_KEY',
        system_prompt = helpful_prompt,
      }, spec.make_curl_args, spec.handle_data)
    end

    vim.keymap.set({ 'n', 'v' }, '<leader>k', llm_help, { desc = 'Send current selection to LLM llm_help' })
  end,
}
```
