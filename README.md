Based on [dingllm.nvim](https://github.com/yacineMTB/dingllm.nvim) - but it'll probably diverge quite a bit from the original state.

- adds some docstring annotations
- refactored to better express some of the inherent coupling
between neovim <> some LLM streaming spec.
- prompt user for additional context
- clean up and handle job state

I recommend you fork the repo and make it work for you.

We're at a point in history where "AI-powered editor" is probably one of the best "hello world" projects for learning about custom Neovim plugins.

See [CONTRIBUTING](CONTRIBUTING.md) to understand the typical development workflow for Neovim plugins using `Lazy`.

https://github.com/chottolabs/kznllm.nvim/assets/171991982/39da67df-1ebc-4866-b563-f6b30d393162

https://github.com/chottolabs/kznllm.nvim/assets/171991982/9de0d9e7-a3ea-4996-8a47-6374a74c3dd1



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

    local function llm_help()
      kznllm.invoke_llm_buffer_mode({
        prompt_template = spec.PROMPT_TEMPLATES.HELPFUL_PROMPT,
      }, spec.make_job)
    end

    local function llm_replace()
      kznllm.invoke_llm_replace_mode({
        prompt_template = spec.PROMPT_TEMPLATES.REPLACE_PROMPT,
      }, spec.make_job)
    end

    vim.keymap.set({ 'n', 'v' }, '<leader>k', llm_replace, { desc = 'Send current selection to LLM llm_replace' })
    vim.keymap.set({ 'n', 'v' }, '<leader>K', llm_help, { desc = 'Send current selection to LLM llm_help' })
  end,
},
```

or for groq
```lua
{
  'chottolabs/kznllm.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  config = function()
    local kznllm = require 'kznllm'
    local spec = require 'kznllm.specs.openai'

    local function llm_help()
      kznllm.invoke_llm_buffer_mode({
        prompt_template = spec.PROMPT_TEMPLATES.HELPFUL_PROMPT,
      }, spec.make_job)
    end

    local function llm_replace()
      kznllm.invoke_llm_replace_mode({
        prompt_template = spec.PROMPT_TEMPLATES.REPLACE_PROMPT,
      }, spec.make_job)
    end

    vim.keymap.set({ 'n', 'v' }, '<leader>k', llm_replace, { desc = 'Send current selection to LLM llm_replace' })
    vim.keymap.set({ 'n', 'v' }, '<leader>K', llm_help, { desc = 'Send current selection to LLM llm_help' })
  end,
}
```
