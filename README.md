Based on [dingllm.nvim](https://github.com/yacineMTB/dingllm.nvim) - but it'll probably diverge quite a bit from the original state.

- adds some docstring annotations
- refactored to better express some of the inherent coupling
between neovim <> some LLM streaming spec.
- prompt user for additional context
- clean up and handle job state

I recommend you fork the repo and make it work for you.

We're at a point in history where "AI-powered editor" is probably one of the best "hello world" projects for learning about custom Neovim plugins.

See [CONTRIBUTING](CONTRIBUTING.md) to understand the typical development workflow for Neovim plugins using `Lazy`.

> [!NOTE]
> This plugin depends on [fd](https://github.com/sharkdp/fd) and [minijinja-cli](https://github.com/mitsuhiko/minijinja) (`cargo install minijinja-cli`, but double-check) - way easier to compose prompts. You should have `fd` already from telescope

# How it works

**Buffer Mode** - like a long-form chat mode
- **Usage**: (1) make a visual selection (2) `leader + k` (3) type out your query/prompt (4) quit and save with `q` or type `:q!` to quit without saving
- **Behavior**: 
  - (initial) opens up a buffer, copies in the prompt template + arguments, and then streams the answer out at the bottom.
  - (debug / render input templates) if you hit `d` while in the completion buffer, it will interrupt (if it is still writing) and open up a buffer with a debug template showing the rendered input context
  - (quit) hit `w` to interrupt + quit and save the buffer to `$HOME/.cache/nvim/kznllm/history` (`vim.fn.stdpath 'cache' .. '/kznllm/history'`) as `<timestamp>/output.xml` along with `args.json` and returns you back to the original buffer. You can also interrupt + quit without saving + delete the buffer from history using `q`
  - (search history) if you quit with `w` the buffer stays listed and you can find it in open buffers again (e.g. using kickstart defaults it would be `space + space`), if you quit with `q` it deletes the buffer and won't clutter up open buffers list

https://github.com/user-attachments/assets/89331af3-3c69-41e3-9293-83b4549a6025

**Project Mode** - same as buffer mode, but lets you retrieve any files using an `fd` call and formats it into multi-document context
- **Usage**: (1) make a visual selection (2) `leader + Kp` (3) input arguments to `fd` (4) navigate the picker and hit `Tab` to select the files you want in the context (5) same as buffer mode

> [!WARNING]
> experimental and mainly built for claude

https://github.com/user-attachments/assets/cfa01851-f2f5-42b5-b042-0bb1fc55e3f7

**Replace Mode** - basically infill specifically for coding
- **Usage**: (1) make a visual selection (2) `leader + Kr`
- **Behavior**: replaces current selection and rewrites the selection based on context provdied by comments + fixing any errors 

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
  config = function(self)
    local kznllm = require 'kznllm'
    local utils = require 'kznllm.utils'
    local spec = require 'kznllm.specs.anthropic'

    utils.TEMPLATE_DIRECTORY = vim.fn.expand(self.dir) .. '/templates'

    local function llm_buffer()
      kznllm.invoke_llm_buffer_mode({
        system_prompt_template = spec.PROMPT_TEMPLATES.BUFFER_MODE_SYSTEM_PROMPT,
        user_prompt_template = spec.PROMPT_TEMPLATES.BUFFER_MODE_USER_PROMPT,
      }, spec.make_job)
    end

    local function llm_project()
      kznllm.invoke_llm_project_mode({
        system_prompt_template = spec.PROMPT_TEMPLATES.PROJECT_MODE_SYSTEM_PROMPT,
        user_prompt_template = spec.PROMPT_TEMPLATES.PROJECT_MODE_USER_PROMPT,
      }, spec.make_job)
    end

    local function llm_replace()
      kznllm.invoke_llm_replace_mode({
        system_prompt_template = spec.PROMPT_TEMPLATES.REPLACE_MODE_SYSTEM_PROMPT,
        user_prompt_template = spec.PROMPT_TEMPLATES.REPLACE_MODE_USER_PROMPT,
      }, spec.make_job)
    end

    vim.keymap.set({ 'n', 'v' }, '<leader>k', llm_buffer, { desc = 'Send current selection to LLM llm_buffer' })
    vim.keymap.set({ 'n', 'v' }, '<leader>Kr', llm_replace, { desc = 'Send current selection to LLM llm_replace' })
    vim.keymap.set({ 'n', 'v' }, '<leader>Kp', llm_project, { desc = 'Send current selection to LLM llm_project' })
  end,
},
```

for groq
```lua
{
  'chottolabs/kznllm.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  config = function(self)
    local kznllm = require 'kznllm'
    local utils = require 'kznllm.utils'
    local spec = require 'kznllm.specs.openai'

    ...
  end,
},
```

for local openai server
(e.g. `vllm serve` w/ `--api-key <token>` and `--served-model-name meta-llama/Meta-Llama-3.1-8B-Instruct`) set `VLLM_API_KEY=<token>`
```lua
{
  'chottolabs/kznllm.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  config = function(self)
    local kznllm = require 'kznllm'
    local utils = require 'kznllm.utils'
    local spec = require 'kznllm.specs.openai'

    spec.SELECTED_MODEL = { name = 'meta-llama/Meta-Llama-3.1-8B-Instruct', max_tokens = 8192 }
    spec.URL = 'http://research.local:8000/v1/chat/completions'
    spec.API_KEY_NAME = 'VLLM_API_KEY'

    ...
  end,
},
```

for lambda labs
```lua
{
  'chottolabs/kznllm.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  config = function(self)
    local kznllm = require 'kznllm'
    local utils = require 'kznllm.utils'
    local spec = require 'kznllm.specs.openai'

    spec.SELECTED_MODEL = { name = 'hermes-3-llama-3.1-405b-fp8' }
    spec.API_KEY_NAME = 'LAMBDA_LABS_API_KEY'
    spec.URL = 'https://api.lambdalabs.com/v1/chat/completions'

    ...
  end,
},

