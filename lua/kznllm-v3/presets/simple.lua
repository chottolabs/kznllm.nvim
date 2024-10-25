--
-- This module provides the basic feature set from kznllm v0.1 with the addition of exported presets.
-- Your lazy config still wants to define the keymaps to make it work (see the main project README.md for recommended setup)
--
local utils = require 'kznllm-v3.utils'
local buffer_manager = (require 'kznllm-v3.buffer').buffer_manager
local Path = require 'plenary.path'
local api = vim.api

local BaseProvider = require 'kznllm-v3.provider'
local anthropic = require 'kznllm-v3.providers.anthropic'
local openai = require 'kznllm-v3.providers.openai'

local M = {}

-- NOTE: this is a relative path meant to point at the template directory
local plugin_dir = Path:new(debug.getinfo(1, 'S').source:sub(2)):parents()[4]
local TEMPLATE_DIRECTORY = Path:new(plugin_dir) / 'templates'

---@class PromptArguments
---@field visual_selection? string
---@field user_query? string
---@field replace? boolean
---@field prefill? string
---@field current_buffer_context? { path: string, text: string, filetype: string }
---@field context_files? { path: string, content: string }

---@param preset_list Preset[]
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

---@param preset_list Preset[]
function M.load_selected_preset(preset_list)
  local idx = vim.g.PRESET_IDX or 1
  local preset = preset_list[idx]

  return preset
end

---@class Preset
---@field id? string
---@field description? string
---@field invoke fun(opts: table)

---@type Preset[]
M.options = {
  {
    id = "sonnet-3-5-chat",
    description = 'claude-3-5-sonnet-20241022 | temp = 0.7',
    invoke = function(opts)
      local replace, user_query, current_buffer_context, selection

      user_query = utils.get_user_input()
      if user_query == nil then return end

      replace = not (api.nvim_get_mode().mode == 'n')
      selection = utils.get_visual_selection(opts)

      local current_buf_id = api.nvim_get_current_buf()
      current_buffer_context = buffer_manager:get_buffer_context(current_buf_id)

      local provider = BaseProvider:new({
        api_key_name = 'ANTHROPIC_API_KEY',
        base_url = 'https://api.anthropic.com',
        handle_data_fn = anthropic.handle_sse_stream,
        template_directory = (opts.template_directory or TEMPLATE_DIRECTORY) / 'anthropic'
      })

      local prompt_args = {
        user_query = user_query,
        visual_selection = selection,
        current_buffer_context = current_buffer_context,
        replace = replace,
      }

      ---@type AnthropicAPIBody
      local data = {
        ["model"] = 'claude-3-5-sonnet-20241022',
        ["stream"] = true,
        ["max_tokens"] = 8192,
        ["temperature"] = 0.7,

        ["system"] = {
          {
            type = "text",
            text = provider:make_prompt_from_template({
              filename = 'fill_mode_system_prompt.xml.jinja',
              prompt_args = prompt_args,
            }),
            cache_control = { type = "ephemeral" },
          },
        },
        ["messages"] = {
          {
            role = 'user',
            content = provider:make_prompt_from_template({
              filename = 'fill_mode_user_prompt.xml.jinja',
              prompt_args = prompt_args,
            }),
          },
        },
      }
      local context_files = utils.get_project_files({
        stop_dir = Path:new(vim.fn.expand '~'),
        context_dir_id = '.kzn'
      })
      if context_files then
        table.insert(data.system, {
          type = "text",
          text = provider:make_prompt_from_template({
            filename = 'long_context_documents.xml.jinja',
            prompt_args = { context_files = context_files },
          }),
          cache_control = { type = "ephemeral" },
        })
      end

      if opts.debug then
        local scratch_buf_id = buffer_manager:create_scratch_buffer()
        local debug_data = provider:make_prompt_from_template({ filename = 'debug.xml.jinja', prompt_args = data, })

        buffer_manager:write_content(debug_data, scratch_buf_id)
        vim.cmd 'normal! G'
        vim.cmd 'normal! zz'
      end

      local args = provider:make_curl_args({
        endpoint = '/v1/messages',
        auth_format = 'x-api-key: %s',
        extra_headers = {
          'anthropic-version: 2023-06-01',
          'anthropic-beta: prompt-caching-2024-07-31',
        },
        data = data,
      })

      local job = buffer_manager:create_streaming_job(provider, args)
      job:start()
    end
  },
}

return M