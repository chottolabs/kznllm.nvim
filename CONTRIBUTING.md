For developing any kind of plugin using `lazy.nvim` you basically just need to do this:
- clone the repo into your workspace so that lua LSP can find dependencies (this should be your config directory if you want type hints to pass through properly)
- point the plugin to local directory
- update the plugin using `:Lazy` and confirm it's looking at the local directory

For development, you want to install the plugin locally and update your lazy config like this (same as the main project README with `dev = true` and `dir = path/to/plugin`):

```lua
{
  'chottolabs/kznllm.nvim',
  dev = true,
  dir = '$HOME/.config/nvim/plugins/kznllm.nvim',
  dependencies = {
    { 'nvim-lua/plenary.nvim' },
    -- { 'chottolabs/plenary.nvim' }, -- patched to resolve symlinked directories
  },
  config = function(self)
  ...
  end
},
```

# Overview

`kznllm` (since `v0.2`) at its core provides:

1. a set of utility functions for pulling context from files on disk and/or your active nvim instance.
2. a minimal implementation of specs from API providers that are relevant to helping you stream tokens into a nvim buffer

If you take a look at `lua/kznllm/presets.lua` you can learn how I built out the entire feature set of kznllm in `v0.1` by basically stitching together utility functions from the core library and telling neovim what you want to do with it (i.e. open up scratch buffers, specify extmark position, etc.)

You don't have to use anything from presets at all, it's just there to provide a starting point for making the plugin functional. It can be relatively simple to add new features/capabilities for example:

- a workflow for interactively cycling through a dataset and triggering an LLM evaluation
- add an intermediate API call to a cheap/fast model for a long-context "project mode"
- ask an slow/expensive model to freely output a response and pipe it into a cheap/fast model for structured output

## Prompt Templates

The "no visual selection mode" is really just a "no replace" mode controlled by `local replace_mode = not (mode == 'n')`.

If you look at the system prompts, it's just defining all the logic in the same template, you can add whatever arguments you want in this to suit your use case:

```j2
{%- if replace -%}
You should replace the code that you are sent, only following the comments. Do not talk at all. Only output valid code. Do not provide any backticks that surround the code. Never ever output backticks like this ```. Any comment that is asking you for something should be removed after you satisfy them. Other comments should left alone. Do not output backticks
{%- else -%}
You are a Senior Engineer at a Fortune 500 Company. You will be provided with code samples, academic papers, and documentation as supporting context to assist you in answering user queries about coding. Your task is to analyze this information and use it to provide accurate, helpful responses to the user's coding-related questions.
{%- endif -%}
```

An interesting thing you might consider is implementing a "project-scoped" template directory that can look for documentation files and pipe it into the args (you can do this with the actual text or the file path `{% include <absolute_file_path> %}`). `minijinja-cli` makes this kind of stuff super easy to do.

# How it works

The plugin tries to do as little *magic* as possible, so the abstraction boundaries are relatively transparent.

From looking at a few key chunks of code, you should get a solid understanding of how you might want to structure things (treat `invoke_llm` as a simple reference, you can come up with your own structure for a feature)

the call to `invoke_llm` in `init.lua`

```lua
...
presets.invoke_llm(
  SELECTED_PRESET.make_data_fn,
  spec.make_curl_args,
  spec.make_job,
  vim.tbl_extend('keep', SELECTED_PRESET.opts, {
    template_directory = TEMPLATE_DIRECTORY,
  })
)
...
```

Here you see that `make_curl_args` and `make_job` was taken straight from the spec definitions - you can expect that these don't change very often and you likely won't need to touch it... however you can just as easily pass your own implementation into it.

Notice that `make_data_fn` comes from a preset - this is where you construct the "data" portion of your API call. The structure varies greatly between API providers and you will often find that you can't just plug in the same prompt across multiple providers and expect the same performance (e.g. take advantage of prefilling in Anthropic or chat vs. completion mode)

Now take a look at `lua/kznllm/presets.lua`

```lua
{
  id = 'chat-model',
  provider = 'groq',
  make_data_fn = make_data_for_openai_chat,
  opts = {
    model = 'llama-3.1-70b-versatile',
    data_params = {
      max_tokens = 8192,
      temperature = 0.7,
    },
    debug_fn = openai_debug_fn,
    base_url = 'https://api.groq.com',
    endpoint = '/openai/v1/chat/completions',
  },
},
```

Here you'll see how we've bundled together all of the things we need - you'll also notice some of the weirder things I've done which is support a custom `debug_fn` which specifies how to parse out the generated data and write it out to a scratch buffer.

In opts, we can pass anything into it that's supported by the model and it will just get passed into `vim.json.encode` at the end
