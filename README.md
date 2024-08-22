Based on [dingllm.nvim](https://github.com/yacineMTB/dingllm.nvim) - but diverge quite a bit

- prompts user for additional context before filling
- structured to make the inherent coupling between neovim logic, LLM streaming spec, and model-specific templates more explicit
- uses jinja as templating engine for ensuring correctness in more complex prompts
- preset defaults + simple approach for overriding them
- free cursor movement during generation

> [!NOTE]
> This plugin depends on [fd](https://github.com/sharkdp/fd) and [minijinja-cli](https://github.com/mitsuhiko/minijinja) (`cargo install minijinja-cli`, but double-check) - way easier to compose prompts. You should have `fd` already from telescope

The only supported command is `leader + k`, it does nothing more than fill in some LLM completion into the text buffer. It has two main behaviors:
1. If you made a visual selection, it will attempt to replace your selection with a valid code fragment. 
2. If you make no visual selection, it can yap freely (or do something else specified by a good template).

By default (in supported templates), it also pipes in the contents of your current buffer.

---

It's easy to hack on and implement customize behaviors without actually understanding much about nvim plugins at all. I recommend you fork the repo and make it work for you.

See [CONTRIBUTING](CONTRIBUTING.md) to understand the typical development workflow for Neovim plugins using `Lazy` and some straightforward ways you can modify the plugin to suit your needs

By keeping the plugin simple with some QOL features, you get **close-to-natty** coding experience because it can keep generating code while you are free to do whatever you want (almost) without getting in the way too much.

https://github.com/user-attachments/assets/932fa67f-0332-4799-b467-ecaeea54c3d1

_editing code while it generates when 405b is too slow_

## Configuration

Make your API keys available via environment variables
```
export LAMBDA_API_KEY=secret_...
export ANTHROPIC_API_KEY=sk-...
export GROQ_API_KEY=gsk_...
```

for lambda labs

```lua
  {
    'chottolabs/kznllm.nvim',
    dependencies = {
      { 'nvim-lua/plenary.nvim' },
      { 'stevearc/dressing.nvim' }, -- optional
    },
    config = function(self)
      local kznllm = require 'kznllm'
      local provider = require 'kznllm.specs.openai'

      -- falls back to `vim.fn.stdpath 'data' .. '/lazy/kznllm/templates'` when the plugin is not locally installed
      kznllm.TEMPLATE_DIRECTORY = vim.fn.expand(self.dir) .. '/templates/'

      provider.SELECTED_MODEL = { name = 'hermes-3-llama-3.1-405b-fp8' }
      provider.API_KEY_NAME = 'LAMBDA_API_KEY'
      provider.URL = 'https://api.lambdalabs.com/v1/chat/completions'

      local function llm_fill()
        kznllm.invoke_llm({
          -- the first template must be for the system prompt when using anthropic
          { role = 'system', prompt_template = provider.PROMPT_TEMPLATES.NOUS_RESEARCH.FILL_MODE_SYSTEM_PROMPT },
          { role = 'user', prompt_template = provider.PROMPT_TEMPLATES.NOUS_RESEARCH.FILL_MODE_USER_PROMPT },
        }, provider.make_job)
      end

      vim.keymap.set({ 'n', 'v' }, '<leader>k', llm_fill, { desc = 'Send current selection to LLM llm_fill' })
    end,
  },
```

```lua
local kznllm = require 'kznllm'
local spec = require 'kznllm.specs.anthropic'

kznllm.TEMPLATE_DIRECTORY = vim.fn.expand(self.dir) .. '/templates/'

local function llm_fill()
  kznllm.invoke_llm({
    { role = 'system', prompt_template = provider.PROMPT_TEMPLATES.NOUS_RESEARCH.FILL_MODE_SYSTEM_PROMPT },
    { role = 'user', prompt_template = provider.PROMPT_TEMPLATES.NOUS_RESEARCH.FILL_MODE_USER_PROMPT },
  }, spec.make_job)
end

vim.keymap.set({ 'n', 'v' }, '<leader>k', llm_fill, { desc = 'Send current selection to LLM llm_fill' })
```

for groq (default)
```lua
local kznllm = require 'kznllm'
local utils = require 'kznllm.utils'
local spec = require 'kznllm.specs.openai'

kznllm.TEMPLATE_DIRECTORY = vim.fn.expand(self.dir) .. '/templates/'
-- no override fallsback to a preset default model configuration

local function llm_fill()
  kznllm.invoke_llm({
    { role = 'system', prompt_template = provider.PROMPT_TEMPLATES.GROQ.FILL_MODE_SYSTEM_PROMPT },
    { role = 'user', prompt_template = provider.PROMPT_TEMPLATES.GROQ.FILL_MODE_USER_PROMPT },
  }, spec.make_job)
end
...
```

for local openai server
(e.g. `vllm serve` w/ `--api-key <token>` and `--served-model-name meta-llama/Meta-Llama-3.1-8B-Instruct`) set `VLLM_API_KEY=<token>`
```lua
local kznllm = require 'kznllm'
local spec = require 'kznllm.specs.openai'

kznllm.TEMPLATE_DIRECTORY = vim.fn.expand(self.dir) .. '/templates/'

spec.SELECTED_MODEL = { name = 'meta-llama/Meta-Llama-3.1-8B-Instruct', max_tokens = 8192 }
spec.API_KEY_NAME = 'VLLM_API_KEY'
spec.URL = 'http://research.local:8000/v1/chat/completions'
...
```

