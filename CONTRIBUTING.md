For developing any kind of plugin using `lazy.nvim` you basically just need to do this:
- clone the repo into your workspace so that lua LSP can find dependencies (this should be your config directory if you want type hints to pass through properly)
- point the plugin to local directory
- update the plugin using `:Lazy` and confirm it's looking at the local directory

```lua
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

This is one of the major changes made, instead of specifying templates as specific arguments it's a single table of arbitrary templates.

```lua
kznllm.invoke_llm({
  -- add more user/assistant stages to this and just supply a path to your custom template directories
  -- every prompt template gets sent the same table of args for simplicity sake, add custom args as needed
  { role = 'system', prompt_template = spec.PROMPT_TEMPLATES.NOUS_RESEARCH.FILL_MODE_SYSTEM_PROMPT },
  { role = 'user', prompt_template = spec.PROMPT_TEMPLATES.NOUS_RESEARCH.FILL_MODE_USER_PROMPT },
}, spec.make_job)
```

If you go into `init.lua` and focus on `invoke_llm` function there's this one table of arguments that gets passed to all the prompt templates. Most of the logic is dictated by the jinja template itself.

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

_Note: Can't be bothered to read about how the event loop works in nvim so it gets weird when I'm using "vim.ui" and other async APIs._

## Debugging

Something that you might find useful is implementing a debug mode. Here is an example of one that opens up a markdown scratch buffer to dump the rendered prompt context.

```lua
local function make_scratch_buffer()
  local scratch_buf_nr = api.nvim_create_buf(false, true)

  -- Set buffer options
  api.nvim_set_option_value('buftype', 'nofile', { buf = scratch_buf_nr })
  api.nvim_set_option_value('bufhidden', 'hide', { buf = scratch_buf_nr })
  api.nvim_set_option_value('swapfile', false, { buf = scratch_buf_nr })
  api.nvim_set_option_value('filetype', 'markdown', { buf = scratch_buf_nr })

  -- Switch to the new buffer
  api.nvim_set_current_buf(scratch_buf_nr)

  -- Enable text wrapping
  api.nvim_set_option_value('wrap', true, { win = 0 })
  api.nvim_set_option_value('linebreak', true, { win = 0 })
  api.nvim_set_option_value('breakindent', true, { win = 0 })

  -- Set up key mapping to close the buffer
  api.nvim_buf_set_keymap(scratch_buf_nr, 'n', 'q', '', {
    noremap = true,
    silent = true,
    callback = function()
      -- Trigger the LLM_Escape event
      api.nvim_exec_autocmds('User', { pattern = 'LLM_Escape' })

      api.nvim_buf_call(scratch_buf_nr, function()
        vim.cmd 'bdelete!'
      end)
    end,
  })
  return scratch_buf_nr
end

function M.debug(prompt_messages, make_job_fn)
  local stream_end_extmark_id, active_job
  local buf_id = api.nvim_win_get_buf(0)
  local mode = api.nvim_get_mode().mode
  local srow, scol, erow, ecol = get_visual_selection(mode)

  local replace_mode = not (mode == 'n')
  local visual_selection, current_buffer_path, current_buffer_context, current_buffer_filetype

  if replace_mode then
    -- get text from visual selection and current buffer
    visual_selection = table.concat(api.nvim_buf_get_text(buf_id, srow, scol, erow, ecol, {}), '\n')
  end
  current_buffer_path = api.nvim_buf_get_name(buf_id)
  current_buffer_context = table.concat(api.nvim_buf_get_lines(buf_id, 0, -1, false), '\n')
  current_buffer_filetype = vim.bo.filetype

  local scratch_buf_id = make_scratch_buffer()

  vim.ui.input({ prompt = 'prompt: ' }, function(input)
    if input ~= nil then
      stream_end_extmark_id = api.nvim_buf_set_extmark(scratch_buf_id, kznllm_ns_id, 0, 0, {})
      local prompt_args = {
        current_buffer_path = current_buffer_path,
        current_buffer_context = current_buffer_context,
        current_buffer_filetype = current_buffer_filetype,
        visual_selection = visual_selection,
        user_query = input,
        replace = replace_mode,
      }

      local rendered_messages = {}
      for _, message in ipairs(prompt_messages) do
        local template_path = (Path:new(M.TEMPLATE_DIRECTORY) / message.prompt_template):absolute()
        table.insert(rendered_messages, { role = message.role, content = make_prompt_from_template(template_path, prompt_args) })

        write_content_at_extmark(message.role .. ':\n\n', kznllm_ns_id, stream_end_extmark_id)
        write_content_at_extmark(make_prompt_from_template(template_path, prompt_args), kznllm_ns_id, stream_end_extmark_id)
        write_content_at_extmark('\n\n---\n\n', kznllm_ns_id, stream_end_extmark_id)
      end
      vim.cmd 'normal! G'

      active_job = make_job_fn(rendered_messages, function(content)
        write_content_at_extmark(content, kznllm_ns_id, stream_end_extmark_id)
      end, function()
        api.nvim_buf_del_extmark(buf_id, kznllm_ns_id, stream_end_extmark_id)
      end)
      active_job:start()

      api.nvim_create_autocmd('User', {
        group = group,
        pattern = 'LLM_Escape',
        callback = function()
          if active_job.is_shutdown ~= true then
            active_job:shutdown()
            print 'LLM streaming cancelled'
          end
        end,
      })
    end
  end)
end
```
