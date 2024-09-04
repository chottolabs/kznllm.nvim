Based on [dingllm.nvim](https://github.com/yacineMTB/dingllm.nvim) - but diverge quite a bit

- prompts user for additional context before filling
- structured to make the inherent coupling between neovim logic, LLM streaming spec, and model-specific templates more explicit
- uses jinja as templating engine for ensuring correctness in more complex prompts
- preset defaults + simple approach for overriding them
- free cursor movement during generation

> [!NOTE]
> This plugin depends on [minijinja-cli](https://github.com/mitsuhiko/minijinja) (`cargo install minijinja-cli`, but double-check) - way easier to compose prompts.

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
export VLLM_API_KEY=vllm_...
```

for lambda

> [!NOTE]
> project-mode is available when you have a directory named `.kzn`. It will
> use the folder closest to your current working directory and traverse backwards
> until it finds a `.kzn` directory or reaches your home directory and exits.
> 
> DON'T PUT ANYTHING OTHER THAN TEXT FILES IN THE DIRECTORY
> 
> A simple way to add specific files to context would've been to symlink another directory
> like this `ln -s $(readlink -f <path>) .kzn/code`... but scandir doesn't do
> that... use my fork of plenary.nvim to resolve symlinks in the directory [see patch](https://github.com/chottolabs/plenary.nvim/commit/7b0bf11bd3c286d6a45d8f5270369626b2ec6505)

```lua
{
  'chottolabs/kznllm.nvim',
  dependencies = {
    { 'nvim-lua/plenary.nvim' },
    -- { 'chottolabs/plenary.nvim' }, -- patched to resolve symlinked directories
  },
  config = function(self)
    local kznllm = require 'kznllm'

    -- starting spec_idx
    local spec
    local spec_idx = 0

    -- for vllm, add openai w/ kwargs (i.e. url + api_key)
    -- { id = 'openai', opts = { api_key_name = 'VLLM_API_KEY', url = 'http://research.local:8000/v1/chat/completions' } }
    local specs = { { id = 'groq' }, { id = 'lambda' }, { id = 'anthropic' }, { id = 'openai' } }

    local function switch_provider()
      spec_idx = (spec_idx % #specs) + 1
      spec = require(('kznllm.specs.%s'):format(specs[spec_idx].id))
      print(('provider: %-10s || model: %s'):format(specs[spec_idx].id, spec.MODELS[spec.SELECTED_MODEL_IDX].name))
    end

    vim.keymap.set({ 'n', 'v' }, '<leader>m', switch_provider, { desc = 'switch between model providers' })

    local function switch_models()
      spec.SELECTED_MODEL_IDX = (spec.SELECTED_MODEL_IDX % #spec.MODELS) + 1
      print(('provider: %-10s || model: %s'):format(specs[spec_idx], spec.MODELS[spec.SELECTED_MODEL_IDX].name))
    end

    vim.keymap.set({ 'n', 'v' }, '<leader>M', switch_models, { desc = 'switch between model providers' })

    -- initialize spec
    switch_provider()

    -- falls back to `vim.fn.stdpath 'data' .. '/lazy/kznllm/templates'` when the plugin is not locally installed
    local TEMPLATE_DIRECTORY = vim.fn.expand(self.dir) .. '/templates'

    local function llm_fill()
      kznllm.invoke_llm(
        -- reference implementations, try base model vs. chat
        spec.make_data_for_chat,
        spec.make_curl_args,
        spec.make_job,
        { template_path = TEMPLATE_DIRECTORY }
      )
    end

    vim.keymap.set({ 'n', 'v' }, '<leader>k', llm_fill, { desc = 'Send current selection to LLM llm_fill' })

    -- optional for debugging purposes
    local function debug()
      kznllm.invoke_llm(
        -- reference implementations, try base model vs. chat
        spec.make_data_for_chat,
        spec.make_curl_args,
        spec.make_job,
        { template_path = TEMPLATE_DIRECTORY, debug = true }
      )
    end

    vim.keymap.set({ 'n', 'v' }, '<leader>d', debug, { desc = 'Send current selection to LLM debug' })

    vim.api.nvim_set_keymap('n', '<Esc>', '', {
      noremap = true,
      silent = true,
      callback = function()
        vim.api.nvim_exec_autocmds('User', { pattern = 'LLM_Escape' })
      end,
    })
  end
},
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

