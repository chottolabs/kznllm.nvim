# kznllm.nvim

Built for a single keybind `leader + k`, it does nothing more than fill in some LLM completion into the text buffer. It has two main behaviors:
1. If you made a visual selection, it will attempt to replace your selection with a valid code fragment. 
2. If you make no visual selection, it can yap freely (or do something else specified by a good template).

> [!NOTE]
> `kznllm.nvim` is compatible with Neovim 0.10.1 or later (uses `vim.system`)
> project-mode is also available when you have `sharkdp/fd` installed and a directory named `.kzn`. It will check your current working directory for a `.kzn`.

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
  dependencies = {
    { 'j-hui/fidget.nvim' },
  },
  config = function(self)
    local presets = require 'kznllm.presets.basic'

    vim.keymap.set({ 'n', 'v' }, '<leader>m', function()
      presets.switch_presets(presets.options)
    end, { desc = 'switch between presets' })

    local function invoke_with_opts(opts)
      return function()
        local preset = presets.load_selected_preset(presets.options)
        preset.invoke(opts)
      end
    end

    vim.keymap.set({ 'n', 'v' }, '<leader>K', invoke_with_opts { debug = true },
      { desc = 'Send current selection to LLM debug' })
    vim.keymap.set({ 'n', 'v' }, '<leader>k', invoke_with_opts { debug = false },
      { desc = 'Send current selection to LLM llm_fill' })

    vim.api.nvim_set_keymap('n', '<Esc>', '', {
      noremap = true,
      silent = true,
      callback = function()
        vim.api.nvim_exec_autocmds('User', { pattern = 'LLM_Escape' })
      end,
    })
  end,
},
```

for local openai server (e.g. `vllm serve` w/ `--api-key <token>` and `--served-model-name meta-llama/Meta-Llama-3.1-8B-Instruct`) set `VLLM_API_KEY=<token>`

---

## Contributing

See [CONTRIBUTING](CONTRIBUTING.md) to understand the typical development workflow for Neovim plugins using `Lazy` and some straightforward ways you can modify the plugin to suit your needs

---

## Custom Progress Updates for your Amusement

`init.lua`
```lua
local function yap_generator()
  math.randomseed(os.time())
  local yap_cycle = {
    "yapped for %ds",
    "...",
  }

  local idx = math.random(1, #yap_cycle)
  return function()
    idx = idx + 1
    if idx > #yap_cycle then
      idx = 1
    end
    return yap_cycle[idx]
  end
end

local yap = yap_generator()

local function progress_fn(state)
  local now = os.time()
  if (now ~= state.last_updated) and ((now - state.start) % 3) == 0 then
    state.last_updated = now
    return yap()
  end
end

vim.keymap.set( { "n", "v" }, "<leader>K", invoke_with_opts({ debug = true, progress_message_fn = progress_fn }), { desc = "..." })
vim.keymap.set( { "n", "v" }, "<leader>k", invoke_with_opts({ debug = false, progress_message_fn = progress_fn }), { desc = "..." })
```

---

## Additional Notes

Originally based on [dingllm.nvim](https://github.com/yacineMTB/dingllm.nvim) - but diverged quite a bit

- prompts user for additional context before filling
- structured to make the inherent coupling between neovim logic, LLM streaming spec, and model-specific templates more explicit
- uses jinja as templating engine for ensuring correctness in more complex prompts
- preset defaults + simple approach for overriding them
- free cursor movement during generation
- avoids "undojoin after undo" error
