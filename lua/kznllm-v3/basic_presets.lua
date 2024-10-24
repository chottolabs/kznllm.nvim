local utils = require 'kznllm-v3.utils'
local buffer_manager = (require 'kznllm-v3.buffers').buffer_manager
local Path = require 'plenary.path'
local api = vim.api

local BaseProvider = require 'kznllm-v3.providers.base'
local anthropic = require 'kznllm-v3.providers.anthropic'
local openai = require 'kznllm-v3.providers.openai'

local M = {}

local plugin_dir = Path:new(debug.getinfo(1, 'S').source:sub(2)):parents()[3]
local TEMPLATE_DIRECTORY = Path:new(plugin_dir) / 'templates'

---@class BasicPreset
---@field id? string
---@field description? string
---@field invoke fun(opts: table)
---
-- Preset configuration builder
---@class BasicPresetConfig
---@field id string
---@field description string
---@field curl_options BaseProviderCurlOptions
---@field template_overrides? table

---@class BasicPresetBuilder
---@field spec "openai" | "anthropic"
---@field provider BaseProvider
local BasicPresetBuilder = {}

---@param config { spec: string, provider: BaseProvider }
---@return BasicPresetBuilder
function BasicPresetBuilder:new(config)
  local instance = { spec = config.spec, provider = config.provider }
  setmetatable(instance, { __index = self })
  return instance
end

---@param config BasicPresetConfig
---@return BasicPreset
function BasicPresetBuilder:build(config)
  return {
    id = config.id,
    description = config.description,
    invoke = function(opts)
      local provider = self.provider
      local replace, user_query, current_buffer_context, selection

      user_query = utils.get_user_input()
      if user_query == nil then return end

      replace = not (api.nvim_get_mode().mode == 'n')
      selection = utils.get_visual_selection(opts)
      current_buffer_context = buffer_manager:get_buffer_context(0)

      local context_files = utils.get_project_files({
        stop_dir = Path:new(vim.fn.expand '~'),
        context_dir_id = '.kzn'
      })

      local prompt_args = {
        user_query = user_query,
        selection = selection,
        current_buffer_context = current_buffer_context,
        replace = replace,
        context_files = context_files,
      }

      if self.spec == "anthropic" then
        self:make_data_for_anthropic_spec(config.curl_options, prompt_args)
      elseif self.spec == "openai" then
        self:make_data_for_openai_spec(config.curl_options, prompt_args)
      end

      if opts.debug then
        local scratch_buf_id = buffer_manager:create_scratch_buffer()
        local debug_data = provider:make_prompt_from_template({ filename = 'debug.xml.jinja', prompt_args = config.curl_options.data })

        buffer_manager:write_content(debug_data, scratch_buf_id)
        vim.cmd 'normal! G'
        vim.cmd 'normal! zz'
      end

      local args = provider:make_curl_args(config.curl_options)
      local job = buffer_manager:create_streaming_job(provider, args)
      job:start()
    end
  }
end

function BasicPresetBuilder:make_data_for_anthropic_spec(curl_options, prompt_args)
  vim.print(prompt_args)
  curl_options.data.system = {
    {
      type = "text",
      text = self.provider:make_prompt_from_template({
        filename = 'long_context_documents.xml.jinja',
        prompt_args = prompt_args,
      }),
      cache_control = { type = "ephemeral" },
    },
  }
  curl_options.data.messages = {
    {
      role = 'user',
      content = self.provider:make_prompt_from_template({
        filename = 'fill_mode_user_prompt.xml.jinja',
        prompt_args = prompt_args,
      }),
    },
  }
  if prompt_args.context_files then
    table.insert(
      curl_options.data.system,
      {
        type = "text",
        text = self.provider:make_prompt_from_template({
          filename = 'fill_mode_system_prompt.xml.jinja',
          prompt_args = prompt_args,
        }),
        cache_control = { type = "ephemeral" },
      }
    )
  end
end

function BasicPresetBuilder:make_data_for_openai_spec(curl_options, prompt_args)
  curl_options.data.messages = {
    {
      role = 'system',
      content = self.provider:make_prompt_from_template({
        filename = 'fill_mode_system_prompt.xml.jinja',
        prompt_args = prompt_args,
      }),
    },
    {
      role = 'user',
      content = self.provider:make_prompt_from_template({
        filename = 'fill_mode_user_prompt.xml.jinja',
        prompt_args = prompt_args,
      }),
    },
  }
end

---@param preset_list BasicPreset[]
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

---@param preset_list BasicPreset[]
function M.load_selected_preset(preset_list)
  local idx = vim.g.PRESET_IDX or 1
  local preset = preset_list[idx]

  return preset
end

local AnthropicPresetBuilder = BasicPresetBuilder:new({
  spec = "anthropic",
  provider = BaseProvider:new({
    api_key_name = "ANTHROPIC_API_KEY",
    base_url = 'https://api.anthropic.com',
    handle_data_fn = anthropic.handle_sse_stream,
    template_directory = TEMPLATE_DIRECTORY / 'anthropic'
  }),
})

local OpenAIPresetBuilder = BasicPresetBuilder:new({
  spec = "openai",
  provider = BaseProvider:new({
    api_key_name = "OPENAI_API_KEY",
    base_url = 'https://api.openai.com',
    handle_data_fn = openai.handle_sse_stream,
    template_directory = TEMPLATE_DIRECTORY / 'openai'
  }),
})


-- Example preset configurations
-- /v1/chat/completions
M.options = {
  AnthropicPresetBuilder:build({
    id = "sonnet-3-5-chat",
    description = 'claude-3-5-sonnet-20241022 | temp = 0.7',
    curl_options = {
      endpoint = '/v1/messages',
      auth_format = 'x-api-key: %s',
      extra_headers = {
        'anthropic-version: 2023-06-01',
        'anthropic-beta: prompt-caching-2024-07-31',
      },
      data = {
        ["model"] = 'claude-3-5-sonnet-20241022',
        ["stream"] = true,
        ["max_tokens"] = 8192,
        ["temperature"] = 0.7,
      }
    }
  }),
  OpenAIPresetBuilder:build({
    id = "gpt-4o-mini",
    description = 'gpt-4o-mini | temp = 0.7',
    curl_options = {
      endpoint = '/v1/chat/completions',
      extra_headers = {},
      data = {
        ["model"] = 'gpt-4o-mini',
        ["stream"] = true,
        ["max_completion_tokens"] = 8192,
        ["temperature"] = 0.7,
      }
    }
  }),
}

return M
