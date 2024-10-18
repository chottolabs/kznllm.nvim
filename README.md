# kznllm.nvim

The only main command is `leader + k`, it does nothing more than fill in some LLM completion into the text buffer. It has two main behaviors:
1. If you made a visual selection, it will attempt to replace your selection with a valid code fragment. 
2. If you make no visual selection, it can yap freely (or do something else specified by a good template).

> [!NOTE]
> project-mode is also available when you have a directory named `.kzn`. It will use the folder closest to your current working directory and traverse backwards until it finds a `.kzn` directory or reaches your home directory and exits.

It's easy to hack on and implement customize behaviors without understanding much about nvim plugins. Try the default preset configuration provided below, but I recommend you fork the repo and using the preset as a reference for implementing your own features.

- **close-to-natty** coding experience
- add custom prompt templates
- pipe any context into template engine
- extend with custom features/modes

https://github.com/user-attachments/assets/406fc75f-c204-42ec-80a0-0f9e186c34c7

## Configuration

Make your API keys available via environment variables
```
export LAMBDA_API_KEY=secret_...
export ANTHROPIC_API_KEY=sk-...
export OPENAI_API_KEY=sk-proj-...
export GROQ_API_KEY=gsk_...
export DEEPSEEK_API_KEY=vllm_...
export VLLM_API_KEY=vllm_...
```

> [!NOTE]
> This plugin depends on [minijinja-cli](https://github.com/mitsuhiko/minijinja) (`cargo install minijinja-cli`, but double-check) - way easier to compose prompts.

full config w/ supported presets and a switch mechanism and provider-specific debug functions

```lua
{
  'chottolabs/kznllm.nvim',
  -- dev = true,
  -- dir = /path/to/your/fork,
  dependencies = {
    { 'nvim-lua/plenary.nvim' }
  },
  config = function(self)
    local presets = require 'kznllm.presets'

    -- bind a key to the preset switcher
    vim.keymap.set({ 'n', 'v' }, '<leader>m', presets.switch_presets, { desc = 'switch between presets' })

    local function llm_fill()
      local spec, preset = presets.load()
      presets.invoke_llm(
        preset.make_data_fn,
        spec.make_curl_args,
        spec.make_job,
        vim.tbl_extend('keep', preset.opts, {})
      )
    end

    vim.keymap.set({ 'n', 'v' }, '<leader>k', llm_fill, { desc = 'Send current selection to LLM llm_fill' })

    -- optional for debugging purposes
    local function debug()
      local spec, preset = presets.load()
      presets.invoke_llm(
        preset.make_data_fn,
        spec.make_curl_args,
        spec.make_job,
        vim.tbl_extend('keep', preset.opts, {
          debug = true,
        })
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

for local openai server (e.g. `vllm serve` w/ `--api-key <token>` and `--served-model-name meta-llama/Meta-Llama-3.1-8B-Instruct`) set `VLLM_API_KEY=<token>`

---

## Contributing

See [CONTRIBUTING](CONTRIBUTING.md) to understand the typical development workflow for Neovim plugins using `Lazy` and some straightforward ways you can modify the plugin to suit your needs

---

## Additional Notes

Originally based on [dingllm.nvim](https://github.com/yacineMTB/dingllm.nvim) - but diverged quite a bit

- prompts user for additional context before filling
- structured to make the inherent coupling between neovim logic, LLM streaming spec, and model-specific templates more explicit
- uses jinja as templating engine for ensuring correctness in more complex prompts
- preset defaults + simple approach for overriding them
- free cursor movement during generation
- avoids "undojoin after undo" error

## Alternative Configurations

minimal configuration with custom `make_data_fn` and no preset switcher. As you can see, the `make_data_fn` is simply building the `data` portion of the API call and will accept anything supported by the associated provider.

```lua
local presets = require 'kznllm'
local presets = require 'kznllm.presets'
local Path = require 'plenary.path'

local TEMPLATE_DIRECTORY = Path:new(vim.fn.expand(self.dir) .. '/templates')

---Example implementation of a `make_data_fn` compatible with `kznllm.invoke_llm` for groq spec
---@param prompt_args any
---@param opts { model: string, temperature: number, template_directory: Path, debug: boolean }
---@return table
---
local function make_data_for_openai_chat(prompt_args, opts)
  return {
    messages = {
      {
        role = 'system',
        content = kznllm.make_prompt_from_template(opts.template_directory / 'nous_research/fill_mode_system_prompt.xml.jinja', prompt_args),
      },
      {
        role = 'user',
        content = kznllm.make_prompt_from_template(opts.template_directory / 'nous_research/fill_mode_user_prompt.xml.jinja', prompt_args),
      },
    },
    model = opts.model,
    temperature = opts.temperature,
    stream = true,
  }
end

-- set initial preset on load
local spec = require('kznllm.specs.groq')

local function llm_fill()
  presets.invoke_llm(
    make_data_for_openai_chat,
    spec.make_curl_args,
    spec.make_job,
    {
      model = 'llama-3.1-70b-versatile',
      max_tokens = 8192,
      temperature = 0.7,
      base_url = 'https://api.groq.com',
      endpoint = '/openai/v1/chat/completions',
      template_directory = TEMPLATE_DIRECTORY,
    })
  )
end

vim.keymap.set({ 'n', 'v' }, '<leader>k', llm_fill, { desc = 'Send current selection to LLM llm_fill' })
```

