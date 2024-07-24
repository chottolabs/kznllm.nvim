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
- **Usage**: (1) make a visual selection (2) `leader + shift + K` (3) type out your query/prompt (4) quit and save with `q` or type `:q!` to quit without saving
- **Behavior**: 
  - (initial) opens up a buffer, copies in the prompt template + arguments, and then streams the answer out at the bottom.
  - (continuation) when you make a selection within that same buffer without closing out of it, it will paste in your new arguments and continue from the bottom of the buffer.
  - (quit) hit `w` to interrupt + quit and save the buffer to `$HOME/.cache/kznllm/history` as `<timestamp>.txt` and returns back to you previous buffer. You can also interrupt + quit without saving + delete the buffer from history using `q`
  - (search history) if you quit with `w` the buffer stays listed and you can find it in open buffers again (e.g. using kickstart defaults it would be `space + space`), if you quit with `q` it deletes the buffer and won't clutter up open buffers list

**Replace Mode** - basically infill specifically for coding
- **Usage**: (1) make a visual selection (2) `leader + k`
- **Behavior**: replaces current selection and rewrites the selection based on context provdied by comments + fixing any errors 

_Note: this plugin depends on `minijinja-cli`, install it from https://github.com/mitsuhiko/minijinja (probably using `cargo install minijinja-cli`, but double-check for your own safety) - it makes the it way easier to compose prompts_

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
  config = function()
    local kznllm = require 'kznllm'
    local spec = require 'kznllm.specs.anthropic'

    local function llm_help()
      kznllm.invoke_llm_buffer_mode({
        system_prompt_template = self.dir .. '/templates/' .. spec.PROMPT_TEMPLATES.BUFFER_MODE_SYSTEM_PROMPT,
        user_prompt_template = self.dir .. '/templates/' .. spec.PROMPT_TEMPLATES.BUFFER_MODE_USER_PROMPT,
      }, spec.make_job)
    end

    local function llm_replace()
      kznllm.invoke_llm_replace_mode({
        system_prompt_template = self.dir .. '/templates/' .. spec.PROMPT_TEMPLATES.REPLACE_MODE_SYSTEM_PROMPT,
        user_prompt_template = self.dir .. '/templates/' .. spec.PROMPT_TEMPLATES.REPLACE_MODE_USER_PROMPT,
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
        system_prompt_template = self.dir .. '/templates/' .. spec.PROMPT_TEMPLATES.BUFFER_MODE_SYSTEM_PROMPT,
        user_prompt_templates = {
          self.dir .. '/templates/' .. spec.PROMPT_TEMPLATES.BUFFER_MODE_USER_PROMPT,
        },
      }, spec.make_job)
    end

    local function llm_replace()
      kznllm.invoke_llm_replace_mode({
        system_prompt_template = self.dir .. '/templates/' .. spec.PROMPT_TEMPLATES.REPLACE_MODE_SYSTEM_PROMPT,
        user_prompt_templates = {
          self.dir .. '/templates/' .. spec.PROMPT_TEMPLATES.REPLACE_MODE_USER_PROMPT,
        },
      }, spec.make_job)
    end

    vim.keymap.set({ 'n', 'v' }, '<leader>k', llm_replace, { desc = 'Send current selection to LLM llm_replace' })
    vim.keymap.set({ 'n', 'v' }, '<leader>K', llm_help, { desc = 'Send current selection to LLM llm_help' })
  end,
}
```
