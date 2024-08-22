local Path = require 'plenary.path'
local Job = require 'plenary.job'

local M = {}
local api = vim.api

local kznllm_ns_id = api.nvim_create_namespace 'kznllm_ns'

-- Specify the path where you want to save the file
M.CACHE_DIRECTORY = vim.fn.stdpath 'cache' .. '/kznllm/history'

M.TEMPLATE_DIRECTORY = vim.fn.stdpath 'data' .. '/lazy/kznllm/templates'

if vim.fn.executable 'minijinja-cli' ~= 1 then
  error("Can't find minijinja-cli, download it from https://github.com/mitsuhiko/minijinja or add it to $PATH", 1)
end

local group = api.nvim_create_augroup('LLM_AutoGroup', { clear = true })

--- Get normalized visual selection such that it returns the start_pos < end_pos 0-indexed
local function get_visual_selection(mode)
  -- get visual selection and current cursor position

  -- 1-indexed
  local _, srow, scol = unpack(vim.fn.getpos 'v')
  local _, erow, ecol = unpack(vim.fn.getpos '.')

  srow, scol, erow, ecol = srow - 1, scol - 1, erow - 1, ecol - 1
  if srow > erow then
    srow, erow = erow, srow
  end

  if scol > ecol then
    scol, ecol = ecol, scol
  end

  -- in visual block and visual line mode, we expect first column of srow and last column of erow
  if mode == 'V' or mode == '\22' or mode == 'n' then
    return srow, 0, erow, -1
  end

  --  last row inclusive, last col exclusive
  return srow, scol, erow, ecol + 1
end

---Renders a prompt template using minijinja-cli and returns the rendered lines
---
---@param prompt_template_path string
---@param prompt_args table
---@return string
local function make_prompt_from_template(prompt_template_path, prompt_args)
  local json_data = vim.json.encode(prompt_args)
  local active_job = Job:new {
    command = 'minijinja-cli',
    args = { '-f', 'json', prompt_template_path, '-' },
    writer = json_data,
    on_stderr = function(message, _)
      error(message, 1)
    end,
  }

  active_job:sync()
  return table.concat(active_job:result(), '\n')
end

---@param content string
---@param ns_id integer
---@param extmark_id integer
local function write_content_at_extmark(content, ns_id, extmark_id)
  local extmark = api.nvim_buf_get_extmark_by_id(0, ns_id, extmark_id, { details = false })
  local mrow, mcol = extmark[1], extmark[2]

  vim.cmd 'undojoin'

  local lines = vim.split(content, '\n')
  api.nvim_buf_set_text(0, mrow, mcol, mrow, mcol, lines)
end

-- mainly for debugging purposes
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

--- Invokes an LLM via a supported API spec in "inline" mode
---
--- Must provide the function for constructing cURL arguments and a handler
--- function for processing server-sent events.
---
---@param prompt_messages { role: string, prompt_template: string, args: table }[]
---@param make_job_fn fun(rendered_message: { role: string, content: string }, writer_fn: fun(content: string), on_exit_fn: fun())
function M.invoke_llm(prompt_messages, make_job_fn, opts)
  api.nvim_clear_autocmds { group = group }

  local active_job, stream_end_extmark_id

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

  local debug = opts and opts.debug

  if debug then
    buf_id = make_scratch_buffer()
    erow = 0
  end

  vim.ui.input({ prompt = 'prompt: ' }, function(input)
    if input ~= nil then
      if replace_mode then
        stream_end_extmark_id = api.nvim_buf_set_extmark(buf_id, kznllm_ns_id, erow, ecol, {})
        api.nvim_buf_set_text(buf_id, srow, scol, erow, ecol, {})
      else
        -- put an extmark at the appropriate spot
        stream_end_extmark_id = api.nvim_buf_set_extmark(buf_id, kznllm_ns_id, erow, 0, {})
      end

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

        if debug then
          write_content_at_extmark(message.role .. ':\n\n', kznllm_ns_id, stream_end_extmark_id)
          write_content_at_extmark(make_prompt_from_template(template_path, prompt_args), kznllm_ns_id, stream_end_extmark_id)
          write_content_at_extmark('\n\n---\n\n', kznllm_ns_id, stream_end_extmark_id)
        end
      end

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

api.nvim_set_keymap('n', '<Esc>', '', {
  noremap = true,
  silent = true,
  callback = function()
    api.nvim_exec_autocmds('User', { pattern = 'LLM_Escape' })
  end,
})

return M
