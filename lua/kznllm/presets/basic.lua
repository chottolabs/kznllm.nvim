local utils = require('kznllm.utils')
local buffer_manager = require('kznllm.buffer').buffer_manager
local api = vim.api

local anthropic = require('kznllm.specs.anthropic')
local openai = require('kznllm.specs.openai')

local progress = require('fidget.progress')

local M = {}

---@class BaseTask
---@field id string
---@field description string
---@field invoke fun(opts: { debug: boolean, progress_fn: fun(state) })

---@param config { id: string, description: string, preset_builder: BasePresetBuilder }
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

local anthropic_template_path = utils.join_path({ utils.TEMPLATE_PATH, 'anthropic' })
local anthropic_system_template = utils.join_path({ anthropic_template_path, 'fill_mode_system_prompt.xml.jinja' })
local anthropic_user_template = utils.join_path({ anthropic_template_path, 'fill_mode_user_prompt.xml.jinja' })

local BasicAnthropicPreset = anthropic.AnthropicPresetBuilder
  :new()
  :add_system_prompts({
    {
      type = 'text',
      path = anthropic_system_template,
      cache_control = { type = 'ephemeral' },
    },
  })
  :add_message_prompts({
    { type = 'text', role = 'user', path = anthropic_user_template },
  })

local openai_template_path = utils.join_path({ utils.TEMPLATE_PATH, 'openai' })
local openai_system_template = utils.join_path({ openai_template_path, 'fill_mode_system_prompt.xml.jinja' })
local openai_user_template = utils.join_path({ openai_template_path, 'fill_mode_user_prompt.xml.jinja' })

local BasicOpenAIPreset = openai.OpenAIPresetBuilder
  :new()
  :add_system_prompts({
    { type = 'text', path = openai_system_template },
  })
  :add_message_prompts({
    { type = 'text', role = 'user', path = openai_user_template },
  })

--- doesn't support system prompt
local BasicOpenAIReasoningPreset = openai.OpenAIPresetBuilder:new():add_message_prompts({
  { type = 'text', role = 'user', path = openai_system_template },
  { type = 'text', role = 'user', path = openai_user_template },
})

-- Example task configurations
M.options = {
  NewBaseTask({
    id = 'sonnet-3-5-chat',
    description = 'claude-3-5-sonnet-20241022 | temp = 0.7',
    preset_builder = BasicAnthropicPreset:with_opts({
      params = {
        ['model'] = 'claude-3-5-sonnet-20241022',
        ['stream'] = true,
        ['max_tokens'] = 8192,
        ['temperature'] = 0.7,
      },
    }),
  }),
  NewBaseTask({
    id = 'haiku-3-5-chat',
    description = 'claude-3-5-haiku-20241022 | temp = 0.7',
    preset_builder = BasicAnthropicPreset:with_opts({
      params = {
        ['model'] = 'claude-3-5-haiku-20241022',
        ['stream'] = true,
        ['max_tokens'] = 8192,
        ['temperature'] = 0.7,
      },
    }),
  }),
  NewBaseTask({
    id = 'gpt-4o-mini',
    description = 'gpt-4o-mini | temp = 0.7',
    preset_builder = BasicOpenAIPreset:with_opts({
      params = {
        ['model'] = 'gpt-4o-mini',
        ['stream'] = true,
        ['max_completion_tokens'] = 8192,
        ['temperature'] = 0.7,
      },
    }),
  }),
  NewBaseTask({
    id = 'o1-mini',
    description = 'o1-mini | temp = ?',
    preset_builder = BasicOpenAIReasoningPreset:with_opts({
      params = {
        ['model'] = 'o1-mini',
        ['stream'] = true,
      },
    }),
  }),
  NewBaseTask({
    id = 'Qwen2.5-Coder-32B-Instruct',
    description = 'Qwen2.5-Coder-32B-Instruct | temp = 0.7',
    preset_builder = BasicOpenAIPreset:with_opts({
      provider = openai.OpenAIProvider:new({
        api_key_name = 'VLLM_API_KEY',
        base_url = 'http://research.local:8000',
      }),
      params = {
        ['model'] = 'Qwen/Qwen2.5-Coder-32B-Instruct',
        ['stream'] = true,
        ['temperature'] = 0.7,
        ['top_p'] = 0.8,
        ['repetition_penalty'] = 1.05,
      },
    }),
  }),
  NewBaseTask({
    id = 'llama-3.2-90b-vision',
    description = 'llama-3.2-90b-vision | temp = 0.7',
    preset_builder = BasicOpenAIPreset:with_opts({
      provider = openai.OpenAIProvider:new({
        api_key_name = 'GROQ_API_KEY',
        base_url = 'https://api.groq.com/openai',
      }),
      params = {
        ['model'] = 'llama-3.2-90b-vision-preview',
        ['stream'] = true,
        ['temperature'] = 0.7,
        ['top_p'] = 1,
        ['max_tokens'] = 8192,
      },
    }),
  }),
  NewBaseTask({
    id = 'deepseek-chat',
    description = 'deepseek-chat | temp = 0.0',
    preset_builder = BasicOpenAIPreset:with_opts({
      provider = openai.OpenAIProvider:new({
        api_key_name = 'DEEPSEEK_API_KEY',
        base_url = 'https://api.deepseek.com',
      }),
      headers = {
        endpoint = '/beta/v1/chat/completions',
        extra_headers = {},
      },
      params = {
        ['model'] = 'deepseek-chat',
        ['stream'] = true,
        ['max_completion_tokens'] = 8192,
        ['temperature'] = 0,
      },
    }),
  }),
}

return M
