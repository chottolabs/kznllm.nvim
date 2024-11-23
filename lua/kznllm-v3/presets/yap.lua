local utils = require 'kznllm-v3.utils'
local buffer_manager = (require 'kznllm-v3.buffer').buffer_manager
local Path = require 'plenary.path'
local api = vim.api

local anthropic = require 'kznllm-v3.specs.anthropic'
local openai = require 'kznllm-v3.specs.openai'

local progress = require 'fidget.progress'

local M = {}

---@class YapPreset
---@field id? string
---@field description? string
---@field invoke fun(opts: table)

-- Preset configuration builder
---@class YapPresetConfig
---@field id string
---@field description string
---@field curl_options BaseProviderCurlOptions

---@class YapPresetBuilder
---@field provider BaseProvider
---@field template_path Path
local YapPresetBuilder = {}

---@param config { provider: BaseProvider, template_path: Path }
---@return YapPresetBuilder
function YapPresetBuilder:new(config)
  local instance = { provider = config.provider, template_path = config.template_path }
  setmetatable(instance, { __index = self })
  return instance
end

---@param curl_options BaseProviderCurlOptions
---@param prompt_args table
function YapPresetBuilder:make_data(curl_options, prompt_args)
  error('make_data NOT IMPLEMENTED', 1)
end

---@param config YapPresetConfig
---@return YapPreset
function YapPresetBuilder:build(config)
  return {
    id = config.id,
    description = config.description,
    invoke = function(opts)
      local provider = self.provider

      local user_query = utils.get_user_input()
      if user_query == nil then
        return
      end

      local selection, replace = utils.get_visual_selection(opts)

      local current_buf_id = api.nvim_get_current_buf()
      local current_buffer_context = buffer_manager:get_buffer_context(current_buf_id)

      local p = progress.handle.create({
        title = ("[%s]"):format(replace and "replacing" or "yapping"),
        lsp_client = { name = "kznllm" },
      })

      local prompt_args = {
        user_query = user_query,
        selection = selection,
        current_buffer_context = current_buffer_context,
        replace = replace,
        context_files = utils.get_project_files {
          stop_dir = Path:new(vim.fn.expand '~'),
          context_dir_id = '.kzn',
        },
      }

      self:make_data(config.curl_options, prompt_args)

      if opts.debug then
        local scratch_buf_id = buffer_manager:create_scratch_buffer()
        local debug_data = utils.make_prompt_from_template {
          template_path = self.template_path,
          filename = 'debug.xml.jinja',
          prompt_args = config.curl_options.data,
        }

        buffer_manager:write_content(debug_data, scratch_buf_id)
        vim.cmd 'normal! Gzz'
      end

      local args = provider:make_curl_args(config.curl_options)

      local state = { start = os.time(), last_updated = nil }
      local message = opts.progress_message_fn(state)
      local _ = buffer_manager:create_streaming_job(
        provider,
        args,
        function()
          local progress_message = opts.progress_message_fn(state)
          if progress_message ~= nil then
            message = progress_message
          end
          p:report({ message = message:format(os.time() - state.start) })
        end,
        function() p:finish() end
      )
    end,
  }
end

---@class AnthropicPresetBuilder : YapPresetBuilder
local AnthropicPresetBuilder = YapPresetBuilder:new {
  provider = anthropic.AnthropicProvider,
  template_path = utils.TEMPLATE_PATH / 'anthropic',
}

---@param curl_options AnthropicCurlOptions
function AnthropicPresetBuilder:make_data(curl_options, prompt_args)
  curl_options.data.system = {
    {
      type = 'text',
      text = utils.make_prompt_from_template {
        template_path = self.template_path,
        filename = 'fill_mode_system_prompt.xml.jinja',
        prompt_args = prompt_args,
      },
      cache_control = { type = 'ephemeral' },
    },
  }
  curl_options.data.messages = {
    {
      role = 'user',
      content = utils.make_prompt_from_template {
        template_path = self.template_path,
        filename = 'fill_mode_user_prompt.xml.jinja',
        prompt_args = prompt_args,
      },
    },
  }
  if prompt_args.context_files then
    table.insert(curl_options.data.system, {
      type = 'text',
      text = utils.make_prompt_from_template {
        template_path = self.template_path,
        filename = 'long_context_documents.xml.jinja',
        prompt_args = prompt_args,
      },
      cache_control = { type = 'ephemeral' },
    })
  end
end

---@class OpenAIPresetBuilder : YapPresetBuilder
local OpenAIPresetBuilder = YapPresetBuilder:new {
  provider = openai.OpenAIProvider,
  template_path = utils.TEMPLATE_PATH / 'openai',
}

---@param curl_options OpenAICurlOptions
function OpenAIPresetBuilder:make_data(curl_options, prompt_args)
  curl_options.data.messages = {
    {
      role = 'system',
      content = utils.make_prompt_from_template {
        template_path = self.template_path,
        filename = 'fill_mode_system_prompt.xml.jinja',
        prompt_args = prompt_args,
      },
    },
    {
      role = 'user',
      content = utils.make_prompt_from_template {
        template_path = self.template_path,
        filename = 'fill_mode_user_prompt.xml.jinja',
        prompt_args = prompt_args,
      },
    },
  }
end

---@class OpenAIReasoningPresetBuilder : YapPresetBuilder
local OpenAIReasoningPresetBuilder = YapPresetBuilder:new {
  provider = openai.OpenAIProvider,
  template_path = utils.TEMPLATE_PATH / 'openai',
}

---@param curl_options OpenAICurlOptions
function OpenAIReasoningPresetBuilder:make_data(curl_options, prompt_args)
  curl_options.data.messages = {
    {
      role = 'user',
      content = table.concat({
        utils.make_prompt_from_template {
          template_path = self.template_path,
          filename = 'fill_mode_system_prompt.xml.jinja',
          prompt_args = prompt_args,
        },
        utils.make_prompt_from_template {
          template_path = self.template_path,
          filename = 'fill_mode_user_prompt.xml.jinja',
          prompt_args = prompt_args,
        },
      }, '\n'),
    },
  }
end

---@class VLLMPresetBuilder: OpenAIPresetBuilder
local VLLMPresetBuilder = OpenAIPresetBuilder:new {
  provider = openai.VLLMProvider,
  template_path = utils.TEMPLATE_PATH / 'openai',
}

---@class LambdaPresetBuilder: OpenAIPresetBuilder
local LambdaPresetBuilder = OpenAIPresetBuilder:new {
  provider = openai.LambdaProvider,
  template_path = utils.TEMPLATE_PATH / 'openai',
}
---@class DeepSeekPresetBuilder: OpenAIPresetBuilder
local DeepSeekPresetBuilder = OpenAIPresetBuilder:new {
  provider = openai.DeepSeekProvider,
  template_path = utils.TEMPLATE_PATH / 'deepseek',
}

---@param preset_list YapPreset[]
function M.switch_presets(preset_list)
  local preset_idx = math.min(vim.g.PRESET_IDX, #preset_list) or 1
  local selected_preset = preset_list[preset_idx]

  vim.ui.select(preset_list, {
    format_item = function(item)
      return ('%-25s %40s'):format(item.id .. (item == selected_preset and ' *' or '  '), item.description)
    end,
  }, function(choice, idx)
    if choice then
      vim.g.PRESET_IDX = idx
      selected_preset = preset_list[idx]
    end
    print(('%-25s %40s'):format(selected_preset.id, selected_preset.description))
  end)
end

---@param preset_list YapPreset[]
function M.load_selected_preset(preset_list)
  local idx = vim.g.PRESET_IDX or 1
  local preset = preset_list[idx]

  return preset
end

-- Example preset configurations
M.options = {
  AnthropicPresetBuilder:build {
    id = 'sonnet-3-5-chat',
    description = 'claude-3-5-sonnet-20241022 | temp = 0.7',
    curl_options = {
      endpoint = '/v1/messages',
      auth_format = 'x-api-key: %s',
      extra_headers = {
        'anthropic-version: 2023-06-01',
        'anthropic-beta: prompt-caching-2024-07-31',
      },
      data = {
        ['model'] = 'claude-3-5-sonnet-20241022',
        ['stream'] = true,
        ['max_tokens'] = 8192,
        ['temperature'] = 0.7,
      },
    },
  },
  AnthropicPresetBuilder:build {
    id = 'haiku-3-5-chat',
    description = 'claude-3-5-haiku-20241022 | temp = 0.7',
    curl_options = {
      endpoint = '/v1/messages',
      auth_format = 'x-api-key: %s',
      extra_headers = {
        'anthropic-version: 2023-06-01',
        'anthropic-beta: prompt-caching-2024-07-31',
      },
      data = {
        ['model'] = 'claude-3-5-haiku-20241022',
        ['stream'] = true,
        ['max_tokens'] = 4096,
        ['temperature'] = 0.7,
      },
    },
  },
  DeepSeekPresetBuilder:build {
    id = 'deepseek-chat',
    description = 'deepseek-chat | temp = 0.0',
    curl_options = {
      endpoint = '/beta/v1/chat/completions',
      extra_headers = {},
      data = {
        ['model'] = 'deepseek-chat',
        ['stream'] = true,
        ['max_completion_tokens'] = 8192,
        ['temperature'] = 0,
      },
    },
  },

  OpenAIReasoningPresetBuilder:build {
    id = 'o1-mini',
    description = 'o1-mini | temp = 0.7',
    curl_options = {
      endpoint = '/v1/chat/completions',
      extra_headers = {},
      data = {
        ['model'] = 'o1-mini',
        ['stream'] = true,
        -- ['max_completion_tokens'] = 8192,
        -- ['temperature'] = 0.7,
      },
    },
  },
  OpenAIPresetBuilder:build {
    id = 'gpt-4o-mini',
    description = 'gpt-4o-mini | temp = 0.7',
    curl_options = {
      endpoint = '/v1/chat/completions',
      extra_headers = {},
      data = {
        ['model'] = 'gpt-4o-mini',
        ['stream'] = true,
        ['max_completion_tokens'] = 8192,
        ['temperature'] = 0.7,
      },
    },
  },
  VLLMPresetBuilder:build {
    id = 'Qwen2.5-Coder-32B-Instruct',
    description = 'Qwen2.5-Coder-32B-Instruct | temp = 0.7',
    curl_options = {
      endpoint = '/v1/chat/completions',
      extra_headers = {},
      data = {
        ['model'] = 'Qwen/Qwen2.5-Coder-32B-Instruct',
        ['stream'] = true,
        ['temperature'] = 0.7,
        ['top_p'] = 0.8,
        ['repetition_penalty'] = 1.05,
        -- ['max_tokens'] = 512,
      },
    },
  },
  VLLMPresetBuilder:build(
    {
      id = 'Llama-3.2-Instruct',
      description = 'Llama-3.2-Instruct | temp = 0.7',
      curl_options = {
        endpoint = '/v1/chat/completions',
        extra_headers = {},
        data = {
          ['model'] = 'meta-llama/Llama-3.2-Instruct',
          ['stream'] = true,
          ['temperature'] = 0.7,
          -- ['max_completion_tokens'] = 512,
        },
      },
    }),
}

return M
