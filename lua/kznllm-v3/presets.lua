--
-- This module provides the basic feature set from kznllm v0.1 with the addition of exported presets.
-- Your lazy config still wants to define the keymaps to make it work (see the main project README.md for recommended setup)
--
local kznllm = require 'kznllm-v3'
local buffer_manager = (require 'kznllm-v3.buffers').buffer_manager
local Path = require 'plenary.path'
local api = vim.api

local BaseProvider = require 'kznllm-v3.providers.base'
local anthropic = require 'kznllm-v3.providers.anthropic'
local openai = require 'kznllm-v3.providers.openai'

local M = {}

local NS_ID = api.nvim_create_namespace 'kznllm_ns'

local plugin_dir = Path:new(debug.getinfo(1, 'S').source:sub(2)):parents()[3]
local TEMPLATE_DIRECTORY = Path:new(plugin_dir) / 'templates'

local group = api.nvim_create_augroup('LLM_AutoGroup', { clear = true })

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
      return ('%-15s %40s'):format(item.id .. (item == selected_preset and ' *' or '  '), item.description)
    end,
  }, function(choice, idx)
    if choice then
      vim.g.PRESET_IDX = idx
      selected_preset = preset_list[preset_idx]
    end
    print(('%-15s %40s'):format(selected_preset.id, selected_preset.description))
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
      api.nvim_clear_autocmds { group = group }
      local origin_buf_id = api.nvim_win_get_buf(0)

      local provider = BaseProvider:new({
        api_key_name = 'ANTHROPIC_API_KEY',
        base_url = 'https://api.anthropic.com',
        handle_data_fn = anthropic.handle_sse_stream,
        template_directory = (opts.template_directory or TEMPLATE_DIRECTORY) / 'anthropic'
      })

      local replace, user_query, current_buffer_context, selection
      replace = not (api.nvim_get_mode().mode == 'n')
      selection = kznllm.get_visual_selection(opts)

      user_query = kznllm.get_user_input()

      if user_query == nil then return end

      current_buffer_context = buffer_manager:get_buffer_context(0)

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
            text = kznllm.make_prompt_from_template({
              prompt_template_path = provider.template_directory / 'fill_mode_system_prompt.xml.jinja',
              prompt_args = prompt_args,
            }),
            cache_control = { type = "ephemeral" },
          },
        },
        ["messages"] = {
          {
            role = 'user',
            content = kznllm.make_prompt_from_template({
              prompt_template_path = provider.template_directory / 'fill_mode_user_prompt.xml.jinja',
              prompt_args = prompt_args,
            }),
          },
        },
      }
      local context_files = kznllm.get_project_files({
        stop_dir = Path:new(vim.fn.expand '~'),
        context_dir_id = '.kzn'
      })
      if context_files then
        table.insert(data.system, {
          type = "text",
          text = kznllm.make_prompt_from_template({
            prompt_template_path = provider.template_directory / 'long_context_documents.xml.jinja',
            prompt_args = {
              context_files = context_files
            },
          }),
          cache_control = { type = "ephemeral" },
        })
      end

      local stream_buf_id

      if opts.debug then
        local scratch_buf_id = buffer_manager:create_scratch_buffer()
        stream_buf_id = scratch_buf_id
        -- local scratch_buf_id = kznllm.make_scratch_buffer()
        api.nvim_buf_set_var(stream_buf_id, 'debug', true)
        local debug_data = kznllm.make_prompt_from_template({
          prompt_template_path = provider.template_directory / 'debug.xml.jinja',
          prompt_args = data,
        })
        buffer_manager:write_content(debug_data, scratch_buf_id)
        -- api.nvim_buf_set_lines(scratch_buf_id, 0, 0, false, vim.split(debug_data, '\n'))
        vim.cmd 'normal! G'
        vim.cmd 'normal! zz'


        -- local last_line = vim.api.nvim_buf_line_count(stream_buf_id) - 1
        -- stream_end_extmark_id = api.nvim_buf_set_extmark(stream_buf_id, NS_ID, last_line, 0, {})
      else
        stream_buf_id = origin_buf_id
      --   stream_end_extmark_id = api.nvim_buf_set_extmark(stream_buf_id, NS_ID, pos.srow, pos.scol, { strict = false })
      end

      -- Make a no-op change to the buffer at the specified extmark to avoid calling undojoin after undo
      kznllm.noop()

      local args = provider:make_curl_args({
        endpoint = '/v1/messages',
        auth_format = 'x-api-key: %s',
        extra_headers = {
          'anthropic-version: 2023-06-01',
          'anthropic-beta: prompt-caching-2024-07-31',
        },
        data = data,
      })

      -- local active_job = provider:make_job(args, function(content)
      --   kznllm.write_content_at_extmark(content, NS_ID, stream_end_extmark_id)
      -- end, function()
      --   api.nvim_buf_del_extmark(stream_buf_id, NS_ID, stream_end_extmark_id)
      -- end)

      local active_job = buffer_manager:create_streaming_job(provider, stream_buf_id, args)
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
  },
}

return M
