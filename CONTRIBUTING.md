For developing any kind of plugin using `lazy.nvim` you basically just need to do this:
- clone the repo into your workspace so that lua LSP can find dependencies (this should be your config directory if you want type hints to pass through properly)
- point the plugin to local directory
- update the plugin using `:Lazy` and confirm it's looking at the local directory

```
{
  'chottolabs/kznllm.nvim',
  dev = true,
  dir = '$HOME/.config/nvim/plugins/kznllm.nvim',
  dependencies = {
    { 'nvim-lua/plenary.nvim' },
    { 'stevearc/dressing.nvim' },
  },
  
  -- this points to whatever you specified as the local `dir = path` in above
  kznllm.TEMPLATE_DIRECTORY = vim.fn.expand(self.dir) .. '/templates/'

  spec.SELECTED_MODEL = { name = 'hermes-3-llama-3.1-405b-fp8' }
  spec.API_KEY_NAME = 'LAMBDA_API_KEY'
  spec.URL = 'https://api.lambdalabs.com/v1/chat/completions'

  local function invoke_llm()
    kznllm.invoke_llm({
      -- add more user/assistant stages to this and just supply a path to your custom template directories
      -- every prompt template gets sent the same table of args for simplicity sake, add custom args as needed
      { role = 'system', prompt_template = spec.PROMPT_TEMPLATES.NOUS_RESEARCH.FILL_MODE_SYSTEM_PROMPT },
      { role = 'user', prompt_template = spec.PROMPT_TEMPLATES.NOUS_RESEARCH.FILL_MODE_USER_PROMPT },
    }, spec.make_job)
  end

  -- add a new keymap with a new behavior
  vim.keymap.set({ 'n', 'v' }, '<leader>k', invoke_llm, { desc = 'Send current selection to LLM invoke_llm' })
},
```
