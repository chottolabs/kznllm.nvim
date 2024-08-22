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

If you go into `init.lua` and focus on `invoke_llm` function there's literally this one table that gets pass to all prompt templates, write whatever logic you want in your templates.

```lua
local prompt_args = {
  current_buffer_path = current_buffer_path,
  current_buffer_context = current_buffer_context,
  current_buffer_filetype = current_buffer_filetype,
  visual_selection = visual_selection,
  user_query = input,
  replace = replace_mode,
}
```

The "no visual selection mode" is really just a "non replace" mode controlled by `local replace_mode = not (mode == 'n')`.

If you look at the system prompts, it's literally just defining all the logic in the same template, you can add whatever arguments you want in this to suit your use case:

```j2
{%- if replace -%}
You should replace the code that you are sent, only following the comments. Do not talk at all. Only output valid code. Do not provide any backticks that surround the code. Never ever output backticks like this ```. Any comment that is asking you for something should be removed after you satisfy them. Other comments should left alone. Do not output backticks
{%- else -%}
You are a Senior Engineer at a Fortune 500 Company. You will be provided with code samples, academic papers, and documentation as supporting context to assist you in answering user queries about coding. Your task is to analyze this information and use it to provide accurate, helpful responses to the user's coding-related questions.
{%- endif -%}
```

An interesting thing you might consider is implementing a "project-scoped" template directory that can look for documentation files and pipe it into the args (you can do this with the actual text or the file path `{% include <absolute_file_path> %}`). `minijinja-cli` makes this kind of stuff super easy to do.

_Note: Can't be bothered to read about how the event loop works in nvim so it gets weird when I'm using "vim.ui" and other async APIs._
