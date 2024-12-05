local utils = require('kznllm.utils')
local buffer_manager = require('kznllm.buffer').buffer_manager
local api = vim.api

local openai = require('kznllm.specs.openai')
local progress = require('fidget.progress')

local M = {}

---@param config { id: string, description: string, preset_builder: OpenAIPresetBuilder }
local function NewBaseTask(config)
  return {
    id = config.id,
    description = config.description,
    invoke = function(opts)
      local user_query = utils.get_user_input()
      if user_query == nil then
        return
      end

      local selection, replace = utils.get_visual_selection(opts)

      local current_buf_id = api.nvim_get_current_buf()
      local current_buffer_context = buffer_manager:get_buffer_context(current_buf_id)

      local p = progress.handle.create({
        title = ('[%s]'):format(replace and 'replacing' or 'yapping'),
        lsp_client = { name = 'kznllm' },
      })

      local prompt_args = {
        user_query = user_query,
        visual_selection = selection,
        current_buffer_context = current_buffer_context,
        replace = replace,
        context_files = utils.get_project_files(),
      }

      local curl_options = config.preset_builder:build(prompt_args)

      if opts.debug then
        local scratch_buf_id = buffer_manager:create_scratch_buffer()
        local debug_data = utils.make_prompt_from_template({
          template_path = config.preset_builder.debug_template_path,
          prompt_args = curl_options,
        })

        buffer_manager:write_content(debug_data, scratch_buf_id)
        vim.cmd('normal! Gzz')
      end

      local provider = config.preset_builder.provider
      local args = provider:make_curl_args(curl_options)

      local state = { start = os.time(), last_updated = nil }
      p:report({ message = ('%s'):format(config.description) })
      local message_fn = opts.progress_message_fn and opts.progress_message_fn
        or function(s)
          return 'yapped'
        end
      local message = message_fn(state)
      local _ = buffer_manager:create_streaming_job(args, provider.handle_sse_stream, function()
        local progress_message = message_fn(state)
        if progress_message ~= nil then
          message = progress_message
        end

        local elapsed = os.time() - state.start
        if message:format(elapsed) ~= message then
          p:report({ message = message:format(os.time() - state.start) })
        end
      end, function()
        p:finish()
      end)
    end,
  }
end

---@param preset_list BaseTask[]
function M.switch_presets(preset_list)
  local preset_idx = vim.g.PRESET_IDX and math.min(vim.g.PRESET_IDX, #preset_list) or 1
  local selected_preset = preset_list[preset_idx]

  vim.ui.select(preset_list, {
    format_item = function(item)
      return ('%-30s %40s'):format(item.id .. (item == selected_preset and ' *' or '  '), item.description)
    end,
  }, function(choice, idx)
    if choice then
      vim.g.PRESET_IDX = idx
      selected_preset = preset_list[idx]
    end
    print(('%-30s %40s'):format(selected_preset.id, selected_preset.description))
  end)
end

function M.load_selected_preset(preset_list)
  local idx = vim.g.PRESET_IDX or 1
  local preset = preset_list[idx]

  return preset
end

local openai_template_path = utils.join_path({ utils.TEMPLATE_PATH, 'openai' })
local openai_system_template = utils.join_path({ openai_template_path, 'fill_mode_system_prompt.xml.jinja' })
local openai_user_template = utils.join_path({ openai_template_path, 'fill_mode_user_prompt.xml.jinja' })

local BasicOllamaPreset = openai.OpenAIPresetBuilder
  :new()
  :add_system_prompts({
    { type = 'text', path = openai_system_template },
  })
  :add_message_prompts({
    { type = 'text', role = 'user', path = openai_user_template },
  })

-- Example task configurations
M.options = {}

for _, model in ipairs({
  'llama3.2:1b',
  'llama3.2:3b',
  'llama3.1',
  'moondream2',
  'deepseek-v2',
  'deepseek-coder-v2',
  'qwen2.5-coder:7b',
  'qwen2.5-coder:3b',
  'qwen2.5-coder:1.5b',
  'qwen2.5-coder:0.5b',
  'gemma2:9b',
  'gemma2:2b',
}) do
  table.insert(
    M.options,
    NewBaseTask({
      id = ('ollama/%s'):format(model),
      description = ('%s | temp = 0.7'):format(model),
      preset_builder = BasicOllamaPreset:with_opts({
        provider = openai.OpenAIProvider:new({
          base_url = 'http://localhost:11434',
        }),
        headers = {
          ['endpoint'] = '/v1/chat/completions',
        },
        params = {
          ['model'] = model,
          ['stream'] = true,
          ['temperature'] = 0.7,
          ['top_p'] = 1,
          ['max_tokens'] = 32768,
        },
      }),
    })
  )
end

return M
