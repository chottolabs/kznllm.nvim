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

https://github.com/user-attachments/assets/89331af3-3c69-41e3-9293-83b4549a6025

# How it works

**Buffer Mode** - like a long-form chat mode
- **Usage**: (1) make a visual selection (2) `leader + kb` (3) type out your query/prompt (4) quit and save with `q` or type `:q!` to quit without saving
- **Behavior**: 
  - (initial) opens up a buffer, copies in the prompt template + arguments, and then streams the answer out at the bottom.
  - (debug / render input templates) if you hit `d` while in the completion buffer, it will interrupt (if it is still writing) and open up a buffer with a debug template showing the rendered input context
  - (quit) hit `w` to interrupt + quit and save the buffer to `$HOME/.cache/kznllm/history` as `<timestamp>.txt` and returns back to you previous buffer. You can also interrupt + quit without saving + delete the buffer from history using `q`
  - (search history) if you quit with `w` the buffer stays listed and you can find it in open buffers again (e.g. using kickstart defaults it would be `space + space`), if you quit with `q` it deletes the buffer and won't clutter up open buffers list

**Project Mode** - same as buffer mode, but lets you retrieve any files using an `fd` call and formats it into multi-document context
- **Usage**: (1) make a visual selection (2) `leader + kp` (3) input arguments to `fd` (4) navigate the picker and hit tab to select the files you want in the context (5) same as buffer mode

_Note: experimental and mainly built for claude

**Replace Mode** - basically infill specifically for coding
- **Usage**: (1) make a visual selection (2) `leader + shift + k`
- **Behavior**: replaces current selection and rewrites the selection based on context provdied by comments + fixing any errors 

_Note: this plugin depends on `fd` and `minijinja-cli`, install it from https://github.com/mitsuhiko/minijinja (probably using `cargo install minijinja-cli`, but double-check for your own safety)- it makes the it way easier to compose prompts. You should have `fd` already from telescope, if not https://github.com/sharkdp/fd_

Hit `esc` to interrupt and stay in the buffer.

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

    utils.TEMPLATE_DIRECTORY = self.dir .. '/templates/'

    local function llm_buffer()
      kznllm.invoke_llm_buffer_mode({
        system_prompt_template = spec.PROMPT_TEMPLATES.BUFFER_MODE_SYSTEM_PROMPT,
        user_prompt_templates = {
          spec.PROMPT_TEMPLATES.BUFFER_MODE_USER_PROMPT,
        },
      }, spec.make_job)
    end

    local function llm_project()
      kznllm.invoke_llm_project_mode({
        system_prompt_template = spec.PROMPT_TEMPLATES.PROJECT_MODE_SYSTEM_PROMPT,
        user_prompt_templates = {
          spec.PROMPT_TEMPLATES.PROJECT_MODE_USER_PROMPT,
        },
      }, spec.make_job)
    end

    local function llm_replace()
      kznllm.invoke_llm_replace_mode({
        system_prompt_template = spec.PROMPT_TEMPLATES.REPLACE_MODE_SYSTEM_PROMPT,
        user_prompt_templates = {
          spec.PROMPT_TEMPLATES.REPLACE_MODE_USER_PROMPT,
        },
      }, spec.make_job)
    end

    vim.keymap.set({ 'n', 'v' }, '<leader>kb', llm_buffer, { desc = 'Send current selection to LLM llm_buffer' })
    vim.keymap.set({ 'n', 'v' }, '<leader>kp', llm_project, { desc = 'Send current selection to LLM llm_project' })
    vim.keymap.set({ 'n', 'v' }, '<leader>K', llm_replace, { desc = 'Send current selection to LLM llm_replace' })
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
    local utils = require 'kznllm.utils'
    local spec = require 'kznllm.specs.openai'

    utils.TEMPLATE_DIRECTORY = self.dir .. '/templates/'

    local function llm_help()
      kznllm.invoke_llm_buffer_mode({
        system_prompt_template = spec.PROMPT_TEMPLATES.BUFFER_MODE_SYSTEM_PROMPT,
        user_prompt_templates = {
          spec.PROMPT_TEMPLATES.BUFFER_MODE_USER_PROMPT,
        },
      }, spec.make_job)
    end

    local function llm_replace()
      kznllm.invoke_llm_replace_mode({
        system_prompt_template = spec.PROMPT_TEMPLATES.REPLACE_MODE_SYSTEM_PROMPT,
        user_prompt_templates = {
          spec.PROMPT_TEMPLATES.REPLACE_MODE_USER_PROMPT,
        },
      }, spec.make_job)
    end

    vim.keymap.set({ 'n', 'v' }, '<leader>k', llm_replace, { desc = 'Send current selection to LLM llm_replace' })
    vim.keymap.set({ 'n', 'v' }, '<leader>K', llm_help, { desc = 'Send current selection to LLM llm_help' })
  end,
}
```
